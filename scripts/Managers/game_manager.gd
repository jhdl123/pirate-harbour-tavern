extends Node


@export_category("Scene References")
@export var customer_scene: PackedScene
@export var entities: Node2D
@export var customer_spawn_point: Marker2D
@export var customer_exit_point: Marker2D
@export var tables: Array[Table]
@export var navigation_region: NavigationRegionManager

@export_category("Configuration")
@export var game_config: GameConfig


signal money_changed(new_amount: int)


var money: int = 0
var customer_number: int = 0


@onready var spawn_timer: Timer = $CustomerSpawnTimer


func _ready() -> void:
	spawn_timer.stop()

	if !spawn_timer.timeout.is_connected(
		_on_customer_spawn_timer_timeout
	):
		spawn_timer.timeout.connect(
			_on_customer_spawn_timer_timeout
		)

	if !validate_game_references():
		return

	if !navigation_region.is_navigation_ready:
		await navigation_region.navigation_ready

	spawn_customer()
	schedule_next_customer()


func spawn_customer() -> void:
	if !validate_spawn_references():
		return

	if !navigation_region.is_navigation_ready:
		print(
			"Customer spawn delayed: navigation is updating."
		)
		return

	var assigned_chair: Chair = find_best_available_chair()

	if assigned_chair == null:
		print("No seats currently available.")
		return

	var customer: Node = customer_scene.instantiate()

	entities.add_child(customer)
	customer.global_position = customer_spawn_point.global_position

	# This allows the customer to read values such as:
	# movement speed, order delay, patience and payment.
	if customer.has_method("configure"):
		customer.configure(game_config)

	var assigned_table: Table = assigned_chair.get_table()

	if assigned_table == null:
		push_error(
			assigned_chair.name
			+ " does not have a valid parent table."
		)

		customer.queue_free()
		return

	if !assigned_table.reserve_chair(
		assigned_chair,
		customer
	):
		push_error(
			"Could not reserve "
			+ assigned_chair.name
			+ " on "
			+ assigned_table.name
		)

		customer.queue_free()
		return

	customer_number += 1
	customer.name = "Customer%d" % customer_number

	customer.set_exit_target(
		customer_exit_point.global_position
	)

	customer.set_chair_target(
		assigned_chair
	)

	customer.customer_paid.connect(
		_on_customer_paid
	)

	customer.customer_finished.connect(
		_on_customer_finished
	)

	customer.customer_abandoned_seat.connect(
		_on_customer_abandoned_seat
	)

	if game_config.show_debug_messages:
		print(
			customer.name,
			" spawned at ",
			customer.global_position,
			" and assigned to ",
			assigned_table.name,
			"/",
			assigned_chair.name,
			". Table occupancy: ",
			assigned_table.get_occupied_seat_count(),
			"/",
			assigned_table.get_chairs().size()
		)


func schedule_next_customer() -> void:
	var next_spawn_delay: float = randf_range(
		game_config.minimum_spawn_delay,
		game_config.maximum_spawn_delay
	)

	spawn_timer.start(next_spawn_delay)

	if game_config.show_debug_messages:
		print(
			"Next customer spawn attempt in ",
			snappedf(next_spawn_delay, 0.1),
			" seconds."
		)


func validate_game_references() -> bool:
	if game_config == null:
		push_error(
			"GameManager has no GameConfig resource assigned."
		)
		return false

	if navigation_region == null:
		push_error(
			"GameManager has no NavigationRegionManager assigned."
		)
		return false

	return true


func validate_spawn_references() -> bool:
	if game_config == null:
		push_error(
			"GameManager has no GameConfig resource assigned."
		)
		return false

	if customer_scene == null:
		push_error(
			"GameManager has no customer scene assigned."
		)
		return false

	if entities == null:
		push_error(
			"GameManager has no Entities node assigned."
		)
		return false

	if customer_spawn_point == null:
		push_error(
			"GameManager has no customer spawn point assigned."
		)
		return false

	if customer_exit_point == null:
		push_error(
			"GameManager has no customer exit point assigned."
		)
		return false

	if navigation_region == null:
		push_error(
			"GameManager has no navigation region assigned."
		)
		return false

	return true


func find_best_available_chair() -> Chair:
	var best_chair: Chair = null
	var best_score: float = INF

	for current_table: Table in tables:
		if current_table == null:
			continue

		var occupied_count: int = (
			current_table.get_occupied_seat_count()
		)

		for chair: Chair in current_table.get_available_chairs():
			var chair_score: float = calculate_chair_score(
				chair,
				occupied_count
			)

			if chair_score < best_score:
				best_score = chair_score
				best_chair = chair

	return best_chair


func calculate_chair_score(
	chair: Chair,
	table_occupied_count: int
) -> float:
	var staging_position: Vector2 = (
		chair.get_staging_position()
	)

	var travel_distance: float = (
		customer_spawn_point.global_position.distance_to(
			staging_position
		)
	)

	var score: float = 0.0

	score += (
		float(table_occupied_count)
		* game_config.occupied_seat_penalty
	)

	score += (
		travel_distance
		* game_config.travel_distance_weight
	)

	return score


func find_customer_table(customer: Node) -> Table:
	for current_table: Table in tables:
		if current_table == null:
			continue

		if current_table.contains_customer(customer):
			return current_table

	return null


func _on_customer_spawn_timer_timeout() -> void:
	spawn_customer()
	schedule_next_customer()


func _on_customer_paid(amount: int) -> void:
	add_money(amount)


func _on_customer_abandoned_seat(
	customer: Node
) -> void:
	clear_customer_reservation(customer)


func _on_customer_finished(
	_customer: Node
) -> void:
	pass


func clear_customer_reservation(
	customer: Node
) -> void:
	var customer_table: Table = find_customer_table(
		customer
	)

	if customer_table != null:
		customer_table.clear_customer(customer)


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)

	if game_config.show_debug_messages:
		print("Money: £", money)
