# Phase 3A.1 — Staff Refinement

A focused correctness and diagnostics pass over the Phase 3A staff, task,
carried-item and reporting systems. The Phase 3A architecture was kept; nothing
was redesigned that was working.

---

## 1. Summary of changes

| Area | What changed |
|---|---|
| Carried items | A reusable policy + recovery service decides what happens to something left in a worker's hands. A worker can no longer start an incompatible task while carrying a drink. |
| Task viability | Serving tasks are now estimated against the customer's remaining patience. Clearly impossible work is skipped; merely tight work is penalised, not refused. |
| Claiming | Same-worker reclaim cooldown, a task-switch score margin and a minimum commitment window remove the tightest oscillation loops. |
| State machine | Idle no longer re-decides to walk home on every interval. A new `RECOVERING_ITEM` state separates "putting a drink back" from "walking to a customer". |
| Transition reasons | `StaffTransitionReason` replaces the generic string `"transition"` everywhere. |
| Diagnostics | Per-decision records, per-task-type aggregates, cancellation-reason counts, viability distribution and grouped state transitions added to the exported report. |
| Alerts | Untouched. Verified unchanged by the Phase 3A regression suite. |
| Navigation | Untouched. No navigation change was made — see section 15. |

---

## 2. Root causes identified

### 2.1 The worker cleaned tables while holding a customer's ale

Confirmed by reading the code, not inferred from the report.

`StaffMember._tick_idle()` asked the board for a task **first**, and only dealt
with a leftover carried item if the board returned nothing:

```text
_tick_idle()
  → TaskBoard.select_best_task()      ← runs first
  → if a task was found: take it      ← cleaning is happily claimed here
  → else if carrying: put it down     ← only reached when the board is empty
```

`CleanSeatExecutor.can_claim()` had no carried-item check, because cleaning
genuinely does not need an item — so nothing anywhere refused the combination.
A serving task cancelled after collection therefore left the worker free to
claim cleaning with the drink still in hand, and the scoring bonus for "already
carrying the right drink" meant it kept hold of it indefinitely.

### 2.2 Urgency scoring actively selected doomed work

The score was `priority + urgency + age − distance + carrying − failures`.
Urgency for a serving task is how far the customer's patience has run down, so
**the most urgent customer is very often the one about to leave**. With no
counterweight, the worker preferentially chased exactly the customers it was
least likely to reach in time.

### 2.3 Idle oscillation was a re-decision loop, not indecision

`EVALUATING_TASKS → RETURNING_TO_IDLE → EVALUATING_TASKS` repeated because an
idle worker re-decided to walk home on every evaluation interval **while
already walking home**. Each re-decision restarted the state transition.

### 2.4 The report could not explain anything

Every `_set_state()` call recorded the literal reason `"transition"`, so a
reader could see a worker move between two states hundreds of times with no way
to find out why.

---

## 3. Files added (11)

```text
systems/staff/staff_transition_reasons.gd     central reason constants
systems/staff/carried_item_policy.gd          Resource: recovery rules
systems/staff/carried_item_recovery.gd        plan/execute recovery service
systems/staff/tasks/task_viability_config.gd  Resource: viability tuning
systems/staff/tasks/task_viability.gd         the estimator itself
Data/staff/carried_item_policy.tres           Tavern Hand's policy instance
Data/staff/task_viability_config.tres         tuned viability values
tests/phase_3a1_refinement_test.gd/.tscn      21-check automated suite
tests/phase_3a1_benchmark.gd/.tscn            A/B overload benchmark
```

---

## 4. Files modified (15)

