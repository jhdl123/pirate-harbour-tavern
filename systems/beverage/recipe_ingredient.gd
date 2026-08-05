class_name RecipeIngredient
extends Resource

## One line of a recipe: what is needed, how much, and where it comes from.
##
## A recipe can need two different kinds of thing, and they are held in
## different places in the game:
##
## [codeblock]
## ITEM      sugar, nutmeg, citrus     an ItemDefinition in an inventory
## CONTENT   rum, water                measures inside a FilledContainer
## [/codeblock]
##
## Keeping both in one resource means a recipe author writes one list, and the
## preparation code asks each line where to find itself rather than the recipe
## having two parallel arrays that can fall out of step.


enum SourceKind {
	## A normal inventory item, consumed by count.
	ITEM,

	## Liquid drawn out of a cask or bottle, consumed by measure.
	CONTENT,
}


@export_category("What")

@export var source_kind: SourceKind = SourceKind.ITEM

## Item id when [member source_kind] is [constant SourceKind.ITEM].
@export var item_id: StringName = &""

## Content id when [member source_kind] is [constant SourceKind.CONTENT].
@export var content_id: StringName = &""


@export_category("How much")

## Units consumed per batch produced: item count, or content measures.
@export_range(1, 10000, 1)
var quantity: int = 1


@export_category("Behaviour")

## Whether the recipe can still be made without this.
##
## An optional ingredient is used when present and skipped when not, which is
## how "spices where configured" works without a second recipe.
@export var optional: bool = false

## Station capability needed to reach this ingredient.
##
## Water needs [constant StationCapabilities.ACCESS_WATER]; nutmeg needs
## [constant StationCapabilities.ACCESS_DRY_INGREDIENTS]. Declared per
## ingredient so the recipe's own capability list stays about *method* rather
## than about storage.
@export var required_access_capability: StringName = &""


func is_item() -> bool:
	return source_kind == SourceKind.ITEM


func is_content() -> bool:
	return source_kind == SourceKind.CONTENT


## The id this line refers to, whichever kind it is.
func get_source_id() -> StringName:
	return item_id if is_item() else content_id


## Units needed to produce [param batches] batches.
func get_required_quantity(batches: int = 1) -> int:
	return quantity * maxi(batches, 1)


func is_valid() -> bool:
	if quantity <= 0:
		return false

	return not get_source_id().is_empty()


func get_display_text(registry: BeverageRegistry = null) -> String:
	var id: StringName = get_source_id()
	var label: String = String(id)

	if registry != null and is_content():
		var content: BeverageContentDefinition = registry.get_content(id)

		if content != null:
			label = content.display_name

	var suffix: String = " (optional)" if optional else ""

	return "%d x %s%s" % [quantity, label, suffix]
