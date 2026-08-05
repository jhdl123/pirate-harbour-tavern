# Basic group loop — reliability pass

Fixes the repeated-group loop so it survives consecutive visits: spawn → staggered
entry → assemble → one shared keg → paced drinking → post-keg wait → staggered
departure → full cleanup.

## Root causes

Four separate faults, diagnosed from `customer_ai_report_2026-08-04_111826.json`
(34 group members across 11 groups) and confirmed against the code.

1. **Groups leaving ~3 minutes after assembly, no thirst change.**
   `GroupManager._place_order()` and `_serve_order()` went straight to
   `begin_departure()` on the first refusal. There was no retry at all. Worse,
   the vessel reserved by `reserve_order()` was never returned on any failure
   path — `begin_departure()` only resolves `shared_serving`, which is still
   null at that point — so every failed group permanently removed one shared
   vessel from circulation. That is why failures clustered later in the session.

2. **One member stuck in `MOVING_TO_GROUP_SLOT` while the rest sat in `IN_GROUP`.**
   `are_members_in_position()` required every member inside 24px *and* in
   `IN_GROUP`, with no bound and no recovery, and it indexed slots by position
   in `get_valid_members()` — which re-indexes the moment anyone is removed, so
   a member could be sent to slot 2 and then checked against slot 1 forever.
   The group sat in `MOVING_TO_PLACE` until patience expired.

3. **`departure_reason: "unknown"` with the state trail stopping at `IN_GROUP`.**
   `fail_visit()` called `finish_customer()` directly on members that were
   inside the tavern, with `departure_reason` still empty, so
   `finish_customer()` fell through to its literal `&"unknown"`.

4. **Members stranded in `IN_GROUP` forever (customers 15 and 16), and one member
   in `LEAVING_TO_DOOR` for 184 world minutes.**
   `_run_departure_sequence()` was an `await` coroutine.
   `_check_departure_complete()` completes on patience, `_sweep_finished()`
   calls `queue_free()`, and the coroutine dies mid-loop — every member it had
   not reached yet never received `begin_group_departure()`. Separately,
   `LEAVING_TO_DOOR` had no watchdog at all, unlike `EXITING`.

Plus: `drinks_consumed` stayed zero because the report field is written by
`CustomerAIReportManager.record_drink_consumed()`, which `on_group_drink_taken()`
never called. It also applied a hard-coded `-0.35` thirst change and no
intoxication.

## Modified files

| File | Change |
| --- | --- |
| `systems/groups/customer_group.gd` | Explicit slot-index map; bounded assembly recovery; one-shot transition guards; process-driven staggered departure queue replacing the `await` loop; `dispatch_all_departures()`; single idempotent `cleanup()`; `keg_emptied_at_minutes` / `post_drink_started_at_minutes`; group diagnostics. |
| `systems/groups/group_manager.gd` | `_transition()` guard for every step; `_run_assembly()`; shared-serving retry via `_handle_serving_setback()` (which now cancels the order so the vessel comes back); first-drink delay; fair rotation with eligibility; `_begin_post_drink()`; post-keg wait measured from `post_drink_started_at_minutes`; departure completion dispatches stragglers; cleanup on sweep and on abort. |
| `systems/groups/group_order_service.gd` | When the forced milestone pairing cannot hold the group *by size*, fall through to normal weighted selection. Genuine station/stock failures still return null loudly. |
| `scripts/Entities/customer.gd` | Bounded `LEAVING_TO_DOOR` recovery; `refresh_group_slot()` / `accept_group_slot_arrival()`; `join_group()` / `leave_group()`; drink-limit check in `is_ready_for_group_drink()`; `on_group_drink_taken()` now uses the balance config's thirst value, applies intoxication from the served drink, and reports the drink; `_resolve_departure_reason()` so a group member is never filed as `unknown`. |
| `systems/customer_ai/diagnostics/visit_record.gd` | `group_id`, `group_state`, `shared_drinks_consumed`, `group_slot_recoveries`. |
| `systems/customer_ai/diagnostics/customer_ai_report_manager.gd` | Recording methods for the four new fields, plus session totals. |
| `Data/beverage/serving_formats/table_cask.tres` | `minimum_group_size` 4 → 2. |
| `tests/group_loop_test.gd` / `.tscn` | New suite, 38 assertions across the ten required cases. |

