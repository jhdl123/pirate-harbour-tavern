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

CleaningTask
└── ActionDefinition

Player
└── ActionRunner

Game scene
├── GameManager
└── EconomyManager
```

## Immediate roadmap

1. Introduce a formal generic interactable contract/base.
2. Upgrade the bar counter to hold placed drinks.
3. Allow the player to put down, pick up and swap drinks.
4. Generalise carried items beyond drinks.
5. Add stock/restocking foundations.
6. Add early management pressure without making service purely arcade-like.

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
- [Learning Log](LEARNING_LOG.md)
