extends Node2D

@export var customer_scene: PackedScene


func _ready() -> void:
	spawn_customer()


func spawn_customer() -> void:
	var customer: CharacterBody2D = customer_scene.instantiate()

	$Entities.add_child(customer)

	customer.global_position = $Markers/CustomerSpawnPoint.global_position
	customer.set_target($Markers/CustomerTablePoint.global_position)
