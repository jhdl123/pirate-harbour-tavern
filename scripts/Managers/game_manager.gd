class_name GameManager
extends Node

## Phase 3A: a customer entered the tavern and is now configured.
##
## Emitted after the customer is fully wired up, so a listener can safely
## inspect it. [TavernTaskCoordinator] uses this to hear about each customer
## once, instead of scanning the roster looking for new arrivals.
signal customer_spawned(customer: Node)

## Owns customer spawning, seat assignment and the active-customer roster.
##
## Given a [code]class_name[/code] so other systems (the Bar Management menu,
## developer tools) can hold a typed reference instead of an untyped [Node]
## and reaching into private state. Read-only summary queries live here
## rather than being re-derived ad hoc in UI scripts.


@export_category("Scene References")
@export var customer_scene: PackedScene
@export var entities: Node2D
@export var customer_door: CustomerDoor
@export var tables: Array[Table]
@export var navigation_region: NavigationRegionManager
@export var economy_manager: EconomyManager
@export var statistics_tracker: StatisticsTracker

@export_category("Configuration")
@export var game_config: GameConfig

## The master item database. Validated once at startup so a duplicate or
## malformed item id is caught immediately rather than surfacing later as a
## mysterious null ItemDefinition somewhere in the order/stock chain.
@export var item_registry: ItemRegistry

## Every activity a customer's CustomerBrain can choose between. Optional:
## a null registry here means every spawned customer configures without the
## AI foundation at all, and behaves exactly as it did before that system
## existed - see Customer._configure_ai().
@export var activity_registry: ActivityRegistry

## Phase 2B: starting-money/thirst/satisfaction/visit-duration ranges and
## satisfaction/thirst/intoxication change amounts. Optional, like
## activity_registry above - a null value here leaves CustomerNeeds.seed_from()
## on its Phase 1 fallback defaults.
@export var customer_ai_balance: CustomerAIBalanceConfig

## Phase 2B: console logging and JSON report export switches. Optional -
## a null value disables both, the same as leaving diagnostics_config's own
## export_enabled/console_debug_enabled false.
@export var customer_ai_diagnostics: CustomerAIDiagnosticsConfig

## Phase 2B: the dedicated diagnostics collector - see its own doc comment
## for why every method on it is safe to call even when disabled. A node
## under Managers/ in main.tscn, the same pattern as economy_manager and
## statistics_tracker above, not an autoload.
@export var customer_ai_report_manager: CustomerAIReportManager

@export_category("Customer Types")
@export var customer_types: Array[CustomerType]


var customer_number: int = 0
var active_customers: Array[Node] = []


## The pending spawn booking with WorldTime, replacing a real-time Timer.
##
## Spawning is world progression: it should stop when the game is paused, run
## faster when time is fast-forwarded, and land correctly after a skip. A Timer
## does none of those. This is also the hook future opening hours will replace -
## a closed tavern simply does not re-book.
var _spawn_event: ScheduledTimeEvent = null


func _ready() -> void:
	if !validate_game_references():
		return
	
	if item_registry != null:
		item_registry.validate_or_warn()
	
	if activity_registry != null:
		activity_registry.validate_or_warn()
	
	economy_manager.initialise(
	game_config.starting_money
)
		
	configure_tables()
	connect_cleaning_signals()

	if !navigation_region.is_navigation_ready:
		await navigation_region.navigation_ready

	spawn_customer()
	schedule_next_customer()


