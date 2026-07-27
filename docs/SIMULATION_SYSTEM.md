# World Time and Simulation System

## Design goal

Two frameworks, deliberately separate, that together answer the only two
questions a simulation ever asks:

```text
Should anything be happening right now?   ->  Simulation
What time is it, and what happens next?   ->  WorldTime
```

Every future system — deliveries, shifts, production, opening hours, festivals,
economy, NPC routines — is a consumer of these two and owns no clock of its own.
A gameplay `Timer` keeps running when the game is paused, ignores time speed,
cannot be skipped and cannot be saved. That is why the rule is absolute:
**anything representing world progression books with `WorldTime` instead.**

---

## Class map

```text
systems/simulation/

SimulationState        enum + stable ids. Vocabulary only.
SimulationStateRules   Resource: what each state permits.
SimulationController   autoload "Simulation". Current state, stack, signals.

systems/time/

GameTimeConfig         Resource: calendar, rate, speeds, formatting.
GameTimeStamp          value object: a moment. Compares, adds, formats.
WorldClock             the time model. Plain object, no node, no signals.
TimeFormatter          static: moments and durations into text.
ScheduledTimeEvent     one booking, returned as a cancellable handle.
TimeScheduler          the booking system. "Call me at this world time."
WorldTime              autoload. Drives the above, announces what happened.
SimulationDebugPanel   development read-out. Reads public APIs only.
```

**Dependency direction**, which is the part that keeps this reusable:

```text
gameplay  ──>  WorldTime  ──>  WorldClock
                   │       └>  TimeScheduler  ──>  ScheduledTimeEvent
                   │
                   └──────>  Simulation        (asks "may I advance?")

gameplay  ──>  Simulation  ──>  SimulationStateRules
```

`Simulation` knows nothing about time. `WorldTime` asks it for permission. That
one-way arrow is why fast-forward, dialogue and cutscenes can be added later
without either framework learning about the other's internals.

---

## Architectural decisions

### The clock is not the autoload

`WorldClock` is a plain `RefCounted`. `WorldTime` is a thin node that owns one.

The autoload should be one instance of the *driver*, not one instance of the
*concept*. Keeping the model separate means it can be unit tested without a
scene tree, serialised directly, and — occasionally useful — instantiated a
second time to answer "what day would it be after three more shifts" without
disturbing the world.

### One integer is the whole state

`total_minutes` is the only mutable value. Day, hour and minute are always
derived, never stored, so they cannot drift apart. Comparison is integer
comparison, and a save file is one number.

### Time never runs backwards

`advance_minutes()` refuses negative values and `skip_to()` refuses a moment in
the past. Every "has this happened yet" check in the game depends on it.
`set_time()` exists for save loading and debug jumps and is documented as not
firing anything in between.

### Speed is a property; fast-forward is a state

They are separate but coordinated. `WorldTime` listens for the simulation
entering `FAST_FORWARD`, remembers the player's chosen speed, applies
`fast_forward_speed_multiplier`, and restores the old speed on leaving. So
fast-forwarding and then stopping returns the player to *their* speed rather
than snapping to normal.

### Two levels of pause, on purpose

```text
Simulation.pause()    the game stops. Time, AI, input, production.
WorldTime.pause()     only the clock freezes. Everything else continues.
```

The second is for debugging and for a future cutscene that wants the world
visible and animating while the day does not advance. The debug panel shows
both, because collapsing them would hide exactly the bug it exists to catch.

### `get_tree().paused` is not used

Engine pause is all-or-nothing and is opted out of node by node. A management
game needs finer answers — UI keeps running while actors freeze, animation may
or may not follow the clock. `SimulationController.mirror_to_engine_pause`
exists for systems that genuinely want the engine flag, and is off by default.

---

## Signals versus the scheduler

**The single most important distinction in this framework.**

```text
signals     react to the moment the world is in NOW.
            A large skip collapses them, so a listener may miss one.

scheduler   never misses. Every booking inside a skipped window fires,
            in order, with the clock standing at the booked moment.
```

A HUD reads signals. A wage payment, a delivery, a production run books with the
scheduler.

Why signals collapse: emitting `minute_passed` across a three-day skip would be
over four thousand emissions to tell listeners something they can read from the
clock in one call. Beyond `maximum_stepped_minutes` (default 120) `WorldTime`
emits `time_skipped(from, to)` plus one `hour_changed` and one `day_changed`
instead.

