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
## Bookings with WorldTime, replacing three real-time Timer nodes.
##
## A Timer keeps counting while the game is paused, ignores time speed, cannot
## be skipped and cannot be saved. A booking does all four correctly, which is
## the whole reason the scheduler exists.
var _order_event: ScheduledTimeEvent = null
var _drink_event: ScheduledTimeEvent = null
var _patience_event: ScheduledTimeEvent = null

## World minute the current patience window ends, for the bar.
var _patience_end_minutes: float = 0.0
var _patience_total_minutes: int = 0

var _order_delay_minutes: int = 2
var _patience_duration_minutes: int = 15
var _drink_duration_minutes: int = 8
@onready var patience_bar: PatienceBar = $PatienceBar

@onready var actor_movement: ActorMovement = (
	$ActorMovement
)

@onready var actor_navigation: ActorNavigation = (
	$ActorNavigation
)


var current_state: State = State.ENTERING
var reserved_chair: Chair

var entrance_inside_position: Vector2
var entrance_outside_position: Vector2


var game_config: GameConfig
var ordered_drink: DrinkDefinition
var customer_type: CustomerType
var payment_multiplier: float = 1.0

var _profiles_are_private: bool = false


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

	_apply_tuning_to_profiles()


func apply_customer_type() -> void:
	movement_speed = customer_type.movement_speed

	seat_movement_speed = (
		customer_type.seat_movement_speed
	)

	_order_delay_minutes = customer_type.order_delay_minutes
	_patience_duration_minutes = customer_type.patience_duration_minutes

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

	_apply_tuning_to_profiles()


## Copies the shared navigation resources so this actor owns its own tuning.
##
## Profiles are Resources, so without this every customer would be writing its
## personal speed onto the one asset the whole tavern shares. Idempotent: safe
## to call again if an actor is reconfigured.
func _create_private_profiles() -> void:
	if _profiles_are_private:
		return

	if actor_movement != null and actor_movement.profile != null:
		actor_movement.profile = actor_movement.profile.duplicate()

	if actor_navigation != null and actor_navigation.profile != null:
		actor_navigation.profile = actor_navigation.profile.duplicate()

	_profiles_are_private = true


## Pushes this customer's exported and configured values onto its profiles.
##
## This is the seam between the old per-customer exports plus [GameConfig] and
## the new profile resources. Anything a future actor type wants to vary lives
## in the profile; this method simply feeds it.
func _apply_tuning_to_profiles() -> void:
	if actor_movement == null or actor_navigation == null:
		return

	_create_private_profiles()

	if actor_movement.profile != null:
		actor_movement.profile.maximum_speed = movement_speed
		actor_movement.profile.careful_speed = seat_movement_speed

	if actor_navigation.profile != null:
		actor_navigation.profile.avoidance_radius = (
			walking_avoidance_radius
		)

		actor_navigation.profile.avoidance_priority = (
			walking_avoidance_priority
		)

		actor_navigation.profile.stuck_check_interval = (
			stuck_check_interval
		)

		actor_navigation.profile.stuck_minimum_movement = (
			minimum_stuck_movement
		)

		actor_navigation.profile.stuck_checks_before_recovery = (
			maximum_stuck_checks
		)

		actor_navigation.profile.maximum_recovery_attempts = (
			maxi(maximum_path_refreshes, 1)
		)

	actor_navigation.set_profile(actor_navigation.profile)


func _ready() -> void:
	add_to_group("navigation_customers")

	order_icon.visible = false
	patience_bar.hide_bar()

	_apply_tuning_to_profiles()

	if not actor_navigation.destination_reached.is_connected(
		_on_destination_reached
	):
		actor_navigation.destination_reached.connect(
			_on_destination_reached
		)

	if not actor_navigation.destination_failed.is_connected(
		_on_destination_failed
	):
		actor_navigation.destination_failed.connect(
			_on_destination_failed
		)


func _process(
	_delta: float
) -> void:
	update_patience_visual()


