class_name DrinksStation
extends StaticBody2D

signal stock_changed(current: int, maximum: int)

@export_category("Drink")
@export var served_drink: DrinkDefinition
@export var refill_item: ItemDefinition
@export_range(1, 999, 1) var maximum_servings: int = 20
@export_range(0, 999, 1) var starting_servings: int = 20
@export_range(1, 999, 1) var servings_per_refill_item: int = 20

@export_category("Interaction")
@export var serve_verb: String = "Pour"
@export var return_verb: String = "Put back"
@export var refill_verb: String = "Refill"

@export_category("Visuals")
@export var normal_texture: Texture2D
@export var empty_texture: Texture2D
@export_range(2, 20, 1) var indicator_segments: int = 10

@export_category("Debug")
@export var show_transfer_messages: bool = false

@onready var interactable: Interactable = $InteractionArea
@onready var sprite: Sprite2D = $Sprite2D

var output_container: ItemContainer
var current_servings: int = 0
var _indicator: VBoxContainer

func _ready() -> void:
	add_to_group(&"drink_stations")
	_build_output_container()
	current_servings = clampi(starting_servings, 0, maximum_servings)
	_build_indicator()
	if normal_texture == null and sprite != null:
		normal_texture = sprite.texture
	_refresh_output()
	_refresh_visuals()

func _build_output_container() -> void:
	var rules := ItemSlotRules.new()
	rules.capacity = 1
	rules.accepted_tags = [ItemTags.PREPARED_DRINK]
	rules.allow_insert = true
	rules.allow_remove = true
	rules.allow_merge = false
	rules.allow_swap = true
	rules.allow_partial = false
	output_container = ItemContainer.new(StringName("%s_output" % name.to_snake_case()), 1, rules)
	output_container.container_tags = [&"station", &"service"]

func get_output_slot() -> ItemSlot:
	return output_container.get_slot(0) if output_container != null else null

func get_interaction_display_name() -> String:
	return "%s Station" % served_drink.display_name if served_drink != null else String(name).capitalize()

func can_interact(request: InteractionRequest) -> bool:
	return served_drink != null and request.get_actor_carrier() != null

func get_interaction_actions(request: InteractionRequest) -> Array[InteractionAction]:
	var actions: Array[InteractionAction] = []
	var carrier := request.get_actor_carrier()
	if carrier == null or served_drink == null:
		return actions
	if refill_item != null and carrier.is_carrying_item(refill_item.item_id):
		var refill_action := InteractionAction.create(&"refill", refill_verb, get_interaction_display_name())
		if current_servings >= maximum_servings:
			refill_action.as_unavailable("Already full")
		actions.append(refill_action)
		return actions
	if carrier.is_carrying_item(served_drink.item_id):
		actions.append(InteractionAction.create(&"return", return_verb, served_drink.display_name))
		return actions
	var verb := serve_verb if not carrier.is_carrying() else "Swap for"
	var action := InteractionAction.create(&"serve", verb, "%s (%d/%d)" % [served_drink.display_name, current_servings, maximum_servings])
	if current_servings <= 0:
		action.as_unavailable("Empty - needs %s" % (refill_item.display_name if refill_item != null else "stock"))
	else:
		var predicted := ItemTransferService.can_transfer(get_output_slot(), carrier.get_slot())
		if not predicted.is_success():
			action.as_unavailable(predicted.get_message().trim_suffix("."))
	actions.append(action)
	return actions

func perform_interaction(request: InteractionRequest) -> bool:
	var carrier := request.get_actor_carrier()
	if carrier == null:
		return false
	match request.action_id:
		&"refill": return _refill_from_carrier(carrier)
		&"return": return _return_carried_drink(carrier)
		_: return _serve_drink(carrier)

func _serve_drink(carrier: ItemCarrier) -> bool:
	if current_servings <= 0:
		return false
	_refresh_output()
	var output_slot := get_output_slot()
	var result := carrier.take_from(output_slot)
	if not result.is_success():
		return false
	if result.status == ItemTransferResult.Status.SWAPPED:
		_on_drink_returned(output_slot.clear())
	current_servings = maxi(current_servings - 1, 0)
	_refresh_output()
	_refresh_visuals()
	return true

func _return_carried_drink(carrier: ItemCarrier) -> bool:
	if not carrier.is_carrying_item(served_drink.item_id):
		return false
	_on_drink_returned(carrier.clear_carried_item())
	_refresh_visuals()
	return true

func _refill_from_carrier(carrier: ItemCarrier) -> bool:
	if refill_item == null or not carrier.is_carrying_item(refill_item.item_id):
		return false
	if current_servings >= maximum_servings:
		return false
	carrier.clear_carried_item()
	current_servings = mini(current_servings + servings_per_refill_item, maximum_servings)
	_refresh_output()
	_refresh_visuals()
	return true

func _refresh_output() -> void:
	var slot := get_output_slot()
	if slot == null:
		return
	if current_servings <= 0:
		slot.clear()
		return
	if slot.is_empty() and served_drink != null:
		ItemTransferService.give_to_slot(slot, ItemStack.create(served_drink, 1))

func _build_indicator() -> void:
	_indicator = VBoxContainer.new()
	_indicator.position = Vector2(23, -34)
	_indicator.add_theme_constant_override("separation", 1)
	_indicator.visible = false
	add_child(_indicator)
	for _i in range(indicator_segments):
		var segment := ColorRect.new()
		segment.custom_minimum_size = Vector2(7, 4)
		_indicator.add_child(segment)


func set_interaction_highlighted(enabled: bool, _request: InteractionRequest) -> void:
	if _indicator != null:
		_indicator.visible = enabled or current_servings <= 0
	var highlight := get_node_or_null("InteractionHighlight")
	if highlight != null and highlight.has_method(&"set_highlighted"):
		highlight.call(&"set_highlighted", enabled)

func _refresh_visuals() -> void:
	if sprite != null:
		if current_servings <= 0 and empty_texture != null:
			sprite.texture = empty_texture
		elif normal_texture != null:
			sprite.texture = normal_texture
	if _indicator != null:
		var filled := ceili(float(current_servings) / float(maximum_servings) * indicator_segments)
		var children := _indicator.get_children()
		for i in range(children.size()):
			children[i].color = Color(0.25, 0.8, 0.35, 1) if i >= indicator_segments - filled else Color(0.16, 0.12, 0.09, 0.8)
		_indicator.visible = _indicator.visible or current_servings <= 0
	stock_changed.emit(current_servings, maximum_servings)
	if interactable != null:
		interactable.notify_state_changed()

func set_servings(amount: int) -> void:
	current_servings = clampi(amount, 0, maximum_servings)
	_refresh_output()
	_refresh_visuals()

func fill_stock() -> void:
	set_servings(maximum_servings)

func empty_stock() -> void:
	set_servings(0)

func get_stock_summary() -> Dictionary:
	return {"name": get_interaction_display_name(), "current": current_servings, "maximum": maximum_servings, "refill_item": refill_item}

func interact(player: Node) -> void:
	perform_interaction(InteractionRequest.create(player, interactable))

func _on_drink_returned(returned_stack: ItemStack) -> void:
	if show_transfer_messages and returned_stack != null and not returned_stack.is_empty():
		print(name, " took back ", returned_stack.get_display_name())