| File | Why |
|---|---|
| `systems/staff/staff_member.gd` | Hands-before-work ordering; carried-item recovery; `RECOVERING_ITEM` state; reasons on every transition; idle oscillation fix; new counters; removed the superseded `_begin_returning_carried_item()` / `_find_free_service_slot()` pair. |
| `systems/staff/tasks/tavern_task_service.gd` | Viability gate and long-shot fallback in selection; carried-item compatibility check; reclaim cooldown; switch margin; decision records; aggregate report sections; cancellation-reason counts; invested-time banking. |
| `systems/staff/tasks/tavern_task.gd` | Viability cache, path-estimate cache, `invested_minutes`, release provenance; exposed in `to_dictionary()`. |
| `systems/staff/tasks/tavern_task_definition.gd` | `CarriedItemRule` enum and `viability_weight`. |
| `systems/staff/tasks/tavern_task_board_config.gd` | Viability, commitment and decision-logging settings. |
| `systems/staff/executors/staff_task_executor.gd` | Estimation hooks (`get_deadline_minutes`, `estimate_travel_pixels`, `get_interaction_count`, `estimate_action_seconds`) and the default `is_compatible_with_carried_item()` rule. |
| `systems/staff/executors/serve_drink_executor.gd` | Real deadline (patience) and two-leg travel estimate. |
| `systems/staff/executors/clean_seat_executor.gd` | No deadline; travel estimate; action duration from the `ActionDefinition`. |
| `systems/staff/staff_definition.gd` | `carried_item_policy` reference. |
| `systems/staff/diagnostics/staff_report_manager.gd` | `state_transitions` section grouped by from/to/reason. |
| `scripts/Entities/customer.gd` | `get_patience_remaining_minutes()` — the deadline viability measures against. |
| `Data/staff/task_board_config.tres` | Wires the viability resource and commitment defaults. |
| `Data/staff/tavern_hand.tres` | Wires the carried-item policy. |
| `Data/staff/tasks/serve_drink.tres` | `carried_item_rule = REQUIRES_MATCHING_OR_EMPTY`. |
| `Data/staff/tasks/clean_seat.tres` | `carried_item_rule = REQUIRES_EMPTY_HANDS`. |

---

## 5. Files requiring deletion

**No files need to be deleted.**

One *function pair* was removed (`StaffMember._begin_returning_carried_item()`
and `_find_free_service_slot()`), replaced by `CarriedItemRecovery`. That is a
change inside a modified file, not a file deletion. Having two mechanisms
decide where a drink belongs is precisely how they drift apart, so the old one
was deleted rather than left in place.

---

## 6. Carried-item recovery behaviour

Two independent defences, so neither alone is load-bearing.

**Defence one — ordering.** `_tick_idle()` deals with the hands before it looks
for work.

**Defence two — a data-driven gate.** `TavernTaskDefinition.carried_item_rule`:

| Rule | Meaning |
|---|---|
| `REQUIRES_MATCHING_OR_EMPTY` | Hands empty, or holding exactly the required item. Default. |
| `REQUIRES_EMPTY_HANDS` | Hands must be empty. Used by cleaning. |
| `IGNORES_CARRIED_ITEMS` | Task does not care. For future use. |

Enforced in `StaffTaskExecutor.is_compatible_with_carried_item()`, so it applies
to every task type and every future staff role without being reimplemented.

**Recovery outcomes**, attempted in `CarriedItemPolicy.outcome_order`:

1. `REASSIGN` — another waiting customer ordered the same drink. Best outcome: nothing moves, the worker simply takes that task instead.
2. `RETURN_TO_SERVICE_SLOT` — put it back on the bar via `ItemCarrier.place_into()`.
3. `RETURN_TO_SOURCE_STATION` — the station's own "put back" interaction, the same one the player gets.
4. `RETURN_TO_STORAGE` — `StockStorage.deposit_carried()`. Rejected by tag for prepared drinks; correct home for a future ingredient.
5. `RETAIN` — keep holding it. Blocks incompatible work unless `may_work_while_holding_unrelated_item` is on.
6. `DISPOSE` — off by default, always writes a diagnostic event.

Planning is separate from execution, so the worker re-plans on arrival: if a
customer orders the carried drink while it is halfway to the bar, the next plan
is a reassignment.

