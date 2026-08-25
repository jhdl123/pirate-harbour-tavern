# Diagnostic Run

## Version

Date: 2026-08-25
Time: 09:54:38
Git branch: darts-multiplayer-and-activity-affinity
Git commit: 01aa9e9b160a7ef1f2874f824384885fa8b52d81
Git short commit: 01aa9e9
Game version: 0.1.0-dev
Diagnostic run ID: 2026-08-25-0954

## Test

Test purpose: (not set)
Duration: 4 min 21 sec
Days: 2

## Overall Result

WARN

## Systems

| System | Result | Key Issue |
|---|---|---|
| Drinks | PASS |  |
| Stations | PASS |  |
| Ordering | PASS |  |
| Delivery | PASS |  |
| Storage | PASS |  |
| Restocking | PASS |  |
| Bar | PASS |  |
| Customers | PASS |  |
| Staff | WARN | 30 stuck recoveries |
| Groups | WARN | 70.0% group success |

## Critical Failures

None.

## Warnings

1. Staff — 30 stuck recoveries
2. Groups — 70.0% group success

## Key Metrics

customers_spawned: 59
completed_visits: 59
total_drinks_ordered: 66
total_drinks_consumed: 60
tasks_created: 159
tasks_completed: 89
tasks_cancelled: 69

## Drink Chain Results

- small_beer     PASS
- grog           PASS
- cider          PASS
- madeira        PASS
- brandy         PASS
- port_wine      PASS
- canary_wine    PASS

## Developer Notes

(none)