func _physics_process(
	_delta: float
) -> void:
	# Movement is owned by ActorNavigation and ActorMovement. The customer only
	# decides *where* to go and what to do on arrival, which is the whole point
	# of the split: this state machine works identically for a bartender.
	pass


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

	_drink_duration_minutes = ordered_drink.drink_duration_minutes


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

	_travel_to(
		entrance_inside_position,
		navigation_arrival_distance,
		"tavern entrance"
	)


func set_door_targets(
	inside_position: Vector2,
	outside_position: Vector2
) -> void:
	entrance_inside_position = inside_position
	entrance_outside_position = outside_position


## Sends this customer somewhere, through the shared navigation framework.
##
## Every journey the customer makes goes through here, so there is exactly one
## place that knows how a destination is described.
func _travel_to(
	world_position: Vector2,
	arrival_distance: float,
	label: String
) -> void:
	actor_navigation.unpark()

	actor_navigation.move_to(
		NavigationDestination.to_position(
			world_position,
			arrival_distance,
			label
		)
	)


## Sends this customer to a spot it must reach precisely, slowly.
##
## The seat, and later any workstation position that has to be stood on exactly.
func _travel_to_exactly(
	world_position: Vector2,
	arrival_distance: float,
	speed_scale: float,
	label: String
) -> void:
	actor_navigation.unpark()

	actor_navigation.move_to(
		NavigationDestination.to_exact_position(
			world_position,
			arrival_distance,
			speed_scale,
			label
		)
	)


## The navigation framework reports that this customer arrived.
##
## Replaces the old per-state arrival checks: the customer no longer measures
## distances, it is simply told.
func _on_destination_reached(
	_destination: NavigationDestination
) -> void:
	match current_state:
		State.ENTERING:
			begin_walking_to_staging()

		State.WALKING_TO_STAGING:
			begin_moving_to_seat()

		State.MOVING_TO_SEAT:
			arrive_at_seat()

		State.LEAVING_TO_DOOR:
			begin_exiting()

		State.EXITING:
			finish_customer()


## The navigation framework gave up on the current destination.
##
## By the time this fires the actor has already tried sidestepping and
## re-planning, so this really is the end of the road for that destination.
func _on_destination_failed(
	destination: NavigationDestination,
	reason: StringName
) -> void:
	if should_show_debug_messages():
		print(
			name,
			" could not reach ",
			"its destination" if destination == null else destination.get_label(),
			" (",
			reason,
			")."
		)

	if current_state == State.EXITING:
		# Already outside and on the way out; there is nothing left to salvage.
		finish_customer()
		return

	handle_invalid_destination()


func begin_walking_to_staging() -> void:
	if reserved_chair == null:
		handle_invalid_destination()
		return

	current_state = State.WALKING_TO_STAGING

	_travel_to(
		reserved_chair.get_staging_position(),
		navigation_arrival_distance,
		"seat staging point"
	)


func begin_exiting() -> void:
	current_state = State.EXITING

	# The outside marker sits beyond the navigation mesh, so this is an exact
	# destination: the framework paths as far as the mesh allows and then walks
	# the remaining distance directly, with avoidance still running.
	_travel_to_exactly(
		entrance_outside_position,
		navigation_arrival_distance,
		1.0,
		"tavern exit"
	)


func begin_leaving() -> void:
	_cancel_all_scheduled()

	order_icon.visible = false
	patience_bar.hide_bar()

	release_reserved_chair()
	customer_abandoned_seat.emit(self)

	current_state = State.LEAVING_TO_DOOR

	_travel_to(
		entrance_inside_position,
		navigation_arrival_distance,
		"door, leaving"
	)