**Diagnostic events emitted**: `carried_item_reassigned`, `carried_item_returned`,
`carried_item_restocked`, `carried_item_disposed`, `carried_item_retained`,
`carried_item_recovery_failed`, `carried_item_incompatible` (rejection reason),
`carried_item_reused`.

---

## 7. Task viability formula and scoring factors

```text
travel_minutes  = travel_pixels / worker_speed  → world minutes
overhead        = interaction_overhead_minutes × interaction_count
action_minutes  = executor's own action duration
estimated       = travel_minutes + overhead + action_minutes

margin          = deadline − estimated − safety_buffer
```

The executor supplies the legs, because only it knows a serve is
worker → bar → customer while a clean is worker → chair. `deadline` is the
customer's remaining patience for serving, and **−1 for cleaning**, which keeps
dirty seats entirely outside the system: they cannot expire, so no estimate
could ever reject one.

| Verdict | Condition | Score contribution |
|---|---|---|
| `VIABLE` | `margin ≥ comfortable_margin` | `+viable_bonus` (40) |
| `MARGINAL` | `rejection_margin ≤ margin < comfortable` | `margin × margin_weight` |
| `NON_VIABLE` | `margin < rejection_margin` | `−non_viable_penalty` (400) |
| `UNKNOWN` | no estimate possible | 0 |

Added to the existing score as a seventh term, so it counterweights urgency
rather than replacing it.

Path lengths use `NavigationService.get_path_length()`, cached per task for
`maximum_path_estimate_age_seconds` — pathfinding every candidate every
evaluation is the only part of this that could get expensive.

**The critical tuning lesson is recorded in the resource's own doc comment.**
A first implementation used `rejection_margin_minutes = −0.5`, and the A/B
benchmark showed it made things *measurably worse*: the worker refused jobs it
would probably have finished, stood idle, and completed fewer customers than
the version with no viability checking at all. Rejecting a doomed task only
helps if there is something better to do. Two changes fixed it:

- `rejection_margin_minutes` → `−3.0` (reject *clearly impossible*, penalise *tight*)
- `accept_best_non_viable_when_idle = true` — a worker with nothing else to do attempts the least hopeless job rather than nothing.

---

## 8. Task reservation and commitment behaviour

| Mechanism | Value | Purpose |
|---|---|---|
| `same_worker_reclaim_cooldown_seconds` | 6.0 | Stops the tightest loop: a worker re-claiming the task it just released. Another worker may take it immediately. |
| `task_switch_score_margin` | 120.0 | Hysteresis band. Prevents abandoning a job for one scoring marginally higher. |
| `minimum_commitment_minutes` | 0.75 | A worker that has just set off is allowed to get somewhere. |

Revalidation points, unchanged from Phase 3A and still in force: before claiming,
before each navigation leg, before executing, and on every board sweep.
`TaskBoard.release_reservations()` remains the single owner of reservation
cleanup and is called on every terminal route — complete, cancel, release, fail
and sweep. Verified: **no finished task retained a reservation** across all
benchmark runs.

Legitimate interruption is unaffected — invalid targets, customer departure,
unavailable stock, unreachable destinations and external completion all still
interrupt immediately, because they cancel the task rather than compete on
score.

---

## 9. State-machine changes

- **New state `RECOVERING_ITEM`** — a worker walking to put a drink down is doing something different from one walking to a customer. Phase 3A reported both as `MOVING_TO_TARGET`.
- **Idle no longer re-decides.** `_no_work_found()` leaves an in-progress walk home alone. `TaskBoard.task_created` still wakes the worker immediately, so responsiveness is unchanged.
- **Empty evaluations are folded out of history** and counted as `empty_evaluations` instead (carried over from Phase 3A).
- Measured: **0 idle round trips in ~15 seconds** in the automated suite.

---

## 10. New diagnostic fields

