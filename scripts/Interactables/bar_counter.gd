class_name BarCounter
extends StaticBody2D

## Functional bar counter with visible service slots.
##
## Ownership is unchanged from before the interaction framework existed:
## the [ItemContainer] owns the logical items, [Marker2D] nodes define where
## they appear, ItemSprite children display them, and every item movement goes
## through [ItemTransferService].
##
## What changed is that the counter no longer hunts for the player, decides on
## its own whether it is selected, or carries a label. It implements the
## interaction protocol described in [Interactable] and the framework does the
## rest:
##
## [codeblock]
## get_interaction_point()       nearest service slot, so distance scoring and
##                               the shared prompt both use the slot, not the
##                               middle of the counter
## can_interact()                a slot must be within reach
## get_interaction_actions()     place / pick up / swap, described against the
##                               slot the player is standing at
## perform_interaction()         the transfer, using the slot the prompt named
## set_interaction_highlighted() moves the slot highlight as the player walks
## [/codeblock]
##
## The counter is the reason [Interactable] lets an object override its own
## highlight and interaction point: it is one interactable made of several
## interaction points. Storage shelves, kegs and multi-seat tables will want the
## same shape, so it is worth understanding this one before writing those.


@export_category("Service Slots")

@export_range(1, 10, 1)
var service_slot_count: int = 3


@export_category("Interaction")

## Maximum distance between the player and a slot marker.
##
## Beyond this the counter reports that it has nothing to offer, so the
## framework selects something else instead of prompting for an unreachable
## slot.
@export_range(8.0, 128.0, 1.0)
var slot_interaction_distance: float = 48.0

## Name shown in prompts.
@export var interaction_display_name: String = "Bar Counter"

## Prints transfer results in the Output panel.
@export var show_transfer_messages: bool = true


@onready var service_slots_node: Node2D = $ServiceSlots
@onready var interactable: Interactable = $InteractionArea


var service_container: ItemContainer

var highlighted_slot_index: int = -1


func _ready() -> void:
	_build_service_container()
	_connect_slot_signals()
	_refresh_all_slot_visuals()
	_validate_slot_views()

	_clear_slot_highlight()


# -----------------------------------------------------------------------------
# Container setup
# -----------------------------------------------------------------------------

func _build_service_container() -> void:
	var slot_rules := ItemSlotRules.new()

	slot_rules.capacity = 1
	slot_rules.accepted_tags = [
		ItemTags.PREPARED_DRINK
	]

	slot_rules.allow_insert = true
	slot_rules.allow_remove = true
	slot_rules.allow_merge = false
	slot_rules.allow_swap = true
	slot_rules.allow_partial = false

	slot_rules.validate_or_warn(
		"%s service slots" % get_path()
	)

	service_container = ItemContainer.new(
		&"bar_service",
		service_slot_count,
		slot_rules
	)


func _connect_slot_signals() -> void:
	if service_container == null:
		return

	if not service_container.slot_changed.is_connected(
		_on_service_slot_changed
	):
		service_container.slot_changed.connect(
			_on_service_slot_changed
		)


func get_service_container() -> ItemContainer:
	return service_container


func get_service_slot(slot_index: int) -> ItemSlot:
	if service_container == null:
		return null

	if slot_index < 0:
		return null

	if slot_index >= service_container.get_slot_count():
		return null

	return service_container.get_slot(slot_index)


func get_service_slot_marker(
	slot_index: int
) -> Marker2D:
	if slot_index < 0:
		return null

	if slot_index >= service_slots_node.get_child_count():
		return null

	return service_slots_node.get_child(
		slot_index
	) as Marker2D


# -----------------------------------------------------------------------------
# Item visuals
# -----------------------------------------------------------------------------

func _on_service_slot_changed(
	slot_index: int,
	_previous_stack: ItemStack,
	_current_stack: ItemStack
) -> void:
	_refresh_slot_visual(slot_index)

	# The prompt for this counter has almost certainly changed - "Place Grog"
	# becomes "Pick up Grog" - so ask the framework to re-read it now rather
	# than on its next polling tick.
	if interactable != null:
		interactable.notify_state_changed()


func _refresh_all_slot_visuals() -> void:
	for slot_index: int in range(service_slot_count):
		_refresh_slot_visual(slot_index)


