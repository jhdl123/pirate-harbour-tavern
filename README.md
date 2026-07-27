# Pirate Harbour Tavern

A desktop-first 2D tavern management game being built in Godot 4.7.1.

The project currently focuses on a small but expandable service loop: customers enter, choose seats, order drinks, wait for service, drink, pay, leave a dirty glass, and exit. The player serves drinks and cleans tables while managing time, movement and money.

## Current playable loop

1. Customers spawn and queue at the tavern door.
2. A customer enters and reserves an available chair.
3. The customer orders a drink according to their `CustomerType`.
4. The player collects the correct drink from a drinks station.
5. The player serves the customer.
6. The customer drinks, pays and leaves.
7. The chair receives an empty-glass cleaning task.
8. Cleaning can produce broken glass and an economy penalty.
9. The chair becomes available again after cleaning is completed.

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
ActionRunner    → runs timed player actions
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
simulation state.

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
docs/                         Project documentation
assets/                       Art and other game assets
```

## Running the project

1. Install Godot 4.7.1 or a compatible Godot 4 version.
2. Open `project.godot` from the repository root.
3. Allow Godot to import assets.
4. Run the main scene with F6/F5 as appropriate.

## Current development status

Completed foundations include:

- player movement and interaction;
- customer spawning, queueing, seating and navigation;
- configurable customer types;
- configurable drink definitions;
- serving, patience, payment and tips;
- cleaning tasks and broken-glass complications;
- generic timed actions with movement blocking and cancellation;
- centralised economy and HUD updates;
- configurable navigation and debugging values;
- a generic item, slot, container and transfer foundation;
- a reusable carrier component replacing drink-specific carrying;
- a 12-slot personal inventory component, ready but not yet used;
- a bar counter with three working service slots;
- a reusable interaction framework covering detection, selection,
  highlighting, prompts and execution;
- a reusable actor navigation framework covering movement, steering,
  avoidance, arrival and recovery;
- a generic reservation system shared by seats and future workstations;
- a world time framework with a single authoritative clock and a scheduler
  that survives pausing, speed changes and skipped time;
- a simulation state framework that decides centrally what may update.

The next planned foundations are chair service slots, storage containers and
drink stock. See [Item System](docs/ITEM_SYSTEM.md) for how those should
connect, and [Interaction System](docs/INTERACTION_SYSTEM.md) for migrating
the chair and customer off the legacy interaction fallback.