**Per decision** (`tasks.decisions`) — one record per claim or rejection, never
per frame, with identical consecutive rejections deduplicated and counted:
`task_id`, `task_type`, `accepted`, `reason`, `final_score`, `base_priority`,
`urgency`, `estimated_minutes`, `margin_minutes`, `viability_verdict`,
`candidates_considered`, `repeat_count`, `world_minutes`, `worker_id`.

**Per task type** (`tasks.by_task_type`): created, claimed, completed,
cancelled, failed, open, `rejected_non_viable`, `average_claim_delay_minutes`,
`average_execution_minutes`, `average_lifetime_minutes`,
`average_invested_before_cancel_minutes`, `completion_rate`,
`cancellation_rate`.

**Cancellation reasons** (`tasks.cancellation_reasons`): counts by reason, with
anything unclassified falling into `other` — a growing `other` bucket is a
visible prompt to classify a reason properly rather than a silent gap.

**Viability distribution** (`tasks.viability_distribution`): `VIABLE`,
`MARGINAL`, `NON_VIABLE`, `UNKNOWN`, `NOT_EVALUATED`, plus
`non_viable_rejections_recorded`.

**State transitions** (`state_transitions`): counts keyed
`"FROM -> TO (reason)"`.

**Per worker** (`staff[]`): `task_switches`, `non_viable_skipped`,
`carried_item_recoveries`, `carried_recovery_failures`,
`carried_events_by_reason`, `recent_carried_events`, `travel_seconds`,
alongside the existing idle/work/navigation counters.

**Per task** (`to_dictionary()`): `invested_minutes` and the full `viability`
record.

---

## 11. Configuration values and where to tune them

| File | Controls |
|---|---|
| `Data/staff/task_viability_config.tres` | Margins, buffer, rejection threshold, scoring weights, estimation, re-evaluation. |
| `Data/staff/carried_item_policy.tres` | Outcome order, reassignment distance, fallbacks, whether work may continue while carrying, retry delay. |
| `Data/staff/task_board_config.tres` | Reclaim cooldown, switch margin, commitment window, decision-log size and dedup. |
| `Data/staff/tasks/*.tres` | Per-type `carried_item_rule` and `viability_weight`. |
| `Data/staff/tavern_hand.tres` | Which policy this role uses; evaluation intervals. |

Set `TaskViabilityConfig.enabled = false` to restore Phase 3A selection exactly.

---

## 12. Tests performed

All run headless on Godot 4.7.1 (`--headless --fixed-fps 60`). Nothing below is
claimed on inspection alone.

| Suite | Command |
|---|---|
| Phase 3A regression | `res://tests/phase_3a_smoke_test.tscn` |
| Phase 3A.1 refinement | `res://tests/phase_3a1_refinement_test.tscn` |
| A/B overload benchmark | `res://tests/phase_3a1_benchmark.tscn` (`-- --legacy` for baseline) |

Scenario coverage against the brief:

| Scenario | Covered by | Result |
|---|---|---|
| A — manageable workload | 3A suite (basic service) | Pass |
| B — deliberate overload | 3A.1 suite + benchmark | Pass |
| C — customer leaves before collection | 3A suite (player takes drink) | Pass |
| D — customer leaves after collection | 3A.1 suite | Pass |
| E — player completes task | 3A suite | Pass |
| F — external completion | Simulated via player-completion path | Partial — see §14 |
| G — stock unavailable | 3A suite (alert lifecycle) | Pass |
| H — marginal viability | 3A.1 suite | Pass |
| I — state stability | 3A.1 suite | Pass |

---

## 13. Test results

**Phase 3A regression: 34/34 passed.** Serving, cleaning, player overrides,
navigation failure, alert raise/dedupe/escalate/resolve all intact.

**Phase 3A.1 refinement: 21/21 passed.** Including:

