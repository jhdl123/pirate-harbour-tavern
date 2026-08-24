# Configuration Guide — Pirate Harbour Tavern

Everything here is edited in the Godot Inspector on a `.tres` resource or a
scene's exported field — no script changes needed for any of it.

## Starting money

- **File:** `resources/config/default_game_config.tres` (a `GameConfig`
  resource, assigned to `GameManager.game_config` in `main.tscn`)
- **Field:** `starting_money`

## Customer payment values

- **File:** each `DrinkDefinition` `.tres` under `Data/items/drinks/`
  (`grog.tres`, `ale.tres`)
- **Field:** `base_sell_price` — what a customer pays per drink, before
  `payment_multiplier`
- **File:** each `CustomerType` `.tres` under `resources/CustomerTypes/`
- **Field:** `payment_multiplier` — scales that customer type's payment
  (e.g. a generous or stingy customer archetype)

## Drink definitions

- **Files:** `Data/items/drinks/grog.tres`, `Data/items/drinks/ale.tres`
  (`DrinkDefinition`, which extends `ItemDefinition` — a drink IS its own
  item, not a separate concept)
- **Identity fields** (from `ItemDefinition`): `item_id`, `display_name`,
  `description`, `tags`
- **Drink-specific fields**: `drink_duration_minutes` (how long a customer
  takes to finish it), `break_chance_multiplier` (how likely cleaning up
  after this drink causes a complication)
- **Visuals:** `order_icon_texture`, `empty_container_texture`,
  `broken_container_texture`, plus `world_texture`/`carried_texture`/
  `inventory_icon` from `ItemDefinition`

## Bulk stock definitions

- **Files:** `Data/items/stock/grog_barrel.tres`,
  `Data/items/stock/ale_keg.tres` (plain `ItemDefinition`s — bulk stock and
  prepared drinks are deliberately distinct items, e.g. `ale.tres` vs
  `ale_keg.tres`)
- These, and every other item in the game, are also listed in
  `Data/items/item_registry.tres` (the `ItemRegistry`). If you add a new
  item `.tres`, add it to this registry's `definitions` array too — it's now
  validated at startup (`GameManager._ready()`), so a missing or duplicate
  `item_id` will surface as a clear editor warning instead of a silent null
  reference somewhere downstream.

## Purchase prices (what the tavern pays a supplier)

- **File:** `Data/suppliers/harbour_supplies.tres` (`SupplierDefinition`)
- **Field:** each entry in `entries` (an `OrderCatalogueEntry`) has
  `unit_price_override` — leave at `-1` to fall back to the item's own
  `base_buy_price` (on the `ItemDefinition`), or set a positive number to
  override it for this supplier specifically
- **Field:** `maximum_order_quantity` on the same entry — the most of that
  item that can be ordered in one go

## Sale prices

- See "Customer payment values" above (`base_sell_price` on each
  `DrinkDefinition`).

## Stack limits

- **File:** each `ItemDefinition` (drinks and stock items alike)
- **Field:** `maximum_stack_size`

## Station capacity, starting stock, servings per refill

- **File:** the `DrinksStation` node's exported fields, set per-instance in
  `scenes/main/main.tscn` (or wherever a station is placed)
- **Fields:** `maximum_servings`, `starting_servings`,
  `servings_per_refill_item`, plus `served_drink` and `refill_item`
  (which `ItemDefinition`/`DrinkDefinition` this station serves and accepts)
- **Visual fields on the same node:** `normal_texture`, `empty_texture`,
  `indicator_segments` (how many segments the stock bar shows)

## Delivery delay

- **File:** the `OrderManager` node's exported field, set on the
  `OrderManager` node under `Managers/` in `main.tscn`
- **Field:** `default_delivery_minutes` — a single project-wide delay in
  world minutes, used for every order regardless of supplier. This is
  intentionally simple per the current design direction — see
  `CLEANUP_REPORT.md` bug 3 for why `SupplierDefinition` does **not** have
  its own delivery-delay field.

## Time speed and calendar

- **File:** `resources/time/default_time_config.tres` (or wherever
  `WorldTime.config` points — a `GameTimeConfig` resource)
- **Fields:** `minutes_per_hour`, `hours_per_day` (Calendar category);
  `starting_day`/`starting_hour`/`starting_minute` (Starting Point);
  `real_seconds_per_game_minute`, `available_speed_multipliers`,
  `default_speed_index` (Rate); `use_24_hour_clock`, `day_label_format`
  (Formatting)

## Customer timings

- **File:** each `CustomerType` `.tres` under `resources/CustomerTypes/`
- **Fields:** `order_delay_minutes` (how long before ordering after being
  seated), `patience_duration_minutes` (how long they'll wait before
  leaving), `preferred_drink_chance` (chance of ordering their
  `preferred_drink` vs any `available_drinks`), `movement_speed`,
  `seat_movement_speed`

## Spawn rates

- **File:** `resources/config/default_game_config.tres` (`GameConfig`)
- **Fields:** `minimum_spawn_delay_minutes`, `maximum_spawn_delay_minutes`
  (world minutes between spawn attempts), `maximum_active_customers`,
  `maximum_door_queue_size`
- **Per-type weighting:** each `CustomerType`'s `spawn_weight` field controls
  its relative chance of being chosen when a customer spawns
  (`GameManager.choose_customer_type()`)

## Seat selection tuning

- **File:** `resources/config/default_game_config.tres` (`GameConfig`)
- **Fields:** `occupied_seat_penalty` (how strongly the seat-scoring avoids
  tables that already have someone at them), `travel_distance_weight`

## Developer mode availability

- **File:** `scripts/UI/stock_dev_panel.gd`
- As of this cleanup pass, the F10 stock/economy/delivery dev panel checks
  `OS.is_debug_build()` in `_ready()` and does nothing at all outside a
  debug/editor build — no Inspector field controls this, it's automatic
  based on how the project is run/exported. See `CLEANUP_REPORT.md` bug 6.
- The F1–F4 simulation debug panel (pause/speed/skip/time readout) is
  **not** gated the same way — the project's `README.md` documents it as a
  normal, shipped control, not a developer-only tool. If you want it
  gated too, `SimulationDebugPanel.start_visible` controls only its initial
  visibility, not whether its hotkeys respond at all.

## Testing switches

- **File:** `resources/config/default_game_config.tres` (`GameConfig`,
  "Testing" category)
- **Fields:** `show_debug_messages` (also now gates `Chair`'s cleaning-state
  prints, see `CLEANUP_REPORT.md` bug 5), `show_item_debug_messages`,
  `disable_patience`, `disable_broken_glass`, `ignore_customer_limit`

---

*Note: the project also has its own internal `docs/CONFIGURATION_GUIDE.md`,*
*written before the stock/order/delivery system existed. It does not yet*
*cover the sections above about stock, suppliers or deliveries — see*
*`KNOWN_ISSUES.md` item 3.*
