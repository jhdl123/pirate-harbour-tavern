class_name FloorController
extends Node

## Keeps both tavern floors loaded and moves only the player between them.
## This preserves the downstairs simulation while the player is upstairs.

@export var player_path: NodePath
@export var downstairs_arrival_path: NodePath
@export var upstairs_arrival_path: NodePath
@export var starting_floor: StringName = &"downstairs"

var current_floor: StringName = &"downstairs"
var _transition_locked := false

func _ready() -> void:
	add_to_group(&"floor_controller")
	current_floor = starting_floor

func request_floor_change(destination_floor: StringName) -> bool:
	if _transition_locked:
		return false

	var player := get_node_or_null(player_path) as Node2D
	var destination := _get_arrival_marker(destination_floor)
	if player == null or destination == null:
		push_warning("Floor transition failed: player or arrival marker is missing.")
		return false

	_transition_locked = true
	current_floor = destination_floor
	player.global_position = destination.global_position

	# Clear any movement left over from the previous floor where supported.
	if player is CharacterBody2D:
		(player as CharacterBody2D).velocity = Vector2.ZERO
	if player.has_method(&"cancel_current_action"):
		player.call(&"cancel_current_action")

	# Prevent the destination stairs immediately accepting the same input press.
	await get_tree().create_timer(0.25).timeout
	_transition_locked = false
	return true

func _get_arrival_marker(destination_floor: StringName) -> Marker2D:
	match destination_floor:
		&"upstairs":
			return get_node_or_null(upstairs_arrival_path) as Marker2D
		&"downstairs":
			return get_node_or_null(downstairs_arrival_path) as Marker2D
		_:
			push_warning("Unknown floor id: %s" % destination_floor)
			return null