```text
[PASS] D: Worker collected a Grog.
[PASS] D: The customer left while the drink was in the worker's hands.
[PASS] D: The drink was resolved without starting an incompatible task.
[PASS] D: Recovery recorded as: carried_item_returned.
[PASS] D: No duplication: 1 drink(s) before, 1 after.
[PASS] INC: Cleaning is correctly refused while carrying a drink.
[PASS] H: Verdict VIABLE: est 3.2m, deadline 8.0m, margin 3.3m
[PASS] I: 0 idle round trips in ~15s - stable.
[PASS] B: No finished task is still holding a reservation.
[PASS] DIAG: All 13 transition groups carry a meaningful reason.
```

**A/B benchmark under sustained overload**, with a simulated attentive player
keeping the bar stocked. Legacy n=4, refined n=5:

| Metric | Legacy 3A | 3A.1 |
|---|---|---|
| Completions (mean) | 15.5 | 18.0 |
| Serve completion **rate** | 0.303 | 0.308 |
| Minutes wasted before cancelling a serve | 1.69 | **1.36** |

**Read this honestly.** The completion *rate* is unchanged within noise. The
measurable gain is roughly **20% less time wasted on work that was never going
to succeed**, which is what the brief actually asked for. Variance between runs
is high and the sample is small; no stronger claim is supported by this data.

---

## 14. Known limitations

- **Scenario F was not tested with two real workers.** The scene contains one Tavern Hand. External completion was exercised through the player-completion path, which uses the same invalidation route, but genuine two-worker contention remains reasoned about rather than observed.
- **Benchmark variance is high.** Completion counts ranged 13–21 across nine runs. Treat the table in §13 as directional.
- **The travel estimate ignores queueing.** It models the current task only, not the fact that a worker already has a job. A task at the back of a busy queue is over-optimistic until the worker is free.
- **Estimates ignore avoidance detours.** A worker weaving through a crowded room is slower than its path length suggests. The safety buffer absorbs this; it is not modelled.
- **`REASSIGN` only considers existing board tasks**, so it cannot hand a drink to a customer who has not yet had a task created for them.
- **`DISPOSE` is off by default.** With every route unavailable and disposal disabled, the worker retains the item and retries every `recovery_retry_seconds`. It cannot deadlock, but it can loiter.
- **No save/load.** Viability and path caches are runtime-only by design; `invested_minutes` and decision records would not survive a reload.

---

## 15. Navigation

**No navigation change was made.** The Phase 3A diagnostic showed 0 navigation
failures and 0 item-transfer failures, and nothing in this pass traced a defect
back to navigation. The 8 stuck recoveries were not investigated further, in
line with the brief's instruction not to rewrite navigation without cause.

The only navigation-adjacent addition is *read-only*:
`TaskViability.measure_distance()` calls `NavigationService.get_path_length()`
to estimate travel. It queries the navigation server and changes nothing.

---

## 16. Recommended next benchmark

1. **Add a second Tavern Hand** and re-run the benchmark. Multi-worker contention is the largest untested area, and the claim index, reclaim cooldown and switch margin were all written for it.
2. **Vary the load ladder** — 4, 8, 12, 16 concurrent customers — and plot completion rate against `comfortable_margin_minutes`. The single overload point tested here cannot show where the margin should sit.
3. **Add queue-aware estimation** (include the current task's remaining time in the estimate) and A/B it. This is the largest known inaccuracy.
4. **Re-check `rejection_margin_minutes`** after either change. It is the value that already caused one regression, and it will need retuning whenever worker throughput changes.

---

## 17. Manual Godot editor steps

**None required.** Every resource reference is wired in the `.tres` files
included in this update, and no scene was changed.

Two optional checks after copying the files in:

- Open `Data/staff/task_board_config.tres` and confirm `viability_config` points at `Data/staff/task_viability_config.tres`.
- Open `Data/staff/tavern_hand.tres` and confirm `carried_item_policy` points at `Data/staff/carried_item_policy.tres`.

Both are set correctly in the delivered files; the check is only worth a moment
if Godot reports a missing sub-resource on first import.
