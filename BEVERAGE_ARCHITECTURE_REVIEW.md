# Beverage Framework — Architecture Review (Stage 1)

Reviewed against the uploaded `pirateharbourtavern_4a_final` build.
Godot 4.7.1 headless verified: project imports clean, `phase_4a_integration_test`
passes 18/18 as a baseline.

Project size: 194 GDScript files, 47,440 lines, 100 `.tres`, 45 `.tscn`.

---

## 1. What can be reused as-is

These are strong and the beverage framework should build *on* them, not beside them.

| System | Files | Why it works |
|---|---|---|
| Item definitions + registry | `systems/items/` | `ItemDefinition` already has stable `item_id`, free-form `tags`, prices, stack size, and a `default_metadata` dictionary explicitly described as the extension point for "future quality, spoilage, ownership". `ItemRegistry` already does id→definition with duplicate detection. |
| Inventory | `systems/inventory/` | `ItemContainer` / `ItemSlot` / `ItemSlotRules` / `ItemTransferService` are genuinely generic and tag-driven. `ItemSlotRules.accepted_tags` is how storage compatibility should be expressed. `ItemTransferResult` already models partial moves, full destinations and empty sources. |
| Staff capability model | `systems/staff/staff_capabilities.gd` | `satisfies(held, required)` with an empty-required-means-anyone rule. This is the exact pattern the brief wants for **station** capabilities — it should be copied in shape, not reinvented. |
| Task framework | `systems/staff/tasks/`, `executors/` | `TavernTaskTypes` already declares `PREPARE_DRINK`, `REFILL_STATION`, `MOVE_STOCK` as reserved names. Adding a task type is documented as "two registrations and one new executor script". |
| Time | `systems/time/time_scheduler.gd` | `schedule_in`, `schedule_repeating`, `cancel_tag`, `to_dictionary`. This is the spoilage engine — no per-frame processing needed, and `cancel_tag` gives clean invalidation. |
| Interaction | `systems/interaction/` | Stations, casks and shared vessels can all become `Interactable`s without touching the player. |
| Ordering | `systems/orders/` | `OrderCatalogueEntry` + `SupplierDefinition` are thin but sound. Extend rather than replace, per the brief. |

## 2. What is currently hardcoded (the actual work)

**`DrinksStation` is one station = one drink.**
`@export var served_drink: DrinkDefinition` plus `current_servings: int`.
There is no container, no contents id, no capability list. `served_drink` is read
from **9 files** outside the station itself (`tavern_task_coordinator`,
`prepare_drink_executor`, `carried_item_recovery`, `stock_alert_coordinator`,
2 test files). Every one of those is a migration site.

**Stock items are hardcoded container+content combinations.**
`grog_barrel.tres` and `ale_keg.tres` are single `ItemDefinition`s tagged
`drink_stock`. There is no separation of "barrel" from "what's in the barrel" —
exactly the anti-pattern the brief calls out. Refill is
`servings_per_refill_item: int = 20`, a flat integer on the station.

**`StockStorage` is a single hardcoded location.**
`ItemContainer.new(&"main_stock_storage", ...)` with `accepted_tags = [&"drink_stock"]`
hardwired in `_ready()`. No cellar/behind-bar/dry/locked distinction. Found via
`get_nodes_in_group(&"stock_storage")` and takes `nodes[0]`.

**Customer ordering is drink-only.**
`Customer.ordered_drink: DrinkDefinition`, chosen from
`CustomerType.available_drinks` — an archetype list, which the brief explicitly
says should not be the primary preference system. There is no serving-format
concept anywhere in the order path.

## 3. Duplicate / conflicting concepts

- `systems/stock/stock_storage.gd` and `scripts/Components/inventory_component.gd`
  both wrap `ItemContainer` with different conventions.
- `scripts/globals/ItemType.gd` (6 lines) is a vestigial enum predating the item system.
- `resources/` and `Data/` both hold `.tres`; drinks live in `Data/`, `CustomerTypes`
  and `config` in `resources/`. New beverage resources should go under `Data/`.

## 4. Three blocking findings

