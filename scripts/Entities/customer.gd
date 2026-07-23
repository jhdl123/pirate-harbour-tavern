extends CharacterBody2D


signal customer_paid(amount: int)
signal customer_finished(customer: Node)
signal customer_abandoned_seat(customer: Node)


enum State {
	WALKING_TO_STAGING,
	MOVING_TO_SEAT,
	WAITING_TO_ORDER,
	ORDERING,
	DRINKING,
	LEAVING
}


@export_category("Movement")
@export var movement_speed: float = 120.0
@export var seat_movement_speed: float = 45.0
@export var navigation_arrival_distance: float = 6.0
@export var seat_arrival_distance: float = 2.0

@export_category("Stuck Detection")
@export var stuck_check_interval: float = 0.5
@export var minimum_stuck_movement: float = 1.0
@export var maximum_stuck_checks: int = 3
@export var maximum_path_refreshes: int = 2

@export_category("Customer")
@export var payment_amount: int = 5

@export_category("Walking Avoidance")
@export var walking_avoidance_radius: float = 12.0
@export var walking_avoidance_priority: float = 0.5
@export var occupied_avoidance_radius: float = 17.0
@export var occupied_zone_offset: float = 2.0

@onready var navigation_agent: NavigationAgent2D = (
	$NavigationAgent2D
)

@onready var order_icon: Sprite2D = $OrderIcon
@onready var order_timer: Timer = $OrderTimer
@onready var drink_timer: Timer = $DrinkTimer
@onready var patience_timer: Timer = $PatienceTimer

var current_state: State = State.WALKING_TO_STAGING
var reserved_chair: Chair

var exit_position: Vector2
var active_target_position: Vector2
var requested_target_position: Vector2

var has_navigation_target: bool = false
var navigation_request_id: int = 0

var stuck_elapsed: float = 0.0
var stuck_check_position: Vector2
var consecutive_stuck_checks: int = 0
var path_refresh_count: int = 0

var game_config: GameConfig

func configure(config: GameConfig) -> void:
	if config == null:
		push_error(name + " received an empty GameConfig.")
		return

	game_config = config

	movement_speed = game_config.movement_speed
	seat_movement_speed = game_config.seat_movement_speed
	payment_amount = game_config.drink_payment_amount

	order_timer.wait_time = game_config.order_delay
	drink_timer.wait_time = game_config.drink_duration
	patience_timer.wait_time = game_config.patience_duration

func _ready() -> void:
	add_to_group("navigation_customers")

	order_icon.visible = false

	if !order_timer.timeout.is_connected(
		_on_order_timer_timeout
	):
		order_timer.timeout.connect(
			_on_order_timer_timeout
		)

	if !drink_timer.timeout.is_connected(
		_on_drink_timer_timeout
	):
		drink_timer.timeout.connect(
			_on_drink_timer_timeout
		)
		
	if !patience_timer.timeout.is_connected(
		_on_patience_timer_timeout
	):
		patience_timer.timeout.connect(
			_on_patience_timer_timeout
		)
	if !navigation_agent.velocity_computed.is_connected(
		_on_navigation_agent_velocity_computed
	):
		navigation_agent.velocity_computed.connect(
			_on_navigation_agent_velocity_computed
		)

	configure_walking_avoidance()
	stuck_check_position = global_position


func set_chair_target(chair: Chair) -> void:
	if chair == null:
		push_error(
			"Customer received an empty chair target."
		)
		return

	reserved_chair = chair
	current_state = State.WALKING_TO_STAGING
	path_refresh_count = 0

	prepare_navigation_target(
		reserved_chair.get_staging_position()
	)


func set_exit_target(
	new_exit_position: Vector2
) -> void:
	exit_position = new_exit_position


func configure_walking_avoidance() -> void:
	navigation_agent.avoidance_enabled = true
	navigation_agent.radius = walking_avoidance_radius
	navigation_agent.avoidance_priority = (
		walking_avoidance_priority
	)

	navigation_agent.velocity = Vector2.ZERO


