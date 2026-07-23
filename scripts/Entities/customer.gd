extends CharacterBody2D

signal customer_paid(amount: int)
signal customer_finished(customer: Node)

enum State {
	WALKING_TO_TABLE,
	WAITING_TO_ORDER,
	ORDERING,
	DRINKING,
	LEAVING
}

@export var movement_speed: float = 120.0
@export var payment_amount: int = 5

var current_state: State = State.WALKING_TO_TABLE
var target_position: Vector2
var exit_position: Vector2


func _ready() -> void:
	$OrderIcon.visible = false

	$OrderTimer.timeout.connect(_on_order_timer_timeout)
	$DrinkTimer.timeout.connect(_on_drink_timer_timeout)


func set_table_target(new_target: Vector2) -> void:
	target_position = new_target
	current_state = State.WALKING_TO_TABLE


func set_exit_target(new_exit_position: Vector2) -> void:
	exit_position = new_exit_position


func _physics_process(_delta: float) -> void:
	match current_state:
		State.WALKING_TO_TABLE:
			move_towards_target(target_position)

		State.LEAVING:
			move_towards_target(exit_position)

		State.WAITING_TO_ORDER, State.ORDERING, State.DRINKING:
			velocity = Vector2.ZERO


func move_towards_target(destination: Vector2) -> void:
	var distance_to_target: float = global_position.distance_to(destination)

	if distance_to_target < 5.0:
		global_position = destination
		velocity = Vector2.ZERO

		if current_state == State.WALKING_TO_TABLE:
			arrive_at_table()
		elif current_state == State.LEAVING:
			finish_customer()

		return

	var direction: Vector2 = global_position.direction_to(destination)
	velocity = direction * movement_speed
	move_and_slide()


func arrive_at_table() -> void:
	current_state = State.WAITING_TO_ORDER
	$OrderTimer.start()
	print("Customer arrived; order timer started")


func _on_order_timer_timeout() -> void:
	current_state = State.ORDERING
	$OrderIcon.visible = true
	print("Customer ordered grog")


func interact(player: Node) -> void:
	if current_state != State.ORDERING:
		print("Customer is not ready to be served")
		return

	if player.carrying_item != ItemType.Type.GROG:
		print("Customer wants grog")
		return

	player.set_carried_item(ItemType.Type.NONE)
	$OrderIcon.visible = false

	current_state = State.DRINKING
	$DrinkTimer.start()

	print("Customer served!")


func _on_drink_timer_timeout() -> void:
	print("Customer finished drinking")
	print("Customer paid")

	customer_paid.emit(payment_amount)
	current_state = State.LEAVING


func finish_customer() -> void:
	customer_finished.emit(self)
	queue_free()
