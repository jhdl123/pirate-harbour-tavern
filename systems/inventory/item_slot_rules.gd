class_name ItemSlotRules
extends Resource

## Inspector-configurable permissions and filters for one [ItemSlot].
##
## Rules are data, so a bar service slot, a cellar crate, a tray and a player
## backpack all use the same [ItemSlot] script with different rule resources.
##
## A rules resource may safely be shared by many slots: it is read-only during
## play. [ItemSlot] never writes to its rules.


@export_category("Capacity")

## Maximum number of items this slot may hold.
##
## The effective capacity is always the SMALLER of this value and the item's
## own [member ItemDefinition.maximum_stack_size]. A slot with capacity 99
## still holds only one prepared drink.
@export_range(1, 9999, 1)
var capacity: int = 1


@export_category("Filtering")

## When non-empty, an item must carry at least one of these tags.
##
## Leave empty to accept any tag.
@export var accepted_tags: Array[StringName] = []

## An item carrying any of these tags is always rejected.
##
## Rejection wins over acceptance.
@export var rejected_tags: Array[StringName] = []

## When non-empty, only these exact item ids are accepted.
##
## Useful for a keg input or a single-product shelf.
@export var accepted_item_ids: Array[StringName] = []


@export_category("Permissions")

## Whether items may be put into this slot.
@export var allow_insert: bool = true

## Whether items may be taken out of this slot.
@export var allow_remove: bool = true

## Whether an incoming stack may merge into a matching stack already here.
@export var allow_merge: bool = true

## Whether an incoming stack may swap places with a different stack here.
@export var allow_swap: bool = true

## Whether a partial amount may be moved when the whole amount does not fit.
@export var allow_partial: bool = true


## Returns the usable capacity for [param definition].
func get_effective_capacity(definition: ItemDefinition) -> int:
	if definition == null:
		return 0

	return mini(capacity, definition.maximum_stack_size)


## Returns true when this slot's filters accept [param definition].
##
## Permissions are checked separately by [ItemSlot], because "this item is the
## wrong kind" and "this slot is locked" are different transfer results.
func accepts_definition(definition: ItemDefinition) -> bool:
	if definition == null:
		return false

	if not definition.has_no_tags(rejected_tags):
		return false

	if not definition.has_any_tag(accepted_tags):
		return false

	if not accepted_item_ids.is_empty():
		if not accepted_item_ids.has(definition.item_id):
			return false

	return true


## Reports impossible rule combinations. Returns true when the rules are usable.
func validate_or_warn(context: String = "") -> bool:
	var is_usable: bool = true
	var label: String = context

	if label.is_empty():
		label = resource_path

	if capacity <= 0:
		push_error(
			"ItemSlotRules "
			+ label
			+ " has a capacity of "
			+ str(capacity)
			+ ". Capacity must be at least 1."
		)
		is_usable = false

	for tag: StringName in accepted_tags:
		if rejected_tags.has(tag):
			push_error(
				"ItemSlotRules "
				+ label
				+ " both accepts and rejects the tag '"
				+ String(tag)
				+ "'. Nothing will ever be accepted."
			)
			is_usable = false

	if not allow_insert and not allow_remove:
		push_warning(
			"ItemSlotRules "
			+ label
			+ " allows neither insertion nor removal."
		)

	return is_usable


## Returns an independent copy, so a caller can tweak rules per slot safely.
func duplicate_rules() -> ItemSlotRules:
	var copy: ItemSlotRules = ItemSlotRules.new()

	copy.capacity = capacity
	copy.accepted_tags = accepted_tags.duplicate()
	copy.rejected_tags = rejected_tags.duplicate()
	copy.accepted_item_ids = accepted_item_ids.duplicate()
	copy.allow_insert = allow_insert
	copy.allow_remove = allow_remove
	copy.allow_merge = allow_merge
	copy.allow_swap = allow_swap
	copy.allow_partial = allow_partial

	return copy
