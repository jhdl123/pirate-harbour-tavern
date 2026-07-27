class_name DrinksStation
extends StaticBody2D

## A station that prepares and hands out one kind of drink.
##
## The station owns a real one-slot output [ItemContainer]. Everything the
## player does with it goes through [ItemTransferService], so picking up,
## returning and swapping a drink follow exactly the same rules that bar slots,
## storage and a future inventory UI will use.
##
## This is the second object migrated to the interaction framework, and it is
## deliberately the simplest possible migration: one interaction point, one
## action, no custom highlight. Compare it with [BarCounter], which needs all
## three, to see how much of the protocol an object is allowed to ignore.
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


@export_category("Interaction")

## Verb used when the player takes a drink from the station.
##
## Data rather than a hard-coded string, so a coffee urn, a soup pot or a
## smuggler's crate can reuse this script with the right word.
@export var serve_verb: String = "Pour"

## Verb used when the player hands this station's own drink back.
@export var return_verb: String = "Put back"


@export_category("Debug")

## Prints why an interaction was refused. Off by default to keep logs quiet.
@export var show_transfer_messages: bool = false


@onready var interactable: Interactable = $InteractionArea


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


# -----------------------------------------------------------------------------
# Interaction protocol
# -----------------------------------------------------------------------------

func get_interaction_display_name() -> String:
	if served_drink == null:
		return String(name).capitalize()

	return "%s Station" % served_drink.display_name


func can_interact(
	request: InteractionRequest
) -> bool:
	if served_drink == null:
		return false

	return request.get_actor_carrier() != null


func get_interaction_actions(
	request: InteractionRequest
) -> Array[InteractionAction]:
	var actions: Array[InteractionAction] = []

	var carrier: ItemCarrier = request.get_actor_carrier()

	if carrier == null or served_drink == null:
		return actions

	# Holding this station's own drink means the player is putting it back.
	if carrier.is_carrying_item(served_drink.item_id):
		actions.append(
			InteractionAction.create(
				&"return",
				return_verb,
				served_drink.display_name
			)
		)

		return actions

	var verb: String = serve_verb

	if carrier.is_carrying():
		verb = "Swap for"

	var action: InteractionAction = InteractionAction.create(
		&"serve",
		verb,
		served_drink.display_name
	)

	# The station always has stock today, so the only thing that can refuse a
	# take is the actor's own hands. Ask the transfer service rather than
	# guessing, so the prompt stays honest once hands gain their own rules.
	var predicted: ItemTransferResult = (
		ItemTransferService.can_transfer(
			get_output_slot(),
			carrier.get_slot()
		)
	)

	if not predicted.is_success():
		action.as_unavailable(
			predicted.get_message().trim_suffix(".")
		)

	actions.append(action)

	return actions


func perform_interaction(
	request: InteractionRequest
) -> bool:
	if served_drink == null:
		push_warning(
			name
			+ " cannot serve a drink because no "
			+ "DrinkDefinition is assigned."
		)
		return false

	var carrier: ItemCarrier = request.get_actor_carrier()

	if carrier == null:
		push_warning(
			name
			+ " could not access the actor's ItemCarrier."
		)
		return false

	if request.action_id == &"return":
		return _return_carried_drink(carrier)

	return _serve_drink(carrier)


func _return_carried_drink(
	carrier: ItemCarrier
) -> bool:
	if not carrier.is_carrying_item(served_drink.item_id):
		return false

	var returned_stack: ItemStack = carrier.clear_carried_item()

	_on_drink_returned(returned_stack)
	_notify_state_changed()

	return true


func _serve_drink(
	carrier: ItemCarrier
) -> bool:
	var output_slot: ItemSlot = get_output_slot()

	if output_slot == null:
		push_error(
			name
			+ " has no output slot."
		)
		return false

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

		return false

	if result.status == ItemTransferResult.Status.SWAPPED:
		# The player's previous drink is now sitting in the output slot.
		_on_drink_returned(output_slot.clear())

	_refill_output()
	_notify_state_changed()

	return true


## Kept so any existing or external caller still works.
##
## New code goes through the interaction framework, which calls
## [method perform_interaction] with a full [InteractionRequest].
func interact(
	player: Node
) -> void:
	perform_interaction(
		InteractionRequest.create(player, interactable)
	)


func _notify_state_changed() -> void:
	if interactable != null:
		interactable.notify_state_changed()


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