func prepare_navigation_target(
	new_target: Vector2
) -> void:
	navigation_request_id += 1

	var this_request_id: int = navigation_request_id

	has_navigation_target = false
	requested_target_position = new_target

	stop_movement()
	reset_stuck_detection()
	configure_walking_avoidance()

	while (
		is_inside_tree()
		and NavigationServer2D.map_get_iteration_id(
			navigation_agent.get_navigation_map()
		) == 0
	):
		await get_tree().physics_frame

	if !is_inside_tree():
		return

	if this_request_id != navigation_request_id:
		return

	var navigation_map: RID = (
		navigation_agent.get_navigation_map()
	)

	active_target_position = (
		NavigationServer2D.map_get_closest_point(
			navigation_map,
			requested_target_position
		)
	)

	var projection_distance: float = (
		requested_target_position.distance_to(
			active_target_position
		)
	)

	if projection_distance > 12.0:
		push_warning(
			name
			+ " target was projected "
			+ str(projection_distance)
			+ " pixels onto the navigation mesh."
		)

	navigation_agent.target_position = (
		active_target_position
	)

	await get_tree().physics_frame

	if !is_inside_tree():
		return

	if this_request_id != navigation_request_id:
		return

	has_navigation_target = true

	if !navigation_agent.is_target_reachable():
		handle_failed_path()


func _physics_process(delta: float) -> void:
	match current_state:
		State.WALKING_TO_STAGING:
			process_navigation(delta)

		State.MOVING_TO_SEAT:
			process_moving_to_seat(delta)

		State.LEAVING:
			process_navigation(delta)

		State.WAITING_TO_ORDER:
			stop_movement()

		State.ORDERING:
			stop_movement()

		State.DRINKING:
			stop_movement()


func process_navigation(delta: float) -> void:
	if !has_navigation_target:
		stop_movement()
		return

	if navigation_agent.is_navigation_finished():
		if has_reached_navigation_target():
			handle_navigation_arrival()
		else:
			handle_failed_path()

		return

	var next_path_position: Vector2 = (
		navigation_agent.get_next_path_position()
	)

	var movement_direction: Vector2 = (
		global_position.direction_to(
			next_path_position
		)
	)

	var desired_velocity: Vector2 = (
		movement_direction * movement_speed
	)

	navigation_agent.velocity = desired_velocity

	update_stuck_detection(delta)


func _on_navigation_agent_velocity_computed(
	safe_velocity: Vector2
) -> void:
	if (
		current_state != State.WALKING_TO_STAGING
		and current_state != State.LEAVING
	):
		return

	velocity = safe_velocity
	move_and_slide()


func has_reached_navigation_target() -> bool:
	if !has_navigation_target:
		return false

	return (
		global_position.distance_to(
			active_target_position
		)
		<= navigation_arrival_distance
	)


func handle_navigation_arrival() -> void:
	has_navigation_target = false
	stop_movement()
	reset_stuck_detection()
	path_refresh_count = 0

	match current_state:
		State.WALKING_TO_STAGING:
			begin_moving_to_seat()

		State.LEAVING:
			finish_customer()


func begin_moving_to_seat() -> void:
	if reserved_chair == null:
		handle_invalid_destination()
		return

	current_state = State.MOVING_TO_SEAT

	# Avoidance is deliberately disabled for the final short,
	# reserved movement from the staging point into the chair.
	navigation_agent.avoidance_enabled = false
	navigation_agent.velocity = Vector2.ZERO

	reset_stuck_detection()


func process_moving_to_seat(delta: float) -> void:
	if reserved_chair == null:
		handle_invalid_destination()
		return

	var seat_position: Vector2 = (
		reserved_chair.get_seat_position()
	)

	var distance_to_seat: float = (
		global_position.distance_to(seat_position)
	)

	if distance_to_seat <= seat_arrival_distance:
		arrive_at_seat()
		return

	var movement_direction: Vector2 = (
		global_position.direction_to(seat_position)
	)

	velocity = (
		movement_direction
		* seat_movement_speed
	)

	move_and_slide()

	update_stuck_detection(delta)


func arrive_at_seat() -> void:
	if reserved_chair == null:
		handle_invalid_destination()
		return

	stop_movement()
	reset_stuck_detection()

	# The chair now supplies a fixed obstacle for other customers.
	# This stops the seated customer being treated as a movable agent.
	navigation_agent.avoidance_enabled = false
	navigation_agent.velocity = Vector2.ZERO

	reserved_chair.set_occupied_zone_enabled(true)

	current_state = State.WAITING_TO_ORDER
	order_timer.start()

	print(
		name,
		" seated at ",
		reserved_chair.get_table().name,
		"/",
		reserved_chair.name
	)


