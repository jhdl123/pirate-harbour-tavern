# Test Map

Index of `tests/` (49 scenes) to the system/area each one actually exercises,
for picking a relevant subset instead of running the whole suite. This is an
index, not a description of what each test does — read the test's own header
comment for that.

**Basis** column:

- **Verified** — the system/area and (where shown) the baseline is already
  stated in `CLAUDE.md` or `CURRENT_STATE.md`. 11 tests.
- **Inferred** — no existing doc assigns this test to a system. The area
  below comes from this test's own header comment and filename, read for this
  map. Not confirmed against a run. 38 tests.

**Baseline** column: only ever a number that is already written down in
`CLAUDE.md`/`CURRENT_STATE.md`, or "none recorded". Never invented — an
absent baseline just means nobody has recorded one, not that the test passes
clean.

Run any of these with `tools/run_tests.ps1` — see its `-List`/`-Test`/`-All`
help. Reconciled against the repository at commit `19a446b`.

## Known runner caveat

`item_system_tests` only calls `get_tree().quit()` when its own
`quit_when_finished` export is `true`; no `.tscn` sets it. Run exactly as its
own header documents and it will not exit on its own — `tools/run_tests.ps1`'s
timeout kills it regardless, so it always terminates for the caller, but it
will show as `TIMEOUT`, not `PASS`/`FAIL`, until that export is addressed.
Not fixed here — this pass does not touch test files.

## Map

| Test | System / area | Basis | Baseline |
|---|---|---|---|
| `behaviour_mix_probe` | Customer AI (activity/time mix) | Inferred | none recorded |
| `beverage_framework_test` | Beverage framework | Inferred | none recorded |
| `beverage_ordering_test` | Beverage framework, orders/delivery | Inferred | none recorded |
| `beverage_station_test` | Beverage framework, drink stations | Inferred | none recorded |
| `customer_identity_test` | Customer AI (identity/personality) | **Verified** | 92 assertions, 0 failed |
| `delivery_storeroom_probe` | Beverage/stock/delivery | **Verified** | demonstrates delivery→storeroom chain (no numeric baseline recorded) |
| `diagnostic_export_probe` | Diagnostics | **Verified** | includes fault injection (no numeric baseline recorded) |
| `door_congestion_test` | Navigation (door/spawn congestion) | Inferred | none recorded |
| `drinks_system_probe` | Beverage framework | Inferred | none recorded |
| `entry_trace_test` | Navigation / Customer AI (arrival) | Inferred | none recorded |
| `exit_stall_test` | Navigation (departure, exit mesh) | Inferred | none recorded |
| `group_and_recovery_probe` | Groups, staff (bartender recovery) | Inferred | none recorded |
| `group_framework_test` | Groups | **Verified** | 2 failures, both SEATED cases (expected while `standing_places_only` is on) |
| `group_keg_loop_test` | Groups | **Verified** | 27/5, flaky — 27/5, 28/4, 29/3 all seen on identical builds; compare failure set, not count |
| `group_keg_ordering_test` | Groups, beverage | **Verified** | 5 failures, unchanged since `0e1f3f1` |
| `group_live_test` | Groups (live `main.tscn`) | Inferred | none recorded |
| `group_loop_test` | Groups (state machine, stub members) | Inferred | none recorded |
| `group_milestone_test` | Groups, staff (`TaskBoard.claim()`) | Inferred | none recorded |
| `group_parity_test` | Groups, staff (delivery executor) | Inferred | none recorded |
| `group_stress_test` | Groups (load/stress) | Inferred | none recorded |
| `item_system_tests` | Items and inventory | **Verified** | covers item/slot/container/transfer (no numeric baseline recorded); see runner caveat above |
| `leave_decision_probe` | Customer AI (leave-decision utility) | Inferred | none recorded |
| `management_menu_test` | UI (bar management menu) | Inferred | none recorded |
| `nav_and_backpressure_probe` | Navigation, staff (stuck recoveries) | Inferred | none recorded |
| `nav_probe` | Navigation | **Verified** | no numeric baseline recorded |
| `navigation_report_probe` | Navigation (diagnostics/telemetry) | Inferred | none recorded |
| `navigation_stress_test` | Navigation | **Verified** | no numeric baseline recorded |
| `phase_3a1_benchmark` | Staff (selection tuning, A/B benchmark — not pass/fail) | Inferred | not applicable — reports churn figures, not PASS/FAIL |
| `phase_3a1_refinement_test` | Staff (worker/task refinement) | Inferred | none recorded |
| `phase_3a2_integration_test` | Staff, diagnostics (debug integration) | Inferred | none recorded |
| `phase_3a_harness` | Staff (serve/clean/stock-alert loop) | Inferred | none recorded |
| `phase_3a_headless_test` | Staff (headless verification harness) | Inferred | none recorded |
| `phase_3a_smoke_test` | Staff (end-to-end staff-loop smoke test) | Inferred | none recorded |
| `phase_4_daily_cycle_test` | Daily cycle, modifiers, demand | Inferred | none recorded |
| `phase_4a_integration_test` | Daily cycle (statistics) | Inferred | none recorded |
| `phase_4a_loop_test` | Daily cycle (player-facing UI loop) | Inferred | none recorded |
| `phase_a_audit_probe` | Customer AI (activity-condition audit) | Inferred | none recorded |
| `phase_a_gate_audit` | Customer AI (activity-gate audit) | Inferred | none recorded |
| `reachability_probe` | Navigation, staff (station reachability) | Inferred | none recorded |
| `report_fields_test` | Diagnostics (report field population) | Inferred | none recorded |
| `restock_chain_probe` | Beverage/stock/delivery | **Verified** | demonstrates restock chain end to end (no numeric baseline recorded) |
| `seat_leak_test` | Groups, reservation (seat leak) | Inferred | none recorded |
| `seat_soak_test` | Groups, reservation (soak test) | Inferred | none recorded |
| `seated_group_probe` | Groups, navigation (seated arrival) | Inferred | none recorded — prints `RESULT: harness failed - manager or spawner missing` if the scene doesn't wire up, distinct from a normal pass/fail count |
| `service_coverage_probe` | Beverage framework (supply/demand coverage) | Inferred | none recorded |
| `service_latency_probe` | Staff, customer AI (service latency, cancellations) | Inferred | none recorded |
| `staff_system_tests` | Staff | Inferred | none recorded — this file's own header self-describes as "Phase 3A smoke test", same description `phase_3a_smoke_test` uses for itself; the two are separate files and this map does not resolve which (if either) is stale |
| `staff_walk_probe` | Staff (task timing) | Inferred | none recorded |
| `storeroom_props_probe` | Beverage/stock (storeroom props, navmesh) | Inferred | none recorded |

## Maintenance

Update this file when a test's system changes, a new test is added, or a
baseline in `CLAUDE.md`/`CURRENT_STATE.md` changes. Do not add a numeric
baseline here that isn't already recorded in one of those two files — record
it there first, then reflect it here.
