# Customer Group Framework

Groups arrive together, settle together, share a drink and leave together.

---

## Architecture

```
CustomerGroupDefinition   resource: what kind of party this is
        │
GroupSpawner              one decision → several customers, one group id
        │
CustomerGroup             runtime controller, one per visit
        │                 owns the group state machine
        ├── members[]  →  Customer nodes, each stamped with group_id
        ├── leader     →  one member, replaceable
        ├── place      →  GroupPlace (seated: Table + Chairs
        │                            standing: GroupStandingArea)
        ├── order      →  GroupOrder (drink id + serving format id)
        └── serving    →  SharedServing  (Beverage Framework, unchanged)

GroupManager              ticks every group on world-minute changes
GroupOrderService         chooses drinks, reserves stock, builds the serving
GroupFormation            pure function: centre + count → slot positions
```

**Division of responsibility.** The group controller decides *where* and
*what*; the customer decides *how to get there*. A member's walking, avoidance,
stuck recovery and animation are its existing `Customer` code, untouched. This
is why groups needed no navigation work at all.

**Ticking is world-time based**, not per-frame. `GroupManager` listens to
`WorldTime.minute_changed`. Members still move every frame — that is their own
navigation.

## Seated vs standing

| | Seated | Standing |
|---|---|---|
| Where | A `Table` with enough free `Chair`s | A `GroupStandingArea` node |
| Reservation | Every chair, **atomically** | The area's `Reservable` |
| Positions | The chairs themselves | `GroupFormation` slots round the centre |
| Serving point | Table centre | The area's `ServingPoint` marker |

**Atomic seating.** `GroupPlace.reserve_seated()` books every chair or rolls
back all of them. A half-reserved table is worse than none — the seats would be
unavailable to everyone including the group that half-booked them.

**Your tavern has 8 seats** (two tables, four chairs). A group of 5+ can never
sit. Standing is the main path until the bar is redesigned.

**Preference, not rule.** A group that prefers standing but finds no free area
will sit rather than be turned away, and vice versa. `standing_allowed = false`
means the group leaves instead of standing.

## Group orders

`GroupOrder` carries a **drink id and a serving-format id together** — "a Table
Cask of Kill-Devil" is two ids, not one. Shared and individual orders are the
same object with `is_shared` flipped, so payment and failure handling have one
path rather than two that can drift.

**Selection** intersects three things, all configurable:
1. the group's `preferred_serving_tags` and portion limits
2. the format's own `minimum_group_size` / tag rules
3. a station that can actually pour it, with the measures in its cask

**Payment happens once.** `GroupOrder.mark_paid()` returns false on any second
call, so revenue can never be counted per member.

## Shared serving integration

Uses the existing `SharedServing` from the Beverage Framework — no second
drink-container system. The `group_id` hook was added when that class was
built, and `is_consumer_eligible()` checks it first, falling back to table
proximity only when empty.

Consumption is atomic: `take_portion()` refuses beyond empty, so the last
portion cannot be taken twice however many members reach for it on one tick.
Members drink on individually jittered timers, so a group never drinks in
unison.

The vessel returns to the `VesselPool` exactly once, whether the serving was
emptied, spoiled or abandoned mid-visit.

---

## Adding a new group archetype

Copy any file in `Data/groups/` and edit. Then add it to `GroupSpawner`'s
`group_definitions` in the scene. Nothing else to register.

Key fields:

| Field | Effect |
|---|---|
| `group_id` | Stable. Never rename once saved. |
| `minimum_size` / `maximum_size` | Range |
| `size_weights` | `{3: 3.0, 4: 2.0, 5: 1.0}` makes threes commonest. Empty = uniform. |
| `spawn_weight` | Relative chance against other archetypes. 0 disables. |
| `place_preference` | `PREFER_SEATED`, `PREFER_STANDING`, `NO_PREFERENCE` |
| `standing_allowed` | False = leaves rather than stands |
| `shared_order_chance` | 0–1, how often they share |
| `preferred_serving_tags` | Steers drink choice (×2.5 per matching tag) |
| `leader_rule` | `FIRST_MEMBER`, `RANDOM`, `WEALTHIEST` |

## Group size weights

Two independent controls, deliberately:

- **`size_weights` on the definition** — how big this archetype tends to be
- **`minimum_shared_portions` / `maximum_shared_portions`** — what size of
  vessel they will accept

Plus the format's own `minimum_group_size`. A firkin declares 6, which is why
two customers can never order one regardless of archetype settings.

## Adding or moving a standing area

`scenes/groups/group_standing_area.tscn`. Drag it anywhere under
`Environment/GroupAreas` and set `area_id`, `minimum_group_size`,
`maximum_group_size`.

