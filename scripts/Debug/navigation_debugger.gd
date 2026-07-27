class_name NavigationDebugger
extends Node

@export_category("Recording")
@export var enabled: bool = true
@export var snapshot_interval: float = 0.25
@export var customer_group_name: StringName = &"navigation_customers"

@export_category("Visual Debug")
@export var show_agent_paths: bool = true
@export var print_important_events: bool = true

const DEBUG_FILE_PATH: String = "user://navigation_debug.csv"

var debug_file: FileAccess
var elapsed_since_snapshot: float = 0.0
var recording_start_time: int = 0

var previous_states: Dictionary = {}
var previous_path_signatures: Dictionary = {}
var previous_map_iterations: Dictionary = {}
var previous_collision_signatures: Dictionary = {}


func _ready() -> void:
	if !enabled:
		return

	recording_start_time = Time.get_ticks_msec()

	debug_file = FileAccess.open(
		DEBUG_FILE_PATH,
		FileAccess.WRITE
	)

	if debug_file == null:
		push_error(
			"Could not create navigation debug file at: "
			+ DEBUG_FILE_PATH
		)
		return

	_write_header()

	print("")
	print("==============================================")
	print("NAVIGATION DEBUG RECORDING STARTED")
	print("File: ", ProjectSettings.globalize_path(DEBUG_FILE_PATH))
	print("Run the game until the problem happens.")
	print("Then stop the game and send this CSV file.")
	print("==============================================")
	print("")


func _exit_tree() -> void:
	if debug_file != null:
		debug_file.flush()
		debug_file.close()


func _physics_process(delta: float) -> void:
	if !enabled:
		return

	if debug_file == null:
		return

	elapsed_since_snapshot += delta

	var customers: Array[Node] = get_tree().get_nodes_in_group(
		customer_group_name
	)

	for customer: Node in customers:
		if !is_instance_valid(customer):
			continue

		_configure_visual_debug(customer)
		_record_important_changes(customer)

	if elapsed_since_snapshot < snapshot_interval:
		return

	elapsed_since_snapshot = 0.0

	for customer: Node in customers:
		if is_instance_valid(customer):
			_record_customer_snapshot(customer)

	debug_file.flush()


func _write_header() -> void:
	var columns: PackedStringArray = [
		"time_seconds",
		"physics_frame",
		"customer",
		"state",
		"position_x",
		"position_y",
		"velocity_x",
		"velocity_y",
		"speed",
		"chair",
		"approach_x",
		"approach_y",
		"seat_x",
		"seat_y",
		"active_target_x",
		"active_target_y",
		"target_distance",
		"approach_mesh_distance",
		"seat_mesh_distance",
		"map_iteration",
		"map_active",
		"has_destination",
		"navigation_state",
		"destination_label",
		"desired_speed",
		"safe_speed",
		"applied_gap",
		"final_approach_radius",
		"in_final_approach",
		"recovery_attempts",
		"world_time_scale",
		"actual_speed",
		"path_reachable",
		"navigation_finished",
		"target_reached",
		"path_index",
		"path_point_count",
		"next_path_x",
		"next_path_y",
		"distance_to_next_path",
		"avoidance_enabled",
		"agent_radius",
		"neighbor_distance",
		"max_neighbors",
		"time_horizon_agents",
		"time_horizon_obstacles",
		"avoidance_priority",
		"collision_layer",
		"collision_mask",
		"slide_collision_count",
		"colliders",
		"path_points"
	]

	debug_file.store_line(",".join(columns))


