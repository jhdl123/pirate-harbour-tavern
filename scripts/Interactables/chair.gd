class_name Chair
extends Node2D


enum SeatState {
	AVAILABLE,
	RESERVED,
	IN_USE,
	NEEDS_CLEANING
}


@export_category("Seat Movement")
@export var staging_distance: float = 48.0
@export var seat_arrival_distance: float = 2.0

@export_category("Occupied Space")
@export var occupied_avoidance_radius: float = 22.0
@export var occupied_zone_offset: float = 4.0


var current_state: SeatState = SeatState.AVAILABLE
var customer: Node = null

var occupied_obstacle: NavigationObstacle2D
var active_drink: DrinkData

@onready var seat_point: Marker2D = $SeatPoint
@onready var drink_sprite: Sprite2D = $DrinkPoint/DrinkSprite
@onready var interaction_area: Area2D = $InteractionArea


func _ready() -> void:
	_create_occupied_obstacle()
	_update_drink_visual()
	_set_cleaning_interaction_enabled(false)


func _create_occupied_obstacle() -> void:
	occupied_obstacle = NavigationObstacle2D.new()
	occupied_obstacle.name = "OccupiedSeatObstacle"
	occupied_obstacle.radius = occupied_avoidance_radius
	occupied_obstacle.avoidance_enabled = false

	add_child(occupied_obstacle)

	_update_occupied_obstacle_position()


func is_available() -> bool:
	return current_state == SeatState.AVAILABLE


func assign_customer(new_customer: Node) -> bool:
	if new_customer == null:
		return false

	if !is_available():
		return false

	customer = new_customer
	current_state = SeatState.RESERVED

	_update_drink_visual()
	_set_cleaning_interaction_enabled(false)

	return true


func begin_use(drink: DrinkData) -> void:
	if current_state != SeatState.RESERVED:
		push_warning(
			name
			+ " cannot begin use from state "
			+ str(current_state)
		)
		return

	if drink == null:
		push_error(
			name + " received empty DrinkData."
		)
		return

	active_drink = drink
	current_state = SeatState.IN_USE

	_update_drink_visual()
	_set_cleaning_interaction_enabled(false)

	print(
		get_table().name,
		"/",
		name,
		" now has ",
		active_drink.display_name,
		"."
	)


func require_cleaning() -> void:
	if current_state != SeatState.IN_USE:
		push_warning(
			name
			+ " cannot show an empty drink from state "
			+ str(current_state)
		)
		return

	customer = null
	current_state = SeatState.NEEDS_CLEANING

	set_occupied_zone_enabled(false)
	_update_drink_visual()
	_set_cleaning_interaction_enabled(true)

	print(
		get_table().name,
		"/",
		name,
		" now has an empty drink."
	)


func clean() -> void:
	if current_state != SeatState.NEEDS_CLEANING:
		return

	current_state = SeatState.AVAILABLE
	active_drink = null

	_update_drink_visual()
	_set_cleaning_interaction_enabled(false)

	print(
		get_table().name,
		"/",
		name,
		" was cleaned and is available again."
	)


func interact(_player: Node) -> void:
	if current_state != SeatState.NEEDS_CLEANING:
		return

	clean()


func clear_customer() -> void:
	customer = null
	active_drink = null
	current_state = SeatState.AVAILABLE

	set_occupied_zone_enabled(false)
	_update_drink_visual()
	_set_cleaning_interaction_enabled(false)
	

func contains_customer(target_customer: Node) -> bool:
	return customer == target_customer


func get_seat_position() -> Vector2:
	return seat_point.global_position


func get_table() -> Table:
	var chairs_container: Node = get_parent()

	if chairs_container == null:
		return null

	var possible_table: Node = chairs_container.get_parent()

	if possible_table is Table:
		return possible_table

	return null


func get_outward_direction() -> Vector2:
	var table: Table = get_table()

	if table == null:
		push_warning(
			name + " could not find its parent table."
		)
		return Vector2.DOWN

	var direction: Vector2 = (
		get_seat_position() - table.global_position
	).normalized()

	if direction == Vector2.ZERO:
		push_warning(
			name + " is positioned at the centre of its table."
		)
		return Vector2.DOWN

	return direction


func get_staging_position() -> Vector2:
	return (
		get_seat_position()
		+ get_outward_direction() * staging_distance
	)


func set_occupied_zone_enabled(enabled: bool) -> void:
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
		+ local_outward_direction * occupied_zone_offset
	)


func _set_cleaning_interaction_enabled(
	enabled: bool
) -> void:
	interaction_area.monitoring = enabled
	interaction_area.monitorable = enabled

	if enabled:
		interaction_area.collision_layer = 1
	else:
		interaction_area.collision_layer = 0


func _update_drink_visual() -> void:
	match current_state:
		SeatState.AVAILABLE:
			drink_sprite.visible = false

		SeatState.RESERVED:
			drink_sprite.visible = false

		SeatState.IN_USE:
			if active_drink == null:
				drink_sprite.visible = false
				return

			drink_sprite.texture = (
				active_drink.full_glass_texture
			)

			drink_sprite.visible = true

		SeatState.NEEDS_CLEANING:
			if active_drink == null:
				drink_sprite.visible = false
				return

			drink_sprite.texture = (
				active_drink.empty_glass_texture
			)

			drink_sprite.visible = true
