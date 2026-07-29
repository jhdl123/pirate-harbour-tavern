# Phase 3A — Change Report

**Reusable Staff Task System, Tavern Hand and Communication Framework**

Godot 4.7.1. Built on the Phase 2C project as supplied.

---

## 1. Summary

One member of staff — the Tavern Hand — now delivers prepared drinks to waiting
customers and cleans dirty seats, using the same world systems the player uses.
Behind that sit three reusable foundations:

- a **generic work-task framework** with priorities, atomic claims, scoring,
  retry policy and structured diagnostics
- a **staff framework** built from data, so a second role is a `.tres` file
- a **communication framework** covering notifications, persistent management
  alerts and speaker messages, with deduplication, escalation and automatic
  resolution

The player's role is unchanged in substance but different in feel: you prepare
drinks, refill stations, move stock, order more, and handle anything unusual.
The repetitive carrying and wiping is delegated.

Everything was verified by running the project headless in Godot 4.7.1.
**41 automated checks pass, 0 fail.** A 6000-frame soak produced no script
errors, no leaked reservations and no recorded issues.

---

## 2. Architecture decisions

### A task is a fact about the world, not an instruction to a worker

`clean_seat` means *this chair is dirty*, not *worker, go and clean*. The world
is always the authority; the board asks it via per-type validators.

This is why player overrides need no plumbing at all. Clean the chair yourself
and the fact stops being true, so the validator fails and the task is cancelled.
Nothing had to notify anything.

### One board, indexed, never scanning

There is a single `TaskBoard` autoload. Tasks are indexed by id, by type and by
target key, so "is there already a cleaning task for this chair?" is a
dictionary lookup. No system scans the scene tree per frame. The only periodic
work is a sweep a couple of times a second over open tasks.

### Executors, so the worker never learns gameplay

`StaffMember` owns navigation, the action runner, recovery and reporting, and
knows nothing about drinks or chairs. A `StaffTaskExecutor` knows everything
about one kind of work and owns no movement code. They meet at a five-value
`StaffTaskStep`.

Executors re-plan from the world every time they are asked, which is what makes
them self-correcting when the player interferes.

Adding a task type therefore never edits `StaffMember`.

### Shared service and cleaning APIs, extracted rather than copied

`Customer.interact()` and `Chair.interact()` each had their body moved into a
new `try_serve(actor)` / `try_clean(actor)`, with `interact()` calling it. The
player path is unchanged, one call deeper; staff call the identical method.
There is one place where a customer becomes served and one place where cleaning
starts.

### Stations own facts; communication owns messages

`DrinksStation` gained thresholds, a hysteresis state machine and a
`stock_state_changed` signal. It knows nothing about toasts or severity.
`StockAlertCoordinator` translates state changes into one deduplicated alert
lifecycle. The Tavern Hand never scans stations; stations never look for staff.

### Where the existing reservation system was and was not reused

`Reservable` is used for node-backed reservations, and the board owns the list
so every exit path releases the same set.

A bar service slot is an `ItemSlot` inside an `ItemContainer`, **not a node**,
so it cannot hold a `Reservable`. Rather than distort `Reservable` into
something it is not, slot exclusivity comes from the board: a slot named by
another live task is skipped. The consequence is that the player can still take
a drink a worker was walking towards — which is correct. The worker arrives,
finds it gone, and re-plans.

This is called out because it is the one place the brief's preferred approach
was not literally followed.

---

## 3. New files

**Task framework** — `systems/staff/tasks/`
`tavern_task_types.gd`, `tavern_task_definition.gd`, `tavern_task.gd`,
`tavern_task_board_config.gd`, `tavern_task_service.gd`

**Producers** — `systems/staff/`
`tavern_task_coordinator.gd`

**Staff** — `systems/staff/`
`staff_capabilities.gd`, `staff_definition.gd`, `staff_member.gd`,
`staff_speech_bubble.gd`

**Executors** — `systems/staff/executors/`
`staff_task_step.gd`, `staff_task_executor.gd`, `serve_drink_executor.gd`,
`clean_seat_executor.gd`

**Diagnostics** — `systems/staff/diagnostics/`
`staff_report_manager.gd`

**Communication** — `systems/communication/`
`comm_message.gd`, `communication_config.gd`, `communication_service.gd`,
`stock_alert_coordinator.gd`, `ui/communication_ui.gd`

