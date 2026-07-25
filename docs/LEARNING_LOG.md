# Learning Log

## Project setup

Completed:

- Created the Godot project and main scene.
- Created a structured folder layout.
- Configured input actions.
- Set up Git version control.
- Established reusable scenes for player, customers, tables, chairs, door and drink stations.

## Concepts learned

### Scenes and nodes

- A scene is a reusable node tree.
- Packed scenes can be instantiated for customers and furniture.
- Exported node/resource references make dependencies visible in the Inspector.

### Signals

- Signals allow systems to react without tightly coupling scripts.
- Customer payments are forwarded to `EconomyManager`.
- The HUD listens to `money_changed` rather than polling or editing money.
- `ActionRunner` reports action start, progress, completion and cancellation.

### Resources and data-driven design

- A custom Godot `Resource` can define reusable gameplay data.
- `DrinkDefinition` stores price, timing, visuals and break behaviour.
- `CustomerType` stores movement, patience, spawning and preferences.
- `CleaningTask` stores a task's visuals, complication and action reference.
- `ActionDefinition` stores generic action duration and input behaviour.
- Changing a `.tres` resource can rebalance gameplay without changing scripts.

### Composition

- Domain-specific resources can contain generic resources.
- `CleaningTask` contains an `ActionDefinition` rather than inheriting all action behaviour.
- `Chair` contains a `CleanableComponent`.
- `Player` contains an `ActionRunner`.

### Managers and ownership

- A system should have one clear owner for important state.
- `EconomyManager` owns money.
- The chair/cleanable component owns cleaning state.
- The player's action runner owns active timed-action progress.
- UI displays state but does not own it.

### Compatibility migrations

- Large architectural changes are safer when migrated in stages.
- Temporary compatibility fields can keep the game playable while references are moved.
- Once all consumers use the new system, obsolete timers, variables and methods can be removed.

## Current understanding checks

- To change a drink's value, edit `Base Sell Price` on its `DrinkDefinition` resource.
- To change cleaning time, edit `Duration Seconds` on the linked `ActionDefinition`.
- To change broken-glass probability/cost, edit the empty-glass `CleaningTask`.
- To change a customer type's speed or patience, edit its `CustomerType` resource.
- To change global spawning or navigation, edit the `GameConfig` resource.
- Scripts should not directly modify the economy balance outside `EconomyManager`.

## Next learning focus

Create a generic interaction layer so chairs, drink stations, counters, storage and future workstations share one predictable contract without adding object-specific logic to the player.
