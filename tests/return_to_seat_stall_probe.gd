extends Node

## Live instrumentation for the 64-152 minute return-to-seat gaps found in
## docs/history/2026-08-25_BEHAVIOURAL_EVALUATION.md. Read-only - queries
## only existing public getters (Customer.current_state, ActorNavigation's
## get_state()/is_travelling()/is_parked()/get_recovery_attempts()), adds
## no new tracking to any customer_ai/gameplay file. Watches every live
## customer's time-in-state and dumps a full diagnostic snapshot the moment
## any of them exceeds STALL_THRESHOLD_MINUTES without a state change -
## catching a stall while it is happening, rather than reconstructing one
## after the fact from VisitRecord's coarser state_trail.

const RUN_SECONDS: float = 420.0
const SAMPLE_SECONDS: float = 1.0
const SPAWN_UNTIL: float = 360.0
const STALL_THRESHOLD_MINUTES: float = 20.0

## runtime_customer_id -> {"state": String, "since": float, "reported": bool}
var _state_by_customer: Dictionary = {}
var _stalls_caught: int = 0


func _ready() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	for _i: int in range(10):
		await get_tree().process_frame

	for node: Node in get_tree().get_nodes_in_group(&"navigation_debugger"):
		node.set(&"enabled", false)

	var game_manager: Node = main.get_node_or_null(^"Managers/GameManager")

	if not Tavern.is_accepting_arrivals():
		Tavern.open_early()

	var elapsed: float = 0.0

	while elapsed < RUN_SECONDS:
		if (
			game_manager != null
			and game_manager.has_method("spawn_customer")
			and elapsed < SPAWN_UNTIL
		):
			game_manager.call("spawn_customer")

		await get_tree().create_timer(SAMPLE_SECONDS).timeout
		elapsed += SAMPLE_SECONDS
		_sample()

	print("")
	print("=== RETURN-TO-SEAT STALL PROBE: RESULT ===")
	print("stalls caught (state unchanged for >= ", STALL_THRESHOLD_MINUTES, " game-minutes): ", _stalls_caught)
	print("=== END RETURN-TO-SEAT STALL PROBE ===")
	get_tree().quit()


func _sample() -> void:
	var world_minutes: float = WorldTime.get_total_minutes()

	for customer: Node in get_tree().get_nodes_in_group(&"navigation_customers"):
		if not is_instance_valid(customer):
			continue

		var runtime_id: Variant = customer.get("runtime_customer_id")

		if runtime_id == null:
			continue

		var state_value: Variant = customer.get("current_state")

		if state_value == null:
			continue

		var state_name: String = (
			Customer.State.keys()[int(state_value)]
			if int(state_value) < Customer.State.keys().size() else "?"
		)

		var record: Dictionary = _state_by_customer.get(runtime_id, {})

		if record.is_empty() or record.get("state") != state_name:
			_state_by_customer[runtime_id] = {
				"state": state_name,
				"since": world_minutes,
				"reported": false,
			}
			continue

		var elapsed_in_state: float = world_minutes - float(record["since"])

		if elapsed_in_state >= STALL_THRESHOLD_MINUTES and not record["reported"]:
			record["reported"] = true
			_state_by_customer[runtime_id] = record
			_stalls_caught += 1
			_dump_stall(customer, runtime_id, state_name, elapsed_in_state, world_minutes)


func _dump_stall(
	customer: Node,
	runtime_id: Variant,
	state_name: String,
	elapsed_in_state: float,
	world_minutes: float
) -> void:
	print("")
	print("################ STALL CAUGHT ################")
	print(
		"customer ", runtime_id, " (", customer.name, ") stuck in ",
		state_name, " for ", "%.1f" % elapsed_in_state,
		" game-minutes (now t=", "%.1f" % world_minutes, ")"
	)

	var nav: Object = customer.get("actor_navigation")

	if nav != null:
		print(
			"  navigation: state=", nav.call("get_state"),
			"  is_travelling=", nav.call("is_travelling"),
			"  is_parked=", nav.call("is_parked"),
			"  recovery_attempts=", nav.call("get_recovery_attempts")
		)
	else:
		print("  navigation: <no actor_navigation found on this customer>")

	print("  global_position: ", customer.get("global_position"))

	var reserved_chair: Object = customer.get("reserved_chair")
	if reserved_chair != null and reserved_chair.has_method("get_seat_position"):
		print(
			"  reserved_chair seat_position: ",
			reserved_chair.call("get_seat_position"),
			"  distance_to_seat: ",
			(customer.get("global_position") as Vector2).distance_to(
				reserved_chair.call("get_seat_position")
			)
		)

	var brain: Object = customer.get("_brain")
	if brain != null:
		print(
			"  brain.state=", brain.get("state"),
			"  current_activity=",
			(
				brain.call("get_current_activity").get("activity_id")
				if brain.call("get_current_activity") != null else "<none>"
			)
		)

	var needs: Object = customer.get("needs")
	if needs != null:
		print(
			"  needs: thirst=", needs.get("thirst"),
			" remaining_visit_minutes=", needs.get("remaining_visit_minutes")
		)

	print("  is_processing: ", customer.is_processing())
	print("  is_physics_processing: ", customer.is_physics_processing())
	print("################################################")
