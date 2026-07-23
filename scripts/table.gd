class_name Table
extends StaticBody2D

var occupied: bool = false
var customer: CharacterBody2D = null


func is_available() -> bool:
	return !occupied


func assign_customer(new_customer: CharacterBody2D) -> void:
	customer = new_customer
	occupied = true


func clear_customer() -> void:
	customer = null
	occupied = false


func get_seat_position() -> Vector2:
	return $SeatPoint.global_position
