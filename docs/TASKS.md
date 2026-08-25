# Tasks

The currently active phase only. When a phase completes, fold its summary
into `CHANGELOG.md` and clear it from here — do not let this file accumulate
history.

## Active phase: none started — awaiting a decision

As of this documentation pass
(`feature/darts-multiplayer-and-activity-affinity` @ `526e2fa`), the previous
phase (cross-activity affinity + two-participant darts) is
implementation-complete to the limits described below. No new development
phase has been started since. Choosing the next one is a decision for the
next planning conversation, not something this pass decides — see
`ROADMAP.md`'s Priority 0 for the standing recommendation.

## Pending decisions before new work starts

- **Merge or continue on the branch?**
  `feature/darts-multiplayer-and-activity-affinity` is 5 commits ahead of
  `main` (`main` is at `235b7ac`) and pushed to `origin`, with no PR opened
  yet. `main` does not currently reflect the darts/activity-affinity work
  this documentation pass describes.
- **Priority 0 (reputation → demand → end-of-day spend)** is the standing
  recommendation in `ROADMAP.md` and remains unscoped — no design brief and
  no architecture review has been done for it yet.

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
