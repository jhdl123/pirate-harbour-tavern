# Group keg loop - integration fix

Scope: make the existing group keg system work in the playable `main.tscn`.
No architecture changes, no new features.

## Confirmed root cause

Group members sent to reserved chairs never finish sitting down.

Driving a real `sailor_pair` visit in `main.tscn` headless:

```
[10.2s] M1(state=IN_GROUP,       dist=6)   M2(state=MOVING_TO_SEAT, dist=27)
[40.0s] M1(state=IN_GROUP,       dist=6)   M2(state=MOVING_TO_SEAT, dist=11)
!! visit_failed: members could not reach their places
```

The second member oscillates around ten pixels short of its seat and never
reaches `seat_arrival_distance` (2 px), so `are_members_in_position()` is never
true, the group's patience runs out in `MOVING_TO_PLACE`, and the visit is
failed before it ever orders. No keg is created and nobody drinks.

`sailor_pair` carries the highest `spawn_weight` (4.0) and prefers seating, so
most arrivals were two-member seated parties dying this way - which is exactly
the reported symptom of "groups spawn, often with two customers, no shared keg".

The standing path had no such handover and already worked end to end.

Two suspicions in the brief were checked against the live scene and ruled out:

- Station capability was NOT the problem. `BeverageSceneSetup` already grants
  `draw_from_cask`, `fill_pitcher` and `fill_shared_cask` plus 96 measures to
  both stations in `main.tscn`.
- Ale already resolves `table_cask` (8 portions, 48 measures, no table
  required) at runtime.

## Changes

- **Standing destinations for the group milestone.** `GroupManager` and
  `CustomerGroup` gained `standing_places_only` (on by default). The whole
  party takes one standing area or the visit does not start, so a group can
  never split between tables and can never hit the seated stall above.
- **One pinned shared order.** `GroupOrderService.force_ale_table_cask`
  produces the milestone Ale table cask, honouring a group's own
  `required_drink_id` / `required_serving_format_id` when it has pinned one.
- **Real failure reasons.** `_diagnose_missing_station()` separates
  `insufficient_stock` from "no station serves ale" and "no station can fill
  table_cask", instead of reporting every case as no stock.
- **No charge without a keg.** The individual-order fallback that paid
  immediately and produced no drink is gone; the order is cancelled, the
  vessel returned, and the group leaves with a recorded reason. Payment now
  happens only after a keg exists at the group.
- **Socialising delay fixed.** It was measured against total visit duration,
  which had always elapsed by the time the keg emptied, so groups left the
  instant they finished. It is now time spent in that state.
- **F10 "Spawn Test Group of 4"** on `GroupDiagnosticsPanel`, calling
  `GroupSpawner.spawn_test_group()` - the production `spawn_group()` path, not
  a separate test implementation. Every spawn path now registers members with
  `GameManager`, so a developer-spawned group occupies and releases population
  slots like any arrival.
- **Diagnostics.** `CustomerGroup.get_diagnostics()` reports group id, member
  ids, leader, size, state, destination, order failure reason, source station,
  stock before/after, keg portions started/remaining, portions per member,
  departure reason and cleanup status. State changes print behind the existing
  `log_state_changes` toggle, enabled in `main.tscn`.
- **NavigationDebugger disabled in `main.tscn`.** It printed a collision line
  every frame per customer and buried all group logging.

## Test results

`godot --headless res://tests/group_keg_loop_test.tscn` - 32 passed, 0 failed.

Test 1, main scene group loop:

```
ENTERING -> FINDING_PLACE -> ENTERING -> MOVING_TO_PLACE -> SETTLING
-> WAITING_TO_ORDER -> ORDERING -> WAITING_FOR_SERVICE -> CONSUMING
-> SOCIALISING -> PREPARING_TO_LEAVE -> LEAVING -> COMPLETE

destination: bar_end          keg: ale / table_cask, 8 portions
Ale stock:   96 -> 48         portions: M1 2, M2 2, M3 2, M4 2
departure:   keg_finished     cleanup_completed: true
```

Test 2, spawn recovery: a solo customer spawns after the group and reaches its
normal order flow; F10 spawns a second test group.

Test 3, failure cleanup: with both casks drained, the group records
`insufficient_stock`, creates no keg, is charged nothing, releases `bar_end`,
and leaves the registry clean.

## Remaining limitations

- **Seated groups are switched off, not fixed.** The underlying seat-approach
  stall is a navigation problem and is out of scope here. Turning
  `standing_places_only` off restores the seated path and the stall with it.
- Reordering is off (`GroupManager.allow_reorders`): one group, one keg, one
  visit, as the brief scopes it.
- The state enum keeps its existing names; `get_state_label()` reports
  `WAITING_FOR_SERVICE` as `WAITING_FOR_KEG` and `CONSUMING` as
  `DRINKING_FROM_KEG` for the milestone trail.
- Drinking is a state and portion change only - no carrying, pouring
  animation, or bartender keg task.
- One portion leaves the keg per world minute, so a group of four empties an
  eight-portion cask in eight tavern minutes. Not balanced, just visible.
