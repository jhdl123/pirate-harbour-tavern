---
description: Take a concise implementation brief (e.g. from a ChatGPT design session) and implement it
argument-hint: <the handoff brief - objective, desired behaviour, constraints, decisions, acceptance criteria>
---

Implement this feature brief:

$ARGUMENTS

If the brief doesn't follow the handoff format in `docs/AI_WORKFLOW.md`
(Objective / Desired behaviour / Constraints / Design decisions / Acceptance
criteria), work with what's given, but flag anything one of those categories
would normally cover and is missing here - especially acceptance criteria,
since without them "done" is a guess.

Follow CLAUDE.md's standard implementation loop:

1. Inspect the current implementation of the relevant system(s) - use
   CLAUDE.md's architecture anchors table to find the owning system(s), then
   read the actual code. Do not assume the repository's shape from memory or
   from the brief's description of it.
2. Check `docs/CURRENT_STATE.md` for that system's current status and known
   issues, and `docs/DECISIONS.md` for durable decisions this must respect.
3. Identify relevant tests from `docs/TEST_MAP.md`.
4. Propose the smallest coherent implementation that satisfies the brief.
   Flag ambiguity or any conflict with an existing decision **before**
   editing, per working rule 2 - do not silently choose an interpretation for
   anything non-trivial.
5. Wait for approval before implementing anything beyond a small, obviously
   correct change.
6. Implement. Do not modify unrelated systems.
7. Determine the appropriate verification level (CLAUDE.md's model) and run
   it - typically the relevant tests via `tools/run_tests.ps1` at minimum for
   any behaviour change.
8. Self-review the diff: does it actually produce the described behaviour,
   not just plausible-looking code for it? Re-check against the brief's
   acceptance criteria specifically.
9. Report: what changed, what was tested and the results, whether each
   acceptance criterion is met, and any remaining uncertainty.

Do not commit. Update `docs/CURRENT_STATE.md` (and `docs/DECISIONS.md` if a
new durable decision was made) as part of the change if the feature changes
what's true there - but do not duplicate information that belongs in the
system doc instead.
