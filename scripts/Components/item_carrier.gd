class_name ItemCarrier
extends Node

## Holds the one item an actor is carrying in its hands.
##
## Attach to the player today, and to staff later. The carrier owns a single
## [ItemSlot], keeps an optional [Sprite2D] in step with it, and routes every
## hand-off through [ItemTransferService] so the player obeys the same transfer
## rules as storage, trays and future UI.
##
## The carrier never knows what a drink is. It reads
## [member ItemDefinition.carried_texture] and tags, so a keg, a tray, a crate
## or a mop will work without changing this script.


## Emitted whenever the carried item changes, including when it is cleared.
##
## [param current_stack] is an independent copy and is empty when the actor's
## hands are free.
signal carried_item_changed(
	previous_stack: ItemStack,
	current_stack: ItemStack
)


@export_category("Visuals")

## Sprite that displays the carried item. Optional.
##
## Hidden automatically whenever the hands are empty.
@export var carried_sprite: Sprite2D


@export_category("Slot Rules")

## How many of one item the hands can hold.
##
## Still capped by the item's own maximum stack size, so a stack-size-1 drink
## stays a single drink even if this is raised.
@export_range(1, 99, 1)
var carry_capacity: int = 1

## When non-empty, only items carrying one of these tags may be picked up.
##
## Left empty by default so the hands can hold anything, which matches how a
## pair of hands actually behaves.
@export var accepted_tags: Array[StringName] = []

## Items carrying any of these tags can never be held.
@export var rejected_tags: Array[StringName] = []


var _slot: ItemSlot


func _ready() -> void:
	_build_slot()
	update_carried_visual()


func _build_slot() -> void:
	var rules: ItemSlotRules = ItemSlotRules.new()

	rules.capacity = carry_capacity
	rules.accepted_tags = accepted_tags.duplicate()
	rules.rejected_tags = rejected_tags.duplicate()
	rules.allow_insert = true
	rules.allow_remove = true
	rules.allow_merge = true
	rules.allow_swap = true
	rules.allow_partial = false

	rules.validate_or_warn(get_path())

	_slot = ItemSlot.new(
		StringName("%s_hands" % get_parent().name.to_snake_case()),
		rules
	)

	_slot.contents_changed.connect(_on_slot_contents_changed)


# --- Reading -----------------------------------------------------------------

## The carrier's slot, for use with [ItemTransferService].
##
## This is how bar slots, storage and trays will exchange items with an actor.
func get_slot() -> ItemSlot:
	return _slot


func is_carrying() -> bool:
	return _slot != null and _slot.has_item()


## An independent copy of the carried stack. Empty when the hands are free.
func get_carried_stack() -> ItemStack:
	if _slot == null:
		return ItemStack.new()

	return _slot.peek()


## The carried item's definition, or null when the hands are free.
func get_carried_definition() -> ItemDefinition:
	if _slot == null:
		return null

	return _slot.get_definition()


func get_carried_item_id() -> StringName:
	if _slot == null:
		return &""

	return _slot.get_item_id()


func get_carried_quantity() -> int:
	if _slot == null:
		return 0

	return _slot.get_quantity()


## True when the hands hold the given item id.
func is_carrying_item(item_id: StringName) -> bool:
	return get_carried_item_id() == item_id


## True when the hands hold an item carrying [param tag].
func is_carrying_tagged(tag: StringName) -> bool:
	var definition: ItemDefinition = get_carried_definition()

	return definition != null and definition.has_tag(tag)


# --- Taking and placing ------------------------------------------------------

## Takes an item from [param source_slot] into the hands.
##
## Swaps when the hands are already full and both sides allow it.
func take_from(source_slot: ItemSlot) -> ItemTransferResult:
	if _slot == null:
		return ItemTransferResult.failure(
			ItemTransferResult.Status.INVALID_REQUEST
		)

	return ItemTransferService.transfer(source_slot, _slot)


## Places the carried item into [param destination_slot].
func place_into(destination_slot: ItemSlot) -> ItemTransferResult:
	if _slot == null:
		return ItemTransferResult.failure(
			ItemTransferResult.Status.INVALID_REQUEST
		)

	return ItemTransferService.transfer(_slot, destination_slot)


## Places the carried item into [param destination_container].
func place_into_container(
	destination_container: ItemContainer
) -> ItemTransferResult:
	if _slot == null:
		return ItemTransferResult.failure(
			ItemTransferResult.Status.INVALID_REQUEST
		)

	return ItemTransferService.transfer_to_container(
		_slot,
		destination_container
	)


## Puts [param stack] straight into the hands.
##
## Only for generators with no real source slot, such as the current drinks
## station's refill. Anything with a real source slot should use
## [method take_from] so the source is emptied correctly.
func give(stack: ItemStack) -> ItemTransferResult:
	if _slot == null:
		return ItemTransferResult.failure(
			ItemTransferResult.Status.INVALID_REQUEST
		)

	return ItemTransferService.give_to_slot(_slot, stack)


## Empties the hands and returns what was held.
##
## Use only where the item is genuinely consumed or handed to something outside
## the item system, such as a customer drinking it. Everything else should go
## through [method place_into] so the item ends up somewhere real.
func clear_carried_item() -> ItemStack:
	if _slot == null:
		return ItemStack.new()

	return _slot.clear()


## True when [param definition] could be picked up right now.
func can_accept(definition: ItemDefinition) -> bool:
	if _slot == null or definition == null:
		return false

	return _slot.get_acceptable_amount(definition) > 0


# --- Visuals -----------------------------------------------------------------

## Refreshes the carried sprite from the carried item's data.
func update_carried_visual() -> void:
	if carried_sprite == null:
		return

	var definition: ItemDefinition = get_carried_definition()

	if definition == null:
		carried_sprite.texture = null
		carried_sprite.visible = false
		return

	if definition.carried_texture == null:
		push_warning(
			"Item '"
			+ String(definition.item_id)
			+ "' has no carried texture assigned, so "
			+ str(get_path())
			+ " cannot display it."
		)

		carried_sprite.texture = null
		carried_sprite.visible = false
		return

	carried_sprite.texture = definition.carried_texture
	carried_sprite.visible = true


func _on_slot_contents_changed(
	previous_stack: ItemStack,
	current_stack: ItemStack
) -> void:
	update_carried_visual()

	carried_item_changed.emit(previous_stack, current_stack)