### Why the `table_cask` data change was necessary

`force_ale_table_cask` pins every group to Ale in a table cask, and
`standing_places_only` is still on (the seated approach stall is a documented
navigation limitation). Every other shared format sets `requires_table`, so a
standing group of 2 or 3 had **no** orderable shared format at all — a
three-member group could never drink, no matter how reliable the loop became.
Lowering the minimum to 2 makes the forced pairing cover the 2–6 range the
milestone actually spawns. The fallback added to `choose_shared_order()` is the
code-side half of the same fix and keeps working if the forcing flag is turned
off later.

## Test results

Run with Godot 4.7.1 headless in the container.

**New — `tests/group_loop_test.tscn`: 38 passed, 0 failed.**

| Case | Result |
| --- | --- |
| 1. Three-member group completes | pass |
| 2. Six-member group completes | pass |
| 3. Member cannot reach its slot, is recovered | pass (2 recoveries, member kept) |
| 4. Serving request fails, retries, succeeds | pass (2 failed attempts, then a keg) |
| 5. Empty stock with `basic_loop_ignore_stock` | pass |
| 6. Two consecutive groups reuse the serving point | pass |
| 7. Ten consecutive groups, no stale state | pass (10/10 completed, 10/10 drank, 0 active, 0 servings, 0 vessels out, all areas free) |
| 8. No completion as `unknown` while in a group state | pass |
| 9. Shared drinks update thirst, intoxication, diagnostics | pass (4/4 members drank, counts agree) |
| 10. Cleanup called three times | pass (one release, no double vessel return) |

**Existing suites — unchanged from the pre-change baseline** (verified by running
the original zip first):

| Suite | Before | After |
| --- | --- | --- |
| `group_framework_test` | 47 / 2 | 47 / 2 |
| `group_keg_ordering_test` | 16 / 4 | 16 / 4 |
| `group_keg_loop_test` | 28 / 4 | 28 / 4 |
| `group_stress_test` | 8 / 0 | 8 / 0 |
| `phase_4a_loop_test` | 22 / 0 | 22 / 0 |
| `beverage_framework_test` | 49 / 0 | 49 / 0 |
| `beverage_ordering_test` | 18 / 0 | 18 / 0 |
| `report_fields_test`, `seat_leak_test`, `exit_stall_test` | 5 / 0 each | 5 / 0 each |

The pre-existing failures are not regressions:

- `group_framework_test` SEATED — the seated group path is switched off by
  `standing_places_only`, a known limitation.
- The four stock assertions across `group_keg_ordering_test` and
  `group_keg_loop_test` expect stock-dependent refusals that
  `basic_loop_ignore_stock` deliberately disables. The brief asked for that
  option to be preserved, so they were left failing rather than "fixed" by
  turning the milestone switch off.

The `group_keg_loop_test` run against `main.tscn` with real `Customer` nodes now
shows a complete loop: `keg_starting_portions: 8`,
`portions_per_member: {M1: 2, M2: 2, M3: 2, M4: 2}`, `shared_drinks_consumed: 8`,
`keg_emptied_at_minutes` equal to `post_drink_started_at_minutes`,
`departure_reason: "keg_finished"`, `cleanup_completed: true`.

## Remaining limitations

- **The seated group path is still off.** Fixing the seat-approach stall is a
  navigation job and was explicitly out of scope.
- **`group_loop_test` uses stub members**, not full `Customer` nodes, so it
  tests the group state machine, its guards and its teardown rather than real
  pathfinding. Real-customer coverage comes from `group_keg_loop_test`, which
  drives `main.tscn`.
- **Reordering is still off** (`allow_reorder`), so a group is one keg then out.
- **The assembly fallback places a member at its slot** rather than solving why
  it could not path there. That is deliberate — it is a bound, not a cure — and
  the count is now reported as `group_slot_recoveries` so a rising number is
  visible instead of silent.
- **`total_shared_drinks_consumed` also counts into `total_drinks_consumed`.**
  Keg portions are real drinks, so they appear in both; the shared figure is the
  subset, not a separate quantity.
- **Not verified in a long play session.** Ten consecutive groups pass in the
  harness; the original report covered 1443 world minutes of mixed traffic, and
  a fresh capture from a real session would be worth comparing.