func update_stuck_detection(delta: float) -> void:
	stuck_elapsed += delta

	if stuck_elapsed < stuck_check_interval:
		return

	stuck_elapsed = 0.0

	var distance_moved: float = (
		global_position.distance_to(
			stuck_check_position
		)
	)

	stuck_check_position = global_position

	if distance_moved >= minimum_stuck_movement:
		consecutive_stuck_checks = 0
		return

	consecutive_stuck_checks += 1

	if consecutive_stuck_checks < maximum_stuck_checks:
		return

	consecutive_stuck_checks = 0

	if current_state == State.MOVING_TO_SEAT:
		push_warning(
			name
			+ " could not complete movement into its seat."
		)

		handle_invalid_destination()
		return

	if (
		current_state == State.WALKING_TO_STAGING
		or current_state == State.LEAVING
	):
		refresh_current_path()


func refresh_current_path() -> void:
	path_refresh_count += 1

	if path_refresh_count > maximum_path_refreshes:
		push_warning(
			name
			+ " exceeded its maximum path refreshes."
		)

		handle_failed_path()
		return

	print(
		name,
		" refreshing navigation path. Attempt ",
		path_refresh_count,
		"/",
		maximum_path_refreshes
	)

	prepare_navigation_target(
		requested_target_position
	)


func reset_stuck_detection() -> void:
	stuck_elapsed = 0.0
	stuck_check_position = global_position
	consecutive_stuck_checks = 0


func stop_movement() -> void:
	velocity = Vector2.ZERO

	if is_instance_valid(navigation_agent):
		navigation_agent.velocity = Vector2.ZERO


func handle_failed_path() -> void:
	has_navigation_target = false
	stop_movement()

	push_warning(
		name
		+ " failed to reach navigation target "
		+ str(active_target_position)
	)

	handle_invalid_destination()


func handle_invalid_destination() -> void:
	reset_stuck_detection()

	if current_state == State.LEAVING:
		finish_customer()
		return

	print(
		name,
		" could not reach its chair and will leave."
	)

	release_reserved_chair()
	customer_abandoned_seat.emit(self)

	current_state = State.LEAVING
	path_refresh_count = 0

	prepare_navigation_target(exit_position)


func release_reserved_chair() -> void:
	if reserved_chair == null:
		return

	reserved_chair.set_occupied_zone_enabled(false)
	reserved_chair = null


func _on_order_timer_timeout() -> void:
	current_state = State.ORDERING
	order_icon.visible = true

	patience_timer.start()

	if should_show_debug_messages():
		print(
			name,
			" ordered grog. Patience: ",
			patience_timer.wait_time,
			" seconds."
		)


func interact(player: Node) -> void:
	if current_state != State.ORDERING:
		if should_show_debug_messages():
			print(
				name,
				" is not ready to be served."
			)
		return

	if player.carrying_item != ItemType.Type.GROG:
		if should_show_debug_messages():
			print(name, " wants grog.")
		return

	patience_timer.stop()

	player.set_carried_item(
		ItemType.Type.NONE
	)

	if reserved_chair != null:
		reserved_chair.begin_use()

	order_icon.visible = false
	current_state = State.DRINKING
	drink_timer.start()

	if should_show_debug_messages():
		print(name, " was served.")


func _on_drink_timer_timeout() -> void:
	print(name, " finished drinking.")
	print(name, " paid £", payment_amount)

	customer_paid.emit(payment_amount)

	if reserved_chair != null:
		reserved_chair.require_cleaning()
		reserved_chair = null

	current_state = State.LEAVING
	path_refresh_count = 0

	prepare_navigation_target(exit_position)


func _on_patience_timer_timeout() -> void:
	if current_state != State.ORDERING:
		return

	order_icon.visible = false

	if should_show_debug_messages():
		print(
			name,
			" ran out of patience and is leaving."
		)

	release_reserved_chair()
	customer_abandoned_seat.emit(self)

	current_state = State.LEAVING
	path_refresh_count = 0

	prepare_navigation_target(exit_position)


func should_show_debug_messages() -> bool:
	if game_config == null:
		return true

	return game_config.show_debug_messages
	
func finish_customer() -> void:
	stop_movement()

	order_timer.stop()
	drink_timer.stop()
	patience_timer.stop()

	navigation_agent.avoidance_enabled = false

	if reserved_chair != null:
		reserved_chair.set_occupied_zone_enabled(false)

	customer_finished.emit(self)
	queue_free()
