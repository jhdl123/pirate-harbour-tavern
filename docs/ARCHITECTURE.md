# Current Architecture

## Design goal

Gameplay systems should depend on reusable definitions and managers rather than embedding balance values in individual scripts.

## Drink flow

```text
DrinkDefinition
    ├── stable item identity
    ├── base selling price
    ├── drinking duration
    ├── carried/world textures
    └── break chance multiplier

CustomerType
    └── available and preferred DrinkDefinitions

DrinksStation
    └── gives a DrinkDefinition to Player

Player
    └── carries one DrinkDefinition

Customer
    └── validates and consumes the served DrinkDefinition
```

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
