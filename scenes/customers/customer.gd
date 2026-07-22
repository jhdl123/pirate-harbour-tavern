extends CharacterBody2D

enum State {
	IDLE,
	WALKING_TO_TABLE,
	ORDERING
}

@export var movement_speed: float = 120.0

var current_state: State = State.IDLE
var target_position: Vector2


func _ready() -> void:
	$OrderIcon.visible = false
	$OrderTimer.timeout.connect(_on_order_timer_timeout)


func set_target(new_target: Vector2) -> void:
	target_position = new_target
	current_state = State.WALKING_TO_TABLE


func _physics_process(_delta: float) -> void:
	match current_state:
		State.WALKING_TO_TABLE:
			move_towards_target()

		State.IDLE, State.ORDERING:
			velocity = Vector2.ZERO


func move_towards_target() -> void:
	var distance_to_target: float = global_position.distance_to(target_position)

	if distance_to_target < 5.0:
		arrive_at_table()
		return

	var direction: Vector2 = global_position.direction_to(target_position)
	velocity = direction * movement_speed
	move_and_slide()


func arrive_at_table() -> void:
	global_position = target_position
	velocity = Vector2.ZERO
	current_state = State.IDLE
	$OrderTimer.start()


func _on_order_timer_timeout() -> void:
	current_state = State.ORDERING
	$OrderIcon.visible = true
	print("Customer ordered grog")
