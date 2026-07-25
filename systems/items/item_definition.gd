class_name ItemDefinition
extends Resource

enum ItemCategory {
	DRINK,
	FOOD,
	INGREDIENT,
	TOOL,
	FURNITURE,
	MATERIAL,
	VALUABLE,
	MISCELLANEOUS
}


@export_category("Identity")

## Stable internal identifier used by save data and systems.
##
## Examples:
## grog
## ale
## cleaning_rag
## wooden_chair
##
## Once an item is used in save data, this should not be renamed.
@export var item_id: StringName = &""

## Name displayed to the player.
@export var display_name: String = "Unnamed Item"

## Optional description used in menus and tooltips.
@export_multiline var description: String = ""

## Broad organisational category.
@export var category: ItemCategory = ItemCategory.MISCELLANEOUS


@export_category("Visuals")

## Texture used by inventories, menus and tooltips.
##
## World and carried textures belong on specialised definitions where needed.
@export var inventory_icon: Texture2D


@export_category("Inventory")

## Maximum number of this item allowed in one stack.
##
## Examples:
## Furniture or unique tools: 1
## Drinks or ingredients: 12+
@export_range(1, 9999, 1)
var maximum_stack_size: int = 1


@export_category("Economy")

## Baseline amount normally paid to acquire one item.
##
## The economy system may later apply supply, reputation and event modifiers.
@export_range(0, 999999, 1)
var base_buy_price: int = 0

## Baseline amount normally received for selling one item.
##
## This is data, not necessarily the final transaction price.
@export_range(0, 999999, 1)
var base_sell_price: int = 0


func is_valid() -> bool:
	return (
		not item_id.is_empty()
		and not display_name.strip_edges().is_empty()
		and maximum_stack_size > 0
		and base_buy_price >= 0
		and base_sell_price >= 0
	)


func can_stack() -> bool:
	return maximum_stack_size > 1


func get_base_buy_value(quantity: int = 1) -> int:
	return base_buy_price * maxi(quantity, 0)


func get_base_sell_value(quantity: int = 1) -> int:
	return base_sell_price * maxi(quantity, 0)
