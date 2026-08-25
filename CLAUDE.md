# Pirate Harbour Tavern — AI Working Instructions

## Project

Godot **4.7.1** 2D tavern management simulation set in a pirate/Caribbean port.

The intended experience is a believable tavern, not a fast-food service line.
Customers should spend meaningful time in the tavern, socialise, drink, join
activities, and create an evolving management problem for the player.

## Source of truth

The Git repository is authoritative for what is implemented. Do not rely on
remembered code, old chat context, ZIPs or pasted files when the repository can
answer the question.

Project-memory layer, in the order to consult it:

| File | Holds |
|---|---|
| `CLAUDE.md` | this operating manual |
| `docs/PLAN.md` | long-term vision and direction — context, not a spec |
| `docs/GAME_DESIGN.md` | intended experience and design principles |
| `docs/ROADMAP.md` | agreed, prioritised future work |
| `docs/PHASE_B_BRIEF.md` | the current work order (Phase B: customer model) |
| `docs/CUSTOMER_MODEL.md` | intended customer architecture (the Phase B target) |
| `docs/CUSTOMER_INSPECTOR.md` | inspection panel spec — debug now, information UI later |
| `docs/TASKS.md` | the current active phase only |
| `docs/CURRENT_STATE.md` | verified implementation status per system |
| `docs/DECISIONS.md` | durable decisions not to re-litigate |
| `docs/CHANGELOG.md` | living record of completed milestones |
| `docs/AI_WORKFLOW.md` | how ChatGPT / Claude Code / Git / Godot fit together |
| `docs/LEARNING_LOG.md` | Godot concepts learned + durable development lessons |
| `docs/ARCHITECTURE.md` | system ownership and data flow |
| `docs/CONFIGURATION_GUIDE.md` | where balance values live |

System-specific docs (`ITEM_SYSTEM`, `NAVIGATION_SYSTEM`, `STAFF_TASK_SYSTEM`,
`BEVERAGE_FRAMEWORK`, `CUSTOMER_AI_SYSTEM`, `GROUP_FRAMEWORK`,
`INTERACTION_SYSTEM`, `SIMULATION_SYSTEM`, `COMMUNICATION_SYSTEM`) — read only
when working in that system.

`docs/history/` holds dated change reports and patch notes (`PHASE_*.md`,
`GROUP_*.md` and similar). They record what a past pass did, not necessarily
current state. Treat them as history; prefer `CURRENT_STATE.md`.

## Architecture anchors

Autoloads (from `project.godot`) are the authoritative owners:

| Concern | Owner |
|---|---|
| Simulation state | `Simulation` — `systems/simulation/simulation_controller.tscn` |
| World time / scheduling | `WorldTime` — `systems/time/world_time.tscn` |
| Staff work | `TaskBoard` — `systems/staff/tasks/tavern_task_service.gd` |
| Notifications / alerts | `Comms` — `systems/communication/communication_service.gd` |
| Stacking modifiers | `Modifiers` — `systems/modifiers/modifier_service.gd` |
| Day lifecycle | `Tavern` — `systems/tavern/tavern_lifecycle.gd` |
| Customer behaviour events | `CustomerBehaviourEvents` |
| Interaction menus | `InteractionMenu` |

Scene-level owners (in `main.tscn` under `Managers`):

| Concern | Owner |
|---|---|
| Money | `EconomyManager` |
| Customer spawning / roster | `GameManager` (`customer_types`) |
| Orders and deliveries | `OrderManager` |
| Beverage stock (abstract) | `Cellar` (`BeverageStorage`) |
| Task creation | `TavernTaskCoordinator` |
| Diagnostics | `CustomerAIReportManager`, `StaffReportManager`, `DiagnosticRunExporter` |

Non-autoload authorities worth knowing:

- **Item movement** — `ItemTransferService`; never mutate slots directly.
- **Navigation projection** — `NavigationService.project_to_mesh_from()`.
- **Station → stock mapping** — `StationStockPlan`, derived from beverage
  content, never from a hand-set `refill_item`.
- **Physical stock display** — `StockedDisplay` observes storage; it is a view,
  never an inventory.

## Working rules

1. Inspect before editing.
2. For non-trivial work, identify affected systems and propose the approach
   before broad edits.
3. Prefer the smallest coherent change that solves the actual problem.
4. Do not modify unrelated systems.
5. Preserve the data-driven architecture.
6. Reuse existing frameworks rather than creating parallel ones.
7. Important state has one authoritative owner.
8. Player and staff use the same gameplay APIs where mechanics are shared.
9. Do not solve navigation problems by disabling navigation or avoidance.
10. World progression uses `WorldTime`, not ad-hoc timers.
11. Items move through `ItemTransferService`.
12. Use the generic interaction framework, not object-specific player searches.
13. Do not rename stable IDs used by resources or save data.
14. UI observes gameplay state; it does not own it.

## Testing and evidence

- Tests live in `tests/` as `<name>.gd` + `<name>.tscn` pairs. Run them with
  `godot --headless res://tests/<name>.tscn`. They print `[PASS]`/`[FAIL]` lines
  and end with `RESULT n passed, m failed`.