func _record_customer_snapshot(customer: Node) -> void:
	var navigation_agent: NavigationAgent2D = (
		_get_navigation_agent(customer)
	)

	if navigation_agent == null:
		return

	var navigation_map: RID = navigation_agent.get_navigation_map()
	var map_iteration: int = (
		NavigationServer2D.map_get_iteration_id(navigation_map)
	)
	var map_active: bool = (
		NavigationServer2D.map_is_active(navigation_map)
	)

	var chair: Node = customer.get("reserved_chair")

	var chair_name: String = ""
	var approach_position: Vector2 = Vector2.ZERO
	var seat_position: Vector2 = Vector2.ZERO

	if is_instance_valid(chair):
		chair_name = str(chair.get_path())

		if chair.has_method("get_approach_position"):
			approach_position = chair.get_approach_position()
		elif chair.has_method("get_staging_position"):
			approach_position = chair.get_staging_position()

		if chair.has_method("get_seat_position"):
			seat_position = chair.get_seat_position()

	# The customer no longer tracks its own target. Navigation state lives on
	# the ActorNavigation component, which is what this now observes.
	var actor_navigation: ActorNavigation = _get_actor_navigation(
		customer
	)

	var active_target: Vector2 = customer.global_position
	var has_destination: bool = false
	var destination_label: String = ""
	var navigation_state: String = "no_component"

	# These five are what separate "the actor is blocked" from "the actor is
	# being told to move at zero". The first debug pass could not tell them
	# apart, which cost a round trip.
	var desired_speed: float = 0.0
	var safe_speed: float = 0.0
	var final_approach_radius: float = 0.0
	var in_final_approach: bool = false
	var recovery_attempts: int = 0

	# The body's velocity is restored to unscaled units after move_and_slide,
	# so the plain speed column under-reports during fast-forward. These two
	# make the real motion legible.
	var world_time_scale: float = 1.0
	var actual_speed: float = 0.0

	if actor_navigation != null:
		navigation_state = _navigation_state_name(
			actor_navigation.get_state()
		)

		var destination: NavigationDestination = (
			actor_navigation.get_destination()
		)

		desired_speed = actor_navigation.get_desired_velocity().length()
		safe_speed = actor_navigation.get_safe_velocity().length()

		final_approach_radius = (
			actor_navigation.get_final_approach_radius()
		)

		in_final_approach = actor_navigation.is_in_final_approach()
		recovery_attempts = actor_navigation.get_recovery_attempts()

		world_time_scale = actor_navigation.get_agent_velocity_scale()
		actual_speed = customer.velocity.length() * world_time_scale

		if destination != null:
			has_destination = true
			active_target = destination.position
			destination_label = destination.get_label()

	var closest_approach_point: Vector2 = Vector2.ZERO
	var closest_seat_point: Vector2 = Vector2.ZERO

	if navigation_map.is_valid():
		closest_approach_point = (
			NavigationServer2D.map_get_closest_point(
				navigation_map,
				approach_position
			)
		)

		closest_seat_point = (
			NavigationServer2D.map_get_closest_point(
				navigation_map,
				seat_position
			)
		)

	var approach_mesh_distance: float = (
		approach_position.distance_to(closest_approach_point)
	)

	var seat_mesh_distance: float = (
		seat_position.distance_to(closest_seat_point)
	)

	var current_path: PackedVector2Array = (
		navigation_agent.get_current_navigation_path()
	)

	var path_index: int = (
		navigation_agent.get_current_navigation_path_index()
	)

	var next_path_position: Vector2 = (
		navigation_agent.get_next_path_position()
	)

	var collision_names: PackedStringArray = (
		_get_collision_names(customer)
	)

	var values: PackedStringArray = [
		_decimal(_elapsed_seconds()),
		str(Engine.get_physics_frames()),
		_csv_escape(customer.name),
		_csv_escape(_get_state_name(customer)),
		_decimal(customer.global_position.x),
		_decimal(customer.global_position.y),
		_decimal(customer.velocity.x),
		_decimal(customer.velocity.y),
		_decimal(customer.velocity.length()),
		_csv_escape(chair_name),
		_decimal(approach_position.x),
		_decimal(approach_position.y),
		_decimal(seat_position.x),
		_decimal(seat_position.y),
		_decimal(active_target.x),
		_decimal(active_target.y),
		_decimal(customer.global_position.distance_to(active_target)),
		_decimal(approach_mesh_distance),
		_decimal(seat_mesh_distance),
		str(map_iteration),
		str(map_active),
		str(has_destination),
		_csv_escape(navigation_state),
		_csv_escape(destination_label),
		_decimal(desired_speed),
		_decimal(safe_speed),
		_decimal(desired_speed - safe_speed),
		_decimal(final_approach_radius),
		str(in_final_approach),
		str(recovery_attempts),
		_decimal(world_time_scale),
		_decimal(actual_speed),
		str(navigation_agent.is_target_reachable()),
		str(navigation_agent.is_navigation_finished()),
		str(navigation_agent.is_target_reached()),
		str(path_index),
		str(current_path.size()),
		_decimal(next_path_position.x),
		_decimal(next_path_position.y),
		_decimal(
			customer.global_position.distance_to(
				next_path_position
			)
		),
		str(navigation_agent.avoidance_enabled),
		_decimal(navigation_agent.radius),
		_decimal(navigation_agent.neighbor_distance),
		str(navigation_agent.max_neighbors),
		_decimal(navigation_agent.time_horizon_agents),
		_decimal(navigation_agent.time_horizon_obstacles),
		_decimal(navigation_agent.avoidance_priority),
		str(customer.collision_layer),
		str(customer.collision_mask),
		str(customer.get_slide_collision_count()),
		_csv_escape("; ".join(collision_names)),
		_csv_escape(_path_to_string(current_path))
	]

	debug_file.store_line(",".join(values))


