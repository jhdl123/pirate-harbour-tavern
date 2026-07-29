# Staff and Task System

Phase 3A. Written for someone who has not seen this code before.

This document covers the work-task framework, the Tavern Hand, and how staff
share the world with the player. The message and alert side lives in
`docs/COMMUNICATION_SYSTEM.md`.

---

## 1. What changed, in one paragraph

Before Phase 3A the player did every repetitive job by hand: pour the drink,
carry it over, hand it across, then wipe the seat afterwards. Now there is one
member of staff, the Tavern Hand, who delivers prepared drinks and cleans dirty
seats. The player still prepares drinks, refills stations, moves stock and
orders more. The point of the phase is the change of role: you supervise, and
step in for stock and for anything unusual.

---

## 2. The central idea: a task is a fact, not an order

This is the one thing worth understanding before reading any code.

A `TavernTask` does **not** mean "worker, go and do this". It means "this is
true about the world right now":

- `clean_seat` — *this chair is dirty*
- `serve_drink` — *this customer is waiting for a grog*

Nothing about a task changes because a worker believes it. The world is always
the authority. That single decision is what makes almost everything else fall
out for free:

- If the player cleans the chair first, the fact stops being true. The task's
  validator notices, the board cancels it, the worker moves on. Nobody had to
  send a message.
- If a customer leaves before their drink arrives, same story.
- If a worker is deleted mid-journey, the fact is still true, so the task goes
  back on the board and somebody else can take it.

The alternative — tasks as instructions — needs invalidation plumbing running
from every gameplay system to every worker, and it goes wrong the first time
somebody forgets a callback.

---

## 3. Data flow

```text
world requirement           a chair is dirty; a customer is waiting
  -> task producer          TavernTaskCoordinator, listening to signals
  -> central task board     TaskBoard: dedup, claim, score, sweep
  -> staff evaluates        StaffMember asks select_best_task()
  -> claimed and reserved   claim() is atomic
  -> staff executes         StaffTaskExecutor drives real world APIs
  -> world confirms result  the customer really was served
  -> task completes         complete(), and the board tells everybody
```

---

## 4. The pieces

| File | Role |
| --- | --- |
| `systems/staff/tasks/tavern_task_types.gd` | Names of every kind of work |
| `systems/staff/tasks/tavern_task_definition.gd` | Resource: priority, capability, retry policy per type |
| `systems/staff/tasks/tavern_task.gd` | One live task: state, target, times, history |
| `systems/staff/tasks/tavern_task_board_config.gd` | Board-wide tuning + the definition list |
| `systems/staff/tasks/tavern_task_service.gd` | The board itself. Autoloaded as `TaskBoard` |
| `systems/staff/tavern_task_coordinator.gd` | The only thing that knows both the world and the board |
| `systems/staff/staff_capabilities.gd` | What a worker is allowed to do |
| `systems/staff/staff_definition.gd` | Resource: one staff archetype |
| `systems/staff/staff_member.gd` | The worker: state machine, navigation, recovery |
| `systems/staff/executors/staff_task_step.gd` | One instruction from executor to worker |
| `systems/staff/executors/staff_task_executor.gd` | Base class + the type→executor registry |
| `systems/staff/executors/serve_drink_executor.gd` | How serving actually works |
| `systems/staff/executors/clean_seat_executor.gd` | How cleaning actually works |
| `systems/staff/diagnostics/staff_report_manager.gd` | JSON report export |

There is exactly **one** board. Two overlapping task managers is how a drink
gets served twice and how a reservation leaks with nobody owning the cleanup.

---

## 5. Task states

```text
AVAILABLE     nobody is doing this
CLAIMED       a worker has taken it and is travelling
IN_PROGRESS   the worker is at the target and acting
BLOCKED       still needed, not doable right now
COMPLETED     the world confirmed the requirement is met
CANCELLED     the requirement went away
FAILED        it was needed, tried, and could not be done
```

`CANCELLED` and `FAILED` are deliberately different. A customer leaving is not
a failure of the tavern; a chair the worker physically cannot reach is.

`BLOCKED` matters more than it looks: a waiting customer with no matching drink
prepared is a **real** requirement that is **not yet actionable**, and the
missing ingredient is the player. Keeping it on the board is what lets the
Tavern Hand pick it up the instant you put a drink on the bar.

---

## 6. How task scoring works

Not a queue. A queue serves whoever ordered first even when someone else is
thirty seconds from walking out.

