# Phase 3B — Bartender and Internal Stock Workflow

## Implemented

A second staff member now uses the existing `StaffMember` framework as a specialised Bartender.

The Bartender can:

- detect active customer drink demand;
- pour the matching drink from a real drink station;
- consume one real serving from that station;
- carry the prepared drink to an empty bar service slot;
- detect low drink stations;
- collect the matching keg/barrel item from Stock Storage;
- carry it to the station and refill it;
- leave ordering and delivery management entirely with the player.

The Tavern Hand remains limited to serving prepared drinks and cleaning seats.

## New task types

- `prepare_drink`
- `refill_station`

Both use the central TaskBoard, capability filtering, viability scoring, normal navigation, carried items and real inventory transfers.

## Demand rule

Preparation is driven by active waiting orders. A preparation task is created only when waiting demand exceeds the number of matching prepared drinks already on the bar and an empty service slot exists.

## Files added

- `Data/staff/bartender.tres`
- `Data/staff/tasks/prepare_drink.tres`
- `Data/staff/tasks/refill_station.tres`
- `scenes/staff/bartender.tscn`
- `systems/staff/executors/prepare_drink_executor.gd`
- `systems/staff/executors/refill_station_executor.gd`

## Files changed

- `Data/staff/task_board_config.tres`
- `scenes/main/main.tscn`
- `scripts/Interactables/drinks_station.gd`
- `systems/stock/stock_storage.gd`
- `systems/staff/executors/staff_task_executor.gd`
- `systems/staff/tasks/tavern_task_types.gd`
- `systems/staff/tavern_task_coordinator.gd`

## Initial test checklist

1. Put grog and ale stock items in Stock Storage.
2. Let customers order both drink types.
3. Confirm the Bartender pours drinks and places them in bar slots.
4. Confirm the Tavern Hand collects those drinks and serves customers.
5. Empty or lower a station and confirm the Bartender collects matching stock from storage.
6. Confirm storage quantity decreases and station servings increase.
7. Confirm the Bartender never serves customers or cleans seats.
8. Confirm the Tavern Hand never pours drinks or refills stations.
9. Remove the required stock from storage and confirm no item is created magically.
10. Export staff diagnostics after a busy test and inspect both workers separately.

## Review note

This is a first functional build intended for Godot testing and Claude review. The project could not be launched in this build environment, so runtime parser, navigation and integration issues should be checked in Godot before treating Phase 3B as complete.
