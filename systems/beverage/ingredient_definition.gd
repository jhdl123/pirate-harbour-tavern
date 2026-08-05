class_name IngredientDefinition
extends ItemDefinition

## An [ItemDefinition] for something consumed by a recipe.
##
## Ingredients are real inventory items, not a parallel bookkeeping system.
## Sugar sits in an [ItemContainer] exactly as a cleaning rag does, is delivered
## by the same order system, and is consumed through the same
## [ItemTransferService]. That is the whole point: when food and cooking arrive,
## they inherit a working ingredient system rather than needing a new one.
##
## This resource adds only what a plain item cannot express: the unit it is
## measured in, whether it goes off, and how much of it one recipe unit is.


@export_category("Measurement")

## Word shown beside quantities: "loaf", "nutmeg", "pound".
@export var unit_name: String = "unit"

## Plural form, when simply adding an s is wrong.
@export var unit_name_plural: String = ""


@export_category("Recipes")

## Whether recipes may consume this at all.
##
## False for something bought and sold but never cooked with.
@export var usable_in_recipes: bool = true


@export_category("Spoilage")

## Whether this goes off. Citrus does; a sugar loaf does not.
@export var can_spoil: bool = false

## Profile used when [member can_spoil] is true.
@export var spoilage_profile: SpoilageProfileDefinition


@export_category("Storage")

## Where this belongs and what that does to it.
@export var storage_profile: StorageProfileDefinition


func get_unit_text(quantity: int) -> String:
	if quantity == 1:
		return unit_name

	if not unit_name_plural.strip_edges().is_empty():
		return unit_name_plural

	return unit_name + "s"


func get_quantity_text(quantity: int) -> String:
	return "%d %s" % [quantity, get_unit_text(quantity)]


func get_spoilage_profile() -> SpoilageProfileDefinition:
	if not can_spoil:
		return null

	return spoilage_profile


func is_perishable() -> bool:
	return can_spoil and spoilage_profile != null and spoilage_profile.is_enabled()


func validate_beverage_or_warn() -> bool:
	if not has_tag(ItemTags.INGREDIENT):
		push_warning(
			"IngredientDefinition '"
			+ String(item_id)
			+ "' is missing the 'ingredient' tag, so recipe and storage "
			+ "filters will not find it."
		)
		return false

	if can_spoil and spoilage_profile == null:
		push_warning(
			"IngredientDefinition '"
			+ String(item_id)
			+ "' is marked can_spoil but has no spoilage_profile."
		)

	return true