func _refresh_slot_visual(slot_index: int) -> void:
	var slot: ItemSlot = get_service_slot(slot_index)
	var marker: Marker2D = get_service_slot_marker(slot_index)

	if slot == null or marker == null:
		return

	var item_sprite: Sprite2D = marker.get_node_or_null(
		"ItemSprite"
	) as Sprite2D

	if item_sprite == null:
		push_warning(
			"Bar service marker '%s' has no ItemSprite child."
			% marker.name
		)
		return

	var definition: ItemDefinition = slot.get_definition()

	if definition == null:
		item_sprite.texture = null
		item_sprite.visible = false
		return

	if definition.world_texture == null:
		push_warning(
			"Item '%s' has no world_texture for bar display."
			% definition.item_id
		)

		item_sprite.texture = null
		item_sprite.visible = false
		return

	item_sprite.texture = definition.world_texture
	item_sprite.visible = true


# -----------------------------------------------------------------------------
# Interaction protocol
# -----------------------------------------------------------------------------

func get_interaction_display_name() -> String:
	return interaction_display_name


## The counter interacts at whichever service slot is nearest the actor.
##
## Returning the slot rather than the counter's origin is what makes distance
## scoring, the highlight and the prompt all agree on the same point.
func get_interaction_point(
	from_position: Vector2
) -> Vector2:
	var slot_index: int = _find_nearest_slot_index(from_position)

	if slot_index < 0:
		return global_position

	var marker: Marker2D = get_service_slot_marker(slot_index)

	if marker == null:
		return global_position

	return marker.global_position


func can_interact(
	request: InteractionRequest
) -> bool:
	if request.get_actor_carrier() == null:
		return false

	return _find_nearest_slot_index(request.actor_position) >= 0


func get_interaction_actions(
	request: InteractionRequest
) -> Array[InteractionAction]:
	var actions: Array[InteractionAction] = []

	var carrier: ItemCarrier = request.get_actor_carrier()

	if carrier == null:
		return actions

	var slot_index: int = _find_nearest_slot_index(
		request.actor_position
	)

	var service_slot: ItemSlot = get_service_slot(slot_index)

	if service_slot == null:
		return actions

	var action: InteractionAction = _build_slot_action(
		carrier,
		service_slot,
		slot_index
	)

	if action != null:
		actions.append(action)

	return actions


## Describes the one thing that would happen at [param service_slot].
##
## Availability is answered by [ItemTransferService] rather than by re-deriving
## the rules here, so the prompt can never disagree with what the transfer will
## actually do.
func _build_slot_action(
	carrier: ItemCarrier,
	service_slot: ItemSlot,
	slot_index: int
) -> InteractionAction:
	var action_data: Dictionary = {
		&"slot_index": slot_index
	}

	var carried_definition: ItemDefinition = (
		carrier.get_carried_definition()
	)

	var slot_definition: ItemDefinition = (
		service_slot.get_definition()
	)

	if carried_definition == null and slot_definition == null:
		return InteractionAction.create(
			&"none",
			"Empty slot",
			"",
			action_data
		).as_unavailable("")

	if carried_definition != null and slot_definition == null:
		return _apply_availability(
			InteractionAction.create(
				&"place",
				"Place",
				carried_definition.display_name,
				action_data
			),
			ItemTransferService.can_transfer(
				carrier.get_slot(),
				service_slot
			)
		)

	if carried_definition == null and slot_definition != null:
		return _apply_availability(
			InteractionAction.create(
				&"take",
				"Pick up",
				slot_definition.display_name,
				action_data
			),
			ItemTransferService.can_transfer(
				service_slot,
				carrier.get_slot()
			)
		)

	return _apply_availability(
		InteractionAction.create(
			&"swap",
			"Swap",
			"%s for %s" % [
				carried_definition.display_name,
				slot_definition.display_name
			],
			action_data
		),
		ItemTransferService.can_transfer(
			carrier.get_slot(),
			service_slot
		)
	)


func _apply_availability(
	action: InteractionAction,
	predicted_result: ItemTransferResult
) -> InteractionAction:
	if predicted_result.is_success():
		return action

	return action.as_unavailable(
		predicted_result.get_message().trim_suffix(".")
	)


