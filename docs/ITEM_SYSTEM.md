# Item, Inventory and Transfer System

This document describes the item foundation added to Pirate Harbour Tavern, how
the current drinks were migrated onto it, and how future storage, bar slots,
trays, shops and UI should connect to it.

Nothing in this system is visible in the tavern yet. It replaces how the player
carries a drink and gives every future container one shared implementation.

---

## Contents

- [Architecture](#architecture)
- [Relationship to drink definitions](#relationship-to-drink-definitions)
- [How the player carries items](#how-the-player-carries-items)
- [Transfer rules](#transfer-rules)
- [How to add an item](#how-to-add-an-item)
- [How to add a drink](#how-to-add-a-drink)
- [Future scene integration](#future-scene-integration)
- [Save and load](#save-and-load)
- [Testing](#testing)
- [Migration summary](#migration-summary)

---

## Architecture

```text
ItemDefinition          static data: what an item IS
    └── DrinkDefinition adds drink timing, order icon and breakage

ItemStack               runtime data: how many, and in what condition
    ├── ItemDefinition reference
    ├── quantity
    └── metadata

ItemSlot                one position holding zero or one ItemStack
    └── ItemSlotRules   capacity, tag filters, permissions

ItemContainer           a fixed, ordered set of ItemSlots
    └── container_id, container_tags

ItemTransferService     the ONE place items move between slots
    └── ItemTransferResult

ItemCarrier             component: one slot = an actor's hands
InventoryComponent      component: one container = an actor's backpack

ItemRegistry            stable item id → ItemDefinition, used by save/load
ItemTags                named tag constants and set helpers
```

The layering rule is that each level only knows about the level below it. A
container knows about slots but not about carriers. A carrier knows about slots
but not about drinks. Nothing in the item system knows about the tavern.

### File locations

```text
systems/items/
    item_definition.gd      ItemDefinition
    drink_definition.gd     DrinkDefinition
    item_registry.gd        ItemRegistry
    item_tags.gd            ItemTags

systems/inventory/
    item_stack.gd           ItemStack
    item_slot_rules.gd      ItemSlotRules
    item_slot.gd            ItemSlot
    item_container.gd       ItemContainer
    item_transfer_result.gd ItemTransferResult
    item_transfer_service.gd ItemTransferService

scripts/Components/
    item_carrier.gd         ItemCarrier
    inventory_component.gd  InventoryComponent

Data/items/                 item definition resources
    item_registry.tres
    drinks/     grog.tres, ale.tres
    tableware/  clean_tankard.tres, dirty_tankard.tres
    waste/      broken_glass.tres
    tools/      cleaning_rag.tres
    stock/      ale_keg.tres, grog_barrel.tres

tests/
    item_system_tests.gd
    item_system_tests.tscn
```

This follows the existing convention: reusable systems in `systems/`, gameplay
components in `scripts/Components/`, resource instances in `Data/`.

### ItemDefinition

Static, shared data for one kind of item. One resource is shared by every stack
of that item in the game, so it never stores a quantity or a location.

| Field | Purpose |
|---|---|
| `item_id` | Stable identifier. **Never rename once saves exist.** |
| `display_name` | Shown to the player |
| `description` | Menus and tooltips |
| `tags` | `Array[StringName]` driving all slot and container rules |
| `inventory_icon` | Icon for menus and future inventory UI |
| `world_texture` | Shown when the item sits in the world |
| `carried_texture` | Shown while an actor holds it |
| `maximum_stack_size` | Per-item stack cap |
| `preferred_destination` | `AUTOMATIC`, `CARRIER`, `INVENTORY` or `STORAGE` |
| `base_buy_price` / `base_sell_price` | Economy data |
| `default_metadata` | Seeds every new stack's metadata |

`preferred_destination` is a hint for future pickup code. It never overrides a
slot rule: rules always win.

**The old `ItemCategory` enum was removed.** An enum is a hard-coded list, and
the brief requires new item groups to arrive through data alone. Tags replace
it. See [ItemTags](#tags) below.

### Tags

`ItemTags` provides spell-checked constants for the tags the project currently
uses:

```text
Handling   small_item, bulky_item, service_item
Drinks     prepared_drink, drink_stock
Tableware  tableware, clean_tableware, dirty_tableware, waste
Making     tool, resource, ingredient, trade_good, contraband
```

**The system is not limited to this list.** `tags` is an `Array[StringName]` on
a resource, so typing `&"smuggled"` into an item in the Inspector works
immediately with no script change. `ItemTags` exists to prevent typos in code,
not to restrict data.

### ItemStack

The runtime quantity of an item, plus optional per-stack `metadata`.

The critical rule is **ownership**. A stack instance belongs to exactly one
holder. `ItemSlot` copies anything put into it and copies anything it hands out,
so two slots can never share one stack object. That single rule is what prevents
accidental duplication when a stack is moved.

Use `ItemStack.create(definition, quantity, overrides)` rather than `new()`. It
seeds metadata from the definition's defaults and validates the quantity.

Useful members:

- `is_empty()`, `is_valid()`, `get_available_space()`
- `matches_definition()` — compares `item_id`, not object identity
- `is_metadata_compatible_with()` — two stacks with different metadata never merge
- `can_merge_with()`
- `duplicate_stack()` — deep-copies metadata
- `split()` — removes items and returns them as an independent stack
- `to_dictionary()` / `from_dictionary()`

### ItemSlotRules

An Inspector-configurable `Resource` holding one slot's permissions and filters.
Separating rules from the slot is what lets a bar slot, a cellar crate, a tray
and a backpack all use the same `ItemSlot` script with different data.

| Field | Purpose |
|---|---|
| `capacity` | Slot's own cap, combined with the item's `maximum_stack_size` |
| `accepted_tags` | Item must carry one of these. Empty = accept any |
| `rejected_tags` | Item carrying any of these is always refused |
| `accepted_item_ids` | Optional exact-id whitelist, e.g. a keg input |
| `allow_insert` / `allow_remove` | Whether items can go in or come out |
| `allow_merge` | Whether an incoming stack may combine with one already there |
| `allow_swap` | Whether contents may be exchanged |
| `allow_partial` | Whether a partial amount may move when the whole will not fit |

Rejection wins over acceptance. `validate_or_warn()` reports impossible
combinations such as a tag being both accepted and rejected.

**Capacity is always the smaller of the two limits.** A slot with capacity 99
still holds only one prepared drink, because the drink's `maximum_stack_size`
is 1.

### ItemSlot

One runtime position holding zero or one stack. Contains no UI code and no scene
references — UI observes `contents_changed` and calls `peek()`.

- `peek()` returns an independent copy; mutating it never affects the slot
- `get_acceptable_amount(definition)` answers "how many could I take right now?"
- `contents_changed(previous_stack, current_stack)` fires on every change

Gameplay should not call the mutating helpers directly. Use
`ItemTransferService`, so every movement follows the same rules.

### ItemContainer

An ordered, fixed set of slots with a stable `container_id`. Slot order and slot
ids never change, so saved items always return to the same visible position.

One container script serves every case: player backpack, cellar crate, cupboard,
bar counter, serving tray, staff pack, keg input, station output, delivery crate
and shop stock. They differ only in slot count, container tags and slot rules —
never in logic.

- `add_stack()` / `add_item()` fill matching stacks before empty slots
- `find_merge_targets()` / `find_empty_slots()`
- `get_total_quantity()`, `has_item()`, `is_empty()`, `is_full()`
- `set_slot_rules(index, rules)` for per-slot overrides
- `remove_item(id, quantity, require_full_amount)`
- `to_dictionary()` / `from_dictionary()`
- Signals: `slot_changed(index, previous, current)` and `contents_changed`

Each slot receives its own **copy** of the default rules, so a per-slot override
never leaks into the other slots.

### ItemTransferService

The single place items move. Player interactions, staff AI, storage furniture,
trays, shops and a future drag-and-drop UI all call the same static methods.

```gdscript
ItemTransferService.transfer(source, destination, amount, allow_swap)
ItemTransferService.can_transfer(source, destination, amount, allow_swap)
ItemTransferService.transfer_to_container(source, container, amount)
ItemTransferService.give_to_slot(destination, stack)
```

`give_to_slot()` is for generators with no real source slot — currently only the
drinks station's refill. Everything with a real source slot must use `transfer()`
so the source is emptied correctly.

Its safety contract:

1. A transfer is fully validated before anything is mutated.
2. The source is never emptied before the destination is confirmed valid.
3. Quantities never go negative and never exceed item or slot capacity.
4. A failed transfer leaves both sides completely unchanged.
5. Items are never silently destroyed and never duplicated.

Internally this is a plan-then-apply split: `_build_plan()` mutates nothing and
returns a description of what would happen; `_apply_plan()` carries it out. If
application somehow fails after validation, anything already removed is returned
to the source and a `push_error` explains what happened.

### ItemTransferResult

Every call returns one of these, successful or not.

| Status | Meaning |
|---|---|
| `MOVED` | Whole stack moved into an empty destination |
| `MERGED` | Whole stack merged into a matching destination stack |
| `PARTIALLY_MOVED` | Some moved into an empty destination |
| `PARTIALLY_MERGED` | Some merged into a matching stack |
| `SWAPPED` | Source and destination exchanged contents |
| `REJECTED_ITEM` | Destination's tag or id filters refused the item |
| `NO_CAPACITY` | Destination is full |
| `SOURCE_EMPTY` | Nothing to move |
| `DESTINATION_LOCKED` | Destination does not allow insertion |
| `SOURCE_LOCKED` | Source does not allow removal |
| `INVALID_REQUEST` | Null slots, negative amount, or a slot moving into itself |
| `INCOMPATIBLE_STACKS` | Same item, but metadata or merge permission blocks it |

Also carries `amount_moved`, `amount_requested`, `definition`, plus
`is_success()`, `is_partial()`, `get_amount_remaining()` and `get_message()` for
future UI prompts.

### ItemCarrier

A `Node` component holding the one item an actor carries in its hands. On the
player today, on staff later.

```text
Player
├── CarriedItemSprite     (existing Sprite2D)
├── ActionRunner
├── ItemCarrier           → carried_sprite = ../CarriedItemSprite
└── InventoryComponent
```

Exports: `carried_sprite`, `carry_capacity`, `accepted_tags`, `rejected_tags`.

The carrier does not know what a drink is. It reads
`ItemDefinition.carried_texture` and tags, so a keg, a tray, a crate or a mop
will work without touching the script.

- `get_slot()` — hand this to `ItemTransferService`
- `take_from(slot)`, `place_into(slot)`, `place_into_container(container)`
- `give(stack)` — generators only
- `clear_carried_item()` — only where the item is genuinely consumed
- `is_carrying()`, `is_carrying_item(id)`, `is_carrying_tagged(tag)`
- `carried_item_changed(previous, current)` signal

`accepted_tags` is empty by default, because a pair of hands can hold anything.

### InventoryComponent

A thin, Inspector-friendly wrapper around one `ItemContainer`, giving an actor a
personal inventory.

Configured on the player as:

- `container_id` = `&"player_backpack"`
- `slot_count` = 12
- `default_slot_capacity` = 99 (still capped per item)
- `rejected_tags` = `prepared_drink`, `bulky_item`
- no weight system

**It is deliberately unused.** Nothing puts items into it and there is no UI.
Prepared drinks are rejected by rule, so a served drink belongs in the hands or
on a future tray, not in a backpack. Attaching it now costs one node and keeps
the later inventory work from touching `player.gd` again.

---

## Relationship to drink definitions

**Decision: `DrinkDefinition` extends `ItemDefinition`. A drink IS an item.**

The project already had `DrinkDefinition extends ItemDefinition`, so this keeps
the existing convention rather than inventing a parallel resource.

The alternatives were rejected because both create two files per drink that can
drift apart:

- a drink definition *referencing* a separate prepared-drink item definition;
- a prepared-drink item definition *referencing* a drink definition.

With inheritance there is exactly one resource per drink and therefore one source
of truth. `grog.tres` is simultaneously the drink's balance data and the item the
player carries.

Responsibilities stay separated by which class owns which field:

| Owned by `ItemDefinition` | Owned by `DrinkDefinition` |
|---|---|
| `item_id`, `display_name`, `description` | `drink_duration_seconds` |
| `tags`, `maximum_stack_size` | `order_icon_texture` |
| `inventory_icon`, `world_texture`, `carried_texture` | `empty_container_texture` |
| `base_buy_price`, `base_sell_price` | `broken_container_texture` |
| `preferred_destination`, `default_metadata` | `break_chance_multiplier` |

Drink-specific gameplay — price, order type, customer preference, payment, tips,
drinking time, station output, breakage — remains entirely configured on the
drink resource, exactly as before.

`CustomerType.available_drinks` and `preferred_drink` still hold
`DrinkDefinition` references, so customer ordering is unchanged. Serving
validation now compares `item_id`, never display names.

---

## How the player carries items

Before:

```text
player.gd
└── var carried_drink: DrinkDefinition        ← authoritative state
    set_carried_drink() / clear_carried_drink()
    update_carried_drink_visual()             ← drink-specific texture lookup
```

After:

```text
player.gd
└── ItemCarrier
    └── ItemSlot                              ← the only source of truth
        └── ItemStack → ItemDefinition.carried_texture
```

`player.gd` no longer stores anything about what is being held. Read-only
accessors remain for convenience:

| Method | Returns |
|---|---|
| `get_item_carrier()` | The `ItemCarrier` component |
| `get_inventory()` | The `InventoryComponent` |
| `get_carried_slot()` | The slot, ready for `ItemTransferService` |
| `get_carried_stack()` | An independent copy |
| `get_carried_definition()` | The definition, or null |
| `get_carried_drink()` | The definition cast to `DrinkDefinition`, or null |

`get_carried_drink()` is a **derived read-only accessor, not stored state**. It
exists because drink-specific gameplay legitimately needs to ask "is this a
drink, and which one?". It is documented as such in `player.gd`. There is no
drink-specific setter: the carrier's slot is the only thing that can change what
is held.

### The drinks station

The station now owns a real one-slot output `ItemContainer`, so every hand-off
runs through `ItemTransferService`:

| Player state | Transfer | Result |
|---|---|---|
| Empty hands | station slot → carrier | `MOVED` |
| Holding this station's drink | carrier cleared, returned to supply | — |
| Holding a different prepared drink | station slot ↔ carrier | `SWAPPED` |
| Holding anything else | refused | `REJECTED_ITEM` / `NO_CAPACITY` |

This preserves the previous behaviour and **fixes a latent bug**: the old code
silently overwrote whatever the player was carrying.

**Current limitation.** There is no drink stock yet, so the output slot is an
infinite supply: it refills after a drink is taken, and a drink handed back is
discarded. `_refill_output()` and `_on_drink_returned()` are the two methods to
change once kegs and stock exist.

---

## Transfer rules

### Move

Whole source stack into an empty, accepting destination. Returns `MOVED`.

### Merge

Whole source stack into a destination holding the same `item_id` with compatible
metadata and room to spare. Returns `MERGED`.

### Partial transfer

When only some items fit, and the destination's `allow_partial` is true, the
amount that fits moves and the rest stays in the source. Returns
`PARTIALLY_MOVED` or `PARTIALLY_MERGED`.

If `allow_partial` is false the whole transfer fails with `NO_CAPACITY` and
nothing changes. The carrier uses `allow_partial = false`, because half-taking a
stack into a single pair of hands is rarely what a player means.

A specific amount can also be requested:
`ItemTransferService.transfer(source, destination, 3)`.

### Swap

Only when **all** of these hold:

- both slots allow swapping;
- the whole source stack is being moved (a partial move has nowhere to put the returned items);
- the source can accept the destination's item;
- the destination can accept the source's item;
- both stacks fit entirely within the other side's capacity.

Anything less would mean splitting a stack with nowhere to put the remainder,
which is how items get lost. Returns `SWAPPED`.

Swapping is disabled inside `transfer_to_container()`, because a container always
has the option of another slot.

### Capacity

Effective capacity is always `min(slot capacity, item maximum_stack_size)`. Both
are enforced on every path, including load.

### Tag filtering

An item is accepted when it carries none of `rejected_tags` **and** at least one
of `accepted_tags` (or `accepted_tags` is empty) **and** its id is in
`accepted_item_ids` (or that list is empty). Rejection wins.

### Metadata compatibility

Two stacks merge only when their metadata dictionaries are equal. Stacks of the
same item with different metadata return `INCOMPATIBLE_STACKS` rather than
merging and losing the distinction. This is the extension point for future
quality, spoilage, vintage or ownership data.

---

## How to add an item

1. Choose the right folder under `Data/items/` — or create one, for example
   `Data/items/ingredients/`.
2. Right-click → **New Resource** → search for `ItemDefinition` → save it as
   `snake_case_name.tres`.
3. **Assign a stable `Item Id`.** Use lower snake case, for example
   `salted_pork`. This goes into save files and must never be renamed once saves
   exist.
4. Set `Display Name` and `Description`.
5. **Select tags.** Add one handling tag (`small_item` or `bulky_item`) plus any
   descriptive tags. See the table in [Tags](#tags). Typing a brand-new tag is
   fine and needs no script change.
6. **Set `Maximum Stack Size`.** Unique or bulky items: 1. Ordinary goods: 8–20.
   Small consumables: higher.
7. **Assign textures.** `Inventory Icon` for menus, `World Texture` for the item
   sitting in the world, `Carried Texture` for an actor holding it. All three may
   be the same file. A missing `Carried Texture` produces a warning when the item
   is picked up.
8. **Configure `Base Buy Price` and `Base Sell Price`.**
9. **Choose `Preferred Destination`** — `AUTOMATIC`, `CARRIER`, `INVENTORY` or
   `STORAGE`. This is only a hint for future pickup code.
10. Leave `Default Metadata` empty unless the item genuinely needs per-stack
    state. Stacks with different metadata will not merge.
11. **Register it.** Open `Data/items/item_registry.tres` and add the new
    resource to `Definitions`. Anything not in the registry cannot be restored
    from a save file.

---

## How to add a drink

A drink is an item, so this is the item process plus the drink fields.

1. Duplicate an existing resource in `Data/items/drinks/`, or create a new
   `DrinkDefinition` resource there.
2. Give it a unique, stable `Item Id`, for example `wine`.
3. Set `Display Name`, `Description` and `Base Sell Price`.
4. **Set `Tags` to `prepared_drink` and `service_item`.** The drinks station
   warns if a served drink is not tagged `prepared_drink`, and bar slots and
   trays will refuse it.
5. **Set `Maximum Stack Size` to 1.** A future tray carries multiple drinks
   through multiple visible slots, not by stacking three into one slot.
6. Set `Preferred Destination` to `CARRIER`.
7. Assign textures:
   - `Inventory Icon`, `World Texture`, `Carried Texture` — the full drink;
   - `Order Icon Texture` — shown above a customer while ordering;
   - `Empty Container Texture` and `Broken Container Texture` — used by cleaning.
8. Set `Drink Duration Seconds` (real-world seconds the seat stays occupied) and
   `Break Chance Multiplier` (multiplies the empty-glass task's complication
   chance).
9. **Connect station output.** Add a `drinks_station.tscn` instance to the level
   and set its `Served Drink` to the new resource.
10. **Connect customer orders.** Open each applicable `CustomerType` in
    `resources/CustomerTypes/` and add the drink to `Available Drinks`.
    Optionally set it as `Preferred Drink`.
11. **Register it** in `Data/items/item_registry.tres`.

Textures for wine and water already exist in `assets/art/items/drinks/`, so those
are the natural next two drinks. No drink resources exist for them yet.

---

## Future scene integration

None of the following exist yet. This section records how each should connect so
the work does not need to reopen the item system.

### Bar service slots

A visible slot on the bar counter holding one item.

```text
BarServiceSlot (Node2D)
├── Sprite2D              ← shows ItemDefinition.world_texture
├── InteractionArea       ← group "interactable"
└── script
    ├── owns an ItemContainer(id, 1, rules)
    ├── rules: capacity 1, accepted_tags [prepared_drink, tableware],
    │          rejected_tags [bulky_item], allow_swap true
    ├── _ready(): container.slot_changed.connect(_update_sprite)
    └── interact(player):
            ItemTransferService.transfer(
                player.get_carried_slot(),
                get_slot()
            )
```

That single `transfer()` call already handles all four required behaviours:

- placement into an empty slot → `MOVED`;
- pickup from an occupied slot (call it with source and destination reversed, or
  transfer from the slot into the carrier) → `MOVED`;
- valid swapping → `SWAPPED`;
- rejection of invalid stock or bulky items → `REJECTED_ITEM`.

The sprite updates from the `slot_changed` signal. No item-specific code.

A bar counter with several visible slots is one `ItemContainer` with several
slots and one child sprite per slot, not several containers.

### Storage containers

```text
StorageChest (StaticBody2D)
├── Sprite2D
├── InteractionArea
└── script
    └── owns an ItemContainer(&"cellar_crate_01", 24, rules)
```

Bulk stock storage, operational station stock, dirty-item returns and delivery
crates all use this with different slot counts and rules. Give each a unique
`container_id` — save data keys on it.

### Storage UI and player inventory UI

Both are the same UI bound to different containers. The UI should:

- take an `ItemContainer` and build one control per slot;
- render from `slot.peek()` and `ItemDefinition.inventory_icon`;
- refresh on `slot_changed(index, previous, current)`;
- perform every drag-and-drop through
  `ItemTransferService.transfer(from_slot, to_slot)`;
- use `can_transfer()` for hover states and `result.get_message()` for prompts.

The UI must never mutate a slot directly. Put it in `ui/inventory/`. No empty UI
folder was created, because there is nothing to put in it yet.

### World pickups

```text
WorldPickup (Area2D)
├── Sprite2D              ← ItemDefinition.world_texture
└── script
    ├── @export var stack_definition: ItemDefinition
    ├── @export var quantity: int
    └── on pickup, honour ItemDefinition.preferred_destination:
            CARRIER   → carrier.take_from(...)
            INVENTORY → inventory.add_item(...)
            AUTOMATIC → try inventory, then hands
```

### Serving tray

A tray is a **container carried in the hands**, so it is both an item and a
container.

- Create `tray.tres` with tags `service_item`, `bulky_item`, stack size 1, so it
  is carried and refused by the backpack.
- The tray scene owns an `ItemContainer` with 3–4 slots, each capacity 1 and
  `accepted_tags = [prepared_drink]`, with one visible sprite per slot.
- Each prepared drink stays stack size 1, so a tray of three drinks is three
  occupied slots, never one slot of quantity 3.
- Mixed drink types work with no extra code, because slots are independent.
- Player and staff both use it, because both hold an `ItemCarrier`.

Serving from a tray is `ItemTransferService.transfer(tray_slot, customer_or_chair_slot)`.

### Keg refilling

- Keg items already exist: `ale_keg.tres`, `grog_barrel.tres`, tagged
  `drink_stock` and `bulky_item`.
- Give the drinks station a second container: a keg input slot with
  `accepted_tags = [drink_stock]`, or `accepted_item_ids = [&"ale_keg"]` for a
  station that only takes one kind.
- Replace `_refill_output()` so it draws from the keg's remaining charges rather
  than creating a drink from nothing, and `_on_drink_returned()` so a returned
  drink produces a `dirty_tankard` instead of being discarded.

### Staff item carrying

Staff need no new item code. Add `ItemCarrier` and optionally
`InventoryComponent` to the staff scene, exactly as on the player. Staff AI then
calls the same `ItemTransferService` methods against station slots, bar slots and
storage containers.

---

## Save and load

No save system exists yet. The item system is built so one can be added without
reworking it.

`ItemStack.to_dictionary()`:

```json
{ "item_id": "grog", "quantity": 1, "metadata": { "vintage": 1712 } }
```

`metadata` is omitted when empty. An empty stack serialises to `{}`.

`ItemContainer.to_dictionary()`:

```json
{
  "container_id": "player_backpack",
  "slot_count": 12,
  "slots": [
    { "slot_id": "player_backpack_0", "stack": {} },
    { "slot_id": "player_backpack_1", "stack": { "item_id": "cleaning_rag", "quantity": 1 } }
  ]
}
```

Rules that a future save system must follow:

- **Store stable item ids, never resource paths or node references.** Moving
  `grog.tres` must not break saves.
- **Key containers on `container_id`.** Each must be unique across a save.
- **Slot positions are fixed.** Items reload into the same visible slot.
- **Resolve ids through an `ItemRegistry`.** Pass
  `Data/items/item_registry.tres` to `from_dictionary()`.
- **Unknown ids degrade gracefully.** A removed item loads as an empty stack with
  a warning rather than crashing.
- **The configured slot count stays authoritative.** `from_dictionary()` does not
  resize a container from save data, so changing a backpack from 12 to 16 slots
  later cannot corrupt the scene. Extra saved slots are reported.
- **Capacity is re-checked on load.** A stack saved above its limit is clamped
  with a warning.

Suggested top-level shape for later:

```json
{
  "version": 1,
  "containers": { "player_backpack": { ... }, "cellar_crate_01": { ... } },
  "carriers":   { "player_hands": { "item_id": "grog", "quantity": 1 } }
}
```

Save migration is explicitly out of scope and not implemented.

---

## Testing

### Automated

```text
tests/item_system_tests.tscn
```

Open it and press **F6**. It is **not** the main scene and adds nothing to the
tavern. Results print to the Output panel.

Headless:

```bash
godot --headless --path . res://tests/item_system_tests.tscn
```

Set `Quit When Finished` on the root node to exit automatically with a non-zero
code on failure.

The tests build their own `ItemDefinition` resources in code, so they never
depend on real drink balance and cannot be broken by a price or texture change.

| # | Test |
|---|---|
| 1 | Empty source transfer is rejected |
| 2 | Whole stack moves into an empty valid slot |
| 3 | An item without an accepted tag is rejected |
| 4 | Matching stacks merge |
| 5 | The item's maximum stack size is respected |
| 6 | The slot's own capacity is respected |
| 7 | A requested partial amount transfers |
| 8 | Two different valid items swap |
| 9 | An invalid swap changes neither slot |
| 10 | Stacks with different metadata do not merge |
| 11 | A stack serialises and restores |
| 12 | A container fills matching stacks before empty slots |
| 13 | A container serialises and restores to the same slots |
| 14 | Repeated transfers neither duplicate nor lose items |
| 15 | An unknown saved item loads as an empty stack |
| 16 | A personal inventory refuses prepared drinks |

### Manual

Gameplay behaviour needs a running tavern. Run the main scene and check:

1. **Pickup.** Walk to the Grog station, press **E**. The grog sprite appears
   beside the player.
2. **Carried sprite clears.** Press **E** at the same station again. The sprite
   disappears.
3. **Swap.** Pick up grog, walk to the Ale station, press **E**. The player is
   now holding ale, not grog. Nothing is lost or duplicated.
4. **Correct serve.** Wait for a customer to show an order icon. Collect that
   drink and press **E** on the customer. They accept it, the icon clears, the
   carried sprite clears and the drink appears on the chair.
5. **Wrong drink is refused.** Carry the other drink to an ordering customer and
   press **E**. Nothing happens, the player keeps the drink, and with
   `Show Debug Messages` on, the Output panel names the drink they wanted.
6. **Empty hands are refused.** Press **E** on an ordering customer while
   carrying nothing. Nothing happens.
7. **Customer flow completes.** The customer drinks, pays, and leaves. Money
   increases in the HUD by the drink's base sell price times the customer type's
   payment multiplier.
8. **Cleaning.** The vacated chair shows an empty glass. Press **E** to clean.
   Movement is blocked for the action's duration; **Escape** cancels it.
9. **Broken glass.** Repeat cleaning until a complication triggers. The broken
   glass sprite appears, money is deducted, and a second clean clears it.
10. **Chair reuse.** After cleaning, a new customer can be seated there.
11. **No warnings.** The Output panel shows no `push_error` or `push_warning`
    from the item system during a normal service loop.

---

## Migration summary

### New files

```text
systems/items/item_tags.gd
systems/items/item_registry.gd
systems/inventory/item_slot_rules.gd
systems/inventory/item_slot.gd
systems/inventory/item_container.gd
systems/inventory/item_transfer_result.gd
systems/inventory/item_transfer_service.gd
scripts/Components/item_carrier.gd
scripts/Components/inventory_component.gd
Data/items/item_registry.tres
Data/items/tableware/clean_tankard.tres
Data/items/tableware/dirty_tankard.tres
Data/items/waste/broken_glass.tres
Data/items/tools/cleaning_rag.tres
Data/items/stock/ale_keg.tres
Data/items/stock/grog_barrel.tres
tests/item_system_tests.gd
tests/item_system_tests.tscn
docs/ITEM_SYSTEM.md
```

### Modified files

| File | Change |
|---|---|
| `systems/items/item_definition.gd` | `ItemCategory` enum removed; added `tags`, `world_texture`, `carried_texture`, `preferred_destination`, `default_metadata`, `validate_or_warn()` and tag helpers |
| `systems/items/drink_definition.gd` | `carried_texture` and `full_container_texture` moved up to `ItemDefinition` (the latter renamed `world_texture`); `is_valid_drink()` now checks the `prepared_drink` tag instead of the enum |
| `systems/inventory/item_stack.gd` | Added `metadata`, `create()`, `matches_definition()`, metadata compatibility, safe `split()`/`duplicate_stack()`, serialisation |
| `scripts/Entities/player.gd` | `carried_drink` and its setters removed; carrying delegated to `ItemCarrier` |
| `scenes/player/player.tscn` | Added `ItemCarrier` and `InventoryComponent` child nodes |
| `scripts/Interactables/drinks_station.gd` | Rewritten around an output `ItemContainer` and `ItemTransferService` |
| `scripts/Entities/customer.gd` | `interact()` validates against the carrier and compares `item_id` |
| `scripts/Interactables/chair.gd` | `full_container_texture` → `world_texture` |
| `scripts/Managers/game_config.gd` | Added `show_item_debug_messages` |
| `Data/items/drinks/grog.tres` | Tags added; stack size 12 → 1; `preferred_destination` CARRIER; `category` removed; `full_container_texture` → `world_texture` |
| `Data/items/drinks/ale.tres` | As grog |

### Deleted files

```text
scripts/globals/ItemType.gd        (and its .uid)
```

A leftover `enum Type { NONE, GROG }`. It was unreferenced and directly competed
with `item_id` as an item-identity mechanism.

### Old carried-item logic removed

| Removed | Replaced by |
|---|---|
| `player.carried_drink` | `ItemCarrier`'s `ItemSlot` |
| `player.set_carried_drink()` | `ItemTransferService.transfer()` / `carrier.take_from()` |
| `player.clear_carried_drink()` | `carrier.clear_carried_item()` |
| `player.is_carrying_drink()` | `player.is_carrying()` |
| `player.update_carried_drink_visual()` | `ItemCarrier.update_carried_visual()`, signal-driven |
| `ItemDefinition.ItemCategory` | `ItemDefinition.tags` |
| `DrinkDefinition.full_container_texture` | `ItemDefinition.world_texture` |

All callers were updated. No dead code was left behind, and no compatibility
shims were needed.

### Retained method

`player.get_carried_drink()` remains as a **derived read-only accessor**, not a
compatibility shim and not stored state. It returns
`carrier.get_carried_definition() as DrinkDefinition` so drink-specific gameplay
stays readable. The corresponding setters were deleted, so the carrier's slot is
the only thing that can change what the player holds.

### Limitations

- **The drinks station is still an infinite supply.** A returned drink is
  discarded because there is no drink stock system. `_refill_output()` and
  `_on_drink_returned()` are the documented extension points.
- **Serving still consumes the drink into nothing.** `carrier.clear_carried_item()`
  is called when a customer is served. Once chairs have service slots this should
  become a transfer into the chair's slot, producing a real dirty tankard.
- **`InventoryComponent` is unused.** By design — no UI, no gameplay path in.
- **No save system exists**, so `to_dictionary()` and `from_dictionary()` are
  covered only by the automated tests.
- **Cleaning still produces no items.** Broken glass and dirty tankards exist as
  definitions but are not yet created by the cleaning flow.
- **Wine and water have textures but no drink resources.**

### Recommended next step

Build the **bar service slot** first, before storage or UI.

It is the smallest piece that exercises the whole system end to end — place,
pick up, swap and reject — against a real scene, and it is the feature already
named in the project roadmap. Concretely:

1. Create `scenes/furniture/bar_service_slot.tscn` following the sketch in
   [Bar service slots](#bar-service-slots).
2. Add three instances as children of the existing `BarCounter` in `main.tscn`.
3. Confirm placing, retrieving and swapping drinks works with no new transfer
   code.
4. Then give the chair a service slot too, so serving becomes a transfer rather
   than a clear — which is what unlocks real dirty tankards and connects cleaning
   to the item system.

Storage containers and the inventory UI should follow, because both benefit from
a proven slot-to-sprite binding pattern.
