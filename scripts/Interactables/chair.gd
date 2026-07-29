class_name Chair
extends Node2D


signal cleaning_cost_requested(
	amount: int,
	reason: String
)


## Retained so existing saves, debug output and tools keep working.
##
## The authoritative state now lives in this chair's [Reservable] component;
## these values are only a readable projection of it.
enum SeatState {
	AVAILABLE,
	RESERVED,
	IN_USE
}


@export_category("Seat Movement")
@export var staging_distance: float = 48.0
@export var seat_arrival_distance: float = 2.0


@export_category("Occupied Space")
@export var occupied_avoidance_radius: float = 22.0
@export var occupied_zone_offset: float = 4.0


@export_category("Cleaning")
@export var empty_glass_task: CleaningTask



var occupied_obstacle: NavigationObstacle2D
var active_drink: DrinkDefinition = null
var _game_config: GameConfig = null


@onready var seat_point: Marker2D = $SeatPoint

## Who has claimed this seat, and how firmly.
##
## Seat state used to be a private enum plus a customer reference on this
## script. It is now the shared [Reservable] component, so a queue slot, a
## station approach point and a future workstation claim themselves with exactly
## the same code and the same two-stage reserve/occupy rules.
@onready var reservable: Reservable = $Reservable

@onready var drink_sprite: Sprite2D = (
	$DrinkPoint/DrinkSprite
)

@onready var interaction_area: Area2D = (
	$InteractionArea
)

@onready var cleanable: CleanableComponent = (
	$CleanableComponent
)

@onready var cleaning_indicator: Node2D = (
	$DrinkPoint/CleaningIndicator
)

@onready var animation_player: AnimationPlayer = (
	$AnimationPlayer
)


func _ready() -> void:
	_create_occupied_obstacle()
	connect_cleanable_signals()

	_update_drink_visual()
	_update_cleaning_interaction()

	cleaning_indicator.visible = false


func configure(
	config: GameConfig
) -> void:
	_game_config = config
	cleanable.configure(config)


func _should_print_debug() -> bool:
	return _game_config == null or _game_config.show_debug_messages


func connect_cleanable_signals() -> void:
	if not cleanable.cleaning_started.is_connected(
		_on_cleaning_started
	):
		cleanable.cleaning_started.connect(
			_on_cleaning_started
		)

	if not cleanable.cleaning_cancelled.is_connected(
		_on_cleaning_cancelled
	):
		cleanable.cleaning_cancelled.connect(
			_on_cleaning_cancelled
		)

	if not cleanable.task_changed.is_connected(
		_on_cleaning_task_changed
	):
		cleanable.task_changed.connect(
			_on_cleaning_task_changed
		)

	if not cleanable.cleaning_completed.is_connected(
		_on_cleaning_completed
	):
		cleanable.cleaning_completed.connect(
			_on_cleaning_completed
		)

	if not cleanable.complication_triggered.is_connected(
		_on_cleaning_complication_triggered
	):
		cleanable.complication_triggered.connect(
			_on_cleaning_complication_triggered
		)


func _create_occupied_obstacle() -> void:
	occupied_obstacle = NavigationObstacle2D.new()
	occupied_obstacle.name = "OccupiedSeatObstacle"
	occupied_obstacle.radius = occupied_avoidance_radius
	occupied_obstacle.avoidance_enabled = false

	add_child(occupied_obstacle)

	_update_occupied_obstacle_position()


## The reservation state, expressed in the old enum.
func get_seat_state() -> SeatState:
	if reservable == null:
		return SeatState.AVAILABLE

	if reservable.is_occupied():
		return SeatState.IN_USE

	if reservable.is_reserved():
		return SeatState.RESERVED

	return SeatState.AVAILABLE


## The customer that claimed this seat, or null.
func get_customer() -> Node:
	if reservable == null:
		return null

	return reservable.get_holder()


func is_available() -> bool:
	return (
		get_seat_state() == SeatState.AVAILABLE
		and not cleanable.has_cleaning_task()
		and not cleanable.is_cleaning
	)


func assign_customer(
	new_customer: Node
) -> bool:
	if new_customer == null:
		return false

	if not is_available():
		return false

	if not reservable.reserve(new_customer):
		return false

	_update_drink_visual()
	_update_cleaning_interaction()

	return true


