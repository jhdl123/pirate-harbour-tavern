class_name BarCounter
extends StaticBody2D

## Functional bar counter with visible service slots.
##
## The ItemContainer owns the logical items.
## Marker2D nodes define where items appear.
## ItemSprite children display the held item.
## Highlight children show which slot will be used.
## InteractionLabel explains the current action.


@export_category("Service Slots")

@export_range(1, 10, 1)
var service_slot_count: int = 3


@export_category("Interaction")

## Maximum distance between the player and a slot marker.
@export_range(8.0, 128.0, 1.0)
var slot_interaction_distance: float = 48.0

## Prints transfer results in the Output panel.
@export var show_transfer_messages: bool = true


@onready var service_slots_node: Node2D = $ServiceSlots
@onready var interaction_label: Label = $InteractionLabel


var service_container: ItemContainer

var nearby_player: Node2D = null
var highlighted_slot_index: int = -1


func _ready() -> void:
	_build_service_container()
	_connect_slot_signals()
	_refresh_all_slot_visuals()
	_validate_slot_views()

	interaction_label.visible = false

	_find_player()


func _process(_delta: float) -> void:
	if nearby_player == null or not is_instance_valid(nearby_player):
		_find_player()

	if nearby_player == null:
		_clear_slot_highlight()
		return

	var nearest_slot_index: int = _find_nearest_slot_index(
		nearby_player.global_position
	)

	if nearest_slot_index < 0:
		_clear_slot_highlight()
		return

	_set_highlighted_slot(nearest_slot_index)
	_update_interaction_label(nearest_slot_index)


func _find_player() -> void:
	nearby_player = get_tree().get_first_node_in_group(
		"player"
	) as Node2D


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

	if highlighted_slot_index == slot_index:
		_update_interaction_label(slot_index)


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
# Player interaction
# -----------------------------------------------------------------------------

func interact(player: Node) -> void:
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

	var slot_index: int = _find_nearest_slot_index(
		player.global_position
	)

	if slot_index < 0:
		if show_transfer_messages:
			print(
				name,
				": player is not close enough to a service slot."
			)

		return

	var service_slot: ItemSlot = get_service_slot(
		slot_index
	)

	if service_slot == null:
		return

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

	_update_interaction_label(slot_index)


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
	interaction_label.visible = false


# -----------------------------------------------------------------------------
# Interaction label
# -----------------------------------------------------------------------------

func _update_interaction_label(slot_index: int) -> void:
	if nearby_player == null:
		interaction_label.visible = false
		return

	if not nearby_player.has_method("get_item_carrier"):
		interaction_label.visible = false
		return

	var carrier: ItemCarrier = (
		nearby_player.get_item_carrier()
	)

	var slot: ItemSlot = get_service_slot(slot_index)

	if carrier == null or slot == null:
		interaction_label.visible = false
		return

	var carried_definition: ItemDefinition = (
		carrier.get_carried_definition()
	)

	var slot_definition: ItemDefinition = (
		slot.get_definition()
	)

	if carried_definition != null and slot_definition == null:
		interaction_label.text = (
			"[E] Place %s"
			% carried_definition.display_name
		)

	elif carried_definition == null and slot_definition != null:
		interaction_label.text = (
			"[E] Pick up %s"
			% slot_definition.display_name
		)

	elif carried_definition != null and slot_definition != null:
		interaction_label.text = (
			"[E] Swap %s for %s"
			% [
				carried_definition.display_name,
				slot_definition.display_name
			]
		)

	else:
		interaction_label.text = "[E] Empty slot"

	interaction_label.visible = true


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
