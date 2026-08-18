# Debug Reports

## latest

The most recent exported diagnostic run. Always inspect this first.
It is overwritten on every export and never mixes two runs.

## archive

Historical runs, one folder per export, named `YYYY-MM-DD-HHMM`.
Use these to compare regressions between commits.

## Recommended review order

1. `RUN_SUMMARY.md` — overall result and which systems failed
2. `drinks_report.txt` — the full service chain per drink
3. `stock_report.txt` — authoritative vs displayed quantities
4. `staff_report.txt` — tasks and navigation trouble by destination
5. `customer_report.txt` — service outcomes
6. `system_diagnostics.txt` — navigation scan and station config

## How to export a run

Press F10 in a debug build and choose **Export Diagnostic Run**.
This refreshes `latest/` and writes an archive folder.

## Git

Every `RUN_SUMMARY.md` records the branch and commit that produced
it, read from `.git` directly — Git does not need to be installed
for the game to run. If the commit reads `unknown`, the run was
made outside a Git checkout.

These reports are intended to be committed.