func begin_use(
	drink: DrinkDefinition
) -> void:
	var current_seat_state: SeatState = get_seat_state()

	# RESERVED -> the customer's first drink this visit, promote the claim.
	# IN_USE -> a later drink at the same visit (Relax/Order Again) - the
	# chair is already occupied by this same customer, so just serve the
	# new drink without re-promoting a reservation that is already active.
	if (
		current_seat_state != SeatState.RESERVED
		and current_seat_state != SeatState.IN_USE
	):
		push_warning(
			name
			+ " cannot begin use from state "
			+ str(current_seat_state)
		)
		return

	if drink == null:
		push_error(
			name
			+ " received an empty DrinkDefinition."
		)
		return

	active_drink = drink

	if current_seat_state == SeatState.RESERVED:
		# The customer is here now, so the claim is promoted from "on its way"
		# to "in use". A reservation that never reaches this point expires by
		# itself.
		reservable.occupy(reservable.get_holder())

	_update_drink_visual()
	_update_cleaning_interaction()

	var table: Table = get_table()

	if table != null and _should_print_debug():
		print(
			table.name,
			"/",
			name,
			" now has ",
			active_drink.display_name,
			"."
		)


## Releases this seat back to the pool with no cleaning implications - for a
## customer who leaves before ever being served (never reached
## [method begin_use]). Safe to call from [SeatState.RESERVED] or
## [SeatState.IN_USE]; a no-op if already [SeatState.AVAILABLE]. Once a chair
## has actually been used, prefer [method require_cleaning] instead - see its
## own doc comment for why a used chair still needs cleaning even when the
## customer eventually leaves without ordering again.
func release_reservation(
	holder: Node = null
) -> void:
	reservable.release(holder)
	set_occupied_zone_enabled(false)


func require_cleaning() -> void:
	if get_seat_state() != SeatState.IN_USE:
		push_warning(
			name
			+ " cannot require cleaning from state "
			+ str(get_seat_state())
		)
		return

	reservable.release()

	set_occupied_zone_enabled(false)

	if empty_glass_task == null:
		push_error(
			name
			+ " has no Empty Glass CleaningTask assigned."
		)

		active_drink = null
		_update_drink_visual()
		_update_cleaning_interaction()
		return

	var break_multiplier: float = 1.0

	if active_drink != null:
		break_multiplier = (
			active_drink.break_chance_multiplier
		)

	cleanable.set_cleaning_task(
		empty_glass_task,
		break_multiplier
	)

	_update_drink_visual()
	_update_cleaning_interaction()

	var table: Table = get_table()

	if table != null and _should_print_debug():
		print(
			table.name,
			"/",
			name,
			" now requires ",
			empty_glass_task.display_name,
			"."
		)


## The interaction-framework entry point, unchanged in behaviour.
##
## Phase 3A moved the body into [method try_clean] so staff can use the same
## path and check whether it worked. The player's experience is identical.
func interact(
	player: Node
) -> void:
	try_clean(player)


## Starts cleaning this seat using [param actor]'s own [ActionRunner].
##
## The one true cleaning entry point, shared by the player's interaction and by
## [CleanSeatExecutor]. Because both hand their own runner to the same
## [CleanableComponent], the duration, the cancel behaviour and the
## broken-glass complication are identical whoever is holding the rag - and
## there is no second code path that could be tuned separately by accident.
##
## [param actor] is duck-typed on [code]get_action_runner[/code], so anything
## with that component can clean: the player, a tavern hand, a future hired
## cleaner.
##
## Returns false when the seat is already clean, when somebody else is already
## cleaning it, or when the actor is busy with another action. All three are
## normal answers, not errors - they are exactly how a second cleaner is
## prevented from starting a duplicate action on the same seat.
func try_clean(
	actor: Node
) -> bool:
	if not cleanable.can_start_cleaning():
		return false

	if actor == null:
		return false

	if not actor.has_method(
		"get_action_runner"
	):
		push_warning(
			name
			+ " was interacted with by an object "
			+ "without an ActionRunner."
		)
		return false

	var actor_action_runner: ActionRunner = (
		actor.get_action_runner()
	)

	if actor_action_runner == null:
		push_warning(
			name
			+ " could not access the actor's ActionRunner."
		)
		return false

	if not cleanable.start_cleaning(
		actor_action_runner
	):
		return false

	_update_cleaning_interaction()

	return true


## True when this seat is waiting for somebody to clean it.
##
## Read by the task coordinator when it decides whether a cleaning requirement
## exists. Kept here rather than having callers reach into the component, so
## the answer has one owner.
func needs_cleaning() -> bool:
	return cleanable != null and cleanable.has_cleaning_task()

func clear_customer() -> void:
	reservable.release()

	set_occupied_zone_enabled(false)

	if not cleanable.has_cleaning_task():
		active_drink = null

	_update_drink_visual()
	_update_cleaning_interaction()


func contains_customer(
	target_customer: Node
) -> bool:
	return reservable.is_held_by(target_customer)


