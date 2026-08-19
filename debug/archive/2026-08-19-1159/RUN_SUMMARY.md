# Diagnostic Run

## Version

Date: 2026-08-19
Time: 11:59:44
Git branch: main
Git commit: eb5899001abda6da69711ff4552a9de31d0ddfcd
Git short commit: eb58990
Game version: 0.1.0-dev
Diagnostic run ID: 2026-08-19-1159

## Test

Test purpose: (not set)
Duration: 14 min 21 sec
Days: 2

## Overall Result

FAIL

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
| Staff | PASS |  |
| Groups | FAIL | 42.9% group success |

## Critical Failures

1. Groups — 42.9% group success

## Warnings

None.

## Key Metrics

customers_spawned: 109
completed_visits: 98
total_drinks_ordered: 90
total_drinks_consumed: 83
tasks_created: 259
tasks_completed: 166
tasks_cancelled: 86

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