Every candidate task gets a score, highest wins:

```text
  base_priority          from the task definition
+ urgency  x weight      how close this customer is to leaving
+ age bonus (capped)     anti-starvation, so awkward jobs still get done
- distance x weight      gentle: breaks ties, does not decide what matters
+ carried-item bonus     already holding the right drink? finish that job
- failures x penalty     things that already defeated us go to the back
```

Every weight lives on the `TavernTaskDefinition` resource. None of it is in the
worker script, so balancing how eagerly staff clean versus serve is editing
two `.tres` files.

Current relative priorities:

| Task | Base | Notes |
| --- | --- | --- |
| `serve_drink` | 100 | Urgency weight is high, so an impatient customer effectively reaches ~180 |
| `clean_seat` | 45 | A dirty seat blocks a seat, so it is never ignored, but it never beats a waiting customer |

`explain_score()` returns the same terms broken out, and the F10 panel prints
it. If a choice ever looks wrong, that is where to look first.

---

## 7. The Tavern Hand

`scenes/staff/tavern_hand.tscn`, configured by `Data/staff/tavern_hand.tres`.

Structurally it is the same kind of actor as a customer:

- `CharacterBody2D` + `NavigationAgent2D`
- `ActorMovement` + `ActorNavigation` — the shared navigation framework, no
  private movement code
- `ItemCarrier` — the same component the player uses to hold a drink
- `ActionRunner` — the same component that runs the player's cleaning action
- `Interactable` — so the player can select and inspect it
- `StaffSpeechBubble` — a short line above their head

Capabilities are `serve_drinks` and `clean_seats`. Nothing else. Give the
resource a different capability list and the same scene becomes a different
worker.

### States

```text
IDLE               nothing to do, standing at the idle point
EVALUATING_TASKS   asking the board what is worth doing
MOVING_TO_SOURCE   walking to the bar to collect a drink
COLLECTING_ITEM    taking the drink out of the service slot
MOVING_TO_TARGET   walking to the customer or the chair
PERFORMING_TASK    serving, or running the cleaning action
COMPLETING_TASK    telling the board the world confirmed it
RECOVERING         navigation failed; pausing before re-planning
RETURNING_TO_IDLE  nothing to do; walking back to the idle point
PAUSED             the player switched them off
```

---

## 8. How staff share the world with the player

This is the part that must not be fudged, so it is worth being explicit.

### Serving

`Customer.interact(player)` used to hold all the serving logic. Its body moved
into **`Customer.try_serve(actor) -> bool`**, and `interact()` now calls that.
So:

- the player's path is unchanged, one call deeper
- staff call the identical method
- there is one place where a customer becomes served

The worker collects the drink with `ItemCarrier.take_from(service_slot)` — the
same `ItemTransferService` transfer the player performs. One `ItemStack` leaves
the counter and arrives in the worker's hands.

**No drink is spawned. No station stock is consumed a second time. There is no
staff-only representation of a drink anywhere.** If you deleted the whole staff
system, the player could still do every step by hand.

### Cleaning

Same pattern. `Chair.interact(player)` body moved into
**`Chair.try_clean(actor) -> bool`**, which calls
`CleanableComponent.start_cleaning(runner)` with the actor's own `ActionRunner`.

Duration, cancellation and the broken-glass complication therefore behave
identically whoever is holding the rag. The worker never sets a cleanliness
flag.

---

## 9. Reservations and concurrency

Two workers must never claim one task, collect one drink, serve one customer or
clean one seat.

**Task claims** are atomic. `TaskBoard.claim()` checks the state and assigns the
worker with no `await` between the two, so whichever call runs second sees a
task that is no longer `AVAILABLE` and is refused.

**Deduplication by target key** means a second task for the same chair or the
same customer cannot exist in the first place.

**Node reservations** use the existing `Reservable` component, and the board
owns the list, so every exit path — complete, cancel, release, fail, sweep —
releases the same set. That single ownership is what stops reservations leaking
when a worker is destroyed mid-journey.

### An honest note on bar service slots

A service slot is an `ItemSlot` inside an `ItemContainer`, not a node, so it
**cannot** hold a `Reservable` child. Exclusivity there comes from the board
instead: a slot already named by another live serve task is skipped when
looking for a drink.

This was a deliberate decision rather than generalising `Reservable` into
something it is not. The consequence is that the player *can* still take a
drink a worker was walking towards — and that is correct. The worker arrives,
finds the slot empty, re-plans, and either finds another matching drink or
releases the task. Authoritative world state wins.

