---
description: Pre-merge verification pass on the current changes - level-appropriate checks, no commit
---

Verify the current uncommitted changes. This does not commit anything.

1. Run `git status` and `git diff --check` (whitespace/conflict-marker
   errors).
2. List every changed file (`git status --short` plus `git diff --stat`) and
   classify the change against CLAUDE.md's verification-level model
   (1-4) based on what actually changed, not on how large the request felt.
3. Confirm no unintended files changed: nothing outside what this change was
   supposed to touch, and in particular no accidental edits to files unrelated
   to the stated task.
4. Run the level-appropriate verification:
   - Level 1 (docs/config/small change): re-read the diff for accuracy; check
     any documentation links/paths introduced actually resolve.
   - Level 2 (local code/behaviour change): run the relevant test(s) from
     `docs/TEST_MAP.md` via `tools/run_tests.ps1`; review the diff.
   - Level 3 (subsystem/feature change): relevant subsystem tests plus any
     tests covering systems it touches indirectly; consider whether a
     diagnostic run (F10 → Export Diagnostic Run) would add real evidence.
   - Level 4 (major milestone/baseline): full suite via
     `tools\run_tests.ps1 -All`, a diagnostic run, and a check that
     `docs/CURRENT_STATE.md` still accurately describes what's implemented.
   Do not run a higher level than the change warrants.
5. State remaining uncertainty explicitly - anything not covered by the
   verification actually run, and anything that would need a human playtest
   or a longer/larger run to confirm (per CLAUDE.md's evidence-discipline
   rules: don't declare something broken, or fixed, from one short run).

Report: files changed, verification level chosen and why, checks run and
their results, confirmation that no unrelated files changed, and remaining
uncertainty. Do not stage, commit, or push anything.