- `docs/TEST_MAP.md` maps all 49 tests to the system/area each covers, and
  says which mappings are verified (already stated elsewhere) versus inferred
  from the test itself. Use it to pick relevant tests instead of guessing or
  running everything. `tools/run_tests.ps1` runs one, several, or all tests
  headlessly with an enforced timeout and a compact per-test result line —
  see its own `-?`/comment-based help before invoking Godot by hand.
- **Watch the assertion count, not just the failure count.** A script error
  mid-run can silently skip most assertions while still printing `0 failed`.
- `godot --headless --check-only --script X.gd` gives false errors for files
  using `class_name`. Only `--headless --editor --quit` is authoritative for
  compilation.
- `godot --headless --import` is what populates `.godot/imported`. Run it first
  on a fresh clone or textures fail to load.
- Do not call behaviour broken from one short run without checking stock,
  staffing, run length, spawning and sample size.
- Use comparable run lengths when comparing.
- If a tuning change produces no meaningful movement twice, instrument instead
  of tuning again.
- State what evidence supports a conclusion and what would falsify it.

Known baseline results (not regressions):

- `group_framework_test` — 2 failures, both SEATED cases, expected while
  `standing_places_only` is on.
- `group_keg_loop_test` — 27/5, and flaky: 27/5, 28/4 and 29/3 have all appeared
  on identical builds. Compare the failure **set**, not the count.
- `group_keg_ordering_test` — 5 failures, unchanged since `0e1f3f1`.
- `group_live_test` — 18/5, all five explained: the SEATED sub-test hits the
  same `standing_places_only` cause as `group_framework_test`, and that
  redirected group leaving standing capacity occupied cascades into the
  STANDING and VISIT sub-tests that run after it in the same live scene
  (neither sub-test waits for real navigation/departure time before
  checking). Not a live gameplay bug; the test predates `standing_places_only`
  defaulting `true` and the three sub-tests were never made independent of
  each other's leftover state.
- `navigation_stress_test` — flaky, no numeric baseline yet: clean PASS 25/0
  and FAIL 24/1 ("2 of 3 travelling actors stuck") have both been observed on
  the same build. Needs several back-to-back runs to establish a range, the
  same treatment as `group_keg_loop_test`.
- `phase_4a_integration_test` — its `DOUBLE: two payments in one frame`
  check is flaky (observed both passing and failing across identical-build
  reruns); no plausible cause identified yet and nothing in this pass's
  changes touches payment recording, so treat as pre-existing until traced.

## Verification levels

Match verification effort to the change; use the lowest sufficient level.

1. **Docs/config/small change** — re-read the diff; check any doc links
   resolve. No test run needed.
2. **Local code/behaviour change** — run the relevant test(s) from
   `docs/TEST_MAP.md`; review the diff.
3. **Subsystem/feature change** — relevant subsystem tests plus tests for
   systems it touches indirectly; a diagnostic run if empirical evidence is
   needed.
4. **Major milestone/release/baseline** — full suite (`tools\run_tests.ps1
   -All`), a diagnostic run, and a check that `CURRENT_STATE.md` still holds.

`/review` picks the level for a proposed change; `/verify` and `/commit`
apply it. Do not default to Level 4 out of caution — that defeats the point.

## Standard implementation loop

1. Read this file and the relevant documentation.
2. Inspect the current implementation.
3. Identify intended behaviour and affected systems.
4. Implement the smallest coherent change.
5. Run targeted tests, then relevant regressions.
6. Run diagnostics when empirical evidence is required.
7. Report changed files, tests, results and remaining uncertainty.
8. Commit a focused change.

## Diagnostics

Press **F10** in a debug build to open the stock/diagnostics dev panel, then
choose **Export Diagnostic Run**. This writes
`debug/latest/` and `debug/archive/YYYY-MM-DD-HHMM/`, each stamped with the Git
commit that produced it. Review order: `RUN_SUMMARY.md`, `drinks_report.txt`,
`stock_report.txt`, `staff_report.txt`, `customer_report.txt`,
`system_diagnostics.txt`. See `debug/README.md`.

A startup navigation scan runs in debug builds and prints either
`NAVIGATION SCAN: all seats, slots and props are approachable` or a FAIL line
per misplaced marker.

## Git discipline

- Start from a clean, committed state.
- Use feature branches for significant work.
- Keep commits focused and descriptive.
- **Never use `git stash` as the only protection for uncommitted work** — it has
  silently shelved an entire session's changes on this project.
- Preserve unrelated user changes; re-patch rather than overwrite files the
  developer has edited.
- Prefer direct repository work over ZIP handoffs when repository access exists.

## Documentation discipline

Document durable facts, design intent, decisions, verified state and lessons.
Do not duplicate the code. Do not record speculation as implemented behaviour.
`TASKS.md` holds only the current phase; fold a completed phase into
`CHANGELOG.md` rather than letting `TASKS.md` accumulate history. Treat
`PLAN.md`'s long-term vision as context for architecture, never as a queue of
features to start implementing — a vision item becomes real work only once
it is explicitly promoted into `ROADMAP.md`. When applying a design handoff
from outside the repository, patch the affected files or state the changes
in prose for Claude Code to apply — do not extract a zip over the project
root. A previous one silently overwrote concurrent edits to `CLAUDE.md`,
`DECISIONS.md`, `ROADMAP.md` and `CURRENT_STATE.md` because it replaced
whole files instead of merging into them.
