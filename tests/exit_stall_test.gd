extends Node

## Reproduces and guards the departure stall.
##
## Customers walked to an exit marker that sits OUTSIDE the navigation mesh.
## The agent stopped at the mesh edge and reported neither arrival nor failure,
## so the visit never ended: customers piled up in the doorway and held
## population slots, which read in game as "nobody is coming in".

var passed: int = 0
var failed: int = 0

var main: Node
var game_manager: Node


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	for _i in range(8):
		await get_tree().process_frame

	game_manager = main.get_node_or_null(^"Managers/GameManager")

	await _test_exit_point_is_off_the_navmesh()
	await _test_customer_at_exit_finishes()
	await _test_stranded_customer_times_out()

	_report()


func _door() -> CustomerDoor:
	return main.get_node_or_null(^"Markers/CustomerDoor") as CustomerDoor


func _spawn() -> Node:
	Tavern.open_early()
	game_manager.spawn_customer()

	await get_tree().process_frame

	var customers: Array[Node] = get_tree().get_nodes_in_group(
		&"navigation_customers"
	)

	return customers.back() if not customers.is_empty() else null


func _test_exit_point_is_off_the_navmesh() -> void:
	var door := _door()
	var exit_position: Vector2 = door.outside_point.global_position

	var map: RID = get_viewport().world_2d.navigation_map
	var closest: Vector2 = NavigationServer2D.map_get_closest_point(
		map, exit_position
	)

	var gap: float = exit_position.distance_to(closest)

	print("  exit marker %s, nearest navmesh point %s, gap %.1fpx" % [
		str(exit_position), str(closest), gap,
	])

	_check(
		true,
		"CAUSE: exit marker is %.0fpx from the navigable area%s" % [
			gap,
			" - unreachable by path, which is the bug" if gap > 1.0 else "",
		],
		""
	)


func _test_customer_at_exit_finishes() -> void:
	var customer: Node = await _spawn()

	_check(customer != null, "EXIT: a customer spawned", "EXIT: none spawned")

	var door := _door()

	# Put it where the stuck customers actually were: at the exit marker.
	(customer as Node2D).global_position = door.outside_point.global_position
	customer.set(&"entrance_outside_position", door.outside_point.global_position)
	customer.begin_leaving()

	# Force the exit leg directly, as reaching the door would.
	customer.begin_exiting()

	for _i in range(10):
		await get_tree().process_frame

	_check(
		not is_instance_valid(customer) or customer.is_queued_for_deletion(),
		"EXIT: a customer standing at the exit is removed",
		"EXIT: it is still here in state %s - the stall is back"
			% (Customer.State.keys()[customer.get(&"current_state")]
				if is_instance_valid(customer) else "?")
	)


func _test_stranded_customer_times_out() -> void:
	var customer: Node = await _spawn()

	if customer == null:
		_check(false, "", "TIMEOUT: no customer to test")
		return

	# Far from the exit and unable to path to it.
	(customer as Node2D).global_position = Vector2(-4000, -4000)
	customer.set(&"entrance_outside_position", Vector2(9000, 9000))
	customer.begin_exiting()

	await get_tree().process_frame

	_check(
		is_instance_valid(customer),
		"TIMEOUT: the stranded customer is still present before the timeout",
		"TIMEOUT: it vanished too early"
	)

	# Push past the timeout.
	WorldTime.advance_minutes(customer.get(&"exit_timeout_minutes") + 2)

	for _i in range(6):
		await get_tree().process_frame

	_check(
		not is_instance_valid(customer) or customer.is_queued_for_deletion(),
		"TIMEOUT: a customer that cannot reach the exit is removed anyway",
		"TIMEOUT: it is stuck forever, holding a population slot"
	)


func _check(condition: bool, pass_text: String, fail_text: String) -> void:
	if fail_text.is_empty() and condition:
		passed += 1
		print("  [INFO] " + pass_text)
		return

	if condition:
		passed += 1
		print("  [PASS] " + pass_text)
	else:
		failed += 1
		print("  [FAIL] " + fail_text)


func _report() -> void:
	print("")
	print("  passed: %d  failed: %d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
