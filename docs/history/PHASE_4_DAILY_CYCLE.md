# Phase 4 — Daily Cycle, Modifier Framework and Demand

Foundational phase. **Stages A, C and D are complete and verified. B was already
built. E and F are deferred** — see §5.

---

## 1. Architecture summary

```text
World time changes
→ TavernLifecycle derives the operating state from the schedule
→ TavernDemandController updates the time-of-day and capacity modifiers
→ ModifierService resolves customer_arrival_rate from every contribution
→ GameManager scales its next arrival booking by that one number
→ Lifecycle gate refuses arrivals outside OPEN
→ End Day skips to the next preparation via WorldTime's existing scheduler
```

The key property: **nothing except `TavernLifecycle` and
`TavernDemandController` reads the clock to make a gameplay decision.** The
spawner asks for a demand multiplier and whether it may spawn; it has no idea
what time it is, and a festival, a storm and the evening peak all reach it
through the same number.

### Inspection finding that shaped the plan

Your `WorldTime` already owns a `TimeScheduler` with
`schedule_at/in/daily/repeating` and a `_advance_to()` that walks a skip
**event by event in chronological order**, including across days. Stage B was
therefore not built — `advance_to_next_day()` calls `WorldTime.skip_to()` and
inherits correct behaviour. Verified: an event inside a 900-minute skip fired
**exactly once**.

---

## 2. Files created

```text
systems/tavern/tavern_schedule.gd            opening hours as data
systems/tavern/tavern_lifecycle.gd           autoload `Tavern`
systems/tavern/demand_profile.gd             interpolated time-of-day curve
systems/tavern/tavern_demand_controller.gd   feeds time + capacity into modifiers
systems/modifiers/modifier.gd                one adjustment
systems/modifiers/modifier_targets.gd        validated target registry
systems/modifiers/modifier_service.gd        autoload `Modifiers`
systems/modifiers/modifier_preset.gd         an event as data
Data/tavern/default_schedule.tres            17:00 / 18:00 / 00:30 / 01:00
Data/tavern/default_demand_profile.tres      keyframed demand curve
Data/modifiers/busy_harbour.tres             test event
Data/modifiers/heavy_storm.tres              test event
tests/phase_4_daily_cycle_test.gd / .tscn    21-check suite
```

## 3. Files modified

| File | Why |
|---|---|
| `project.godot` | Registered `Modifiers` and `Tavern` autoloads. |
| `scripts/Managers/game_manager.gd` | Arrival gate on the lifecycle; demand-scaled interval; capacity/occupancy accessors; rejection reasons. |
| `scenes/main/main.tscn` | Added `Managers/TavernDemandController`. |
| `systems/time/game_time_config.gd` | `starting_hour` 8 → 17 (see §6). |
| `systems/statistics/statistics_tracker.gd` | **Pre-existing bug fix** — see §7. |

---

## 4. How to use it

**New time profile** — duplicate `default_demand_profile.tres`, edit
`keyframes` (minutes past midnight → multiplier), assign to the controller. No
code.

**New modifier**
```gdscript
var m := Modifier.create(&"my_source", ModifierTargets.CUSTOMER_SPENDING,
    Modifier.Operation.MULTIPLY, 1.2, "Reputation: renowned")
m.stacking = Modifier.Stacking.REPLACE
Modifiers.add(m)
```

**New event** — duplicate `busy_harbour.tres`, edit `entries`. Apply with
`for m in preset.build_modifiers(): Modifiers.add(m)`; end with
`Modifiers.remove_source(preset.preset_id)`.

**New target** — add a constant to `ModifierTargets` and list it in
`get_all()`. Unregistered targets warn at creation rather than failing silently.

**Requesting a value**
```gdscript
var rate := Modifiers.evaluate(ModifierTargets.CUSTOMER_ARRIVAL_RATE, 1.0)
print(Modifiers.explain_text(ModifierTargets.CUSTOMER_ARRIVAL_RATE, 1.0))
```

