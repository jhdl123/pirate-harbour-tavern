extends Node

@export var customer_scene: PackedScene
@export var entities: Node2D
@export var customer_spawn_point: Marker2D
@export var customer_table_point: Marker2D


func _ready() -> void:
	spawn_customer()


func spawn_customer() -> void:
	if customer_scene == null:
		push_error("GameManager has no customer scene assigned.")
		return

	var customer: Node = customer_scene.instantiate()
	entities.add_child(customer)

	customer.global_position = customer_spawn_point.global_position
	customer.set_target(customer_table_point.global_position)
