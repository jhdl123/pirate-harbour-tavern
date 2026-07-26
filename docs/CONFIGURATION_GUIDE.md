# Configuration and Balancing Guide

This guide lists the main values that can be changed without rewriting gameplay code.

## Safe editing workflow

1. Stop the running game.
2. Open the relevant `.tres` resource or scene in Godot.
3. Change one or two values at a time.
4. Save the resource.
5. Run a short test that specifically exercises the changed behaviour.
6. Record useful balance changes in Git with a focused commit.

Prefer editing resources through the Godot Inspector. Stable IDs such as `item_id` and `action_id` should not be renamed once save data begins using them.

---

## Drinks

Drink resources are stored in:

```text
Data/items/drinks/
```

Current resources:

```text
grog.tres
ale.tres
```

Open a drink resource in the Inspector to change the following.

### Drink sale price

Field:

```text
Economy → Base Sell Price
```

This is the base amount paid for one drink before customer payment modifiers or tips.

Current values:

| Drink | Base sell price |
|---|---:|
| Grog | £5 |
| Ale | £7 |

### Future purchase/restock price

Field:

```text
Economy → Base Buy Price
```

This is available in the data model but is not yet used by the current drinks station.

### Customer drinking time

Field:

```text
Drink Timing → Drink Duration Seconds
```

This is real-world time. A higher value keeps the seat occupied for longer after service.

The current drink files do not override this field, so they use the script default of `8.0` seconds.

### Drink-specific break chance

Field:

```text
Breakage → Break Chance Multiplier
```

This multiplies the base chance stored on the empty-glass cleaning task.

Examples:

| Multiplier | Effect |
|---:|---|
| `0.0` | This drink never causes the configured complication |
| `0.5` | Half the base chance |
| `1.0` | Normal base chance |
| `2.0` | Double the base chance, capped at 100% |

The final chance is:

```text
CleaningTask complication chance × DrinkDefinition break chance multiplier
```

### Drink visuals

Fields:

```text
Visuals → Inventory Icon
Visuals → World Texture
Visuals → Carried Texture
Drink Visuals → Order Icon Texture
Drink Visuals → Empty Container Texture
Drink Visuals → Broken Container Texture
```

Keep these assigned when duplicating a drink resource.

`World Texture` and `Carried Texture` now live on `ItemDefinition` rather than
`DrinkDefinition`, because every item needs them. `World Texture` replaced the
old `Full Container Texture`.

### Drink classification

Fields:

```text
Classification → Tags
Inventory → Maximum Stack Size
Inventory → Preferred Destination
```

Prepared drinks must be tagged `prepared_drink` and `service_item`, use a
maximum stack size of 1, and set `Preferred Destination` to `CARRIER`. The
drinks station warns if a served drink is missing the `prepared_drink` tag.

A future serving tray carries several drinks through several visible slots, not
by stacking them into one slot, so the stack size stays at 1.

### Adding a new drink