func get_seat_position() -> Vector2:
	return seat_point.global_position


func get_table() -> Table:
	var chairs_container: Node = get_parent()

	if chairs_container == null:
		return null

	var possible_table: Node = (
		chairs_container.get_parent()
	)

	if possible_table is Table:
		return possible_table

	return null


func get_outward_direction() -> Vector2:
	var table: Table = get_table()

	if table == null:
		push_warning(
			name
			+ " could not find its parent table."
		)
		return Vector2.DOWN

	var direction: Vector2 = (
		get_seat_position()
		- table.global_position
	).normalized()

	if direction == Vector2.ZERO:
		push_warning(
			name
			+ " is positioned at the centre of its table."
		)
		return Vector2.DOWN

	return direction


func get_staging_position() -> Vector2:
	return (
		get_seat_position()
		+ get_outward_direction()
		* staging_distance
	)


func set_occupied_zone_enabled(
	enabled: bool
) -> void:
	if occupied_obstacle == null:
		return

	_update_occupied_obstacle_position()

	occupied_obstacle.avoidance_enabled = enabled


func _update_occupied_obstacle_position() -> void:
	if occupied_obstacle == null:
		return

	var local_outward_direction: Vector2 = (
		global_transform.basis_xform_inv(
			get_outward_direction()
		)
	)

	occupied_obstacle.position = (
		seat_point.position
		+ local_outward_direction
		* occupied_zone_offset
	)


func _update_cleaning_interaction() -> void:
	var should_enable: bool = (
		cleanable.has_cleaning_task()
	)

	interaction_area.monitoring = should_enable
	interaction_area.monitorable = should_enable

	if should_enable:
		interaction_area.collision_layer = 1
	else:
		interaction_area.collision_layer = 0

func _update_drink_visual() -> void:
	if cleanable.has_cleaning_task():
		var task: CleaningTask = (
			cleanable.current_task
		)

		if (
			task != null
			and task.task_texture != null
		):
			drink_sprite.texture = task.task_texture
			drink_sprite.visible = true
			return

		drink_sprite.texture = null
		drink_sprite.visible = false
		return

	match get_seat_state():
		SeatState.AVAILABLE:
			drink_sprite.texture = null
			drink_sprite.visible = false

		SeatState.RESERVED:
			drink_sprite.texture = null
			drink_sprite.visible = false

		SeatState.IN_USE:
			if active_drink == null:
				drink_sprite.texture = null
				drink_sprite.visible = false
				return

			if active_drink.world_texture == null:
				push_warning(
					active_drink.display_name
					+ " has no world texture assigned."
				)

				drink_sprite.texture = null
				drink_sprite.visible = false
				return

			drink_sprite.texture = (
				active_drink.world_texture
			)

			drink_sprite.visible = true


func _on_cleaning_started(
	task: CleaningTask
) -> void:
	_update_cleaning_interaction()

	cleaning_indicator.visible = true
	animation_player.play("cleaning")

	var table: Table = get_table()

	if table != null and _should_print_debug():
		print(
			table.name,
			"/",
			name,
			" started cleaning ",
			task.display_name,
			"."
		)


func _on_cleaning_cancelled(
	_task: CleaningTask
) -> void:
	stop_cleaning_animation()
	_update_cleaning_interaction()


func stop_cleaning_animation() -> void:
	animation_player.stop()
	cleaning_indicator.visible = false


func _on_cleaning_task_changed(
	task: CleaningTask
) -> void:
	_update_drink_visual()
	_update_cleaning_interaction()

	var table: Table = get_table()

	if table != null and _should_print_debug():
		print(
			table.name,
			"/",
			name,
			" now requires ",
			task.display_name,
			"."
		)


func _on_cleaning_complication_triggered(
	task: CleaningTask,
	cost: int
) -> void:
	stop_cleaning_animation()

	_update_drink_visual()
	_update_cleaning_interaction()

	var reason: String = "Cleaning complication"

	if task != null:
		reason = task.display_name

	if cost > 0:
		cleaning_cost_requested.emit(
			cost,
			reason
		)

	var table: Table = get_table()

	if table != null and _should_print_debug():
		print(
			table.name,
			"/",
			name,
			" cleaning caused ",
			reason,
			". Cost: £",
			cost
		)


func _on_cleaning_completed() -> void:
	stop_cleaning_animation()

	active_drink = null

	_update_drink_visual()
	_update_cleaning_interaction()

	var table: Table = get_table()

	if table != null and _should_print_debug():
		print(
			table.name,
			"/",
			name,
			" was cleaned and is available again."
		)