Why the scheduler does not collapse: `_advance_to()` steps the clock, pausing at
every booked event on the way, rather than jumping and then firing. An event
booked for 09:00 runs with the clock reading 09:00, not with the clock already
at 17:00. A day's worth of wages, deliveries and reports therefore happen in the
right order and see the right world.

---

## Signal flow

```text
_process(delta)
    └── can_advance()?          Simulation.is_running() and not time paused
        └── accumulate real seconds into whole game minutes
            └── advance_minutes(n)
                └── _advance_to(target)
                     │
                     ├── scheduler.process_until(now)     fire anything due
                     ├── step clock to the next booking, or to the target
                     ├── _emit_advancement_signals(from, to)
                     │      ├── small step:  minute_passed x n
                     │      │                hour_changed / day_changed as crossed
                     │      └── large step:  time_skipped + one boundary each
                     └── repeat until the target is reached
                     │
                     └── time_changed        once, at the end
```

### WorldTime signals

| Signal | Fires |
|---|---|
| `minute_passed(stamp)` | every in-game minute, ordinary advancement only |
| `hour_changed(stamp)` | the hour reading changed |
| `day_changed(stamp)` | the day reading changed |
| `time_changed(stamp)` | once after any advance, however large |
| `time_skipped(from, to)` | a jump beyond `maximum_stepped_minutes` |
| `speed_changed(multiplier)` | speed was changed |
| `time_paused_changed(is_paused)` | the clock was frozen or unfrozen |

### Simulation signals

| Signal | Fires |
|---|---|
| `state_changed(previous, current)` | any transition |
| `capabilities_changed` | any transition — for "may I update" listeners |
| `simulation_started` | entered a time-advancing state from one that was not |
| `simulation_paused` | entered `PAUSED` |
| `simulation_resumed` | left `PAUSED` for a running state |

---

## Public API

### WorldTime

```gdscript
# reading
WorldTime.get_timestamp() -> GameTimeStamp     # preferred
WorldTime.get_day() / get_hour() / get_minute() / get_total_minutes()
WorldTime.get_day_progress() -> float          # 0.0 at midnight, 1.0 at the next
WorldTime.get_clock_text() / get_full_text()

# moving
WorldTime.advance_minutes(minutes)
WorldTime.skip_to(day, hour, minute)
WorldTime.skip_to_next_hour() / skip_to_next_day()
WorldTime.set_time(day, hour, minute)          # jump; fires nothing in between

# pause and speed
WorldTime.pause() / resume() / toggle_pause() / is_paused()
WorldTime.set_speed(multiplier) / set_speed_index(i) / cycle_speed()
WorldTime.get_speed() / get_speed_text()

# scheduling
WorldTime.schedule_in(minutes, callback, tag)      -> ScheduledTimeEvent
WorldTime.schedule_at(stamp, callback, tag)        -> ScheduledTimeEvent
WorldTime.schedule_daily(hour, minute, cb, tag)    -> ScheduledTimeEvent
WorldTime.schedule_repeating(interval, cb, tag)    -> ScheduledTimeEvent
WorldTime.cancel_scheduled(event) / cancel_scheduled_tag(tag)

# internals, for tools and save code
WorldTime.get_clock() / get_scheduler() / get_config()
```

### Simulation

```gdscript
Simulation.get_state() -> SimulationState.State
Simulation.set_state(state)          # hard transition, clears the stack
Simulation.push_state(state)         # overlay, remembers what it interrupted
Simulation.pop_state() -> bool       # restore
Simulation.pause() / resume() / toggle_pause()

Simulation.is_running()      # should the clock advance
Simulation.is_paused()
Simulation.accepts_input()   # may the player act on the world
Simulation.updates_actors()  # should AI think and move
Simulation.shows_world()     # is the world on screen
Simulation.get_state_name()
```

---

## Simulation state flow

```text
LOADING ──> MAIN_MENU ──> PLAYING <──> FAST_FORWARD
                             │
                             ├── push ──> PAUSED    ── pop ──┐
                             ├── push ──> DIALOGUE  ── pop ──┤
                             └── push ──> CUTSCENE  ── pop ──┘
                                            back to whatever was underneath
```

