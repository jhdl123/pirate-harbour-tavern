extends CharacterBody2D

@export var movement_speed: float = 250.0


func _physics_process(_delta: float) -> void:
	var input_direction := Input.get_vector(
		"player_move_left",
		"player_move_right",
		"player_move_up",
		"player_move_down"
	)

	velocity = input_direction * movement_speed
	move_and_slide()
