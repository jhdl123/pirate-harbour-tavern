# Diagnostic Run

## Version

Date: 2026-08-24
Time: 21:56:01
Git branch: main
Git commit: d51e6c801943b9992cf271ed8395f63346aea557
Git short commit: d51e6c8
Game version: 0.1.0-dev
Diagnostic run ID: 2026-08-24-2156

## Test

Test purpose: (not set)
Duration: 6 min 27 sec
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
| Staff | WARN | 39 stuck recoveries |
| Groups | WARN | 60.0% group success |

## Critical Failures

None.

## Warnings

1. Staff — 39 stuck recoveries
2. Groups — 60.0% group success

## Key Metrics

customers_spawned: 79
completed_visits: 79
total_drinks_ordered: 82
total_drinks_consumed: 97
tasks_created: 234
tasks_completed: 163
tasks_cancelled: 67

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
