extends Node

## Focused milestone test: one group of four, one shared Ale keg, in main.tscn.
##
## Loads the real playable scene, uses the production developer spawn path, and
## watches the whole loop through to cleanup. Deliberately small - it answers
## "does the group keg loop work in the game" and nothing else.

var passed: int = 0
var failed: int = 0

var main: Node
var manager: GroupManager
var spawner: GroupSpawner
var order_service: GroupOrderService
var game_manager: Node
var ale_station: DrinksStation


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	for _i: int in range(8):
		await get_tree().process_frame

	manager = main.get_node_or_null(^"Managers/GroupManager")
	spawner = main.get_node_or_null(^"Managers/GroupSpawner")
	order_service = main.get_node_or_null(^"Managers/GroupOrderService")
	game_manager = main.get_node_or_null(^"Managers/GameManager")
	ale_station = main.get_node_or_null(^"Environment/Ale_station")

	if manager != null:
		manager.log_state_changes = true

	_quieten_scene()
	_report_environment()

	await _test_main_scene_group_loop()
	await _test_spawn_recovery()
	await _test_insufficient_stock()

	_finish()


# --- Environment -------------------------------------------------------------

func _quieten_scene() -> void:
	# The navigation debugger floods stdout and buries every group line.
	for node: Node in get_tree().get_nodes_in_group(&"navigation_debugger"):
		node.set(&"enabled", false)

	var debugger: Node = main.get_node_or_null(^"NavigationDebugger")

	if debugger != null:
		debugger.set(&"enabled", false)

	# Automatic arrivals are re-enabled for the recovery test.
	if game_manager != null:
		game_manager.set(&"enable_automatic_group_arrivals", false)


func _report_environment() -> void:
	print("--- Environment ---")

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station == null:
			continue

		print(
			"  station %s: drink=%s content=%s caps=%s measures=%d" % [
				station.name,
				String(station.served_drink.item_id)
					if station.served_drink != null else "-",
				String(station.get_service_content_id()),
				str(station.station_capabilities),
				station.get_available_measures(),
			]
		)

	for node: Node in get_tree().get_nodes_in_group(&"group_standing_areas"):
		var area: GroupStandingArea = node as GroupStandingArea
		print(
			"  standing area %s free=%s (%d-%d)" % [
				String(area.area_id), str(area.is_free()),
				area.minimum_group_size, area.maximum_group_size,
			]
		)


# --- Test 1 ------------------------------------------------------------------