**Scenes**
`scenes/staff/tavern_hand.tscn`, `scenes/ui/communication_ui.tscn`

**Data**
`Data/staff/task_board_config.tres`, `Data/staff/tasks/serve_drink.tres`,
`Data/staff/tasks/clean_seat.tres`, `Data/staff/tavern_hand.tres`,
`Data/navigation/staff_movement.tres`, `Data/navigation/staff_navigation.tres`,
`Data/communication/communication_config.tres`

**Tests**
`tests/phase_3a_headless_test.gd` / `.tscn` — the verification harness
`tests/staff_system_tests.gd` / `.tscn` — unit-level checks

**Documentation**
`docs/STAFF_TASK_SYSTEM.md`, `docs/COMMUNICATION_SYSTEM.md`

---

## 4. Modified files, and why

| File | Lines | Why |
| --- | --- | --- |
| `project.godot` | +2 | Autoloads `TaskBoard` and `Comms`, placed after `WorldTime` because both use the world clock in `_ready`. No input-map changes. |
| `scenes/main/main.tscn` | additive | Instances the Tavern Hand and communication UI, adds three manager nodes, wires the F10 panel. Nothing existing removed or reparented. |
| `scripts/Entities/customer.gd` | 1847→1963 | Serving body extracted into `try_serve(actor)`; added `is_awaiting_service()`, `get_requested_drink()`, `get_service_urgency()`, `get_service_approach_position()` and a `service_state_changed` signal so tasks are event-driven. No behaviour change to the AI. |
| `scripts/Interactables/chair.gd` | 606→645 | Cleaning body extracted into `try_clean(actor)`; added `needs_cleaning()`. |
| `scripts/Interactables/drinks_station.gd` | 195→312 | Stock thresholds, a `StockState` enum with hysteresis, `stock_state_changed`, `get_stock_state()`. The station owns its factual state. |
| `scripts/Interactables/bar_counter.gd` | 574→581 | Joins the `bar_counters` group so staff can find service slots without a hard reference. |
| `scripts/Managers/game_manager.gd` | 636→648 | Emits `customer_spawned` so the coordinator can wire new customers without polling. |
| `scripts/UI/stock_dev_panel.gd` | 276→839 | Four new F10 sections: Staff, Tasks, Communication, Diagnostics. Existing buttons unchanged. Now scrollable. |

---

## 5. Autoload, scene, input and configuration changes

**Autoloads added** (after `WorldTime`, before nothing that matters):

```text
TaskBoard = "*res://systems/staff/tasks/tavern_task_service.gd"
Comms     = "*res://systems/communication/communication_service.gd"
```

**Scene changes to `main.tscn`** — all additive:

- `Entities/TavernHand` — instance of `tavern_hand.tscn`
- `Managers/TavernTaskCoordinator`, `Managers/StockAlertCoordinator`,
  `Managers/StaffReportManager`
- `CommunicationUI` — instance of `communication_ui.tscn`
- three new NodePath exports on the existing `StockDevPanel`

**Input map:** unchanged. F10 still opens the developer panel.

**New configuration resources:** listed in §3. Tuning lives there, not in
scripts.

---

## 6. F10 developer tools

Four new sections, grouped, in the existing panel:

**Staff** — spawn/reset Tavern Hand, enable/disable staff AI, pause/resume,
show worker state, return to idle, force navigation failure (clearly labelled
as the only teleport in the system).

**Tasks** — show task board, show claimed tasks, show reservations, create test
serve task, create test cleaning task, force-release current task, rescan world.

**Communication** — trigger low-stock warning, trigger out-of-stock alert,
trigger stock-restored resolution, trigger staff dialogue, list active alerts,
acknowledge selected, resolve all test alerts, clear history.

**Diagnostics** — export the staff/task/communication report.

Example worker readout:

```text
Worker: tavern_hand_01
State: MOVING_TO_SOURCE
Task: serve_drink_00017
Source: BarCounter slot 2
Reserved item: grog
Target customer: Sailor8
Path status: active
Retry count: 0
```

---

## 7. Test procedure

Automated, from the project root:

```bash
godot --headless --path . res://tests/phase_3a_headless_test.tscn
```

This loads the **real** main scene and drives the real systems — no mocks. It
prints one PASS/FAIL line per behaviour and exits non-zero on failure.

Current result: **41 checks, 0 failed.**

Manual scenarios are in `TEST_CHECKLIST.md`.

