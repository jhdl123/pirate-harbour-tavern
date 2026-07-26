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
└── GameManager
```

This supports future save/load sessions and makes dependencies visible in the scene Inspector.

## Dependency rules

- UI observes systems through signals rather than owning gameplay data.
- The player should not directly edit customer or economy state.
- Interactable objects request actions through the player's `ActionRunner`.
- New balance values should normally be exported to resources/configuration.
- Stable IDs should not be renamed after save data begins using them.
- Items move only through `ItemTransferService`, never by editing a slot directly.
- Item behaviour is driven by tags on resources, not by hard-coded item checks.
- A slot or container never contains UI code; UI observes their change signals.
