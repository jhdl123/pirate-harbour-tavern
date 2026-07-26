extends CharacterBody2D


signal customer_paid(amount: int)
signal customer_finished(customer: Node)
signal customer_abandoned_seat(customer: Node)


enum State {
	ENTERING,
	WALKING_TO_STAGING,
	MOVING_TO_SEAT,
	WAITING_TO_ORDER,
	ORDERING,
	DRINKING,
	LEAVING_TO_DOOR,
	EXITING
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


@export_category("Walking Avoidance")
@export var walking_avoidance_radius: float = 12.0
@export var walking_avoidance_priority: float = 0.5
@export var occupied_avoidance_radius: float = 17.0
@export var occupied_zone_offset: float = 2.0


@onready var navigation_agent: NavigationAgent2D = (
	$NavigationAgent2D
)

@onready var customer_sprite: Sprite2D = $Sprite2D
@onready var order_icon: Sprite2D = $OrderIcon
@onready var order_timer: Timer = $OrderTimer
@onready var drink_timer: Timer = $DrinkTimer
@onready var patience_timer: Timer = $PatienceTimer
@onready var patience_bar: PatienceBar = $PatienceBar


var current_state: State = State.ENTERING
var reserved_chair: Chair

var entrance_inside_position: Vector2
var entrance_outside_position: Vector2

var active_target_position: Vector2
var requested_target_position: Vector2

var has_navigation_target: bool = false
var navigation_request_id: int = 0

var stuck_elapsed: float = 0.0
var stuck_check_position: Vector2
var consecutive_stuck_checks: int = 0
var path_refresh_count: int = 0

var game_config: GameConfig
var ordered_drink: DrinkDefinition
var customer_type: CustomerType
var payment_multiplier: float = 1.0


func configure(
	config: GameConfig,
	new_customer_type: CustomerType
) -> void:
	if config == null:
		push_error(
			name + " received an empty GameConfig."
		)
		return

	if new_customer_type == null:
		push_error(
			name + " received an empty CustomerType."
		)
		return

	game_config = config
	customer_type = new_customer_type

	apply_game_config()
	apply_customer_type()


func apply_game_config() -> void:
	navigation_arrival_distance = (
		game_config.navigation_arrival_distance
	)

	seat_arrival_distance = (
		game_config.seat_arrival_distance
	)

	stuck_check_interval = (
		game_config.stuck_check_interval
	)

	minimum_stuck_movement = (
		game_config.minimum_stuck_movement
	)

	maximum_stuck_checks = (
		game_config.maximum_stuck_checks
	)

	maximum_path_refreshes = (
		game_config.maximum_path_refreshes
	)

	walking_avoidance_radius = (
		game_config.walking_avoidance_radius
	)

	walking_avoidance_priority = (
		game_config.walking_avoidance_priority
	)


func apply_customer_type() -> void:
	movement_speed = customer_type.movement_speed

	seat_movement_speed = (
		customer_type.seat_movement_speed
	)

	order_timer.wait_time = (
		customer_type.order_delay
	)

	patience_timer.wait_time = (
		customer_type.patience_duration
	)

	payment_multiplier = (
		customer_type.payment_multiplier
	)

	if customer_type.customer_texture != null:
		customer_sprite.texture = (
			customer_type.customer_texture
		)
	else:
		push_warning(
			customer_type.display_name
			+ " has no customer texture assigned."
		)

	navigation_agent.max_speed = movement_speed


func _ready() -> void:
	add_to_group("navigation_customers")

	order_icon.visible = false
	patience_bar.hide_bar()

	if not order_timer.timeout.is_connected(
		_on_order_timer_timeout
	):
		order_timer.timeout.connect(
			_on_order_timer_timeout
		)

	if not drink_timer.timeout.is_connected(
		_on_drink_timer_timeout
	):
		drink_timer.timeout.connect(
			_on_drink_timer_timeout
		)

	if not patience_timer.timeout.is_connected(
		_on_patience_timer_timeout
	):
		patience_timer.timeout.connect(
			_on_patience_timer_timeout
		)

	if not navigation_agent.velocity_computed.is_connected(
		_on_navigation_agent_velocity_computed
	):
		navigation_agent.velocity_computed.connect(
			_on_navigation_agent_velocity_computed
		)

	configure_walking_avoidance()
	stuck_check_position = global_position


func _process(
	_delta: float
) -> void:
	update_patience_visual()


func _physics_process(
	delta: float
) -> void:
	match current_state:
		State.ENTERING:
			process_navigation(delta)

		State.WALKING_TO_STAGING:
			process_navigation(delta)

		State.MOVING_TO_SEAT:
			process_moving_to_seat(delta)

		State.LEAVING_TO_DOOR:
			process_navigation(delta)

		State.EXITING:
			process_exiting(delta)

		State.WAITING_TO_ORDER:
			stop_movement()

		State.ORDERING:
			stop_movement()

		State.DRINKING:
			stop_movement()


func choose_order() -> void:
	ordered_drink = (
		choose_drink_from_customer_type()
	)

	if ordered_drink == null:
		push_error(
			name
			+ " could not choose a valid drink."
		)