**Why a stack.** A conversation opening over play, a menu over a conversation, a
cutscene over a menu — each wants to suspend what was happening and put it back
exactly as it was. Callers that `push_state` and `pop_state` never have to
remember what they interrupted, which is what stops "resume" bugs.

**What each state permits** is data, in `Data/simulation/default_state_rules.tres`:

| State | advances time | accepts input | updates actors | shows world |
|---|---|---|---|---|
| `loading` | | | | |
| `main_menu` | | | | |
| `playing` | yes | yes | yes | yes |
| `paused` | | | | yes |
| `fast_forward` | yes | yes | yes | yes |
| `dialogue` | | | | yes |
| `cutscene` | | | yes | yes |

Listing state ids per capability, rather than a boolean per state per
capability, keeps this readable and means adding a state does not add three more
exports. A state absent from a list simply does not have that capability.

**No system decides for itself whether it should update.** It asks.

---

## How future systems subscribe

Four patterns cover essentially everything the game will need.

### 1. Something happens at a fixed time every day

Opening hours, closing time, a supplier's rounds, a daily report.

```gdscript
func _ready() -> void:
    WorldTime.schedule_daily(9, 0, _open_tavern, &"tavern_opening")
    WorldTime.schedule_daily(23, 0, _close_tavern, &"tavern_closing")
```

Survives skips, speed changes and pauses. No comparison logic, no `_process`.

### 2. Something takes a length of world time

Production, brewing, a delivery in transit, a crafting run.

```gdscript
func start_brewing(recipe: BrewRecipe) -> void:
    _current_run = WorldTime.schedule_in(
        recipe.duration_minutes,
        _on_brewing_finished,
        &"brewing"
    )

func cancel_brewing() -> void:
    WorldTime.cancel_scheduled(_current_run)
```

This is the direct replacement for a gameplay `Timer`, and the reason to prefer
it: a forty-minute brew takes forty *in-game* minutes whether the player is at
normal speed, at six times speed, or skipped the afternoon entirely.

### 3. Something recurs on an interval

Economy ticks, reputation decay, ambient events.

```gdscript
WorldTime.schedule_repeating(30, _apply_upkeep, &"upkeep")
```

### 4. Something reacts to the current moment

A HUD, a lighting curve, a mood system.

```gdscript
func _ready() -> void:
    WorldTime.time_changed.connect(_on_time_changed)
    WorldTime.day_changed.connect(_on_day_changed)

func _on_time_changed(stamp: GameTimeStamp) -> void:
    label.text = TimeFormatter.format_day_and_clock(stamp)
```

### Systems that must stop when paused

```gdscript
func _physics_process(delta: float) -> void:
    if not Simulation.updates_actors():
        return
    ...
```

Or, better, react once to `capabilities_changed` rather than checking every
frame.

### Cleaning up

A booking whose target object has been freed retires itself — customers and
staff are removed constantly, and a schedule outliving its owner should go
quietly. Doing it explicitly is still cheaper and clearer:

```gdscript
func _exit_tree() -> void:
    WorldTime.get_scheduler().cancel_all_for(self)
```

---

## Rules for gameplay systems

1. **Never create a `Timer` for world progression.** Book with `WorldTime`.
2. **Never store your own day/hour/minute.** Store a `GameTimeStamp`, or store
   nothing and ask.
3. **Never decide for yourself whether to update.** Ask `Simulation`.
4. **Never format time yourself.** Use `TimeFormatter`, so a twelve-hour option
   or a translation is one change in one place.
5. **Use signals to react, the scheduler to not miss.** If missing it would be a
   bug, book it.
6. **Tag your bookings.** `&"delivery_window"` costs nothing and makes both the
   debug panel and save/load legible.

---

## Save and load

Both frameworks are already serialisable. Nothing needs refactoring when save
code arrives.

```gdscript
var save_data: Dictionary = {
    "world_time": WorldTime.to_dictionary(),
    "simulation": Simulation.to_dictionary(),
}

WorldTime.apply_dictionary(save_data["world_time"])
Simulation.apply_dictionary(save_data["simulation"])
```

`WorldTime.to_dictionary()` stores the minute count, the speed, the pause flag
and a listing of pending bookings. `Simulation.to_dictionary()` stores the
current state id and the suspended stack, by **stable string id** rather than
enum integer — so inserting a state later cannot silently change the meaning of
an existing save.

### Why scheduled callbacks are not restored automatically