**Operation order** (documented and tested):
base → **ADD** → **MULTIPLY** → **MIN/MAX clamps** → **OVERRIDE** (highest
priority, absolute).

**Skipped-time events** — `WorldTime.schedule_in(minutes, callable, tag)`. They
fire during any skip automatically.

---

## 5. Stages completed and deferred

| Stage | Status |
|---|---|
| A — schedule and lifecycle | **Complete** |
| B — end-day and skipped time | **Already existed**; verified and wired |
| C — modifier framework | **Complete** |
| D — demand profiles and arrival controller | **Complete** |
| E — type weighting, group size, stay duration | **Deferred**. Framework and targets exist; the customer-selection call site is not yet routed through `CUSTOMER_TYPE_WEIGHT`. |
| F — dev controls, debug panel, full JSON export | **Deferred**. `build_report_section()` exists on the lifecycle, modifier service and demand controller, but is not yet wired into the F10 panel or the report managers. |

Deferred honestly rather than stubbed: E and F are call-site wiring, and doing
them badly would create exactly the disposable code the brief warned against.

---

## 6. Behavioural change worth knowing

`starting_hour` moved from 08:00 to 17:00. Under the new schedule a game
starting at 08:00 begins in `CLOSED` and sits dead for nine game hours, which
reads as a broken build. 17:00 starts at preparation, one hour before opening.

---

## 7. Warnings found in the existing project

**`statistics_tracker.gd:90` accessed `stamp.day`**, but `GameTimeStamp`
exposes `get_day()` and has no `day` property. This threw
`Invalid access to property or key 'day'` on **every day rollover** — latent
because nothing previously crossed midnight in a test. Fixed to
`stamp.get_day()`.

---

## 8. Test results

**Phase 4 suite: 21/21 passed.** Covers schedule maths at 7 time points,
midnight crossing (23:50 → 00:30 = 40 minutes), a full day entering all five
states in order, operation order, override precedence, re-triggering an event
without compounding, `remove_source()`, tag-scoped modifiers, expiry during a
time skip, misspelt-target detection, profile interpolation, the arrival gate,
and End Day skipping 900 minutes with a scheduled event firing exactly once.

**Regressions:** `phase_3a2_integration_test` 16/16. `phase_3a_smoke_test`
29 passed / 1 failed — scenario C fails because the bartender has filled every
bar slot, so the test cannot place its own drink. Test drift, not a lifecycle
regression; scenarios A, B, D–L still pass.

Project imports and runs with **no parser errors and no runtime errors**.

---

## 9. Manual test plan

1. Start a new game — should begin at 17:00 in `PREPARING`, no customers.
2. Wait to 18:00 — "The tavern is now open", customers begin arriving.
3. Watch arrivals through the evening — frequency should rise towards 21:00.
4. Fill the tavern — arrivals should taper, not stop dead, then recover.
5. At 00:30 — "Last orders!", no new arrivals, those inside continue.
6. At 01:00 — closing; nobody is deleted.
7. At 01:30 — closed; End Day becomes available.
8. `Tavern.end_day()` then `Tavern.advance_to_next_day()` — skips to 17:00.
9. Place a stock order before ending the day; confirm it arrives during the skip exactly once.
10. Apply `busy_harbour.tres` twice; confirm demand does not compound.

---

## 10. Known limitations

- **Stage E is not wired.** `choose_customer_type()` still uses raw `spawn_weight`. The target and scoping are proven by test, but archetypes have no tags yet, so a "sailors ×2" event has nothing to match on.
- **No dev controls or debug panel yet** (Stage F). Actions are callable from code and tests but not exposed in the F10 panel.
- **Group size and stay duration** are not yet routed through the framework.
- **No end-of-day UI.** `build_day_summary()` returns the data; nothing displays it.
- Day-summary figures are limited to what the project genuinely tracks — wages, rent and net result are deliberately absent rather than invented.
- The demand profile's default keyframes are **not balanced values**.
