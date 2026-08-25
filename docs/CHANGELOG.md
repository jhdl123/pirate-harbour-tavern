# Changelog

Living, append-only record of significant completed systems and
milestones — newest first. Not a per-commit log (`git log` is authoritative
for that) and not a replacement for `docs/history/`'s detailed per-pass
reports (kept for their reasoning trails). This is the short version: what
shipped, and where to read more if it matters.

When a phase in `TASKS.md` completes, fold its summary in here and clear it
from `TASKS.md`.

## On `feature/darts-multiplayer-and-activity-affinity`, not yet merged to `main`

### Cross-activity affinity and two-participant darts — 2026-08-24/25
Commits `a6e8993`..`526e2fa`. Customers now get a soft scoring bonus toward
specific next activities based on what they just finished (drink→socialise,
darts→drink, darts↔socialise), via a new `PreviousActivityAffinityCondition`
and `.tres` data — no new branching in `CustomerBrain`. Darts now supports a
genuine second participant: `ActivityDefinition` gained
`min_participants`/`max_participants`, `TavernActivityPoint` gained
multi-slot support via new `TavernActivitySlot` children, and a nearby
customer is co-opted through a new `Customer.find_nearby_activity_partner()`
— reusing the existing reservation framework rather than a new one. Found
and fixed along the way: `return_to_seat` could be selected by normal
competitive scoring instead of only ever being entered directly. Added a
real customer picker to the F9/F10 dev panels (previously always "customer
index 0"). **Gap:** no dedicated automated test for solo/two-player darts
landed — see `TASKS.md`. Full detail: `CUSTOMER_AI_SYSTEM.md`,
`CURRENT_STATE.md`.

## On `main`

### Repair pass on confirmed P1/P2 bugs — 2026-08-24
`7d242cb`. Fixed: a dead `patience_expired` stat (renamed to
`repeated_neglect` without updating 5 consumers), a leave-decision window
that could interrupt an active order, a duplicate dartboard-texture resource
UID, a freed-instance crash in `SocialPresenceService`, a use-after-await
crash in `seated_group_probe`, and an orphaned-process leak in
`tools/run_tests.ps1`'s timeout handling. Re-measured group success and task
cancellation at 1x speed after finding that `WorldTime.set_speed()` only
scales the world clock, not staff movement — the earlier high-speed
measurements had been overstating both failure rates.

### Phase A — visit-duration bands, leave-decision window, `repeated_neglect` — 2026-08-19
`4923617` (shipped without a commit-message disclosure or doc entry;
documented for the first time by the pass above). Customer types can carry a
per-type visit-duration band; a "leave decision window" gives a customer one
extra scored chance to choose to leave before the hard visit timer; patience
now takes several missed orders (`abandoned_orders_before_leaving`) rather
than one slow serve before the customer leaves.

### Project-memory documentation layer established — 2026-08-24
`4923617`, `19a446b`, `d51e6c8`. Added `CLAUDE.md` plus `GAME_DESIGN.md`,
`CURRENT_STATE.md`, `DECISIONS.md`, `ROADMAP.md`, `AI_WORKFLOW.md` under
`docs/`; added `.claude/commands/` workflow commands and
`tools/run_tests.ps1`.

## Earlier phases (see `docs/history/` for full reports)

- **Phase 2C** — tavern activities, social behaviour, reasons to stay
  (Socialise at Seat, the generic `TavernActivityPoint` framework, Darts as
  its proof-of-concept). Documented directly in `CUSTOMER_AI_SYSTEM.md`
  rather than a dated report.
- **Phase 2A / 2B / 2B1 / 2B2** — customer AI balancing passes. See
  `docs/history/PHASE_2A_CHANGE_REPORT.md` through
  `docs/history/PHASE_2C_CHANGE_REPORT.md`.
- **Phase 3A / 3A1 / 3A2 / 3B** — staff task system, refinement, debug
  integration, the bartender role. See `docs/history/PHASE_3A_CHANGE_REPORT.md`
  and siblings.
- **Phase 4A** — daily cycle, end-of-day summary, statistics. See
  `docs/history/PHASE_4A_*.md`.
- **Group framework** — build-out and reliability passes. See
  `docs/history/GROUP_*.md` and `docs/history/BASIC_GROUP_LOOP_*.md`.