func begin_moving_to_seat() -> void:
	if reserved_chair == null:
		handle_invalid_destination()
		return

	current_state = State.MOVING_TO_SEAT

	# A seat sits inside furniture and therefore off the navigation mesh. The
	# framework handles that as a final approach rather than as a special case
	# here, and unlike the old code it keeps avoidance running all the way in.
	var seat_speed_scale: float = 1.0

	if actor_movement.profile.maximum_speed > 0.0:
		seat_speed_scale = clampf(
			seat_movement_speed
			/ actor_movement.profile.maximum_speed,
			0.05,
			1.0
		)

	_travel_to_exactly(
		reserved_chair.get_seat_position(),
		seat_arrival_distance,
		seat_speed_scale,
		"seat"
	)


func arrive_at_seat() -> void:
	if reserved_chair == null:
		handle_invalid_destination()
		return

	# Parking keeps the customer in the avoidance solver at maximum priority, so
	# other actors flow around a seated customer instead of shoving it out of
	# its chair. The old code removed the customer from avoidance entirely.
	actor_navigation.park()

	reserved_chair.set_occupied_zone_enabled(true)

	choose_order()

	if ordered_drink == null:
		handle_invalid_destination()
		return

	current_state = State.WAITING_TO_ORDER
	_order_event = WorldTime.schedule_in(
		_order_delay_minutes,
		_on_order_ready,
		&"customer_order"
	)

	if should_show_debug_messages():
		print(
			name,
			" seated at ",
			reserved_chair.get_table().name,
			"/",
			reserved_chair.name
		)


func handle_invalid_destination() -> void:
	_cancel_all_scheduled()

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


## Cancels every outstanding booking this customer holds.
##
## Called anywhere the old code stopped three timers, and on the way out, so a
## customer that is freed never leaves work booked behind it.
func _cancel_all_scheduled() -> void:
	WorldTime.cancel_scheduled(_order_event)
	WorldTime.cancel_scheduled(_drink_event)
	WorldTime.cancel_scheduled(_patience_event)

	_order_event = null
	_drink_event = null
	_patience_event = null
	_patience_total_minutes = 0


func _cancel_patience() -> void:
	WorldTime.cancel_scheduled(_patience_event)

	_patience_event = null
	_patience_total_minutes = 0


func update_patience_visual() -> void:
	if current_state != State.ORDERING:
		return

	if _patience_event == null or _patience_total_minutes <= 0:
		return

	# Read against the fractional world minute so the bar slides smoothly and
	# drains faster under fast-forward, rather than stepping once a minute.
	var remaining: float = (
		_patience_end_minutes
		- WorldTime.get_total_minutes_precise()
	)

	patience_bar.set_patience_ratio(
		clampf(
			remaining / float(_patience_total_minutes),
			0.0,
			1.0
		)
	)


func _on_order_ready() -> void:
	if ordered_drink == null:
		handle_invalid_destination()
		return

	current_state = State.ORDERING
	order_icon.visible = true

	if (
		game_config == null
		or not game_config.disable_patience
	):
		_patience_total_minutes = _patience_duration_minutes

		_patience_end_minutes = (
			WorldTime.get_total_minutes_precise()
			+ float(_patience_total_minutes)
		)

		_patience_event = WorldTime.schedule_in(
			_patience_duration_minutes,
			_on_patience_expired,
			&"customer_patience"
		)

		patience_bar.show_bar()
	else:
		patience_bar.hide_bar()

	if should_show_debug_messages():
		print(
			name,
			" ordered ",
			ordered_drink.display_name,
			". Patience: ",
			_patience_duration_minutes,
			" world minutes."
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

	_cancel_patience()
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
	_drink_event = WorldTime.schedule_in(
		_drink_duration_minutes,
		_on_drink_finished,
		&"customer_drinking"
	)

	if should_show_debug_messages():
		print(
			name,
			" was served ",
			ordered_drink.display_name,
			"."
		)


func _on_drink_finished() -> void:
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


func _on_patience_expired() -> void:
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
	actor_navigation.stop()
	_cancel_all_scheduled()

	order_icon.visible = false
	patience_bar.hide_bar()

	if reserved_chair != null:
		reserved_chair.set_occupied_zone_enabled(false)

	customer_finished.emit(self)
	queue_free()