---

## 8. One real bug found and fixed during verification

Worth recording because it was found by testing rather than reading.

Cleaning an empty glass can break it — existing gameplay — leaving the chair
needing a second, different clean. The `task_changed` signal announcing the
broken glass fired **while the original cleaning task was still live**, so
deduplication correctly refused to create a second task. The first task then
completed, and the still-dirty chair had no task at all. The seat would have
stayed dirty indefinitely.

Fix: `TavernTaskCoordinator` now listens to the board's `task_completed` and
`task_cancelled` signals and re-checks the chair once the old task has retired.
Deliberately **not** connected to `task_failed`: a task that exhausted its
failure budget is one the tavern could not do, and recreating it would spin
forever on, say, a walled-off chair. That case is recorded as an issue and
revived by the F10 rescan instead.

---

## 9. Known limitations

- One worker is instanced. The design supports several and nothing assumes a
  single worker, but multi-worker behaviour is untuned.
- Path feasibility is not part of task scoring. A worker may pick a task it
  then finds it cannot reach; recovery handles it, but the choice was
  uninformed. `NavigationService.get_path_length()` is there when it is worth
  the cost.
- Pending deliveries are not counted in the replacement-stock figure shown in
  alerts.
- Speaker choices are modelled and routed but not drawn as buttons. Portraits
  are modelled and not displayed.
- The communication UI is functional, not styled.
- Sound is a hook, not an implementation.

## 10. Deferred work

Everything in the brief's exclusion list: drink preparation, station refilling,
stock running, supplier ordering, delivery unloading, hiring, wages, schedules,
fatigue, morale, relationships, progression, accommodation, multiple
specialised workers, roster management, branching dialogue, quests, factions,
combat, save/load redesign, final artwork.

Extension points exist for each; none are implemented.

---

## 11. Regression risks

Judged low, and specifically checked:

| Risk | Mitigation |
| --- | --- |
| Customer AI behaviour drift | `try_serve` is the old `interact` body verbatim. Soak run shows unchanged spawn → seat → order → drink → pay → leave. |
| Chair cleaning behaviour drift | `try_clean` is the old body verbatim; `CleanableComponent` untouched. |
| Extra drinks or double-charging | Verified: exactly one drink leaves the bar per serve; payment flow untouched. |
| Navigation regression for customers | `ActorNavigation` untouched. Staff use their own profile resources. |
| Performance | No per-frame tree scans. Board sweeps twice a second over open tasks only. |
| Autoload ordering | `TaskBoard` and `Comms` are declared after `WorldTime`, which both use in `_ready`. |

**Areas most worth watching in your own play testing:** the worker's chosen
standing positions near the bar and chairs, since those are derived by
projecting onto the navigation mesh rather than from hand-placed markers.

---

## 12. Rollback guidance

The phase is additive. To disable it without reverting code:

1. Remove the `TaskBoard` and `Comms` autoloads from `project.godot`.
2. Delete `Entities/TavernHand`, `CommunicationUI` and the three new
   `Managers/` nodes from `main.tscn`.

The game returns to Phase 2C behaviour. The extracted `try_serve` and
`try_clean` methods stay and are harmless — `interact()` calls them and the
player path is identical.

For a full revert, delete `systems/staff/`, `systems/communication/`,
`Data/staff/`, `Data/communication/`, `scenes/staff/`,
`scenes/ui/communication_ui.tscn`, and restore the eight modified files.

---

## 13. Assumptions made, stated honestly

1. **The Tavern Hand's starting position** was inferred from the room layout
   (open floor between the bar and the tables) and verified as walkable at
   runtime. It is a reasonable spot, not a designed one — nudge it in the editor
   if you dislike it.
2. **Stock thresholds** default to 4 low / 8 reset / 0 empty against a
   20-serving station. Chosen to demonstrate the lifecycle clearly; they are
   exported for balancing.
3. **Staff serve only from bar counters**, never from a station's output slot,
   because taking from a station consumes stock and pouring is the player's job
   this phase.
4. **Task priorities** (serve 100, clean 45) follow the brief's recommended
   ordering. They are a starting point.
5. **The placeholder sprite** uses an existing `32x32_staff_*.png` asset already
   in the project. No player or customer art was touched.
6. **"Selected customer/alert"** in the F10 tools means the first in the
   relevant list, matching the existing convention in that panel.
