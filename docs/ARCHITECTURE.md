# Current Architecture

## Design goal

Gameplay systems should depend on reusable definitions and managers rather than embedding balance values in individual scripts.

## Items and drink flow

A drink is an item. `DrinkDefinition` extends `ItemDefinition`, so there is one
resource per drink holding both its item identity and its drink balance.

```text
ItemDefinition
    ├── stable item_id
    ├── tags (drive every slot and container rule)
    ├── maximum stack size
    ├── icon / world / carried textures
    ├── base buy and sell prices
    └── preferred destination
        │
        └── DrinkDefinition
                ├── drinking duration
                ├── order icon
                ├── empty and broken container textures
                └── break chance multiplier

CustomerType
    └── available and preferred DrinkDefinitions

DrinksStation
    └── output ItemContainer (1 slot)
            └── ItemTransferService ──> Player's ItemCarrier

Player
    ├── ItemCarrier        → one ItemSlot → one ItemStack
    └── InventoryComponent → ItemContainer (12 slots, unused for now)

Customer
    └── validates the carried item_id, then consumes it
```

The player no longer stores a carried drink. The carrier's slot is the only
source of truth for what is in the player's hands.

## Item system

```text
ItemDefinition      what an item is
ItemStack           how many, and in what condition
ItemSlot            one position holding zero or one stack
    └── ItemSlotRules   capacity, tag filters, permissions
ItemContainer       a fixed, ordered set of slots
ItemTransferService the ONE place items move
    └── ItemTransferResult
ItemCarrier         component: an actor's hands
InventoryComponent  component: an actor's backpack
ItemRegistry        stable item id → ItemDefinition, for save/load
ItemTags            named tag constants
```

Every transfer — player, staff, storage, trays, shops and future UI — goes
through `ItemTransferService`, which validates the whole transaction before
mutating either side. Items are never duplicated, lost or silently overwritten.

Full detail, including how to add items and how future bar slots, trays and
storage should connect, is in [Item System](ITEM_SYSTEM.md).

## Interaction

```text
Player
├── InteractionDetector   Area2D   "who is within reach"
└── InteractionSelector   Node     "which one do we mean"
        ├── scoring: distance + priority + stickiness
        ├── TAB cycling with a manual hold
        ├── highlight lifecycle
        └── prompt signals
                │
                └── InteractionSelectionRules (Resource)

Interactive object
├── Interactable          Area2D   the object's whole public surface
├── InteractionHighlight  Node     reusable default highlight
└── root node             the provider: all gameplay lives here

UI (CanvasLayer)
└── InteractionPrompt              the ONE prompt in the game
```

The framework detects, selects, highlights, prompts and executes. It holds no
gameplay state and knows no object types. Objects answer three questions —
"am I worth offering", "what could this actor do", "do this thing" — and
perform the work with the systems they already own.

```text
E pressed
    └── player.try_interact()
            └── selector.perform_primary()
                    └── interactable.perform(request)
                            └── BarCounter.perform_interaction()
                                    └── ItemTransferService.transfer(...)
```

The player knows nothing about bars, stations, customers or storage. The
selector moves an opaque `action.id` and `action.data` from the object that
offered them back to that same object.

Bar Counter and Drinks Station implement the full protocol. Chair and Customer
run on a legacy fallback that gives them highlighting and prompts without any
change to their scripts.

Full detail, including how to create a new interactable and how future
secondary actions and mouse interaction plug in, is in
[Interaction System](INTERACTION_SYSTEM.md).

## Navigation and reservation

```text
Actor (CharacterBody2D)
├── NavigationAgent2D
├── ActorMovement      owns velocity and the ONE move_and_slide()
│       └── ActorMovementProfile (Resource)
└── ActorNavigation    path, steering, arrival, avoidance, recovery
        └── ActorNavigationProfile (Resource)

NavigationDestination  value object: "go here, like this"
    └── optional Reservable, so losing a claim invalidates the journey

NavigationService      static: map readiness, projection, reachability, cost

Reservable             Node: FREE -> RESERVED -> OCCUPIED, with expiry
ReservationService     static: search and claim across a set
ApproachPoint          Marker2D: "stand here to use me", reservable
```

