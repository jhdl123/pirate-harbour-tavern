# Diagnostic Run

## Version

Date: 2026-08-24
Time: 20:23:58
Git branch: main
Git commit: d51e6c801943b9992cf271ed8395f63346aea557
Git short commit: d51e6c8
Game version: 0.1.0-dev
Diagnostic run ID: 2026-08-24-2023

## Test

Test purpose: (not set)
Duration: 5 min 4 sec
Days: 3

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
| Staff | WARN | 23 stuck recoveries |
| Groups | FAIL | 37.5% group success |

## Critical Failures

1. Groups — 37.5% group success

## Warnings

1. Staff — 23 stuck recoveries

## Key Metrics

customers_spawned: 129
completed_visits: 121
total_drinks_ordered: 188
total_drinks_consumed: 91
tasks_created: 391
tasks_completed: 188
tasks_cancelled: 191

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
