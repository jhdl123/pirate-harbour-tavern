# Navigation System

## Design goal

Actors move. Customers today; bartenders, cellar hands, NPCs, animals and
companions later. None of them should own navigation code.

The framework splits the problem into three questions, each answered by a
different component:

```text
Where am I going?          ActorNavigation   (path, steer, arrive, recover)
How does my body move?     ActorMovement     (accelerate, settle, move_and_slide)
Who else may use that?     Reservable        (claim, occupy, release, expire)
```

Nothing in `systems/navigation/` or `systems/reservation/` mentions customers,
seats, drinks or tables. A customer is one implementation of an actor, not the
subject of the framework.

---

## Class map

```text
systems/navigation/

NavigationService          static helpers for NavigationServer2D
    ├── map readiness
    ├── project a point onto the mesh
    ├── reachability
    └── path length, for scoring destinations before walking them

ActorMovementProfile       Resource: speed, acceleration, arrival, settling
ActorMovement              Node: owns velocity and the ONE move_and_slide()

ActorNavigationProfile     Resource: avoidance, path following, recovery
ActorNavigation            Node: the controller. Path -> steering -> movement.

NavigationDestination      value object: "go here, like this"
ApproachPoint              Marker2D: "stand here to use me", reservable

systems/reservation/

Reservable                 Node: one claimable thing, two-stage claiming
ReservationService         static: search and claim across a set
```

**Dependency direction**, which is what makes this reusable:

```text
customer.gd  ──>  ActorNavigation  ──>  ActorMovement  ──>  CharacterBody2D
     │                   │
     │                   └──>  NavigationDestination  ──>  Reservable
     │
     └──>  Chair  ──>  Reservable
```

Never the other way. No framework file imports anything from `scripts/`.

---

## What was wrong, and what fixed it

Worth reading before the rest, because most of the design follows from it.

### Unexpected pauses

`prepare_navigation_target()` was an `async` function. It set
`has_navigation_target = false`, called `stop_movement()`, then awaited up to
two physics frames. Meanwhile `process_navigation()` saw no target and called
`stop_movement()` again every frame.

Every destination change therefore produced a visible stall — and stuck
recovery *also* called it, so an actor that was struggling was made to stand
still before trying again.

**Fixed by:** `ActorNavigation.move_to()` returns immediately and never stops
the actor. If the navigation map is not synchronised yet the request is held in
`_target_pending` and applied on the first frame it can be, while the actor
carries on moving.

### Twitching and rapid direction changes

Desired velocity was `direction_to(get_next_path_position()) * speed`,
recomputed every frame and assigned straight to `velocity`. When the path
advanced a corner, the direction flipped instantly, and so did the actor.

**Fixed by two independent things:**

- `ActorNavigation` smooths the steering direction (`steering_smoothing`),
  framerate-independently, so a corner flip becomes a curve.
- `ActorMovement` ramps velocity with `acceleration`/`deceleration` rather than
  assigning it, so even an instant direction request is physically smoothed.

### Overshooting and jitter at the destination

Actors ran at full speed until they were within 6 pixels, then stopped dead.
The avoidance solver kept handing back small non-zero velocities afterwards.

**Fixed by:** a slowing radius (`ActorMovementProfile.slowing_radius`) that
scales speed down across the last ~44 pixels with a floor so the actor does not
creep, plus a `settle_speed` below which velocity is treated as zero.

### Clipping and awkward furniture navigation

`begin_moving_to_seat()` set `avoidance_enabled = false` and walked in a
straight line at the seat with `move_and_slide()`. `process_exiting()` did the
same for the door. Avoidance was off for exactly the two moments actors were
most likely to be near each other.

