# Beverage Framework

Data-driven drinks, stock, preparation and storage.

The rule this framework is built around: **adding normal content is a resource
edit, not a code change.** If you find yourself writing a script to add a drink,
something has gone wrong — check this document first.

---

## Resource relationships

```
BeverageContentDefinition ── the liquid            kill_devil, ale, water
        │
        ├── held by ─→ FilledContainer ──→ ContainerDefinition
        │                (runtime batch)      hogshead, firkin, bottle
        │
        ├── referenced by ─→ DrinkDefinition ── what a customer orders
        │                          │
        │                          ├─→ ServingFormatDefinition[]  dram, tankard
        │                          └─→ DrinkRecipeDefinition      if prepared
        │
        └── consumed by ─→ DrinkRecipeDefinition ─→ RecipeIngredient[]
                                                         │
                                                         └─→ IngredientDefinition
                                                             (a normal item)

SpoilageProfileDefinition  attached to contents, drinks and recipe results
StorageProfileDefinition   decides which BeverageStorage a batch may live in
StationCapabilities        the join between a drink/recipe and a station
```

Three separations do the heavy lifting:

| Separation | Why |
|---|---|
| Content vs. container | One hogshead resource holds rum today and Madeira tomorrow. No `HogsheadOfRum` class ever exists. |
| Drink vs. serving format | 13 drinks × 12 formats needs 25 resources, not 156. The format rides in the `ItemStack` metadata of the served item. |
| Capability vs. station | No drink name appears in any station script. |

---

## Initial content

**Contents (14)** — kill_devil, arrack, brandy, small_beer, ale, cider, madeira,
port_wine, canary_wine, water, prepared_bumbo, prepared_rum_punch,
brewed_coffee, drinking_chocolate

**Drinks (13)** — Kill-Devil, Bumbo, Rum Punch, Small Beer, Ale, Cider, Madeira
Wine, Port Wine, Canary Wine, French Brandy, Arrack, Coffee, Drinking Chocolate
(plus the two migrated legacy drinks, Grog and Ale)

**Containers (19)** — Firkin (small cask), Kilderkin (medium cask), Barrel (large
cask), Hogshead (very large cask), Puncheon (bulk rum cask), Pipe (large wine
cask), Service Cask (tapped bar cask), Bottle, Crate (case of bottles), Dram
Glass, Cup, Mug, Tankard, Glass, Pitcher (shared jug), Punch Bowl (shared bowl),
Table Cask (shared small keg), Coffee Pot, Sack (dry goods sack)

**Serving formats (12)** — Dram, Cup, Glass, Mug, Tankard, Bottle, Pitcher, Punch
Bowl, Table Cask, Pot, Firkin, Kilderkin

**Ingredients (6)** — Sugar Loaf, Nutmeg, Citrus Fruit, Coffee Beans, Cocoa,
Mixed Spices

**Recipes (4)** — Bumbo, Rum Punch, Coffee, Drinking Chocolate

**Profiles** — 8 spoilage, 8 storage

> All capacities, prices and durations are **configurable placeholder balance
> values**. They are historically *inspired*, not historical measurements —
> real cask sizes varied by period, place and contents.

---

## How to add a new drink

No code. Two resources, one registry entry.

1. **Content** — if the liquid does not exist yet, create a
   `BeverageContentDefinition` in `Data/beverage/contents/`. Set `content_id`,
   `display_name`, and `tags` (include `liquid`). Set `can_spoil` + a profile
   only if it should go off.
2. **Drink** — create a `DrinkDefinition` in `Data/beverage/drinks/`. Set:
   - `item_id` (stable, never rename once saved)
   - `tags` — must include `prepared_drink`; add family tags (`rum`, `wine`) and
     any affinity tags (`sailor_favourite`)
   - `content_id` — the liquid above
   - `serving_format_ids` — first entry is the default
   - `required_station_capabilities` — e.g. `draw_from_cask`
   - `base_sell_price`, `alcohol_strength`, `drink_duration_minutes`
3. **Register** — add the drink to `Data/items/item_registry.tres`, and the
   content to `Data/beverage/beverage_registry.tres`.
4. **Check** — open the diagnostics panel (F7) → Validation.

The format must also accept the drink. If `valid_drink_tags` on the format does
not overlap the drink's tags, validation reports it as an error rather than
letting it fail silently at service time.

## How to add a new mixed drink

Everything above, plus a `DrinkRecipeDefinition` in `Data/beverage/recipes/`:

- `output_drink_id` — the drink it produces
- `output_content_id` — set this for anything a group drinks down
- `ingredients` — one `RecipeIngredient` per line:
  - `source_kind = ITEM` for inventory items (sugar, nutmeg)
  - `source_kind = CONTENT` for liquid drawn from casks (rum, water)
  - `required_access_capability` — how the station reaches it
  - `optional = true` for lines that can be skipped when absent