		begin_leaving()
		return

	order_icon.texture = (
		ordered_drink.order_icon_texture
	)

	drink_timer.wait_time = (
		ordered_drink.drink_duration_seconds
	)


func choose_drink_from_customer_type() -> DrinkDefinition:
	if customer_type == null:
		push_error(
			name + " has no CustomerType."
		)
		return null

	var valid_drinks: Array[DrinkDefinition] = []

	for drink: DrinkDefinition in (
		customer_type.available_drinks
	):
		if drink == null:
			continue

		if not valid_drinks.has(drink):
			valid_drinks.append(drink)

	if valid_drinks.is_empty():
		push_error(
			customer_type.display_name
			+ " has no available drinks."
		)

		return null

	var preferred: DrinkDefinition = (
		customer_type.preferred_drink
	)

	var preferred_is_valid: bool = (
		preferred != null
		and valid_drinks.has(preferred)
	)

	if (
		preferred_is_valid
		and randf()
		< customer_type.preferred_drink_chance
	):
		return preferred

	var alternative_drinks: Array[DrinkDefinition] = []

	for drink: DrinkDefinition in valid_drinks:
		if drink == preferred:
			continue

		alternative_drinks.append(drink)

	if not alternative_drinks.is_empty():
		return alternative_drinks.pick_random()

	if preferred_is_valid:
		return preferred

	return valid_drinks.pick_random()


func set_chair_target(
	chair: Chair
) -> void:
	if chair == null:
		push_error(
			"Customer received an empty chair target."
		)
		return

	reserved_chair = chair
	current_state = State.ENTERING
	path_refresh_count = 0

	prepare_navigation_target(
		entrance_inside_position
	)


func set_door_targets(
	inside_position: Vector2,
	outside_position: Vector2
) -> void:
	entrance_inside_position = inside_position
	entrance_outside_position = outside_position


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

	if not is_inside_tree():
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

	if not is_inside_tree():
		return

	if this_request_id != navigation_request_id:
		return

	has_navigation_target = true

	if not navigation_agent.is_target_reachable():
		handle_failed_path()


func process_navigation(
	delta: float
) -> void:
	if not has_navigation_target:
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
		current_state != State.ENTERING
		and current_state != State.WALKING_TO_STAGING
		and current_state != State.LEAVING_TO_DOOR
	):
		return

	velocity = safe_velocity
	move_and_slide()


func has_reached_navigation_target() -> bool:
	if not has_navigation_target:
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
		State.ENTERING:
			begin_walking_to_staging()

		State.WALKING_TO_STAGING:
			begin_moving_to_seat()

		State.LEAVING_TO_DOOR:
			begin_exiting()

		State.EXITING:
			finish_customer()


func begin_walking_to_staging() -> void:
	if reserved_chair == null:
		handle_invalid_destination()
		return

	current_state = State.WALKING_TO_STAGING

	prepare_navigation_target(
		reserved_chair.get_staging_position()
	)


func begin_exiting() -> void:
	current_state = State.EXITING

	has_navigation_target = false
	navigation_agent.avoidance_enabled = false
	navigation_agent.velocity = Vector2.ZERO

	stop_movement()
	reset_stuck_detection()


func process_exiting(
	delta: float
) -> void:
	var distance_to_exit: float = (
		global_position.distance_to(
			entrance_outside_position
		)
	)

	if distance_to_exit <= navigation_arrival_distance:
		finish_customer()
		return

	var movement_direction: Vector2 = (
		global_position.direction_to(
			entrance_outside_position
		)
	)

	velocity = movement_direction * movement_speed
	move_and_slide()

	update_stuck_detection(delta)


func begin_leaving() -> void:
	order_timer.stop()
	patience_timer.stop()
	drink_timer.stop()

	order_icon.visible = false
	patience_bar.hide_bar()

	release_reserved_chair()
	customer_abandoned_seat.emit(self)

	current_state = State.LEAVING_TO_DOOR
	path_refresh_count = 0

	prepare_navigation_target(
		entrance_inside_position
	)


func begin_moving_to_seat() -> void:
	if reserved_chair == null:
		handle_invalid_destination()
		return

	current_state = State.MOVING_TO_SEAT

	navigation_agent.avoidance_enabled = false
	navigation_agent.velocity = Vector2.ZERO

	reset_stuck_detection()


