class_name FloorTransition
extends Node2D

@export var destination_floor: StringName = &"upstairs"
@export var display_name: String = "Stairs"
@export var action_verb: String = "Go upstairs"

func get_interaction_display_name() -> String:
	return display_name

func can_interact(_request: InteractionRequest) -> bool:
	return get_tree().get_first_node_in_group(&"floor_controller") != null

func get_interaction_actions(_request: InteractionRequest) -> Array[InteractionAction]:
	return [InteractionAction.create(&"change_floor", action_verb)]

func perform_interaction(request: InteractionRequest) -> bool:
	if request.action_id != &"change_floor":
		return false
	var controller := get_tree().get_first_node_in_group(&"floor_controller")
	if controller == null or not controller.has_method(&"request_floor_change"):
		return false
	controller.call_deferred(&"request_floor_change", destination_floor)
	return true