An actor asks for a destination and is told when it arrives:

```text
customer.gd  ──move_to──>  ActorNavigation  ──request_velocity──>  ActorMovement
     ^                            │
     └────destination_reached─────┘
          destination_failed
```

The customer state machine is unchanged - enter, stage, sit, order, drink, pay,
leave - but it no longer measures distances, manages an agent, or writes
velocity. Staff, NPCs and animals become the same two components with different
profile resources.

Seat state moved off `Chair` and onto the generic `Reservable`, so queue slots,
station approach points and future workstations claim themselves with the same
two-stage rules and the same expiry safety net. `Chair` keeps its whole public
API, so `Table`, `GameManager` and `Customer` are untouched.

Full detail, including why each old behaviour was wrong and how future staff
reuse the system unchanged, is in [Navigation System](NAVIGATION_SYSTEM.md).

## Cleaning and actions

```text
Chair
    └── CleanableComponent
            └── CleaningTask
                    ├── ActionDefinition
                    ├── task texture
                    ├── complication chance
                    ├── complication task
                    └── complication cost

Player
    └── ActionRunner
            ├── starts ActionDefinition
            ├── tracks progress
            ├── blocks movement when configured
            ├── supports cancellation
            └── emits completion/cancellation signals
```

The chair owns the cleaning state. The player owns performance of the timed action. Cleaning does not use a chair-specific timer.

## World time and simulation

```text
Simulation (autoload)          the authoritative "is the game running"
    ├── SimulationState        enum + stable ids
    ├── SimulationStateRules   Resource: what each state permits
    └── state stack            push/pop, so dialogue and menus restore cleanly

WorldTime (autoload)           the one authoritative clock
    ├── WorldClock             the model. Plain object, no node, no signals.
    ├── TimeScheduler          "call me at this world time"
    ├── GameTimeStamp          a moment, as a comparable value
    ├── GameTimeConfig         calendar, rate, speeds, formatting
    └── TimeFormatter          moments and durations into text
```

`Simulation` knows nothing about time; `WorldTime` asks it for permission each
frame. That one-way dependency is what lets fast-forward, dialogue and cutscenes
arrive later without either framework learning the other's internals.

The distinction that matters most:

```text
signals     react to the moment the world is in now; a large skip
            collapses them, so a listener may miss one
scheduler   never misses; every booking inside a skipped window fires,
            in order, with the clock standing at the booked moment
```

A HUD reads signals. A wage payment, a delivery or a production run books with
the scheduler. No gameplay system creates a `Timer` for world progression.

Both frameworks serialise through `to_dictionary()` / `apply_dictionary()`, and
simulation state is saved by stable string id rather than enum integer.

Full detail, including how future systems subscribe and how save/load
integrates, is in [Simulation System](SIMULATION_SYSTEM.md).

## Staff, tasks and communication

```text
TaskBoard (autoload)           the one list of outstanding work
    ├── TavernTask             one real requirement, with its full history
    ├── TavernTaskDefinition   Resource: priority, capability, retry policy
    └── TavernTaskBoardConfig  Resource: sweep rate, history caps, definitions

Comms (autoload)               notifications, alerts and speaker messages
    ├── CommMessage            one message, with its deduplication key
    └── CommunicationConfig    Resource: severity styling, limits, lifetimes
```

Work reaches a worker along one path, and only one:

```text
world requirement       a chair is dirty, a customer is waiting
  → task producer       TavernTaskCoordinator, listening to world signals
  → central task board  dedup, atomic claim, scoring, sweep
  → staff evaluates     StaffMember asks the board for the best task
  → claimed & reserved  the claim is the reservation
  → staff executes      StaffTaskExecutor drives the real world API
  → world confirms      the customer really was served
  → task completes
```