A `Callable` cannot be serialised. Restoring one would mean a save file naming
methods on live objects, which breaks the moment anything is renamed and is a
security problem the day mods exist.

The correct pattern, and the one the framework is built around:

```text
on load:
    1. WorldTime.apply_dictionary(...)      restores the moment
    2. each system re-registers its own schedules in _ready
    3. schedule_daily() books the NEXT occurrence from the restored time
```

A tavern that opens at 09:00 re-books itself correctly because
`next_daily_occurrence()` works from whatever time was loaded. A production run
mid-flight is the one case needing care: the system saves its own finish
timestamp and calls `schedule_at()` with it, which is one line and is honest
about where that state belongs — with the brewery, not with the clock.

The serialised event listing exists so that a save can be inspected and so a
future system could reconcile against it, not because it is replayed.

---

## Configuration

`Data/time/default_time_config.tres`

| Property | Default | Effect |
|---|---|---|
| `minutes_per_hour` | 60 | Length of an hour. Nothing assumes 60. |
| `hours_per_day` | 24 | Length of a day. Nothing assumes 24. |
| `starting_day` / `starting_hour` / `starting_minute` | 1 / 8 / 0 | New game start |
| `game_minutes_per_real_second` | 1.0 | The one number that decides how long a day feels |
| `available_speed_multipliers` | 1, 2, 4 | What the player can cycle |
| `default_speed_index` | 0 | Speed a new game starts on |
| `fast_forward_speed_multiplier` | 6.0 | Applied by the fast-forward state |
| `maximum_stepped_minutes` | 120 | Above this, minute signals collapse |
| `use_24_hour_clock` | true | 14:30 versus 2:30 pm |
| `day_label_format` | `"Day %d"` | Day label, ready for translation |

`Data/simulation/default_state_rules.tres` holds the capability table above.

There are no hard-coded time constants anywhere in the framework.

---

## Debug panel

Bottom-left of the HUD, toggled with **F1**.

```text
Day 1
08:30
Speed x1
State: Playing
Paused: No   Time frozen: No
Scheduled: 3   next in 45m
[F1] panel   [F2] pause   [F3] speed   [F4] skip hour
```

| Key | Action |
|---|---|
| F1 | Toggle the panel |
| F2 | `Simulation.toggle_pause()` |
| F3 | `WorldTime.cycle_speed()` |
| F4 | `WorldTime.skip_to_next_hour()` |

The panel reads the two public APIs and nothing else, so it doubles as a worked
example. If it ever needs a private hook, that is a sign the public API is
missing something.

---

## What is wired in today

The framework is not a passenger. Gameplay runs on it.

### Pause

`Simulation.pause()` (F2) freezes everything, the player included:

| System | How it stops |
|---|---|
| World clock | `WorldTime.can_advance()` |
| AI actors | `ActorNavigation._physics_process` returns on `updates_actors()` |
| Player | `player.gd` returns on `accepts_input()` |
| Timed actions | `ActionRunner` accumulates world delta, which is zero |
| Interaction selection | `InteractionSelector._process` returns on `accepts_input()` |
| Customer orders, drinking, patience | scheduler bookings; the clock is stopped |
| Customer spawning | scheduler booking |

`ActorNavigation` returns *without* calling `movement.apply()`, so a paused
actor keeps its velocity and resumes mid-stride rather than restarting from a
standstill. `InteractionSelector` freezes rather than clearing, so unpausing
does not flicker the selection back into place.

### Speed

**The world scales; the player does not.** Time speed makes the tavern run
faster while the player keeps walking at a constant real pace, so serving stays
precise during fast-forward.

`ActorMovement` reads `WorldTime.get_world_time_scale()`. All of its
acceleration and settling maths runs in unscaled "logical" space, so
`settle_speed` and the arrival curve mean the same thing at any speed; only the
velocity handed to `move_and_slide()` is scaled, and it is restored immediately
after. `follows_world_time` is exported and defaults to true — the player has no
`ActorMovement`, and any future real-time actor sets it false.

Because the scale is zero when the world is not advancing, the same code gives
freezing for free rather than needing a separate pause branch.

### Durations

Every gameplay duration is now world time, and every gameplay `Timer` node is
gone:

