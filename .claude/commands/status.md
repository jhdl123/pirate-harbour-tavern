---
description: Quick repository health check - branch, working tree, recent commit, Godot version
---

Report current repository health. Keep it short - this is a status check,
not an investigation.

1. Run `git branch --show-current`.
2. Run `git status`.
3. Run `git log -3 --oneline`.
4. Run `godot --version` and compare it against the version CLAUDE.md states
   (currently 4.7.1). Flag a mismatch; otherwise just confirm it matches.
5. Note anything that affects safety before further work: uncommitted
   changes, a branch other than `main` with no obvious relation to open work,
   or `main` diverged from `origin/main`.

Report as a compact list: branch, working-tree state (clean/dirty + what's
dirty), last 3 commits, Godot version match. Do not read any other files, run
tests, or propose changes - this command is read-only and diagnostic only.
