extends Node2D

## A station that prepares and hands out one kind of drink.
##
## The station owns a real one-slot output [ItemContainer]. Everything the
## player does with it goes through [ItemTransferService], so picking up,
## returning and swapping a drink follow exactly the same rules that bar slots,
## storage and a future inventory UI will use.
##
## Current limitation
## ------------------
## There is no drink stock yet, so the output slot is an infinite supply: it
## refills itself after a drink is taken, and a drink handed back is discarded.
## [method _refill_output] and [method _on_drink_returned] are the two places to
## change once kegs and stock exist.


@export_category("Drink")

## The prepared drink this station supplies.
##
## A [DrinkDefinition] IS an [ItemDefinition], so this resource doubles as the
## item handed to the player. There is no second drink-item resource.
@export var served_drink: DrinkDefinition


@export_category("Debug")

## Prints why an interaction was refused. Off by default to keep logs quiet.
@export var show_transfer_messages: bool = false


var output_container: ItemContainer


func _ready() -> void:
	_build_output_container()

	if served_drink == null:
		push_warning(
			name
			+ " has no DrinkDefinition assigned."
		)
		return

	if not served_drink.validate_or_warn():
		return

	if not served_drink.has_tag(ItemTags.PREPARED_DRINK):
		push_warning(
			name
			+ " serves '"
			+ String(served_drink.item_id)
			+ "', which is not tagged '"
			+ String(ItemTags.PREPARED_DRINK)
			+ "'. Bar slots and trays will refuse it."
		)

	_refill_output()


func _build_output_container() -> void:
	var rules: ItemSlotRules = ItemSlotRules.new()

	rules.capacity = 1
	rules.accepted_tags = [ItemTags.PREPARED_DRINK]
	rules.allow_insert = true
	rules.allow_remove = true
	rules.allow_merge = false
	rules.allow_swap = true
	rules.allow_partial = false

	output_container = ItemContainer.new(
		StringName("%s_output" % name.to_snake_case()),
		1,
		rules
	)

	output_container.container_tags = [&"station", &"service"]


## The slot the player takes a drink from.
##
## A future bar-slot or staff system can transfer against this directly.
func get_output_slot() -> ItemSlot:
	if output_container == null:
		return null

	return output_container.get_slot(0)


func interact(player: Node) -> void:
	if served_drink == null:
		push_warning(
			name
			+ " cannot serve a drink because no "
			+ "DrinkDefinition is assigned."
		)
		return

	if not player.has_method("get_item_carrier"):
		push_warning(
			name
			+ " was interacted with by an object "
			+ "that cannot carry items."
		)
		return

	var carrier: ItemCarrier = player.get_item_carrier()

	if carrier == null:
		push_warning(
			name
			+ " could not access the player's ItemCarrier."
		)
		return

	# Holding this station's own drink means the player is putting it back.
	if carrier.is_carrying_item(served_drink.item_id):
		var returned_stack: ItemStack = carrier.clear_carried_item()
		_on_drink_returned(returned_stack)
		return

	var output_slot: ItemSlot = get_output_slot()

	if output_slot == null:
		push_error(
			name
			+ " has no output slot."
		)
		return

	if output_slot.is_empty():
		_refill_output()

	# One transfer handles all three cases:
	# empty hands  -> move
	# other drink  -> swap
	# anything else-> rejected, with both sides left untouched
	var result: ItemTransferResult = carrier.take_from(output_slot)

	if not result.is_success():
		if show_transfer_messages:
			print(
				name,
				" refused the interaction: ",
				result.get_message()
			)

		return

	if result.status == ItemTransferResult.Status.SWAPPED:
		# The player's previous drink is now sitting in the output slot.
		_on_drink_returned(output_slot.clear())

	_refill_output()


## Places a fresh drink in the output slot.
##
## Replace this with a draw from real drink stock once kegs exist.
func _refill_output() -> void:
	var output_slot: ItemSlot = get_output_slot()

	if output_slot == null or served_drink == null:
		return

	if output_slot.has_item():
		return

	var result: ItemTransferResult = ItemTransferService.give_to_slot(
		output_slot,
		ItemStack.create(served_drink, 1)
	)

	if not result.is_success():
		push_error(
			name
			+ " could not refill its output slot: "
			+ result.get_message()
		)


## Handles a prepared drink given back to the station.
##
## With no stock system the drink is poured away. This is the extension point
## for returning liquid to a keg or producing a dirty tankard.
func _on_drink_returned(returned_stack: ItemStack) -> void:
	if returned_stack == null or returned_stack.is_empty():
		return

	if show_transfer_messages:
		print(
			name,
			" took back ",
			returned_stack.quantity,
			" x ",
			returned_stack.get_display_name(),
			"."
		)
