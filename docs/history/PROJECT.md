# Pirate Harbour Tavern — Project Status

## Project goal

Learn Godot and game development by building an expandable pirate harbour tavern management game.

The long-term direction is to move from hands-on drink delivery into broader tavern management through staff, stock, production, trading, reputation, upgrades, events, gambling and smuggling systems.

## Current playable milestone

The current build supports a complete basic service cycle:

```text
Customer spawns
→ queues and enters through the door
→ finds and reserves a chair
→ orders a configured drink
→ waits with a patience bar
→ player collects and serves the drink
→ customer drinks
→ payment and tip enter the economy
→ customer exits
→ empty glass requires cleaning
→ cleaning may create broken glass and a penalty
→ chair becomes available again
```

## Completed foundations

- Player movement, collision, camera zoom and interaction detection.
- Customer state machine and navigation to doors, tables and chairs.
- Maximum active customers and door queue flow.
- Configurable `CustomerType` resources.
- Configurable `ItemDefinition` and `DrinkDefinition` resources.
- Generic item, slot, container and transfer foundation.
- Reusable `ItemCarrier` and `InventoryComponent` components.
- Multiple drink prices, visuals, durations and preferences.
- Customer patience and patience-based tip behaviour.
- Cleaning tasks and breakage complications.
- Generic `ActionDefinition` and `ActionRunner` system.
- Movement blocking and Escape cancellation for actions.
- Centralised `EconomyManager` with HUD signal updates.
- Configurable spawning, navigation, door and testing values.

## Current architecture milestone

The project has completed the main migration from early hard-coded gameplay values to reusable resources and managers:

```text
ItemDefinition
└── DrinkDefinition

ItemStack → ItemSlot → ItemContainer
                 └── ItemTransferService

CleaningTask
└── ActionDefinition

Player
├── ActionRunner
├── ItemCarrier
└── InventoryComponent

Game scene
├── GameManager
└── EconomyManager
```

Carried items have been generalised beyond drinks. The player holds an
`ItemCarrier` rather than a drink-specific variable, and every future container
— storage, bar slots, trays, staff packs, shops — shares one `ItemContainer` and
one `ItemTransferService`. See [Item System](ITEM_SYSTEM.md).

## Immediate roadmap

1. ~~Generalise carried items beyond drinks.~~ Done.
2. Add bar service slots on the counter, connected to `ItemSlot`.
3. Give chairs a service slot so serving becomes a transfer, not a clear.
4. Introduce a formal generic interactable contract/base.
5. Add storage containers and drink stock, replacing the station's infinite supply.
6. Add the inventory and storage UI.
7. Add early management pressure without making service purely arcade-like.

## Development approach

- Desktop-first development.
- Godot 4.7.1 and GDScript.
- Data-driven and configurable systems.
- Reusable components over scene-specific logic.
- Small playable changes with testing between steps.
- Full-script replacements when migrations require coordinated changes.
- Git commits at stable milestones.

## Related documentation

- [README](../README.md)
- [Configuration and Balancing Guide](CONFIGURATION_GUIDE.md)
- [Architecture](ARCHITECTURE.md)
- [Item System](ITEM_SYSTEM.md)
- [Interaction System](INTERACTION_SYSTEM.md)
- [Navigation System](NAVIGATION_SYSTEM.md)
- [Simulation System](SIMULATION_SYSTEM.md)
- [Learning Log](LEARNING_LOG.md)
