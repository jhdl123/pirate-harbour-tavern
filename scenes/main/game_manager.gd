extends Node

@export var customer_scene: PackedScene
@export var entities: Node2D
@export var customer_spawn_point: Marker2D
@export var customer_table_point: Marker2D
@export var customer_exit_point: Marker2D

signal money_changed(new_amount: int)

var money: int = 0

func _ready() -> void:
	spawn_customer()


func spawn_customer() -> void:
	if customer_scene == null:
		push_error("GameManager has no customer scene assigned.")
		return

	var customer: Node = customer_scene.instantiate()

	entities.add_child(customer)

	customer.global_position = customer_spawn_point.global_position
	customer.set_table_target(customer_table_point.global_position)
	customer.set_exit_target(customer_exit_point.global_position)

	customer.customer_paid.connect(_on_customer_paid)
	customer.customer_finished.connect(_on_customer_finished)


func _on_customer_paid(amount: int) -> void:
	add_money(amount)


func _on_customer_finished(_customer: Node) -> void:
	spawn_customer()

func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)
	print("Money: £", money)