func _test_main_scene_group_loop() -> void:
	print("\n=== TEST 1: main scene group loop ===")

	var before: int = ale_station.get_available_measures() \
		if ale_station != null else -1

	var group: CustomerGroup = spawner.spawn_test_group(4)

	_check(group != null, "TEST1: a test group spawned")

	if group == null:
		return

	_check(
		group.get_valid_members().size() == 4,
		"TEST1: the group has four members (%d)"
			% group.get_valid_members().size()
	)
	_check(not group.group_id.is_empty(), "TEST1: the group has an id")
	_check(group.leader != null, "TEST1: the group has exactly one leader")

	var shared_ids: bool = true
	var spread: float = 0.0
	var first: Node2D = group.get_valid_members()[0] as Node2D

	for member: Node in group.get_valid_members():
		if StringName(String(member.get(&"group_id"))) != group.group_id:
			shared_ids = false

		var member_2d: Node2D = member as Node2D
		spread = maxf(
			spread, first.global_position.distance_to(member_2d.global_position)
		)

	_check(shared_ids, "TEST1: every member shares the group id")
	_check(spread <= 160.0, "TEST1: members spawn close together (%.0f px)" % spread)

	var registered: bool = true

	for member: Node in group.get_valid_members():
		if not _is_active_customer(member):
			registered = false

	_check(registered, "TEST1: members are registered as active customers")

	var trail: Array[String] = await _run_group(group, 180.0)

	var diagnostics: Dictionary = _last_diagnostics

	print("  state trail: %s" % " -> ".join(trail))
	print("  diagnostics: %s" % str(diagnostics))

	_check(
		trail.has("MOVING_TO_PLACE"),
		"TEST1: the group moved to one shared destination"
	)
	_check(
		String(diagnostics.get("destination_id", "")) != "",
		"TEST1: one destination was reserved (%s)"
			% String(diagnostics.get("destination_id", ""))
	)
	_check(
		int(diagnostics.get("keg_starting_portions", 0)) > 0,
		"TEST1: a shared keg was created with portions"
	)
	_check(
		String(diagnostics.get("keg_drink_id", "")) == "ale",
		"TEST1: the keg holds Ale (%s)"
			% String(diagnostics.get("keg_drink_id", ""))
	)

	var after: int = ale_station.get_available_measures() \
		if ale_station != null else -1

	_check(
		after < before,
		"TEST1: Ale stock decreased (%d -> %d)" % [before, after]
	)

	var consumed: Dictionary = diagnostics.get("portions_per_member", {})
	var drinkers: int = 0
	var total_portions: int = 0

	for key: Variant in consumed:
		if int(consumed[key]) > 0:
			drinkers += 1

		total_portions += int(consumed[key])

	_check(drinkers == 4, "TEST1: all four members drank (%d)" % drinkers)
	_check(
		total_portions == int(diagnostics.get("keg_starting_portions", 0)),
		"TEST1: portions consumed match the keg (%d)" % total_portions
	)
	_check(
		int(diagnostics.get("keg_remaining_portions", -1)) == 0,
		"TEST1: the keg finished empty"
	)
	_check(
		trail.has("LEAVING"), "TEST1: the group left together"
	)
	_check(
		trail.has("COMPLETE"),
		"TEST1: the visit completed rather than failing (%s)"
			% trail.back()
	)

	await _settle(3.0)

	_check(_count_shared_servings() == 0, "TEST1: the keg was cleaned up")
	_check(_all_areas_free(), "TEST1: the standing area was released")
	_check(
		manager.get_active_group_count() == 0,
		"TEST1: the group left the active registry"
	)
	_check(
		_active_customer_count() == 0,
		"TEST1: members left active customer tracking (%d)"
			% _active_customer_count()
	)


# --- Test 2 ------------------------------------------------------------------

func _test_spawn_recovery() -> void:
	print("\n=== TEST 2: spawn recovery ===")

	var known: Array[Node] = _current_customers()
	var solo: Node = null
	var waited: float = 0.0

	# The tavern may legitimately be full of seated solo customers, so this
	# retries rather than failing on the first busy moment.
	while waited < 60.0 and solo == null:
		game_manager.call(&"spawn_customer")
		await _settle(1.0)
		waited += 1.0

		for customer: Node in _current_customers():
			if not known.has(customer):
				solo = customer
				break

	_check(solo != null, "TEST2: a solo customer spawned after the group")

	if solo == null:
		return

	var served: bool = false
	var elapsed: float = 0.0

	while elapsed < 60.0 and is_instance_valid(solo):
		if solo.get(&"ordered_drink") != null or bool(solo.get(&"has_had_a_drink")):
			served = true
			break

		await get_tree().create_timer(0.25).timeout
		elapsed += 0.25

	_check(served, "TEST2: the solo customer reached its normal order flow")

	# Driven through the real F10 handler rather than by calling the spawner,
	# so the developer action itself is covered and not just the code beneath
	# it.
	var panel: Node = main.get_node_or_null(^"UI/GroupDiagnosticsPanel")
	var key_event: InputEventKey = InputEventKey.new()
	key_event.keycode = KEY_F10
	key_event.pressed = true

	_check(panel != null, "TEST2: the group diagnostics panel is in main.tscn")

	if panel != null:
		panel.call(&"_unhandled_input", key_event)
		await _settle(1.0)

	var group: CustomerGroup = manager.active_groups[0] \
		if not manager.active_groups.is_empty() else null

	_check(group != null, "TEST2: F10 spawned another test group")

	if group != null:
		group.begin_departure()
		await _settle(3.0)
		manager.abort_all_groups("test 2 teardown")
		await _settle(2.0)