Everything positional is a **child marker** (`Centre`, `Entry`, `ServingPoint`),
so the whole area moves as one node. No script refers to a world coordinate.
Duplicate and drag freely when you redesign the bar.

`draw_debug_gizmo` shows the radius in-game while you position it.

Three areas ship in `main.tscn`: `floor_centre` (2–8), `bar_end` (2–6),
`back_corner` (3–8). Positions are provisional — move them after the bar update.

## Formation spacing

| To change | Edit |
|---|---|
| Distance from centre | `GroupStandingArea.formation_radius` |
| Shape | `GroupStandingArea.layout` — `LOOSE_CIRCLE`, `ARC`, `CLUSTER`, `FORMAL` |
| Randomness | `GroupStandingArea.formation_variation` (0 = perfectly even) |

Slots are computed **once** on arrival and held. Recomputing as members shuffle
is what produces jitter, so nothing recalculates them.

## Reorder and departure

| To change | Edit |
|---|---|
| Chance of reordering | `Data/groups/*.tres` → `reorder_chance` |
| Hard cap on orders | → `maximum_orders_per_visit` |
| How long they linger | `GroupManager.minutes_socialising_after_empty` |
| Patience | `CustomerGroup.base_patience_minutes` × definition's `patience_modifier` |
| Closing grace | `GroupManager.closing_grace_minutes` |
| Time between drinks | `GroupManager.minutes_between_drinks` |
| Delay before ordering | `GroupManager.minutes_before_ordering` |

Reordering is bounded by `maximum_orders_per_visit`, so it cannot loop forever.

## Failure handling

Every failure path leads to departure. A group that cannot find a place, cannot
order, loses its leader, or has members stuck in navigation still resolves and
still releases its reservations — a stuck group holding the only free table
would be far worse than one that gives up and goes.

- **Leader lost** → replacement promoted, place and order preserved
- **Members can't reach slots** → visit fails once patience runs out
- **No place available** → turned away rather than milling at the door
- **Closing time** → grace window, then forced departure
- **Orphan sweep** → `GroupManager.clear_orphaned_reservations()`, also on F8
- **Stalled in any state** → `GroupManager.maximum_ticks_per_state` (default
  240) forces departure

The stall backstop is **clock-independent** on purpose. Patience is measured in
tavern minutes, which is right for balance but useless if the clock is stopped
or scaled oddly — a group whose members could not reach their slots would then
hold its table indefinitely. Counting ticks guarantees every state ends.

---

## Debug panels

- **F8 — Group Diagnostics.** Active groups with state, place, order, portions,
  patience, duration and current problem. Actions tab: spawn test groups, force
  seated/standing, force order, fill/empty serving, force reorder, remove leader,
  force departure, tick once, clear orphans.
- **F7 — Beverage Diagnostics.** Definitions, validation, stock, stations,
  vessels, spoilage.

---

## Temporary fallbacks — remove during the storage pass

1. **`BeverageSceneSetup.grant_starting_stock`** fills every station with 96
   measures at startup. Deliveries reach *bulk cellar* storage only, so without
   this every station starts dry and no group could be served.
2. **No staff carry the shared serving.** It appears at the group's serving
   point when the order completes. The vessel and stock accounting are real;
   only the walk is missing.
3. **No staff task fills a service cask from cellar bulk.** Use F7 → "Fill every
   service container from bulk".

## Known gaps

- **`CustomerType` has no stable id**, so `allowed_customer_type_ids` matches on
  the display name. Worth adding a real `type_id` when that resource is next
  touched.
- **Mixed drinks are off** for groups (`GroupOrderService.allow_prepared_drinks
  = false`). Recipes, ingredients and punch bowls are authored and validated;
  the only missing piece is a staff preparation task.
- **Active customers are not saved** by the current game, so group visits are
  not persisted either. Group state is save-ready (`to_save_dict` on orders and
  servings) but nothing calls it yet.
- **Social behaviour is minimal** — facing, staggered drinking timers. No
  gestures or conversation animations.
- **Individual orders within a group** are chosen and priced but flow through
  the existing per-customer service path rather than a group-specific one.

---

## Fix pass: customers stuck at the door (Aug 2026)

Two independent causes, both found from the uploaded diagnostic reports.

### 1. Doorway gridlock (the visible symptom)

Every arrival spawned at **one exact coordinate** and every departure walked to
**that same coordinate**. Arrivals and leavers converged on a single point,
avoidance jammed them together, and nobody could reach their arrival tolerance.
Groups made it far worse by putting 2–8 customers there at once.

