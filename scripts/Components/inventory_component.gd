class_name InventoryComponent
extends Node

## A personal inventory attached to an actor.
##
## This is a thin, Inspector-friendly wrapper around one [ItemContainer]. It
## exists so the player and future staff can own a backpack without any script
## knowing how containers work internally.
##
## Current status
## --------------
## The player carries this component, but nothing puts items into it yet and
## there is no UI. It is the connection point for a future inventory screen,
## world pickups and staff restocking. Attaching it now costs one node and
## keeps that later work from touching the player script again.


## Emitted after any change to the inventory's contents.
signal inventory_changed

## Emitted when one slot changes, for future per-slot UI updates.
signal slot_changed(
	slot_index: int,
	previous_stack: ItemStack,
	current_stack: ItemStack
)


@export_category("Layout")

## Stable identifier used by save data.
##
## Must be unique across every container in a save, for example
## &"player_backpack" or &"staff_01_backpack".
@export var container_id: StringName = &"personal_inventory"

## Number of fixed slots.
##
## Twelve is the project's default backpack size. There is no weight system:
## capacity is slot count plus per-item stack sizes.
@export_range(1, 200, 1)
var slot_count: int = 12


@export_category("Rules")

## Optional shared rules resource applied to every slot.
##
## Leave empty to build rules from the fields below.
@export var slot_rules: ItemSlotRules

## Default per-slot capacity when [member slot_rules] is empty.
##
## Still capped by each item's own maximum stack size.
@export_range(1, 9999, 1)
var default_slot_capacity: int = 99

## When non-empty, only items with one of these tags may be stored.
@export var accepted_tags: Array[StringName] = []

## Items carrying any of these tags are refused.
##
## Prepared customer drinks are rejected by default: a served drink belongs in
## the hands or on a tray, not in a backpack.
@export var rejected_tags: Array[StringName] = [
	&"prepared_drink",
	&"bulky_item",
]


var _container: ItemContainer


func _ready() -> void:
	_build_container()


func _build_container() -> void:
	var rules: ItemSlotRules = slot_rules

	if rules == null:
		rules = ItemSlotRules.new()
		rules.capacity = default_slot_capacity
		rules.accepted_tags = accepted_tags.duplicate()
		rules.rejected_tags = rejected_tags.duplicate()
		rules.allow_insert = true
		rules.allow_remove = true
		rules.allow_merge = true
		rules.allow_swap = true
		rules.allow_partial = true

	rules.validate_or_warn(get_path())

	_container = ItemContainer.new(
		container_id,
		slot_count,
		rules
	)

	_container.container_tags = [&"personal"]

	_container.contents_changed.connect(_on_container_contents_changed)
	_container.slot_changed.connect(_on_container_slot_changed)


func _on_container_contents_changed() -> void:
	inventory_changed.emit()


func _on_container_slot_changed(
	slot_index: int,
	previous_stack: ItemStack,
	current_stack: ItemStack
) -> void:
	slot_changed.emit(slot_index, previous_stack, current_stack)


# --- Access ------------------------------------------------------------------

## The underlying container, for use with [ItemTransferService] and future UI.
func get_container() -> ItemContainer:
	return _container


func get_slot_count() -> int:
	if _container == null:
		return 0

	return _container.get_slot_count()


func get_slot(slot_index: int) -> ItemSlot:
	if _container == null:
		return null

	return _container.get_slot(slot_index)


func is_empty() -> bool:
	return _container == null or _container.is_empty()


func is_full() -> bool:
	return _container != null and _container.is_full()


func get_total_quantity(item_id: StringName) -> int:
	if _container == null:
		return 0

	return _container.get_total_quantity(item_id)


func has_item(
	item_id: StringName,
	minimum_quantity: int = 1
) -> bool:
	if _container == null:
		return false

	return _container.has_item(item_id, minimum_quantity)


## True when this inventory would accept [param definition] at all.
func accepts_definition(definition: ItemDefinition) -> bool:
	if _container == null:
		return false

	return _container.accepts_definition(definition)


# --- Mutation ----------------------------------------------------------------

func add_item(
	definition: ItemDefinition,
	quantity: int = 1,
	stack_metadata: Dictionary = {}
) -> ItemTransferResult:
	if _container == null:
		return ItemTransferResult.failure(
			ItemTransferResult.Status.INVALID_REQUEST
		)

	return _container.add_item(definition, quantity, stack_metadata)


func add_stack(stack: ItemStack) -> ItemTransferResult:
	if _container == null:
		return ItemTransferResult.failure(
			ItemTransferResult.Status.INVALID_REQUEST
		)

	return _container.add_stack(stack)


## Removes up to [param quantity] of [param item_id].
##
## Returns the amount actually removed.
func remove_item(
	item_id: StringName,
	quantity: int = 1,
	require_full_amount: bool = false
) -> int:
	if _container == null:
		return 0

	return _container.remove_item(
		item_id,
		quantity,
		require_full_amount
	)


# --- Serialisation -----------------------------------------------------------

## Save-friendly data for this inventory.
func to_dictionary() -> Dictionary:
	if _container == null:
		return {}

	return _container.to_dictionary()


func from_dictionary(
	data: Dictionary,
	registry: ItemRegistry
) -> void:
	if _container == null:
		push_error(
			"InventoryComponent at "
			+ str(get_path())
			+ " cannot load before its container is built."
		)
		return

	_container.from_dictionary(data, registry)