- `required_station_capabilities` — the *method* (`mix_single`, `prepare_batch`)
- `required_vessel_container_id` — reserved before preparation starts
- `preparation_minutes`, `is_batch_preparation`
- `result_can_spoil` + `result_spoilage_profile`

Then set `recipe_id` on the drink and `service_method` to `MIXED_TO_ORDER` or
`PREPARED_AS_BATCH`.

Station capability requirements merge from **both** the drink and its recipe —
see `DrinksStation.get_required_capabilities()`. A drink that declares nothing
itself is still gated by its recipe.

## How to add a new container size

Create a `ContainerDefinition` in `Data/beverage/containers/`:

- `container_id`, `historical_name`, `simplified_explanation`
- `maximum_capacity` in measures, `category`
- `supported_content_tags` — `liquid` or `dry_good`
- `bulk_storage` / `customer_serving` — keep these mutually exclusive
- `can_be_transfer_source` / `can_be_transfer_destination`

Add it to the registry. The player-facing name renders automatically as
`Firkin (small cask)` via `get_display_name_with_explanation()`.

## How to add a new station capability

1. Add the constant to `systems/beverage/station_capabilities.gd`.
2. Add it to `get_all_capabilities()` — otherwise the validator reports it as
   unrecognised (a warning, not an error; it still works).
3. Add it to the `station_capabilities` array on whichever stations have it.
4. Reference it from drinks or recipes.

This is the one addition that touches a script, and only to name the constant.

## How to change balance values

| What | Where |
|---|---|
| Cask capacities | `ContainerDefinition.maximum_capacity` |
| Measures per serving | `ServingFormatDefinition.measures_per_serving` |
| Portions in a shared serving | `ServingFormatDefinition.portion_count` |
| Drink prices | `DrinkDefinition.base_sell_price` × format `price_modifier` |
| Purchase prices | `ItemDefinition.base_buy_price` |
| Preparation times | `DrinkRecipeDefinition.preparation_minutes` × format `service_time_modifier` |
| Drinking times | `DrinkDefinition.drink_duration_minutes` × format `consumption_time_modifier` |
| Spoilage timing | `SpoilageProfileDefinition.expiry_minutes` / `grace_minutes` |
| Storage effect on spoilage | `StorageProfileDefinition.spoilage_modifier`, `BeverageStorage.spoilage_modifier` |

To **disable spoilage** for something, set `expiry_minutes = 0` or
`can_spoil = false`. Every field stays safe to read — freshness returns 1.0 and
no event is scheduled.

---

## Migrating a station

Existing stations keep working untouched. To move one onto the framework, set
four properties in the inspector:

- `beverage_registry`
- `service_container` — e.g. Service Cask
- `station_capabilities` — e.g. `draw_from_cask`
- `service_content_id` — optional, defaults to the drink's `content_id`

The station then holds real measures. `current_servings` is kept in step
automatically, so the task coordinator, stock alerts and UI need no changes.

---

## Ordering

`OrderCatalogueEntry` was extended rather than replaced. An entry is one of two
shapes:

- **ITEM** — an `ItemDefinition`, delivered into `StockStorage`
- **FILLED_CONTAINER** — a `container_id` + `content_id`, delivered into a
  `BeverageStorage` as a real `FilledContainer`

That is why "Hogshead of Kill-Devil" never needed an item resource. Delivery
routes by `destination_storage_tags`, so premium bottles land in locked storage
rather than the first location with room.

Four suppliers ship with the framework: Harbour Distillery (rum casks), Town
Brewer (ale, small beer, cider), Island Importer (wine, brandy, arrack — the
rare lines have `availability` below 1.0 and a reputation requirement), and
Port Provisioner (dry ingredients).

## Regenerating the data

```
godot --headless --script tools/generate_beverage_data.gd
godot --headless --script tools/update_item_registry.gd
godot --headless --script tools/migrate_legacy_drinks.gd
godot --headless --script tools/generate_supplier_offers.gd
godot --headless --script tools/validate_beverage.gd
```

The generator **overwrites** `Data/beverage/`. Run the other three afterwards or
hand edits to the legacy drinks are lost. `migrate_legacy_drinks.gd` preserves
resource UIDs so scene references stay exact.

---

## Testing

```
godot --headless res://tests/beverage_framework_test.tscn    # 49 checks
godot --headless res://tests/beverage_station_test.tscn      # 27 checks
godot --headless res://tests/beverage_ordering_test.tscn     # 18 checks
```

All three drive real gameplay paths — moving real stock, reserving real ingredients,
reading results back. Neither checks that a class exists.