The board holds no gameplay knowledge. It cannot serve a customer and has no
opinion on whether a chair is dirty; producers tell it what exists, registered
validators tell it whether that is still true, and executors do the work. That
is what makes a player override free: nothing has to announce that the player
cleaned a chair, because the next validation finds the chair clean and cancels
the task.

Staff use the same authoritative APIs the player does — `Customer.try_serve()`,
`Chair.try_clean()`, `ItemCarrier.take_from()` — so no behaviour exists twice
and nothing is teleported, spawned or force-set.

Stock warnings follow the same shape, with the station owning the fact and the
communication service owning the message:

```text
station stock changes
  → station evaluates its own state, with hysteresis
  → stock_state_changed
  → StockAlertCoordinator
  → deduplicated alert lifecycle
  → toast / alert panel / speaker UI
  → acknowledgement or automatic resolution
```

Full detail is in [Staff and Task System](STAFF_TASK_SYSTEM.md) and
[Communication System](COMMUNICATION_SYSTEM.md).

## Economy

```text
Customer payment ───────┐
                         ├──> EconomyManager ───> money_changed ───> HUD
Cleaning complication ──┘
```

`EconomyManager` owns the balance and provides distinct behaviour for income, affordable purchases and unavoidable deductions.

## Customer configuration

`CustomerType` controls:

- relative spawn weight;
- movement and final seating speeds;
- order delay;
- patience duration;
- available and preferred drinks;
- payment multiplier;
- customer texture.

Customer scripts consume this data rather than defining a separate script for every type.

## Global configuration

`GameConfig` currently controls:

- customer spawn limits and delays;
- door queue size;
- navigation and stuck recovery tuning;
- door timing;
- starting money;
- testing overrides.

Some old cleaning fields remain in `GameConfig`, but active cleaning balance now belongs to `CleaningTask` and `ActionDefinition` resources.

## Scene-level managers

The main scene contains managers rather than relying on global autoloads:

```text
Managers
├── EconomyManager
├── GameManager
├── OrderManager
├── CustomerAIReportManager
├── StatisticsTracker
├── TavernTaskCoordinator      turns world signals into tasks
├── StockAlertCoordinator      turns stock states into alerts
└── StaffReportManager         exports the staff/task/comms diagnostics
```

`TaskBoard` and `Comms` are autoloads rather than scene managers because staff,
stations and UI all need them and none of them owns the others. The two
coordinators stay in the scene, because they are the only pieces that know both
the world and those services, and keeping them visible in the Inspector is what
makes that wiring auditable.

This supports future save/load sessions and makes dependencies visible in the scene Inspector.

## Dependency rules

- UI observes systems through signals rather than owning gameplay data.
- The player should not directly edit customer or economy state.
- Interactable objects request actions through the player's `ActionRunner`.
- Anything representing world progression books with `WorldTime`, never a `Timer`.
- No system decides for itself whether it should update; it asks `Simulation`.
- Nothing stores its own day/hour/minute; it stores a `GameTimeStamp` or asks.
- Time is never formatted outside `TimeFormatter`.
- Only `ActorMovement` writes an AI actor's velocity or calls `move_and_slide()`.
- Navigation is never toggled off to solve a movement problem; use `park()`
  and the final-approach radius instead.
- Anything claimable by one actor uses `Reservable`, never its own state enum.
- Actors ask for a `NavigationDestination`; they do not measure their own arrival.
- The player never knows what it is interacting with; it asks the `InteractionSelector` to run whatever the selected object offered.
- Interaction determines *what is selected* and *what was requested*. The object performs the work with its own existing systems.
- There is exactly one interaction prompt, on the HUD. World objects never carry their own labels.
- An object never searches for the player; the actor arrives in the `InteractionRequest`.
- New balance values should normally be exported to resources/configuration.
- Stable IDs should not be renamed after save data begins using them.
- Items move only through `ItemTransferService`, never by editing a slot directly.
- Item behaviour is driven by tags on resources, not by hard-coded item checks.
- A slot or container never contains UI code; UI observes their change signals.