func spawn_customer() -> void:
	if !validate_spawn_references():
		return

	if has_reached_customer_limit():
		if game_config.show_debug_messages:
			print(
				"Customer not spawned. Active customers: ",
				active_customers.size(),
				"/",
				game_config.maximum_active_customers
			)

		return

	if !navigation_region.is_navigation_ready:
		if game_config.show_debug_messages:
			print(
				"Customer spawn delayed: navigation is updating."
			)

		return

	var assigned_chair: Chair = (
		find_best_available_chair()
	)

	if assigned_chair == null:
		if game_config.show_debug_messages:
			print("No seats currently available.")

		return

	var selected_customer_type: CustomerType = (
		choose_customer_type()
	)

	if selected_customer_type == null:
		push_error(
			"No valid CustomerType is available."
		)
		return

	var customer: Node = customer_scene.instantiate()

	entities.add_child(customer)

	customer.global_position = (
		customer_door.get_spawn_position()
	)

	if customer.has_method("configure"):
		customer.configure(
			game_config,
			selected_customer_type,
			activity_registry,
			customer_ai_balance,
			customer_ai_diagnostics,
			customer_ai_report_manager
		)
	else:
		push_error(
			"Customer scene does not have a configure() function."
		)

		customer.queue_free()
		return

	var assigned_table: Table = (
		assigned_chair.get_table()
	)

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

	var safe_type_name: String = (
		selected_customer_type.display_name
			.replace(" ", "")
	)

	if safe_type_name.is_empty():
		safe_type_name = "Customer"

	customer.name = "%s%d" % [
		safe_type_name,
		customer_number
	]

	customer.set_door_targets(
		customer_door.get_inside_position(),
		customer_door.get_exit_position()
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

	active_customers.append(customer)

	# Phase 3A: announce the new arrival once it is completely set up - door
	# targets, chair, signals and all - so listeners never see a half-built
	# customer.
	customer_spawned.emit(customer)

	if statistics_tracker != null:
		statistics_tracker.update_active_customer_peak(
			active_customers.size()
		)
	
	if game_config.show_debug_messages:
		print(
			customer.name,
			" spawned as ",
			selected_customer_type.display_name,
			". Active customers: ",
			active_customers.size(),
			"/",
			game_config.maximum_active_customers,
			". Assigned to ",
			assigned_table.name,
			"/",
			assigned_chair.name,
			". Table occupancy: ",
			assigned_table.get_occupied_seat_count(),
			"/",
			assigned_table.get_chairs().size()
		)


func choose_customer_type() -> CustomerType:
	var valid_types: Array[CustomerType] = []
	var total_weight: float = 0.0

	for current_type: CustomerType in customer_types:
		if current_type == null:
			continue

		if current_type.spawn_weight <= 0.0:
			continue

		valid_types.append(current_type)
		total_weight += current_type.spawn_weight

	if valid_types.is_empty():
		return null

	var random_weight: float = randf_range(
		0.0,
		total_weight
	)

	var accumulated_weight: float = 0.0

	for current_type: CustomerType in valid_types:
		accumulated_weight += (
			current_type.spawn_weight
		)

		if random_weight <= accumulated_weight:
			return current_type

	return valid_types.back()


func schedule_next_customer() -> void:
	var next_spawn_delay: int = randi_range(
		game_config.minimum_spawn_delay_minutes,
		game_config.maximum_spawn_delay_minutes
	)

	WorldTime.cancel_scheduled(_spawn_event)

	_spawn_event = WorldTime.schedule_in(
		next_spawn_delay,
		_on_customer_spawn_due,
		&"customer_spawn"
	)

	if game_config.show_debug_messages:
		print(
			"Next customer spawn attempt in ",
			next_spawn_delay,
			" world minutes."
		)


func has_reached_customer_limit() -> bool:
	if game_config.ignore_customer_limit:
		return false

	return (
		active_customers.size()
		>= game_config.maximum_active_customers
	)


func validate_game_references() -> bool:
	if game_config == null:
		push_error(
			"GameManager has no GameConfig resource assigned."
		)
		return false
	if economy_manager == null:
		push_error(
			"GameManager has no EconomyManager assigned."
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

	if customer_types.is_empty():
		push_error(
			"GameManager has no CustomerType resources assigned."
		)
		return false

	var has_valid_customer_type: bool = false

	for current_type: CustomerType in customer_types:
		if (
			current_type != null
			and current_type.spawn_weight > 0.0
		):
			has_valid_customer_type = true
			break

	if !has_valid_customer_type:
		push_error(
			"GameManager has no CustomerType with a positive spawn weight."
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

	if customer_door == null:
		push_error(
			"GameManager has no CustomerDoor assigned."
		)
		return false

	if navigation_region == null:
		push_error(
			"GameManager has no navigation region assigned."
		)
		return false

	if tables.is_empty():
		push_error(
			"GameManager has no tables assigned."
		)
		return false

	var has_valid_table: bool = false

	for current_table: Table in tables:
		if current_table != null:
			has_valid_table = true
			break

	if !has_valid_table:
		push_error(
			"GameManager has no valid Table references assigned."
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

		for chair: Chair in (
			current_table.get_available_chairs()
		):
			var chair_score: float = (
				calculate_chair_score(
					chair,
					occupied_count
				)
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
		customer_door.get_inside_position().distance_to(
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


func find_customer_table(
	customer: Node
) -> Table:
	for current_table: Table in tables:
		if current_table == null:
			continue

		if current_table.contains_customer(customer):
			return current_table

	return null


func clear_customer_reservation(
	customer: Node
) -> void:
	var customer_table: Table = (
		find_customer_table(customer)
	)

	if customer_table != null:
		customer_table.clear_customer(customer)


func _on_customer_spawn_due() -> void:
	spawn_customer()
	schedule_next_customer()


func _on_customer_paid(
	amount: int
) -> void:
	var amount_added: int = economy_manager.add_money(
		amount,
		&"customer_payment"
	)

	if (
		amount_added > 0
		and statistics_tracker != null
	):
		statistics_tracker.record_customer_served(
			amount_added
		)

	if (
		amount_added > 0
		and game_config.show_debug_messages
	):
		print(
			"Customer payment: £",
			amount_added,
			". Money: £",
			economy_manager.get_money()
		)

func configure_tables() -> void:
	for current_table: Table in tables:
		if current_table == null:
			continue

		for chair: Chair in current_table.get_chairs():
			if chair == null:
				continue

			chair.configure(game_config)


func connect_cleaning_signals() -> void:
	for current_table: Table in tables:
		if current_table == null:
			continue

		for chair: Chair in current_table.get_chairs():
			if chair == null:
				continue

			if !chair.cleaning_cost_requested.is_connected(
				_on_cleaning_cost_requested
			):
				chair.cleaning_cost_requested.connect(
					_on_cleaning_cost_requested
				)

func _on_cleaning_cost_requested(
	amount: int,
	reason: String
) -> void:
	if amount <= 0:
		return

	var amount_removed: int = (
		economy_manager.deduct_money(
			amount,
			StringName(reason)
		)
	)

	if game_config.show_debug_messages:
		print(
			reason,
			" requested a £",
			amount,
			" charge. Removed £",
			amount_removed,
			". Money: £",
			economy_manager.get_money()
		)



func _on_customer_abandoned_seat(
	customer: Node
) -> void:
	clear_customer_reservation(customer)


## Read-only summary queries
## -----------------------------------------------------------------------
## These exist so UI (Bar Management overview, developer tools) can display
## accurate live numbers instead of hard-coded placeholder text.

func get_active_customer_count() -> int:
	return active_customers.size()


func get_total_seat_count() -> int:
	var total: int = 0

	for current_table: Table in tables:
		if current_table != null:
			total += current_table.get_chairs().size()

	return total


func get_occupied_seat_count() -> int:
	var occupied: int = 0

	for current_table: Table in tables:
		if current_table != null:
			occupied += current_table.get_occupied_seat_count()

	return occupied


func get_available_seat_count() -> int:
	return get_total_seat_count() - get_occupied_seat_count()


func _on_customer_finished(
	customer: Node
) -> void:
	active_customers.erase(customer)
	clear_customer_reservation(customer)

	if game_config.show_debug_messages:
		print(
			customer.name,
			" finished. Active customers: ",
			active_customers.size(),
			"/",
			game_config.maximum_active_customers
		)