---

## 10. Recovery: what happens when things go wrong

The worker must never become permanently stuck. Every one of these is handled:

| Situation | What happens |
| --- | --- |
| Task disappears | Validator fails, board cancels, worker picks another |
| Customer leaves | Same; if the worker is holding the drink it puts it back on the bar |
| Player takes the reserved drink | Worker re-plans, finds another or releases |
| Player serves the customer first | `is_awaiting_service()` is false, task released |
| Player cleans the seat first | `can_start_cleaning()` is false, task cancelled |
| Navigation fails | Pause, then re-plan; after N failures, return to idle and release |
| Target deleted | Weak references resolve to null, task cancelled |
| Worker deleted mid-task | Board sweep finds a claim with no worker, releases it |
| Claim goes nowhere | World-minute timeout takes the task back |
| Carried item changes | Task released rather than silently dropping the item |

Nothing teleports. The only teleport in the system is behind an explicitly
labelled developer button.

---

## 11. How to add another task type

Four steps, none of which touch `StaffMember`:

1. Add the id to `TavernTaskTypes`.
2. Create a `TavernTaskDefinition` `.tres` and add it to
   `Data/staff/task_board_config.tres`.
3. Create or extend a producer that calls `TaskBoard.create_task()` and
   registers a validator via `TaskBoard.register_validator()`.
4. Subclass `StaffTaskExecutor` and register the script in its
   `EXECUTOR_SCRIPTS` dictionary.

## 12. How to add another staff role

1. Duplicate `Data/staff/tavern_hand.tres`.
2. Change `archetype_id`, `display_name`, `role_name` and, most importantly,
   `capabilities`.
3. Instance `tavern_hand.tscn` again and point its `definition` at the new
   resource.

No new scene, no subclass, no branch anywhere.

---

## 13. Configuration reference

| What | Where |
| --- | --- |
| Task priorities, urgency, retries, timeouts | `Data/staff/tasks/*.tres` |
| Which task types exist; sweep rate; history caps | `Data/staff/task_board_config.tres` |
| Staff capabilities, reach, evaluation rate, recovery | `Data/staff/tavern_hand.tres` |
| Staff movement and avoidance | `Data/navigation/staff_movement.tres`, `staff_navigation.tres` |
| Stock thresholds | Per-station exports on each `DrinksStation` |

---

## 14. Diagnostics

`StaffReportManager` writes JSON to `user://staff_reports/`. On Windows that is
`%APPDATA%\Godot\app_userdata\PirateHarbourTavern\staff_reports\`.

Export it from the F10 panel, or call `finalize_and_write_report()`.

Sections: `staff`, `tasks` (open, finished, issues) and `communication`.
Each task carries its full state and reservation history, so you can follow one
job from creation to completion and see the score it was chosen on.

Issue types recorded include `duplicate_task`, `stale_task_claim`,
`leaked_reservation`, `staff_navigation_failed`, `invalid_task_target`,
`missing_prepared_item`, `item_transfer_failure`,
`attempted_duplicate_service` and `attempted_duplicate_cleaning`.

Normal expected recovery is recorded but is not treated as severe. That
distinction is deliberate: a report full of red for ordinary events is a report
nobody reads.

---

## 15. Current limitations

- One worker is instanced in `main.tscn`. The design supports several — nothing
  assumes a single worker — but multi-worker behaviour has not been tuned.
- Staff only serve from bar counters, never from a drink station's output slot.
  That is intentional: pouring is the player's job this phase.
- The worker's idle position is a fixed marker. No shifts, breaks or schedules.
- Path feasibility is not part of task scoring. A worker may choose a task it
  then discovers it cannot reach; recovery handles it, but the choice was not
  informed. `NavigationService.get_path_length()` exists for this when it
  becomes worth the cost.
- No wages, hiring, fatigue, morale or progression. Deliberately out of scope.

## 16. Recommended next steps

1. **A second worker.** Everything is built for it; it mostly needs balancing
   and a second idle point.
2. **`refill_station` as the next task type.** It is the natural next one and
   exercises the stock storage side of the item system.
3. **Path-aware scoring**, once there are enough tasks for a bad choice to
   actually cost something.
4. **Staff-attributed dialogue with choices** — the message model already
   carries actions and the UI already routes a choice back to the speaker.
