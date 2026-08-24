---
description: Run relevant/selected/all tests via tools/run_tests.ps1 and report a compact summary
argument-hint: [test names, comma-separated] or [a system/area name] or [nothing for "figure it out from recent changes"]
---

Run tests using `tools/run_tests.ps1` (PowerShell). Arguments given: $ARGUMENTS

1. Work out which tests to run:
   - If specific test names were given, use those.
   - If a system/area was named (or none was, and there's a recent diff to
     infer one from), look it up in `docs/TEST_MAP.md` and select the tests
     listed for that system/area.
   - Only fall back to `-All` if the user explicitly asked for the full
     suite, or the change is broad enough that CLAUDE.md's verification
     levels would call for full regression (Level 4).
2. Invoke the runner:
   `tools\run_tests.ps1 -Test name_one,name_two` (comma-separated, no spaces
   needed but no bare-space list either - PowerShell's array binder does not
   reliably split `-Test a b`), or `tools\run_tests.ps1 -All`. Use
   `-TimeoutSeconds` above the default (90s) for tests known to run long
   (e.g. `leave_decision_probe`, `phase_a_audit_probe`). Do not pass
   `-ShowOutput` unless a result needs deeper inspection than the summary
   line gives - the point of this command is a compact result.
3. Read the runner's own summary table directly; do not re-run tests or dump
   full Godot output into the conversation.
4. Cross-check every result against `docs/TEST_MAP.md`'s recorded baseline
   (and CLAUDE.md's "Known baseline results") before calling anything a
   regression:
   - A result matching a recorded baseline is expected, not a new problem.
   - A result that differs from a recorded baseline, or has no recorded
     baseline and shows FAIL/SUSPECT/TIMEOUT/NO_RESULT, is worth flagging.
   - Never treat `PASSED: 0, FAILED: 0` (or any status other than PASS with
     a nonzero passed count) as a pass. The runner already encodes this as
     SUSPECT/NO_RESULT/TIMEOUT rather than PASS - do not override that
     classification.

Report per test: name, status, passed/failed counts, whether it matches a
recorded baseline. Then one overall line: total run, how many matched
expectations, how many need attention. If anything needs attention, say what
evidence would help decide whether it's a regression versus a known-flaky
result (see CLAUDE.md's evidence-discipline notes on flaky tests like
`group_keg_loop_test`).
