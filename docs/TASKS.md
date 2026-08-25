# Tasks

The currently active phase only. When a phase completes, fold its summary
into `CHANGELOG.md` and clear it from here — do not let this file accumulate
history.

## Active phase: Priority 0.5 — Phase B, the customer model (briefed, not yet implemented)

The customer decision architecture is being restructured from a flat
utility contest to a two-stage decision (motivation, then activity within
it) — see `PHASE_B_BRIEF.md` for the work order and `CUSTOMER_MODEL.md` for
the target architecture. `DECISIONS.md` #19–25 record the design calls
behind it.

**What exists so far:** the brief, the target-architecture doc, the
inspector spec, `docs/DECISIONS.md` #19–25, and one diagnostic probe
(`tests/darts_score_probe.gd`, no assertions) that measured *why* darts
currently loses the scoring contest at `235b7ac` — see `CURRENT_STATE.md`'s
"Customer AI — activity selection, measured 2026-08-25" section. **No
implementation has landed yet** — this is design and measurement only.

**Next step:** implement against `PHASE_B_BRIEF.md`'s work order
(audit → implement → measure), starting from its own stated scope.

## Pending decisions

- **Priority 0 (reputation → demand → end-of-day spend)** is still the
  standing roadmap recommendation ahead of Phase B in `ROADMAP.md`'s own
  ordering, but Phase B was started first and is now the active phase. Not
  contradictory by accident: `ROADMAP.md` places Phase B at Priority 0.5
  specifically because it blocks Priority 2 and the future information
  layer — see its own reasoning there.
- **Process note:** the Phase B brief was delivered as a zip extracted
  directly over the project root rather than as a patch, which silently
  overwrote whole files (`CLAUDE.md`, `DECISIONS.md`, `ROADMAP.md`,
  `CURRENT_STATE.md`) and destroyed unrelated concurrent edits to them
  before this pass reconciled the two. See `CLAUDE.md`'s Documentation
  discipline section for the rule this added.

## Carried-over backlog from the last completed phase

Not blocking, but should not be forgotten. From `CUSTOMER_AI_SYSTEM.md`'s
"Known limitations, honestly" and `CURRENT_STATE.md`'s Customer AI section:

- **No dedicated automated test for solo/two-player darts and post-match
  divergence.** Three attempts were made this pass; each found and fixed a
  real bug (see `CHANGELOG.md`), but the test itself stayed too
  environmentally fragile — customer-type visit-duration variance and
  `--fixed-fps` timing races on transient states — to land reliably in the
  time available. Coverage today is indirect: `group_parity_test.gd`'s
  existing legacy-stub darts case, plus the unchanged full regression suite.
- Darts' scene position (`Vector2(650, 450)` in `main.tscn`) and the new
  second slot's marker position are both placed without visual confirmation
  in the editor.
- `TavernActivityPoint.cooldown_minutes` is recorded but never enforced.
- 1x-speed group success and task cancellation figures have only been
  measured once (see `CURRENT_STATE.md`'s Groups/Staff sections) — worth an
  independent re-run before leaning on them for a balance decision.

## Standing baseline caveats

See `CLAUDE.md`'s "Known baseline results" before treating any test run as a
regression — several tests are documented as flaky by design
(`group_keg_loop_test`, `navigation_stress_test`,
`phase_4a_integration_test`'s `DOUBLE` check). Compare failure sets, not
counts.