func _record_important_changes(customer: Node) -> void:
	var navigation_agent: NavigationAgent2D = (
		_get_navigation_agent(customer)
	)

	if navigation_agent == null:
		return

	var customer_id: int = customer.get_instance_id()
	var state_name: String = _get_state_name(customer)

	var navigation_map: RID = navigation_agent.get_navigation_map()
	var map_iteration: int = (
		NavigationServer2D.map_get_iteration_id(navigation_map)
	)

	var current_path: PackedVector2Array = (
		navigation_agent.get_current_navigation_path()
	)

	var path_signature: String = _path_to_string(current_path)
	var collision_signature: String = "; ".join(
		_get_collision_names(customer)
	)

	if (
		!previous_states.has(customer_id)
		or previous_states[customer_id] != state_name
	):
		_print_event(
			customer,
			"STATE",
			state_name
		)

		previous_states[customer_id] = state_name

	if (
		!previous_map_iterations.has(customer_id)
		or previous_map_iterations[customer_id] != map_iteration
	):
		_print_event(
			customer,
			"MAP ITERATION",
			str(map_iteration)
		)

		previous_map_iterations[customer_id] = map_iteration

	if (
		!previous_path_signatures.has(customer_id)
		or previous_path_signatures[customer_id] != path_signature
	):
		_print_event(
			customer,
			"PATH CHANGED",
			"points=%d path=%s"
			% [
				current_path.size(),
				path_signature
			]
		)

		previous_path_signatures[customer_id] = path_signature

	if (
		collision_signature != ""
		and (
			!previous_collision_signatures.has(customer_id)
			or previous_collision_signatures[customer_id]
			!= collision_signature
		)
	):
		_print_event(
			customer,
			"COLLISION",
			collision_signature
		)

		previous_collision_signatures[customer_id] = (
			collision_signature
		)


func _configure_visual_debug(customer: Node) -> void:
	if !show_agent_paths:
		return

	var navigation_agent: NavigationAgent2D = (
		_get_navigation_agent(customer)
	)

	if navigation_agent == null:
		return

	navigation_agent.debug_enabled = true
	navigation_agent.debug_path_custom_point_size = 6.0


## The navigation component on an actor, or null.
##
## Looked up by node name rather than by type search, to match how this file
## already finds the NavigationAgent2D.
func _get_actor_navigation(
	customer: Node
) -> ActorNavigation:
	if customer == null or not is_instance_valid(customer):
		return null

	return customer.get_node_or_null(
		"ActorNavigation"
	) as ActorNavigation


func _navigation_state_name(
	state: ActorNavigation.NavigationState
) -> String:
	match state:
		ActorNavigation.NavigationState.IDLE:
			return "idle"

		ActorNavigation.NavigationState.TRAVELLING:
			return "travelling"

		ActorNavigation.NavigationState.SIDESTEPPING:
			return "sidestepping"

		ActorNavigation.NavigationState.PARKED:
			return "parked"

		_:
			return "unknown"


func _get_navigation_agent(
	customer: Node
) -> NavigationAgent2D:
	var agent: Node = customer.get_node_or_null(
		"NavigationAgent2D"
	)

	if agent is NavigationAgent2D:
		return agent

	return null


func _get_collision_names(
	customer: CharacterBody2D
) -> PackedStringArray:
	var collision_names: PackedStringArray = []

	for collision_index: int in range(
		customer.get_slide_collision_count()
	):
		var collision: KinematicCollision2D = (
			customer.get_slide_collision(collision_index)
		)

		if collision == null:
			continue

		var collider: Object = collision.get_collider()

		var collider_name: String = "<unknown>"

		if collider is Node:
			collider_name = str(collider.get_path())
		elif collider != null:
			collider_name = collider.get_class()

		var normal: Vector2 = collision.get_normal()

		collision_names.append(
			"%s normal=(%.2f, %.2f)"
			% [
				collider_name,
				normal.x,
				normal.y
			]
		)

	return collision_names


func _get_state_name(customer: Node) -> String:
	var raw_state: Variant = customer.get(
		"current_state"
	)

	if raw_state == null:
		return "UNKNOWN"

	var state_value: int = int(raw_state)

	match state_value:
		0:
			return "ENTERING"
		1:
			return "WALKING_TO_STAGING"
		2:
			return "MOVING_TO_SEAT"
		3:
			return "WAITING_TO_ORDER"
		4:
			return "ORDERING"
		5:
			return "DRINKING"
		6:
			return "LEAVING_TO_DOOR"
		7:
			return "EXITING"
		_:
			return "UNKNOWN_%d" % state_value

func _path_to_string(
	path: PackedVector2Array
) -> String:
	var points: PackedStringArray = []

	for point: Vector2 in path:
		points.append(
			"(%.1f %.1f)" % [point.x, point.y]
		)

	return " -> ".join(points)


func _print_event(
	customer: Node,
	event_name: String,
	details: String
) -> void:
	if !print_important_events:
		return

	print(
		"[NAV DEBUG ",
		_decimal(_elapsed_seconds()),
		"s] ",
		customer.name,
		" | ",
		event_name,
		" | ",
		details
	)


func _elapsed_seconds() -> float:
	return (
		Time.get_ticks_msec() - recording_start_time
	) / 1000.0


func _decimal(value: float) -> String:
	return "%.3f" % value


func _csv_escape(value: String) -> String:
	return "\"" + value.replace("\"", "\"\"") + "\""