func process_moving_to_seat(
	delta: float
) -> void:
	if reserved_chair == null:
		handle_invalid_destination()
		return

	var seat_position: Vector2 = (
		reserved_chair.get_seat_position()
	)

	var distance_to_seat: float = (
		global_position.distance_to(
			seat_position
		)
	)

	if distance_to_seat <= seat_arrival_distance:
		arrive_at_seat()
		return

	var movement_direction: Vector2 = (
		global_position.direction_to(
			seat_position
		)
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

	navigation_agent.avoidance_enabled = false
	navigation_agent.velocity = Vector2.ZERO

	reserved_chair.set_occupied_zone_enabled(true)

	choose_order()

	if ordered_drink == null:
		handle_invalid_destination()
		return

	current_state = State.WAITING_TO_ORDER
	order_timer.start()

	if should_show_debug_messages():
		print(
			name,
			" seated at ",
			reserved_chair.get_table().name,
			"/",
			reserved_chair.name
		)


func update_stuck_detection(
	delta: float
) -> void:
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

	if current_state == State.EXITING:
		push_warning(
			name
			+ " became stuck while passing through the exit."
		)

		finish_customer()
		return

	if (
		current_state == State.ENTERING
		or current_state == State.WALKING_TO_STAGING
		or current_state == State.LEAVING_TO_DOOR
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

	if should_show_debug_messages():
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

	order_timer.stop()
	patience_timer.stop()

	order_icon.visible = false
	patience_bar.hide_bar()

	if (
		current_state == State.LEAVING_TO_DOOR
		or current_state == State.EXITING
	):
		finish_customer()
		return

	if should_show_debug_messages():
		print(
			name,
			" could not reach its destination and will leave."
		)

	begin_leaving()


func release_reserved_chair() -> void:
	if reserved_chair == null:
		return

	reserved_chair.set_occupied_zone_enabled(false)
	reserved_chair = null


func update_patience_visual() -> void:
	if current_state != State.ORDERING:
		return

	if patience_timer.is_stopped():
		return

	if patience_timer.wait_time <= 0.0:
		patience_bar.set_patience_ratio(0.0)
		return

	var remaining_ratio: float = (
		patience_timer.time_left
		/ patience_timer.wait_time
	)

	patience_bar.set_patience_ratio(
		remaining_ratio
	)


func _on_order_timer_timeout() -> void:
	if ordered_drink == null:
		handle_invalid_destination()
		return

	current_state = State.ORDERING
	order_icon.visible = true

	if (
		game_config == null
		or not game_config.disable_patience
	):
		patience_timer.start()
		patience_bar.show_bar()
	else:
		patience_bar.hide_bar()

	if should_show_debug_messages():
		print(
			name,
			" ordered ",
			ordered_drink.display_name,
			". Patience: ",
			patience_timer.wait_time,
			" seconds."
		)


func interact(
	player: Node
) -> void:
	if current_state != State.ORDERING:
		if should_show_debug_messages():
			print(
				name,
				" is not ready to be served."
			)

		return

	if ordered_drink == null:
		return

	if not player.has_method(
		"get_item_carrier"
	):
		push_error(
			name
			+ " was interacted with by an invalid player."
		)

		return

	var carrier: ItemCarrier = player.get_item_carrier()

	if carrier == null:
		push_error(
			name
			+ " could not access the player's ItemCarrier."
		)

		return

	var carried_definition: ItemDefinition = (
		carrier.get_carried_definition()
	)

	# Compare stable item ids, never display names.
	if (
		carried_definition == null
		or carried_definition.item_id != ordered_drink.item_id
	):
		if should_show_debug_messages():
			if carried_definition == null:
				print(
					name,
					" wants ",
					ordered_drink.display_name,
					", but the player is carrying nothing."
				)
			else:
				print(
					name,
					" wants ",
					ordered_drink.display_name,
					", not ",
					carried_definition.display_name,
					"."
				)

		return

	patience_timer.stop()
	patience_bar.hide_bar()

	# The drink leaves the item system here: the customer consumes it.
	# Future work: hand it to a chair service slot instead of clearing it.
	carrier.clear_carried_item()

	if reserved_chair != null:
		reserved_chair.begin_use(
			ordered_drink
		)

	order_icon.visible = false
	current_state = State.DRINKING
	drink_timer.start()

	if should_show_debug_messages():
		print(
			name,
			" was served ",
			ordered_drink.display_name,
			"."
		)


func _on_drink_timer_timeout() -> void:
	if ordered_drink == null:
		push_error(
			name
			+ " finished drinking without a valid "
			+ "DrinkDefinition."
		)
		return

	var payment_amount: int = roundi(
		float(
			ordered_drink.base_sell_price
		)
		* payment_multiplier
	)

	if should_show_debug_messages():
		print(
			name,
			" finished drinking ",
			ordered_drink.display_name,
			"."
		)

		print(
			name,
			" paid £",
			payment_amount
		)

	customer_paid.emit(payment_amount)

	if reserved_chair != null:
		reserved_chair.require_cleaning()
		reserved_chair = null

	ordered_drink = null

	begin_leaving()


func _on_patience_timer_timeout() -> void:
	if current_state != State.ORDERING:
		return

	order_icon.visible = false
	patience_bar.hide_bar()

	if should_show_debug_messages():
		print(
			name,
			" ran out of patience and is leaving."
		)

	ordered_drink = null
	begin_leaving()


func should_show_debug_messages() -> bool:
	if game_config == null:
		return true

	return game_config.show_debug_messages


func finish_customer() -> void:
	stop_movement()

	order_timer.stop()
	drink_timer.stop()
	patience_timer.stop()

	order_icon.visible = false
	patience_bar.hide_bar()

	navigation_agent.avoidance_enabled = false

	if reserved_chair != null:
		reserved_chair.set_occupied_zone_enabled(false)

	customer_finished.emit(self)
	queue_free()
