# Changelog — Cleanup Pass

## Changed

- `systems/orders/order_manager.gd` — `process_due_orders()` and
  `complete_all_deliveries()` now iterate a shallow `.duplicate()` of
  `pending_orders` instead of a deep one, fixing a stock-duplication bug on
  partial deliveries.
- `systems/orders/supplier_definition.gd` — removed the unused
  `delivery_delay_days` field and updated the class doc comment.
- `scripts/Managers/game_manager.gd` — added `class_name GameManager`; added
  `item_registry: ItemRegistry` export plus startup validation; added
  `get_active_customer_count()`, `get_total_seat_count()`,
  `get_occupied_seat_count()`, `get_available_seat_count()`.
- `scripts/UI/bar_management_menu.gd` — typed `game_manager`/`economy_manager`
  exports; added `statistics_tracker` export; replaced hard-coded placeholder
  Overview text with live data; added `refresh_progression()` wiring the
  previously-unused Progression page labels; added live refresh on
  `money_changed`/`statistic_changed`/`time_changed`.
- `scripts/UI/stock_dev_panel.gd` — added `item_registry: ItemRegistry`
  export; `_add_test_stock()` now looks items up by stable ID instead of a
  hardcoded `load()` path; added an `OS.is_debug_build()` guard so the panel
  is inert in a release export.
- `scripts/Interactables/chair.gd` — `configure()` now stores its
  `GameConfig`; added `_should_print_debug()`; gated six previously
  unconditional `print()` calls behind it.
- `scripts/Entities/customer.gd` — added `class_name Customer`.
- `scenes/main/main.tscn` — wired `StatisticsTracker` and
  `Data/items/item_registry.tres` into `GameManager` and `StockDevPanel`.

## Removed

- `scripts/main.gd`, `scripts/main.gd.uid` — orphaned prototype script, not
  attached to any node, calling a method that no longer exists.
- `scenes/furniture/table.tscn8647504531.tmp` — Godot crash-recovery temp
  file.
- `INSTALL_INTERACTION_LEDGER.txt`, `INSTALL.txt`,
  `STOCK_DELIVERY_BUILD_README.md` — three obsolete "how to merge this
  patch" instruction files from earlier incremental delivery sessions;
  their described changes are already merged into the project.

## Added

- `CLEANUP_REPORT.md`, `ARCHITECTURE_OVERVIEW.md`, `TEST_CHECKLIST.md`,
  `CONFIGURATION_GUIDE.md`, `KNOWN_ISSUES.md`, `CHANGELOG.md` (this file) —
  the deliverables for this cleanup pass, at the project root.

## Not changed

- No gameplay features added or removed. No delivery-timing, staff, pricing,
  or other out-of-scope systems introduced. See "Areas deliberately left
  unchanged" in `CLEANUP_REPORT.md`.