**Fixed by:** the final approach is now a normal part of the journey. Inside
`_final_approach_radius` the actor steers straight at the destination instead
of following the path — but avoidance, acceleration and the slowing curve all
keep running. See [Arrival](#arrival) below for why the radius is dynamic.

### Fighting over movement

A seated customer had avoidance switched off entirely, so it was invisible to
the solver and got shoved around by passers-by.

**Fixed by:** `ActorNavigation.park()`. A parked actor stays in the solver at
maximum `avoidance_priority`, which makes it something others flow around
rather than push through.

### Getting stuck

The only recovery was a full re-path, capped at two attempts, after which the
customer gave up and left the tavern. Re-pathing does not help the most common
jam, which is two actors politely refusing to pass each other.

**Fixed by:** an escalating recovery ladder — sidestep, re-path, sidestep —
before failure. See [Recovery](#recovery).

### Cost

`map_get_closest_point` plus a full re-path on every state change and every
stuck check, per actor, with an await loop each.

**Fixed by:** `minimum_repath_interval` throttles recalculation, a moving
destination only re-paths after it has moved `destination_move_repath_distance`,
and sidesteps cost no pathfinding at all.

---

## Navigation flow

```text
customer.gd decides where to go
    │
    ▼
_travel_to(position, arrival, label)
    └── NavigationDestination.to_position(...)
        │
        ▼
ActorNavigation.move_to(destination)
    ├── unpark if parked
    ├── reset recovery counters
    └── _request_path(new = true)
            ├── map not ready?  -> hold as pending, keep moving
            ├── project the target onto the navigation mesh
            ├── remember how far the projection moved it
            └── agent.target_position = projected
    │
    ▼
_physics_process, every frame
    ├── destination still valid?      reservation held, tracked node alive
    ├── arrived?                      -> _arrive()
    ├── destination moved far?        -> throttled re-path
    ├── desired direction
    │     ├── sidestepping            -> sidestep direction
    │     ├── inside final approach   -> straight at the destination
    │     ├── path finished early     -> _begin_recovery()
    │     └── otherwise               -> towards next path position
    ├── smooth the direction
    ├── scale speed by destination.speed_scale x arrival slowing curve
    ├── agent.velocity = desired            (solver computes a safe velocity)
    ├── movement.request_velocity(safe velocity from last frame)
    ├── movement.apply(delta)               (accelerate, settle, move_and_slide)
    └── stuck detection
    │
    ▼
destination_reached  ->  customer.gd picks the next state
destination_failed   ->  customer.gd recovers or leaves
```

The customer's state machine is unchanged. It still enters, walks to a staging
point, sits, orders, drinks, pays and leaves. What changed is that it no longer
measures distances, manages an agent, or writes velocity — it asks for a
destination and is told when it arrives.

### Why the avoidance velocity is deferred one frame

`NavigationAgent2D` emits `velocity_computed` part-way through the physics
step. The common pattern is to call `move_and_slide()` inside that callback,
which is what the old customer did — and it is why movement had two entry
points and a state check inside an engine callback.

Instead, `ActorNavigation` stores the safe velocity and uses it on the next
frame, so every write to the body happens in one place, in a predictable order.
The cost is one frame of latency at 60 Hz, which is not perceptible. The gain is
that "why did this actor move" has exactly one answer.

---

## Movement

`ActorMovement` is the only thing in the project that writes an AI actor's
`velocity` or calls `move_and_slide()`.

```gdscript
movement.request_velocity(desired)   # or request_direction(dir, ratio)
movement.apply(delta)                # once per physics frame
```

If nothing requests a velocity in a frame, `apply()` decelerates towards zero.
An actor whose controller goes quiet therefore coasts to a stop naturally
rather than freezing mid-stride — which also means a bug in a future AI is a
gentle halt, not a T-pose.

`movement_state_changed` fires when the actor starts or stops moving, ready for
walk animations and footsteps without polling.

---

## Arrival

Three things combine to make arrivals clean:

**Slowing curve.** Speed is scaled by `get_arrival_speed_ratio(distance)`
across `slowing_radius`, with `minimum_slowing_ratio` as a floor so the actor
does not creep for the last few pixels.

**Final approach radius.** A seat sits inside furniture, so it is *off* the
navigation mesh. A path can only ever deliver an actor to the mesh edge. When a
path is requested, `ActorNavigation` measures how far the projection moved the
target and stores:

```text
_final_approach_radius = max(
    profile.target_desired_distance,
    projection_error + destination.arrival_distance
)
```

Inside that radius the actor abandons the path and steers straight at the true
destination. This is the general solution to the old "turn navigation off and
walk at the chair" special case, and it works for anything off-mesh: seats,
the outside door marker, a future counter hatch.

**Settling.** `ActorMovement` snaps velocity to zero below `settle_speed`, and
`_arrive()` calls `stop()` — by which point the slowing curve has already
brought the actor to a crawl, so it is a tidy-up, not a jolt.

`NavigationDestination.ArrivalMode` distinguishes the two cases:

| Mode | Used for | Behaviour |
|---|---|---|
| `NEAR` | doors, staging points, general travel | warns if the target is far off-mesh |
| `EXACT` | seats, workstation spots | expects to be off-mesh; approached slowly |

---

## Avoidance

Avoidance is configured once from `ActorNavigationProfile` and then left alone.
It is never toggled mid-journey.

The lever that matters most is `avoidance_priority`. Higher means the actor
yields less. Giving staff a higher priority than customers will make customers
step aside for a bartender carrying a tray, with no code change — it is one
number in one resource.

### Parking

```gdscript
actor_navigation.park()     # seated, working a station, leaning on a wall
actor_navigation.unpark()   # back into normal traffic
```

A parked actor keeps its agent in the solver at
`parked_avoidance_priority` (1.0 by default). Others path around it. This is
what stops seated customers being shunted out of their chairs in a busy room,
and it will do the same for a bartender standing at a keg.

The chair's own `NavigationObstacle2D` is unchanged and still marks the
occupied seat zone. The two work together: the obstacle keeps paths out of the
seat, parking keeps other actors from pushing the one in it.

---

## Recovery

Recovery escalates through cheap options before spending a path query, and only
declares failure at the end:

```text
progress checked every stuck_check_interval
    └── moved less than stuck_minimum_movement?
            └── after stuck_checks_before_recovery failures:

                attempt 1   sidestep      (no pathfinding at all)
                attempt 2   force re-path
                attempt 3   sidestep the other way
                ...
                beyond maximum_recovery_attempts  ->  destination_failed
```

Sidestep direction is perpendicular to travel, alternating sides between
attempts, and is checked against the navigation mesh — if that side is off-mesh
the other is used instead.

Alternating matters: a jam a sidestep cannot fix still reaches a re-path, and a
bad path a re-path cannot fix still gets shaken loose by a sidestep.

A successful stretch of movement resets both counters, so an actor that is
briefly blocked ten times over a long journey never accumulates its way to
failure.

### Destination invalidation

Before steering each frame, `ActorNavigation` asks
`NavigationDestination.is_valid(actor)`:

- the tracked node still exists, and
- the reservation, if there is one, is still held by this actor

Either failing raises `destination_failed` with reason `invalid`. An actor
therefore stops walking towards a seat that was taken from it, or a station
that was removed, without any object needing to notify it.

`customer.gd` handles the three reasons — `unreachable`, `blocked`, `invalid` —
identically today, by leaving. Staff will want to distinguish them: a blocked
route deserves a retry, an invalid reservation deserves a new target.

---

## Reservation

Seat state used to be a private enum and a `customer` field on `Chair`. That
worked for chairs and nothing else, so queue slots, station approach points and
workstations would each have grown their own copy.

`Reservable` is that logic, extracted:

```text
FREE  ──reserve(actor)──>  RESERVED  ──occupy(actor)──>  OCCUPIED
  ^                            │                             │
  └────────release()───────────┴─────────────────────────────┘
                    or expiry, or the holder is freed
```

**Two stages, not one.** Without the middle stage two actors walk to the same
chair; the first to arrive is not necessarily the one that claimed it. `reserve`
says "on my way", `occupy` says "I am here and using it", and only the holder
may promote its own reservation.

**Expiry.** `reservation_timeout_seconds` releases a reservation that is never
converted to occupancy. An actor that is destroyed, blocked or bugged en route
no longer costs the tavern a seat for the rest of the session. `Reservable` also
notices a holder that was freed without releasing and cleans up after it.

**Tags, not subclasses.** `reservation_tags` (`seat`, `approach`, `queue`)
filter searches, so a new kind of reservable never needs a script.

`ReservationService` is the layer above — searching and claiming across a set:

```gdscript
ReservationService.reserve_nearest_free(chairs, actor, position)
ReservationService.find_best_free(candidates, score_function)
ReservationService.release_all_for(candidates, actor)
ReservationService.collect_from(table, &"seat")
```

`reserve_nearest_free` retries down the list when a claim fails, so two actors
choosing in the same frame never both walk to the same spot.

### The chair today

`Chair` keeps its whole public API — `is_available()`, `assign_customer()`,
`begin_use()`, `require_cleaning()`, `clear_customer()`, `contains_customer()`
— so `Table`, `GameManager` and `Customer` are unchanged. Internally those are
now four lines each on top of `Reservable`, and `SeatState` survives as a
read-only projection through `get_seat_state()`.

---

## Interaction positions

`ApproachPoint` is a `Marker2D` that declares "stand here to use me", with a
`Reservable` created automatically.

It is the counterpart to the interaction framework's
`Interactable.get_interaction_position()`. That returns a point *on* the object
— a bar service slot, the middle of a keg — which is exactly where an actor
must not stand. An approach point is the walkable spot from which that
interaction point can be reached.

```gdscript
var spot: ApproachPoint = ApproachPoint.reserve_nearest(
    keg, self, global_position
)

if spot != null:
    actor_navigation.move_to_approach_point(spot)
```

`NavigationDestination.to_approach_point()` attaches the reservation to the
journey, so losing the spot automatically invalidates the walk towards it.

**Nothing uses approach points yet.** The chair still has its own staging
position and the drinks station is still reached by walking at it. They exist
now so that storage, kegs, cleaning stations and crafting benches can be built
without touching navigation again — which was the point of the brief.

---

## How future staff reuse this

A bartender needs no new navigation code. The whole integration is:

**1. Scene**

```text
Bartender (CharacterBody2D)
├── NavigationAgent2D
├── Sprite2D
├── CollisionShape2D
├── ActorMovement      profile: staff_movement.tres
├── ActorNavigation    profile: staff_navigation.tres
├── ItemCarrier        (existing item framework)
└── InteractionDetector + InteractionSelector  (existing interaction framework)
```

**2. Two resources**, differing from the customer's only in numbers:

```text
staff_movement.tres     faster, brisker acceleration
staff_navigation.tres   avoidance_priority 0.8 - customers yield to staff
```

**3. Script**

```gdscript
extends CharacterBody2D

@onready var actor_navigation: ActorNavigation = $ActorNavigation

func serve_next_order(station: Node) -> void:
    var spot: ApproachPoint = ApproachPoint.reserve_nearest(
        station, self, global_position
    )

    if spot == null:
        return   # every spot at that station is taken; try another

    actor_navigation.move_to_approach_point(spot)

func _on_destination_reached(_destination: NavigationDestination) -> void:
    actor_navigation.park()
    # then use the interaction framework exactly as the player does
```

That is it. Smoothing, avoidance, arrival, recovery, reservation expiry and
repath throttling all apply immediately, because none of them were ever
customer-specific.

## How future NPCs and animals reuse this

Same components, different profiles and different destination choices.

- **A patrolling guard** cycles a list of `ApproachPoint`s or plain positions.
  `destination_reached` picks the next one.
- **A tavern cat** gets a low `avoidance_priority` (everyone ignores it), a
  small `avoidance_radius`, and wanders using
  `NavigationService.find_free_point_near()`.
- **A companion** follows the player with
  `NavigationDestination.target_node` set, which the framework re-paths only
  when the target has moved `destination_move_repath_distance`.
- **A drunk** gets high `steering_smoothing` and low `deceleration`, and
  weaves without a line of bespoke code.

None of these need a new class. Two of them need no new resource.

---

## Performance

The design assumes a much busier tavern than exists today.

| Cost | How it is contained |
|---|---|
| Path queries | `minimum_repath_interval` throttles all recalculation |
| Moving targets | only re-path after `destination_move_repath_distance` |
| Stuck recovery | sidestep first, which costs no pathfinding |
| Avoidance | `maximum_neighbours` caps solver work per actor |
| Map readiness | `NavigationService` is shared, not an await loop per actor |
| Parked actors | `_physics_process` early-outs to a single `apply()` call |

The one thing to watch as actor counts grow is `maximum_neighbours` and
`neighbour_distance`, which together decide how much RVO work happens per actor
per frame. Both are per-profile, so crowds can be made cheaper than staff.

---

## Tuning

### `ActorMovementProfile` — `Data/navigation/customer_movement.tres`

| Property | Default | Effect |
|---|---|---|
| `maximum_speed` | 120 | Top speed, px/s |
| `careful_speed` | 45 | Speed for the seat shuffle |
| `acceleration` | 900 | How briskly it gets up to speed |
| `deceleration` | 1400 | Higher than acceleration: stopping late reads as an overshoot |
| `slowing_radius` | 44 | Distance over which arrival slowing happens |
| `minimum_slowing_ratio` | 0.18 | Floor, so actors do not creep |
| `settle_speed` | 6 | Below this, treated as stopped |

### `ActorNavigationProfile` — `Data/navigation/customer_navigation.tres`

| Property | Default | Effect |
|---|---|---|
| `avoidance_radius` | 12 | Personal space, not collision size |
| `avoidance_priority` | 0.5 | Higher yields less. The staff-vs-customer lever |
| `neighbour_distance` | 80 | How far the solver looks |
| `maximum_neighbours` | 10 | Main per-actor cost knob |
| `time_horizon_agents` | 0.7 | Seconds ahead when avoiding actors |
| `path_desired_distance` | 12 | Corner-hugging vs corner-cutting |
| `target_desired_distance` | 10 | When the path counts as finished |
| `steering_smoothing` | 0.55 | The anti-twitch value |
| `minimum_repath_interval` | 0.5 | The main cost throttle |
| `stuck_checks_before_recovery` | 3 | Patience before recovering |
| `maximum_recovery_attempts` | 3 | Attempts before giving up |
| `sidestep_distance` | 28 | How far a sidestep nudges |
| `parked_avoidance_priority` | 1.0 | Immovability of a seated actor |

`GameConfig` still drives `walking_avoidance_radius`, `walking_avoidance_priority`
and the stuck values; the customer copies them onto its own duplicated profile
in `_apply_tuning_to_profiles()`. New tuning should go in the profile rather
than `GameConfig`, which is global and cannot vary per actor type.

**Profiles are duplicated per actor** on ready. Without that, writing one
customer's speed onto a profile would edit the resource every other customer is
sharing.

---

## Future expansion

Things that fit the existing seams, roughly in order of value:

**Queue slots at the door.** A row of `ApproachPoint`s with `queue` tags, and
`ReservationService.reserve_first_free()`. Customers waiting for a seat stand in
a tidy line instead of clustering. No framework change.

**Staff.** As above. The single largest reuse, and it needs two resources.

**Path length seat scoring.** `GameManager.calculate_chair_score()` currently
uses straight-line distance from the door. `NavigationService.get_path_length()`
would make it account for walls and furniture. One line, meaningfully better
seat choices.

**Facing on arrival.** `ApproachPoint.facing_degrees` is already stored and
unused. When the interaction framework gains facing, both read the same value.

**Group movement / crowd density.** `neighbour_distance` and
`maximum_neighbours` per profile already give coarse crowd control. Real
flocking was explicitly out of scope and nothing here forecloses it.

**Dynamic re-baking.** `NavigationRegionManager` already handles rebakes and
signals. `ActorNavigation` could listen for `navigation_rebake_finished` and
force a re-path, which would let furniture be moved at runtime.

**Multi-floor.** Out of scope, but the seam is `NavigationService`: it is the
only thing that talks to `NavigationServer2D`, so adding map selection means
changing one file.

---

## Gotchas

**Call `movement.apply()` exactly once per physics frame.** `ActorNavigation`
does this on every path through `_physics_process`, including the early-outs.
A new controller driving `ActorMovement` directly must do the same.

**Do not toggle `avoidance_enabled`.** It is set once from the profile. Use
`park()`/`unpark()` for "this actor has stopped somewhere".

**Do not write `velocity` on an actor.** Ask `ActorMovement`. The whole reason
the old bugs were hard to diagnose is that four methods and one engine callback
all wrote it.

**Destinations are cheap; make new ones.** `NavigationDestination` is a value
object built per journey. Do not cache and mutate one.

**A seat is off the navigation mesh, and that is fine.** Use `EXACT` mode.
`NEAR` will warn about the projection distance, which is the point: for a
travel destination that warning means a badly placed marker.
