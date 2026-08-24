# Pirate Harbour Tavern

A desktop-first 2D tavern management game being built in Godot 4.7.1.

Customers spawn, queue, enter, are seated (solo or in groups), order and are
served drinks by the player or by staff, socialise, pay and leave; cleaning,
stock and staff task assignment run alongside. See
[`docs/CURRENT_STATE.md`](docs/CURRENT_STATE.md) for verified status per
system, [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md) for the intended
experience, and [`docs/ROADMAP.md`](docs/ROADMAP.md) for what's next.

## Controls

| Input | Action |
|---|---|
| WASD / arrow keys | Move |
| E | Interact with the selected object |
| Tab | Cycle to the next nearby object |
| Escape | Cancel a cancellable action |
| F1 | Toggle the simulation debug panel |
| F2 | Pause / resume the simulation |
| F3 | Cycle time speed |
| F4 | Skip to the next hour |
| M | Open the bar management menu |
| F10 | Open the stock/diagnostics dev panel (debug builds) — see `CLAUDE.md` |
| Mouse wheel / configured zoom inputs | Camera zoom |
| Mouse | Menus and UI |

## Project principles

The project prioritises systems that are:

- data-driven rather than hard-coded;
- configurable in Godot resources;
- reusable across future mechanics;
- easy to balance without changing scripts;
- readable enough to support learning and debugging.

Examples include `ItemDefinition`, `DrinkDefinition`, `ItemContainer`, `CustomerType`, `CleaningTask`, `ActionDefinition`, `GameConfig` and `EconomyManager`.

## Core architecture

```text
ItemDefinition  → item identity, tags, stack size, textures and prices
DrinkDefinition → an ItemDefinition plus drink timing and break multiplier
ItemContainer   → reusable slots for hands, backpacks, storage and stations
ItemTransferService → the one place items move between slots
WorldTime       → the one authoritative clock, with scheduling
Simulation      → the authoritative game state; nothing self-decides to update
ActorNavigation → paths, steers, arrives and recovers for any AI actor
ActorMovement   → the one place an actor's velocity is written
Reservable      → seats, approach points and queue slots, claimed generically
Interactable     → marks an object as interactive and lists its actions
InteractionSelector → picks the target, drives highlight and prompt
CustomerType    → spawning, speed, patience and drink preferences
CleaningTask    → cleaning state, complication chance, cost and next task
ActionDefinition→ duration, movement blocking and cancellation
ActionRunner    → runs timed actions, for the player and for staff alike
TaskBoard       → the one list of work the tavern needs doing
StaffMember     → a worker that claims tasks and performs them
StaffTaskExecutor → how one kind of task is actually carried out
Comms           → notifications, alerts and speaker messages
EconomyManager  → owns all money changes
GameConfig      → global spawning, navigation, door and test settings
```

See [Architecture](docs/ARCHITECTURE.md) for the current system flow,
[Item System](docs/ITEM_SYSTEM.md) for items, inventory and transfers, and
[Interaction System](docs/INTERACTION_SYSTEM.md) for target selection,
prompts and how to make a new object interactive, and
[Navigation System](docs/NAVIGATION_SYSTEM.md) for actor movement, avoidance,
arrival and reservations, and
[Simulation System](docs/SIMULATION_SYSTEM.md) for world time, scheduling and
simulation state, and
[Customer AI System](docs/CUSTOMER_AI_SYSTEM.md) for how customers decide
what to do, and how to add new activities, behaviours and customer types, and
[Staff and Task System](docs/STAFF_TASK_SYSTEM.md) for how work reaches a
worker and how to add a new task type or staff role, and
[Communication System](docs/COMMUNICATION_SYSTEM.md) for notifications,
management alerts and stock warnings.

## Changing game balance

Most common values can be edited without touching code. See [Configuration and Balancing Guide](docs/CONFIGURATION_GUIDE.md) for exact files and Inspector fields covering:

- drink prices and drink times;
- breakage chances and costs;
- cleaning durations;
- customer speeds, patience and preferences;
- spawn timing and customer limits;
- door timings;
- player speed;
- testing switches.

## Main folders

```text
Data/                         Item and action resource instances
resources/                    Customer, cleaning and global config resources
scenes/                       Godot scenes
scripts/                      Gameplay scripts, components and domain resources
systems/                      Reusable action, economy, item, inventory and time systems
tests/                        Technical validation scenes, not part of gameplay
                              (see CLAUDE.md's Testing and evidence section)
docs/                         Project documentation (docs/history/ holds
                              superseded, dated reports — historical only)
assets/                       Art and other game assets
```

## Running the project

1. Install Godot 4.7.1 or a compatible Godot 4 version.
2. Open `project.godot` from the repository root.
3. Allow Godot to import assets.
4. Run the main scene with F6/F5 as appropriate.

To run a test headlessly without opening the editor:

```text
godot --headless res://tests/<name>.tscn
```

Each test prints `[PASS]`/`[FAIL]` lines and ends with a result count. See
`CLAUDE.md`'s Testing and evidence section for the full pattern, known
baseline results, and pitfalls (watch the assertion count, not just the
failure count).
