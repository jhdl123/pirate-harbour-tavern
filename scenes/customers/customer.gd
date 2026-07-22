extends CharacterBody2D

@export var movement_speed: float = 120.0

var target_position: Vector2
var has_target: bool = false


func set_target(new_target: Vector2) -> void:
	target_position = new_target
	has_target = true


func _physics_process(_delta: float) -> void:
	if not has_target:
		velocity = Vector2.ZERO
		return

	var direction: Vector2 = global_position.direction_to(target_position)
	velocity = direction * movement_speed

	if global_position.distance_to(target_position) < 5.0:
		global_position = target_position
		velocity = Vector2.ZERO
		has_target = false

	move_and_slide()