func perform_interaction(
	request: InteractionRequest
) -> bool:
	var carrier: ItemCarrier = request.get_actor_carrier()

	if carrier == null:
		push_warning(
			name
			+ " was interacted with by an object "
			+ "that cannot carry items."
		)
		return false

	# The prompt named a slot, so honour it. Falling back to the nearest slot
	# keeps the object usable by staff AI or scripted calls that pass no data.
	var slot_index: int = int(
		request.get_data(&"slot_index", -1)
	)

	if slot_index < 0:
		slot_index = _find_nearest_slot_index(
			request.actor_position
		)

	if slot_index < 0:
		if show_transfer_messages:
			print(
				name,
				": player is not close enough to a service slot."
			)

		return false

	var service_slot: ItemSlot = get_service_slot(slot_index)

	if service_slot == null:
		return false

	var result: ItemTransferResult

	if carrier.is_carrying():
		result = carrier.place_into(service_slot)
	else:
		result = carrier.take_from(service_slot)

	if show_transfer_messages:
		print(
			name,
			" slot ",
			slot_index,
			": ",
			result.get_message()
		)

	return result.is_success()


## Moves the slot highlight to whichever slot the actor is standing at.
##
## Called every selection tick while the counter is selected, which is what
## lets the highlight follow the player along the counter.
func set_interaction_highlighted(
	enabled: bool,
	request: InteractionRequest
) -> void:
	if not enabled:
		_clear_slot_highlight()
		return

	var slot_index: int = _find_nearest_slot_index(
		request.actor_position
	)

	if slot_index < 0:
		_clear_slot_highlight()
		return

	_set_highlighted_slot(slot_index)


func _find_nearest_slot_index(
	world_position: Vector2
) -> int:
	var nearest_index: int = -1
	var nearest_distance: float = INF

	for slot_index: int in range(service_slot_count):
		var marker: Marker2D = get_service_slot_marker(
			slot_index
		)

		if marker == null:
			continue

		var distance: float = world_position.distance_to(
			marker.global_position
		)

		if distance > slot_interaction_distance:
			continue

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = slot_index

	return nearest_index


# -----------------------------------------------------------------------------
# Highlight
# -----------------------------------------------------------------------------

func _set_highlighted_slot(slot_index: int) -> void:
	if highlighted_slot_index == slot_index:
		return

	_clear_slot_highlight()

	var marker: Marker2D = get_service_slot_marker(
		slot_index
	)

	if marker == null:
		return

	var highlight: CanvasItem = marker.get_node_or_null(
		"Highlight"
	) as CanvasItem

	if highlight != null:
		highlight.visible = true

	highlighted_slot_index = slot_index


func _clear_slot_highlight() -> void:
	if highlighted_slot_index >= 0:
		var previous_marker: Marker2D = (
			get_service_slot_marker(
				highlighted_slot_index
			)
		)

		if previous_marker != null:
			var previous_highlight: CanvasItem = (
				previous_marker.get_node_or_null(
					"Highlight"
				) as CanvasItem
			)

			if previous_highlight != null:
				previous_highlight.visible = false

	highlighted_slot_index = -1

	_hide_all_slot_highlights()


## Belt and braces for the first frame, when nothing has been highlighted yet
## but the scene may have been saved with a highlight left visible.
func _hide_all_slot_highlights() -> void:
	for slot_index: int in range(service_slots_node.get_child_count()):
		var marker: Marker2D = get_service_slot_marker(slot_index)

		if marker == null:
			continue

		var highlight: CanvasItem = marker.get_node_or_null(
			"Highlight"
		) as CanvasItem

		if highlight != null:
			highlight.visible = false


# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

func _validate_slot_views() -> void:
	var marker_count: int = (
		service_slots_node.get_child_count()
	)

	if marker_count != service_slot_count:
		push_warning(
			"BarCounter has %d logical slots but %d slot markers."
			% [
				service_slot_count,
				marker_count
			]
		)

	for child: Node in service_slots_node.get_children():
		if not child is Marker2D:
			push_warning(
				"'%s' under ServiceSlots is not a Marker2D."
				% child.name
			)
			continue

		if child.get_node_or_null("ItemSprite") == null:
			push_warning(
				"Service slot '%s' has no ItemSprite child."
				% child.name
			)

		if child.get_node_or_null("Highlight") == null:
			push_warning(
				"Service slot '%s' has no Highlight child."
				% child.name
			)