Full step-by-step instructions, including tags and the item registry, are in
[Item System — How to add a drink](ITEM_SYSTEM.md#how-to-add-a-drink).

In short:

1. Duplicate an existing drink resource in `Data/items/drinks/`.
2. Give it a unique `Item Id` that will remain stable.
3. Change its display name, description, price, timing and textures.
4. Set `Tags` to `prepared_drink` and `service_item`, stack size 1 and
   `Preferred Destination` to `CARRIER`.
5. Open each applicable `CustomerType` resource.
6. Add the drink to `Available Drinks`.
7. Optionally assign it as `Preferred Drink` and set the preference chance.
8. Add or configure a drinks station that supplies the new resource.
9. Add the resource to `Data/items/item_registry.tres`.

---

## Cleaning, breakage and damage costs

Cleaning task resources are stored in:

```text
resources/CleaningTask/
```

Current resources:

```text
empty_glass.tres
broken_glass.tres
```

Timed action resources are stored in:

```text
Data/Actions/cleaning/
```

### Empty-glass cleaning duration

Open:

```text
Data/Actions/cleaning/clean_empty_glass.tres
```

Change:

```text
Real-Time Behaviour → Duration Seconds
```

Current project value: `3.0` seconds.

### Broken-glass clearing duration

Open:

```text
Data/Actions/cleaning/clear_broken_glass.tres
```

Change:

```text
Real-Time Behaviour → Duration Seconds
```

Current value: `1.5` seconds.

`ActionDefinition.duration_seconds` is now the source of truth. Do not add a separate timer to the chair or cleanable component.

### Whether cleaning blocks movement

On either cleaning action, change:

```text
Real-Time Behaviour → Blocks Movement
```

When enabled, the player cannot move while the action is active.

### Whether Escape can cancel cleaning

Change:

```text
Real-Time Behaviour → Can Cancel
```

When enabled, Escape cancels the action. The cleaning task remains and can be restarted immediately while the player stays in range.

### Base broken-glass chance

Open:

```text
resources/CleaningTask/empty_glass.tres
```

Change:

```text
Complication → Complication Chance
```

Current value: `0.5`, meaning 50% before the drink multiplier is applied.

### Broken-glass cost

In the same resource, change:

```text
Complication → Complication Cost
```

Current value: `£2`.

This cost is passed to `EconomyManager.deduct_money()`. It removes as much as possible without allowing the balance to become negative.

### Which task follows a complication

Field:

```text
Complication → Complication Task
```

For `empty_glass.tres`, this currently points to `broken_glass.tres`.

---

## Customer types

Customer resources are stored in:

```text
resources/CustomerTypes/
```

Current types:

```text
sailor.tres
sailor_impatient.tres
```

### Spawn frequency

Field:

```text
Spawning → Spawn Weight
```

Weights are relative, not percentages by themselves.

Current values:

| Type | Weight | Approximate share when these are the only types |
|---|---:|---:|
| Sailor | 8 | 80% |
| Impatient Sailor | 2 | 20% |

### Walking speed

Fields:

```text
Movement → Movement Speed
Movement → Seat Movement Speed
```

`Movement Speed` is used for normal navigation. `Seat Movement Speed` is the slower final movement into position at a chair.

Current notable override:

| Type | Movement | Seat movement |
|---|---:|---:|
| Sailor | 120 | 45 |
| Impatient Sailor | 135 | 50 |

### Order delay

Field:

```text
Service → Order Delay
```

This controls how long the customer waits after sitting before showing an order.

### Patience

Field:

```text
Service → Patience Duration
```

A shorter duration makes the customer lose patience faster and reduces the available time for a strong tip.

Current values:

| Type | Patience |
|---|---:|
| Sailor | 15 seconds |
| Impatient Sailor | 8 seconds |

### Drink selection

Fields:

```text
Drink Preferences → Available Drinks
Drink Preferences → Preferred Drink
Drink Preferences → Preferred Drink Chance
```

`Available Drinks` is the pool this customer may order from. The preferred drink is selected using the configured chance; otherwise another available drink is chosen.

### Payment multiplier

Field:

```text
Economy → Payment Multiplier
```

This changes how much this customer type pays relative to the drink's base sell price. Keep `1.0` for normal payment.

---

## Global game configuration

Open:

```text
resources/config/default_game_config.tres
```

The fields are defined by:

```text
scripts/Managers/game_config.gd
```

### Customer spawning

| Inspector field | Purpose |
|---|---|
| Minimum Spawn Delay | Shortest random delay between spawn attempts |
| Maximum Spawn Delay | Longest random delay between spawn attempts |
| Maximum Active Customers | Maximum customers currently active in the tavern flow |
| Maximum Door Queue Size | Maximum customers allowed to wait outside/at the door |

The current resource overrides `Maximum Active Customers` to `4`. Other values use script defaults unless overridden in the resource.

### Navigation and movement tuning

| Inspector field | Purpose |
|---|---|
| Navigation Arrival Distance | How close a customer must be to a navigation target |
| Seat Arrival Distance | How close a customer must be to count as seated |
| Occupied Seat Penalty | Strongly discourages choosing blocked/occupied seat routes |
| Travel Distance Weight | Importance of distance when selecting seats |
| Stuck Check Interval | Time between stuck checks |
| Minimum Stuck Movement | Minimum movement required to count as progress |
| Maximum Stuck Checks | Checks allowed before recovery logic runs |
| Maximum Path Refreshes | Path recalculations before giving up/recovering |
| Walking Avoidance Radius | Personal space used by moving customers |
| Walking Avoidance Priority | Relative avoidance priority |

Change navigation values cautiously and test with a busy tavern. Small changes can affect path choice, congestion and whether customers reach chairs cleanly.

### Door timings

| Inspector field | Purpose |
|---|---|
| Door Opening Duration | Opening animation/time |
| Door Hold Open Duration | Time held open between movements |
| Door Closing Duration | Closing animation/time |
| Customer Entry Pause | Pause during entry flow |
| Customer Exit Pause | Pause during exit flow |

### Starting money

Field:

```text
Economy → Starting Money
```

This is passed to `EconomyManager.initialise()` when the game starts.

### Testing switches

| Field | Effect |
|---|---|
| Show Debug Messages | Enables gameplay debug output |
| Disable Patience | Prevents normal patience behaviour for testing |
| Disable Broken Glass | Prevents cleaning complications |
| Ignore Customer Limit | Allows spawn testing beyond the normal active limit |

Turn temporary testing overrides back off before normal balance testing.

### Legacy fields to avoid

The script still contains old global cleaning fields:

```text
Cleaning Duration
Broken Glass Chance
Broken Glass Cleaning Duration
Broken Glass Cost
```

The active cleaning duration, chance and cost are now configured through `ActionDefinition` and `CleaningTask` resources as described above. Do not use the old `GameConfig` cleaning values for balancing unless the code is deliberately migrated back to them.

---

## Player movement and camera

Open:

```text
scenes/player/player.tscn
```

Select the player root node.

### Player speed

Field:

```text
Movement → Movement Speed
```

Current script default: `250.0`.

### Camera zoom

Fields:

```text
Camera Zoom → Minimum Camera Zoom
Camera Zoom → Maximum Camera Zoom
Camera Zoom → Camera Zoom Step
Camera Zoom → Camera Zoom Speed
Camera Zoom → Default Camera Zoom
```

These control limits, input increments and smoothness rather than game-world speed.

---

## Economy rules

`EconomyManager` is the only system that should directly own the balance.

Use:

```text
add_money(amount, reason)
```

for income.

Use:

```text
spend_money(amount, reason)
```

for optional purchases that must be fully affordable.

Use:

```text
deduct_money(amount, reason)
```

for unavoidable penalties. This removes up to the available balance but never goes below £0.

Do not directly modify `current_money` from customer, chair, HUD or future shop scripts.

---

## Recommended balancing order

When the game feels too rushed or too slow, adjust in this order:

1. Customer spawn delay and maximum active customers.
2. Customer patience duration.
3. Customer order delay and drink duration.
4. Player movement speed and physical room layout.
5. Cleaning action durations.
6. Drink prices and payment multipliers.
7. Break chance and break cost.

This order helps avoid using higher rewards to disguise a service loop that is fundamentally too fast or congested.

---

## Items, inventory and containers

Item resources live in:

```text
Data/items/
    drinks/     grog.tres, ale.tres
    tableware/  clean_tankard.tres, dirty_tankard.tres
    waste/      broken_glass.tres
    tools/      cleaning_rag.tres
    stock/      ale_keg.tres, grog_barrel.tres
    item_registry.tres
```

Only the drinks are used by gameplay today. The rest are foundations for
storage, cleaning and stock, and are deliberately not wired into the tavern yet.

Every item exposes the same configurable fields — id, tags, stack size, prices,
textures and preferred destination. See
[Item System — How to add an item](ITEM_SYSTEM.md#how-to-add-an-item).

### Player carrying and inventory

Configured on `scenes/player/player.tscn`:

```text
Player/ItemCarrier
    Visuals → Carried Sprite        (../CarriedItemSprite)
    Slot Rules → Carry Capacity     1
    Slot Rules → Accepted Tags      empty (hands accept anything)
    Slot Rules → Rejected Tags      empty

Player/InventoryComponent
    Layout → Container Id           player_backpack
    Layout → Slot Count             12
    Rules → Default Slot Capacity   99
    Rules → Rejected Tags           prepared_drink, bulky_item
```

There is no weight system. Capacity is slot count plus each item's own maximum
stack size. The inventory has no UI yet and nothing puts items into it.

### Item debug output

```text
GameConfig → Testing → Show Item Debug Messages
```

Off by default. Item transfers happen often enough that logging them would
drown normal gameplay output. The drinks station has its own
`Show Transfer Messages` export for the same reason.

