---
description: Investigate a bug systematically before touching any code
argument-hint: <description of the observed problem>
---

Investigate this bug, described below. Do not change behaviour until a
diagnosis is stated and, for anything non-trivial, agreed:

$ARGUMENTS

Follow `docs/AI_WORKFLOW.md`'s standard bug workflow:

1. Reproduce it, or identify exactly what evidence already demonstrates it
   (a diagnostic run, a test failure, a described play session).
2. Collect the smallest useful evidence rather than the largest available -
   a targeted `tools/run_tests.ps1` run or a specific diagnostic section,
   not a full run "just in case".
3. Check prerequisites before suspecting AI/behaviour logic: stock levels,
   staffing, run length, sample size, spawn count. CLAUDE.md's "Diagnostic
   lessons that keep recurring" section lists the confounds that have
   repeatedly turned out to be the real cause on this project - check those
   first.
4. Classify the problem: implementation, configuration/data, navigation,
   staffing, stock, timing, test setup, or design. Configuration/data bugs
   are more common here than logic bugs - check the relevant `.tres`
   resources and `docs/CONFIGURATION_GUIDE.md` before assuming the code path
   is wrong.
5. Identify the owning system (CLAUDE.md's architecture anchors table) and
   any relevant tests from `docs/TEST_MAP.md`.
6. State a diagnosis: root cause, the evidence supporting it, and what would
   falsify it. If the evidence is insufficient to be confident, say so rather
   than guessing.
7. Only after stating the diagnosis, propose the fix - the smallest change
   that addresses the actual cause, not the symptom. For anything beyond a
   trivial one-line fix, propose it and wait rather than implementing
   immediately.

If you do implement a fix as part of this command, run the targeted test(s)
covering the affected system afterwards via `tools/run_tests.ps1`, and report
exactly what changed, what was tested, and the result.
