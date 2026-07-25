class_name CustomerDoor
extends Node2D


@onready var outside_point: Marker2D = $OutsidePoint
@onready var inside_point: Marker2D = $InsidePoint


func get_spawn_position() -> Vector2:
	return outside_point.global_position


func get_inside_position() -> Vector2:
	return inside_point.global_position


func get_exit_position() -> Vector2:
	return outside_point.global_position