# --- Test 3 ------------------------------------------------------------------

func _test_insufficient_stock() -> void:
	print("\n=== TEST 3: failure cleanup with insufficient stock ===")

	manager.abort_all_groups("test 3 setup")
	await _settle(2.0)

	var drained: Array[int] = []

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station == null:
			continue

		drained.append(station.draw_measures(station.get_available_measures()))

	print("  stations drained: %s" % str(drained))

	var group: CustomerGroup = spawner.spawn_test_group(4)

	_check(group != null, "TEST3: the group spawned")

	if group == null:
		return

	var trail: Array[String] = await _run_group(group, 120.0)
	var diagnostics: Dictionary = _last_diagnostics

	print("  state trail: %s" % " -> ".join(trail))
	print("  diagnostics: %s" % str(diagnostics))

	_check(
		String(diagnostics.get("order_failure_reason", "")).contains(
			"insufficient_stock"
		),
		"TEST3: a clear insufficient_stock reason was recorded (%s)"
			% String(diagnostics.get("order_failure_reason", ""))
	)
	_check(
		int(diagnostics.get("keg_starting_portions", 0)) == 0,
		"TEST3: no keg was created"
	)
	_check(
		int(diagnostics.get("amount_paid", -1)) == 0,
		"TEST3: the group was not charged (%d)"
			% int(diagnostics.get("amount_paid", -1))
	)

	await _settle(3.0)

	_check(_all_areas_free(), "TEST3: the destination was released")
	_check(
		manager.get_active_group_count() == 0,
		"TEST3: the group registry is clean"
	)
	_check(_count_shared_servings() == 0, "TEST3: no keg was left behind")


# --- Helpers -----------------------------------------------------------------

var _trail: Array[String] = []
var _last_diagnostics: Dictionary = {}


## Watches one group to completion.
##
## Driven by the group's own state_changed signal rather than by polling, so
## the final states are recorded even though the manager frees the group node
## on the sweep immediately afterwards.
func _run_group(group: CustomerGroup, timeout: float) -> Array[String]:
	_trail = [group.get_state_name()]
	_last_diagnostics = group.get_diagnostics()

	group.state_changed.connect(_on_watched_state_changed.bind(group))

	var elapsed: float = 0.0

	while elapsed < timeout:
		if not is_instance_valid(group):
			break

		_last_diagnostics = group.get_diagnostics()

		if group.is_finished():
			break

		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	return _trail


func _on_watched_state_changed(
	_previous: CustomerGroup.State,
	_current: CustomerGroup.State,
	group: CustomerGroup
) -> void:
	if not is_instance_valid(group):
		return

	var state_name: String = group.get_state_name()

	if _trail.is_empty() or _trail.back() != state_name:
		_trail.append(state_name)

	_last_diagnostics = group.get_diagnostics()


func _settle(seconds: float) -> void:
	var elapsed: float = 0.0

	while elapsed < seconds:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1


func _count_shared_servings() -> int:
	var count: int = 0

	for node: Node in get_tree().get_nodes_in_group(&"shared_servings"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			count += 1

	return count


func _all_areas_free() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"group_standing_areas"):
		var area: GroupStandingArea = node as GroupStandingArea

		if area != null and not area.is_free():
			return false

	return true


func _is_active_customer(member: Node) -> bool:
	if game_manager == null:
		return false

	var list: Variant = game_manager.get(&"active_customers")

	return list != null and list.has(member)


func _active_customer_count() -> int:
	if game_manager == null:
		return -1

	var list: Variant = game_manager.get(&"active_customers")

	return list.size() if list != null else -1


func _current_customers() -> Array[Node]:
	var customers: Array[Node] = []

	if game_manager == null:
		return customers

	var list: Variant = game_manager.get(&"active_customers")

	if list == null:
		return customers

	for entry: Variant in list:
		var customer: Node = entry as Node

		if customer != null and is_instance_valid(customer):
			customers.append(customer)

	return customers


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("  PASS  " + label)
	else:
		failed += 1
		print("  FAIL  " + label)


func _finish() -> void:
	print("\n=== RESULT: %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