| Was | Now |
|---|---|
| `CustomerType.order_delay` (real seconds) | `order_delay_minutes` |
| `CustomerType.patience_duration` | `patience_duration_minutes` |
| `DrinkDefinition.drink_duration_seconds` | `drink_duration_minutes` |
| `GameConfig.minimum/maximum_spawn_delay` | `..._spawn_delay_minutes` |
| `OrderTimer`, `DrinkTimer`, `PatienceTimer` | `WorldTime.schedule_in()` |
| `CustomerSpawnTimer` | `WorldTime.schedule_in()` |

The conversion is 1:1 and therefore neutral at normal speed: one game minute is
one real second at the default rate, so a 15-second patience became 15 world
minutes and feels identical. The whole game's pace is now tuned from the single
`game_minutes_per_real_second` value.

The patience bar reads `get_total_minutes_precise()` rather than whole minutes,
so it slides smoothly instead of stepping once a second.

Bookings are tagged — `customer_order`, `customer_drinking`,
`customer_patience`, `customer_spawn` — so the debug panel's pending count is
legible and `cancel_scheduled_tag()` works.

### The one balance change

`sailor_impatient.tres` had `order_delay = 1.5`. The scheduler works in whole
minutes, so this became `order_delay_minutes = 2`. Everything else converted
exactly.

## Future expansion

Things that fit the existing seams, roughly in order of value:

**Opening hours** — two `schedule_daily` calls and a `bool is_open`. The
spawner already books through `WorldTime`, so a closed tavern simply does not
re-book. `GameManager.schedule_next_customer()` is the whole hook.

**Daily economy report** — `schedule_daily(23, 59, ...)` reading
`EconomyManager`. The framework part is one line.

**Staff shifts** — a `ShiftDefinition` resource holding start and end hours,
booked with `schedule_daily`. Staff reuse the navigation framework to walk to
their station and the interaction framework to work it; this framework decides
*when*.

**Production and brewing** — `schedule_in` plus the item framework. The three
pillars already meet here.

**Deliveries** — `schedule_daily` for the supplier's rounds, `schedule_at` for a
specific ordered consignment.

**Seasons and festivals** — `GameTimeStamp` already derives day number; a season
is `(day - 1) / days_per_season`. Add `days_per_season` to the config and a
`season_changed` signal to `WorldTime`.

**Time-of-day lighting** — `get_day_progress()` returns 0.0 to 1.0 across a day,
ready to drive a gradient. Deliberately not implemented.

**Weather** — a `schedule_daily` roll plus a `WeatherState` resource. Weather
becomes another consumer, not another clock.

**Save/load** — as above.

**A second calendar** — a dream sequence, a flashback or a tutorial that runs at
a fixed hour needs a second `WorldClock` instance, which is possible precisely
because the model is not the autoload.

---

## What changed from the old `GameTime`

The previous system worked and its time maths was sound. What it lacked was
everything around the edges:

| Old | Now |
|---|---|
| `MINUTES_PER_HOUR` / `HOURS_PER_DAY` as script constants | config properties |
| `advance_minutes` looped one minute at a time, emitting per minute | batched, with collapse above a configurable threshold |
| No scheduling — every future system would hand-roll `_on_hour_changed` | `TimeScheduler` |
| Formatting baked into the clock | `TimeFormatter` |
| Model and autoload were the same object | `WorldClock` is a plain object |
| No simulation state at all | `SimulationController` |
| Pause was time-local only | two deliberate levels |
| Day/hour/minute passed as three loose ints | `GameTimeStamp` |
| No serialisation | `to_dictionary()` / `apply_dictionary()` on both |

`is_between_hours()` survives, on `GameTimeStamp`, and still handles windows
that wrap past midnight.

---

## Gotchas

**Autoload order matters.** `Simulation` is registered before `WorldTime`
because `WorldTime._ready()` connects to it. Do not reorder them.

**The initial state transition is deferred.** `SimulationController` applies
`initial_state` on a deferred call so that every other autoload and the first
scene are listening. Without it the very first `state_changed` would be emitted
into an empty room.

**`set_time()` fires nothing in between.** It is for loading and debugging. Use
`advance_minutes()` or `skip_to()` when scheduled events should be honoured.

**Bookings are handles, not callables.** Keep the `ScheduledTimeEvent` returned
to you if you might cancel, or use a tag and `cancel_scheduled_tag()`.

**A repeating booking with a tiny interval crossed by a huge skip** is bounded
per pump. Anything left over fires on the next frame rather than locking one.
