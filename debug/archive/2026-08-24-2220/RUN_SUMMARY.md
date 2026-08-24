# Diagnostic Run

## Version

Date: 2026-08-24
Time: 22:20:46
Git branch: main
Git commit: 7d242cb6f5c03ed691beba544436d26a9d51818c
Git short commit: 7d242cb
Game version: 0.1.0-dev
Diagnostic run ID: 2026-08-24-2220

## Test

Test purpose: (not set)
Duration: 6 min 43 sec
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
| Staff | FAIL | 1 navigation failures |
| Groups | PASS |  |

## Critical Failures

1. Staff — 1 navigation failures

## Warnings

None.

## Key Metrics

customers_spawned: 60
completed_visits: 60
total_drinks_ordered: 90
total_drinks_consumed: 79
tasks_created: 219
tasks_completed: 135
tasks_cancelled: 84

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
