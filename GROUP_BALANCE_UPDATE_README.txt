GROUP BALANCE / ORDERING UPDATE
================================

Patience
--------
Patience is configured per CustomerType resource, not in the player config.
Updated defaults:
- resources/CustomerTypes/sailor.tres: 25 game minutes
- resources/CustomerTypes/sailor_impatient.tres: 15 game minutes
GameConfig.disable_patience remains the global on/off switch.

Small Ale Keg ordering
----------------------
Data/suppliers/harbour_supplies.tres now includes Small Ale Keg in the Supply Ledger catalogue.
It uses Data/items/group_servings/ale_table_keg.tres and is delivered through the existing order system.

Keg prices
----------
- Buy price: £20
- Base sell price: £30
- Ale table-cask customer price: approximately £30 before group spending modifiers
The table-cask price is controlled by Data/beverage/serving_formats/table_cask.tres.

Keg sprites
-----------
Open Data/items/group_servings/ale_table_keg.tres in Godot.
Set:
- Inventory Icon: ledger/storage UI icon
- World Texture: placed/world keg image
- Carried Texture: sprite shown while staff carries the keg

The carried texture is read automatically by ItemCarrier.
The currently placed SharedServing still uses Managers/GroupOrderService -> Placeholder Texture in scenes/main/main.tscn.
Set that Inspector property to the same placed-keg texture until SharedServing is changed to read ItemDefinition.world_texture directly.

Diagnostics
-----------
Customer AI reports now include:
- balance_summary.solo service and patience rates
- balance_summary.groups success, payment, activity, drink and recovery rates
- group_runs: one compact row per group
Raw completed_visits remain unchanged and authoritative.