`CustomerDoor` now spreads positions over a small disc, with a **stable
per-actor offset** — derived from the instance id, not randomised per call, so
a customer keeps the same target for its whole walk. A jittering destination
would cause constant re-pathing, which is the problem this is meant to fix.

Configurable: `spawn_spread`, `inside_spread` (the important one),
`exit_spread` on the `CustomerDoor` node.

Group members get their door targets **inside `GroupSpawner`**, not from
`GameManager` — spawning a group from the F8 debug panel bypasses `GameManager`
entirely, and members without their own points all walk to the same spot.

### 2. Seat reservation leak

`Reservable.release(actor)` **silently ignores a holder mismatch** by design.
A group reserved chairs as the *group*, then handed one to each member — but
the member later released as *itself*, so the release did nothing and the chair
stayed booked forever. The tavern lost seats one group visit at a time.

Fixed with ownership transfer:
- `Reservable.transfer_to(new_holder)` — hands a live reservation over
- `Chair.transfer_reservation()` — exposes it
- `Customer.assign_group_chair()` — takes ownership on handover
- `GroupPlace.release(members)` — releases against the group *and* its members
- `GroupManager.clear_orphaned_reservations()` — now sweeps chairs whose holder
  is invalid or belongs to a finished group

`Chair` and `CustomerDoor` now join the `chairs` and `customer_door` groups so
they are findable without scene paths.

### Note on the live test

`group_live_test` runs inside the real `main.tscn`, so the tavern's own solo
customers spawn and depart during it. The cleanup assertion is scoped to
*group* state deliberately — a chair swept because a solo customer was freed
mid-visit is the safety net working, not a group failure.

---

## Diagnostics added for the entry problem (Aug 2026)

The earlier reports could say a customer left with patience expired and nothing
served, but not **where it had got to**. A visit that never reached the door and
a visit that sat down and was ignored looked identical — and they need
completely different fixes.

`VisitRecord` now carries a lifecycle trace, exported in every report:

| Field | Answers |
|---|---|
| `state_trail` | `["1020 SPAWNED", "1021 ENTERING", …]` — exactly where the visit stopped progressing |
| `current_state` / `current_state_since_minutes` | what it is doing now, and for how long |
| `never_entered` | **the headline** — did this customer ever get inside? |
| `reached_inside_at_minutes` | when it got in, or -1 |
| `seated_at_minutes` / `first_order_at_minutes` | how far the visit got |
| `last_position_x/y`, `distance_from_door`, `distance_from_target` | where it is stuck |
| `navigation_target_label` | what it is walking toward |
| `navigation_failures` | how often its pathing was reported blocked |

Every state change in `Customer` now goes through `_set_state()` rather than
assigning `current_state` directly — a trail with gaps is worse than none,
because it makes a stuck visit look like it stopped somewhere it did not.

The trail is seeded with `SPAWNED` when the visit record is created, because a
customer enters its first state before the report manager is attached to it.

Positions are refreshed only when a report is written, so live tracking costs
nothing during play.

---

## Root cause: customers "not entering" (Aug 2026)

Found from the lifecycle trace added in the previous pass. The diagnosis was
the opposite of the symptom.

**Customers were not failing to enter. They were failing to leave.**

Six of seven active customers sat in `EXITING` for 50–120 game minutes, at
positions clustered in the doorway, reporting **zero navigation failures**.

The cause: `OutsidePoint` is **204px outside the navigation mesh**. Deliberately
so — customers should walk out of the doorway rather than vanishing inside it.
But an agent cannot report arrival at a point it can never path onto. It walked
to the mesh edge, stopped, and reported neither arrival nor failure. The visit
never ended.

Both reported symptoms follow from that one bug:

1. Customers **pile up in the doorway** — they arrive there and never leave.
2. **Nobody new comes in** — every stalled customer holds an `active_customers`
   slot, so the population limit is reached and `spawn_customer()` refuses
   every arrival.

### The fix

`Customer._physics_process()` now checks its own exit progress, the one place
it does not defer to the navigation framework:

- **`exit_arrival_radius`** (default 64px) — close enough to the exit counts as
  having left, whether or not the agent can path the last stretch.
- **`exit_timeout_minutes`** (default 5) — a customer that cannot reach the
  exit at all is removed anyway, and the reason is logged as an
  `exit_timed_out` issue. A customer holding a population slot forever is far
  worse than one that disappears slightly early.

Both are exported on the customer scene, so they can be tuned once the bar is
redesigned and the door moves.

### Guarded by

`tests/exit_stall_test.tscn` — asserts the marker/navmesh gap, that a customer
standing at the exit is removed, and that a stranded one times out.
