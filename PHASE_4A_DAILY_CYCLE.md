# Phase 4A — Complete and Expose the Daily Cycle

**Stages 1, 2, 3 (partial) and 5 (partial) implemented and verified.
Stage 4 deferred.** Status per feature in §5.

**No project ZIP was attached to this request.** This continues from the
Phase 4 build I produced previously. If you have a newer build, re-send it.

---

## 1. What was implemented

| Stage | Status |
|---|---|
| 1 — Core lifecycle integrity | **Complete** |
| 2 — Statistics and frozen summary | **Complete** (data layer + F10 view; no dedicated screen) |
| 3 — HUD, countdowns, warnings | **Partial** — HUD and warnings done; preparation assessment deferred |
| 4 — Modifier target completion | **Deferred** |
| 5 — Developer tooling | **Partial** — F10 controls done; health checks deferred |

---

## 2. Lifecycle states and transition rules

```text
PREPARING  →  OPEN  →  LAST_ORDERS  →  CLOSING  →  CLOSED
                                                     ↓ end_day()
                                              END_OF_DAY  (summary frozen)
                                                     ↓ advance_to_next_day()
                                                 PREPARING (next day)
```

`END_OF_DAY` and `READY_FOR_NEXT_DAY` are separate states because the player
is *reading* the summary in the first, and the move out of it is theirs.

**State is derived, not driven by timers.** `_evaluate()` recomputes from the
clock, so a skip, a speed change, a save loaded mid-evening or a developer
jump all reach the right state by one path.

**Manual actions raise a floor.** `open_early()` would otherwise be undone by
the next evaluation noticing it is still 17:30. The floor clears on a new day.

### Last orders and closing rules (as implemented)

- Normal arrivals **stop** at last orders (`is_accepting_arrivals()` is true only in `OPEN`).
- Seated customers may still order (`is_accepting_orders()` covers `OPEN` and `LAST_ORDERS`).
- No arrivals during closing.
- Closing runs for `closing_grace_minutes` (default 30) then becomes `CLOSED`.
- **Nobody is deleted at closing.**

---

## 3. Idempotency and cleanup

`end_day()` and `advance_to_next_day()` are safe to press repeatedly —
**verified by test**:

- A second or third `end_day()` returns the *same* frozen record.
- Recording sales after the freeze does not move the frozen summary, but live counters keep updating behind it.
- `advance_to_next_day()` refuses unless a day was actually ended.

**Cleanup rule on Start Next Day:** remaining customers are sent home through
their own `finish_customer()` departure path, *not deleted*. Staff tasks
referring to them invalidate through ordinary task-board validation. The count
is reported in the return value and the event history.

**Reset scope:** per-day counters, warning flags, announcements and the frozen
summary. **Money, stock and progression are untouched.**

---

## 4. Daily statistics

`DailyStatistics` is owned by `TavernLifecycle` — one trading day in progress,
one owner. `StatisticsTracker` keeps lifetime totals and is unchanged.

Tracked: sales income, tips, total income, drinks sold, sales and income by
item, stock used by item, customers served, customers lost **split by reason**
(patience / no seating / no stock), groups served and lost, breakages,
deliveries, arrivals rejected, service start/end and duration, peaks, average
spend, average tip, service rate.

Everything is recorded from gameplay events. Nothing is derived by scanning UI
or the scene tree, and the record contains **no node references**, so it
survives the customers being freed and is already save-ready.

`freeze()` latches a deep copy. `get_record()` returns the frozen record once
finalised; `build_record()` is the live view.

---

## 5. Deferred, honestly

- **Stage 4 (modifier targets)** — customer-type weighting, group size and visit duration are still not wired. This needs `CustomerType` to carry **tags** first, which it does not; a "more sailors" event has nothing to match on. The framework and scoping are proven by test.
- **Preparation assessment service** (§5 of the brief) — not built.
- **End-of-day summary screen** — the frozen record exists and is viewable via F10; there is no dedicated UI screen.
- **Health checks** (§13) and the **expanded diagnostic export** (§12) — `build_report_section()` returns the data but is not wired into the report managers, and no health-check validator exists.
- **Save/load** — records are structured for it; no persistence written.

---

## 6. F10 controls added

**Daily Cycle:** show status; jump to preparation / opening / peak / last
orders / closing; open now; last orders now; close now; advance to next
transition; end day; show summary; start next day.

Jumps use `WorldTime.skip_to()`, not `set_time()`, so every transition and
scheduled event between here and there still fires — a developer jump
exercises the systems being tested rather than stepping around them.

**Demand & Modifiers:** show breakdown; force low/high/peak; clear override;
trigger Busy Harbour; trigger Heavy Storm; list active modifiers; clear all
(marked dangerous).

**Daily Statistics:** show today's totals; add test sale / breakage / customer
served / customer lost.

Every button calls a public API. None writes to another system's internals.

---

## 7. HUD

A single line that changes shape with the state, built in code (no scene edit):

```text
17:42  |  Day 1  |  Preparation - opens in 18 min
19:05  |  Day 1  |  Open - busy  |  last orders in 5h 25m
00:41  |  Day 1  |  Last orders - 19 min remaining
```

Event-driven plus a per-minute tick. Countdowns never show negative values.

**Transition warnings** are configured on the schedule
(`warning_offsets_minutes`, default `[60, 30, 10]`) and fire once each per
transition per trading day, cleared on a new day. They use the existing
`Comms` notification system.

---

## 8. Bugs found and fixed

**The lifecycle only re-evaluated on `minute_passed`.** Any direct clock
manipulation — `set_time()`, a loaded save, a developer jump backwards — left
the state stale. This is precisely the "lifecycle state does not match current
time" fault §13 asks for a health check on. Now also listens to `time_changed`.

Caught by a test that set the clock backwards and found `end_day()` refusing
while the clock said 02:00.

---

## 9. Test results

**Phase 4 suite: 27/27 passed.** Schedule maths at 7 time points, midnight
crossing, full-day walk through all five trading states, modifier operation
order, override precedence, non-compounding re-triggered events,
`remove_source()`, tag scoping, expiry during a skip, misspelt-target
detection, profile interpolation, arrival gating, End Day skipping 900 minutes
with a scheduled event firing exactly once, **end_day idempotency across three
calls**, **frozen summary immutability**, live counters continuing behind the
freeze, per-day reset, and repeat-press guarding.

**Regression:** `phase_3a2_integration_test` 16/16.

Project imports and runs with **no parser errors and no runtime errors**.

---

## 10. Configuration

`Data/tavern/default_schedule.tres` — times, closing grace, early-open/close
permissions, **warning offsets**.
`Data/tavern/default_demand_profile.tres` — keyframed demand curve.
`Data/modifiers/*.tres` — event presets.
`systems/time/game_time_config.gd` — `starting_hour` (17).

---

## 11. Recommended next work

1. **Add `tags` to `CustomerType`** and wire `CUSTOMER_TYPE_WEIGHT`. This unblocks Stage 4 entirely and is the single highest-value next step.
2. **Preparation assessment service** — the checks are all readable from existing systems.
3. **End-of-day summary screen** reading the frozen record.
4. **Health checks and report wiring** — the data exists; it needs a validator and a hook into the report managers.