### 4.1 There is no save/load system

Searched the whole tree. `ItemStack`, `ItemContainer` and `TimeScheduler` each have
`to_save_dict()` / `from_save_dict()` helpers, and many files carry comments about
save-safety — but **nothing orchestrates a save, and nothing writes a save file.**
The only `FileAccess` writes outside `addons/` are diagnostic report exporters.

The brief's migration section ("preserve stable save compatibility", "update save/load
to persist resource IDs", acceptance criterion "existing save/load does not crash")
has no target. This is not a problem — it is an opportunity, because the
serialisation format can be designed correctly the first time with no legacy to
carry. But it changes what "migration" means: the migration is of **live resources
and scene wiring**, not of save files.

### 4.2 There is no group system

Zero occurrences of any group concept. `ModifierTargets.CUSTOMER_GROUP_SIZE` is a
declared-but-unread constant, consistent with the known deferred work at end of
Phase 4A. Customers spawn, seat and drink entirely individually.

The brief's shared-serving section says "integrate this with the current group work
if it already exists" — it does not. But the acceptance criteria still require
"group members can consume from them repeatedly" and "punch bowls can function as
group anchors", while the scope rules forbid redesigning group AI.

The resolution that satisfies both: implement the shared serving object as a
**table-anchored world object**, where the "group" is defined as the set of
customers currently seated at that table. This needs no group AI, no group spawner
and no changes to customer selection — a seated customer simply gains one extra
activity ("take a portion from the shared serving at my table"). A real group system
can later supply a `group_id` to the same object without changing its design.

### 4.3 `DrinkDefinition extends ItemDefinition` conflicts with the brief

The current model is deliberate and documented: *a drink IS its own item definition,
one resource per drink, so balance and item identity never drift.*

The brief instead asks for separation of liquids, finished drinks and physical stock
items, plus a `compatible stock-content ID` field on `DrinkDefinition`.

These are reconcilable but only one way: keep `DrinkDefinition extends ItemDefinition`
as the **served/carried** item, and add a separate lightweight `content_id`
(the liquid) that bulk stock, service casks and recipes all refer to. So
`kill_devil` the liquid is one thing; `kill_devil_dram`, `kill_devil_mug` etc. are
the served items generated per serving format. This preserves your earlier decision
and satisfies the brief — but it means the number of drink item resources grows
with serving formats, which is worth confirming before I generate them.

## 5. Risk register

| Risk | Where | Mitigation |
|---|---|---|
| Breaking the working customer loop | `customer.gd` (2,032 lines) | Serving format defaults to a per-drink `default_serving_format_id`, so existing order paths keep working with one id added. |
| Breaking staff tasks | 9 `served_drink` call sites | Station keeps a `served_drink`-compatible accessor during migration; remove only after tests pass. |
| Stock alerts spamming | `stock_alert_coordinator.gd` | Station stock state must be computed from container contents, preserving the existing hysteresis rule exactly. |
| Test suite rot | `tests/` 8 suites | All 8 run as a regression gate after each stage, not just at the end. |
| Resource explosion | `Data/` | Serving-format item variants generated from a template at load, not authored by hand, if 4.3 is confirmed. |

## 6. Files that will change

**New** — `systems/beverage/` (definitions, registry, capabilities, transfer,
spoilage, shared servings), `Data/beverage/` (drinks, liquids, ingredients,
containers, serving formats, recipes, storage profiles, supplier offers).

**Modified** — `drinks_station.gd`, `stock_storage.gd`, `order_manager.gd`,
`supplier_definition.gd`, `order_catalogue_entry.gd`, `customer.gd`,
`customer_type.gd`, `tavern_task_coordinator.gd`, `prepare_drink_executor.gd`,
`refill_station_executor.gd`, `carried_item_recovery.gd`,
`stock_alert_coordinator.gd`, `bar_management_menu.gd`, `stock_dev_panel.gd`,
`item_tags.gd`, `item_registry.tres`, `main.tscn`, `drinks_station.tscn`.

**Deleted** — `scripts/globals/ItemType.gd` only.
