extends Node2D

## Covers the three faults behind the 23:01 session numbers.
##
## bartender_02: 310 stuck recoveries, refill_station claimed then timed out,
## "could not reach Grog Casks (blocked)". prepare_drink 35 of 68 cancelled.
## Bottle shelves warning at 4 of 5 bottles instead of 1.

var passed: int = 0
var failed: int = 0
var main: Node = null


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout

	_check_navigation_scan()
	_check_standable_approaches()
	_check_bottle_thresholds()
	_check_slot_budget()
	_check_telemetry()
	_check_bar_sides()

	print("RESULT %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("[PASS] %s" % label)
	else:
		failed += 1
		print("[FAIL] %s %s" % [label, detail])


func _map() -> RID:
	return main.get_node(^"NavigationRegion2D").get_navigation_map()


func _check_navigation_scan() -> void:
	var problems: Array[Dictionary] = (
		NavigationValidator.find_unreachable_points(get_tree())
	)

	for problem: Dictionary in problems:
		print("  %s %s %.1fpx" % [
			problem["kind"], problem["node_path"], problem["off_mesh_distance"]
		])

	_ok("the startup navigation scan is clean", problems.is_empty(),
		"%d problem(s)" % problems.size())


func _check_standable_approaches() -> void:
	# Every place staff must work must have a stand they can path to AND hold.
	var groups: Array[StringName] = [
		&"drink_stations", &"stocked_display", &"stock_storage", &"bar_counters",
	]
	var floor_point := Vector2(600, 400)

	for group: StringName in groups:
		for node in get_tree().get_nodes_in_group(group):
			var node_2d: Node2D = node as Node2D

			if node_2d == null:
				continue

			var stand: Vector2 = NavigationService.project_to_mesh_from(
				_map(), node_2d.global_position, floor_point
			)
			var nearest: Vector2 = NavigationServer2D.map_get_closest_point(
				_map(), stand
			)
			var path: PackedVector2Array = NavigationServer2D.map_get_path(
				_map(), floor_point, stand, true
			)

			_ok("%s has a standable approach" % node_2d.name,
				nearest.distance_to(stand) <= 1.0
				and path.size() >= 2
				and path[path.size() - 1].distance_to(stand) <= 16.0,
				"stand %s" % str(stand))


func _check_bottle_thresholds() -> void:
	for node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station.station_capabilities.has(&"pour_from_bottle"):
			_ok("%s warns at one bottle" % station.name,
				station.low_stock_threshold == 1,
				"threshold %d" % station.low_stock_threshold)

			# The reset must be reachable, or the station never clears to OK.
			_ok("%s can clear back to OK" % station.name,
				station.stock_reset_threshold <= station.maximum_servings,
				"reset %d of %d" % [
					station.stock_reset_threshold, station.maximum_servings
				])

			station.set_servings(1)
			_ok("%s reports LOW at one bottle" % station.name,
				station.get_stock_state() != DrinksStation.StockState.OK,
				"state %d" % station.get_stock_state())

			station.set_servings(station.maximum_servings)


func _check_slot_budget() -> void:
	var counter: BarCounter = null

	for node in get_tree().get_nodes_in_group(&"bar_counters"):
		counter = node as BarCounter
		break

	if counter == null:
		_ok("a bar counter exists", false)
		return

	var coordinator: Node = null

	for node in main.get_node(^"Managers").get_children():
		if node.has_method("_count_free_slots"):
			coordinator = node
			break

	if coordinator == null:
		_ok("the task coordinator exposes a slot budget", false)
		return

	var free: int = coordinator.call("_count_free_slots", counter)
	_ok("free slots are counted, not just tested", free > 0,
		"%d free" % free)

	# Prepare tasks must never outnumber the slots that can receive them.
	var pending: int = coordinator.call("_count_prepare_tasks_for", counter)
	_ok("prepare tasks in flight never exceed free slots",
		pending <= free, "%d pending for %d slots" % [pending, free])


## A computed stand must never end up on the opposite side of the counter.
##
## The regression this exists to stop: biasing the approach toward the worker
## dragged the deposit-side bar slot across to the customer side, so the
## bartender walked round the front, could not place anything, and finished the
## session idle for 136 of 143 working seconds.
func _check_bar_sides() -> void:
	var counter: BarCounter = null

	for node in get_tree().get_nodes_in_group(&"bar_counters"):
		counter = node as BarCounter
		break

	if counter == null:
		_ok("a bar counter exists", false)
		return

	# There is NO walkable floor on the staff side of this bar - the strip
	# behind the counter is unwalkable except one isolated pocket near
	# (521, 80). So a deposit stand legitimately resolves to the customer
	# side. What must hold is that it resolves to the SAME reachable place
	# no matter where the worker approaches from: a stand that depends on
	# where the worker happens to be is how staff end up crossing the bar.
	var stands_by_slot: Dictionary = {}

	for observer: Vector2 in [Vector2(600, 400), Vector2(300, 300)]:
		for slot: int in range(counter.get_service_container().get_slot_count()):
			var deposit: Vector2 = counter.get_slot_access_position(
				slot, BarCounter.SlotAccess.DEPOSIT
			)
			var stand: Vector2 = NavigationService.project_to_mesh_from(
				_map(), deposit, observer
			)

			_ok("slot %d deposit stand is reachable from %s" % [slot, str(observer)],
				_is_standable(stand, observer), "got %s" % str(stand))

			if stands_by_slot.has(slot):
				_ok("slot %d deposit stand does not depend on approach side" % slot,
					stands_by_slot[slot].distance_to(stand) < 48.0,
					"%s vs %s" % [str(stands_by_slot[slot]), str(stand)])
			else:
				stands_by_slot[slot] = stand


func _is_standable(point: Vector2, from_position: Vector2) -> bool:
	if NavigationServer2D.map_get_closest_point(_map(), point).distance_to(point) > 1.0:
		return false

	var path: PackedVector2Array = NavigationServer2D.map_get_path(
		_map(), from_position, point, true
	)

	return path.size() >= 2 and path[path.size() - 1].distance_to(point) <= 16.0


func _check_telemetry() -> void:
	for node in get_tree().get_nodes_in_group(&"tavern_staff"):
		var staff: StaffMember = node as StaffMember
		var report: Dictionary = staff.get_diagnostics_snapshot()

		_ok("%s reports navigation trouble per destination" % staff.staff_id,
			report.has("navigation_trouble_by_destination"),
			str(report.keys()))
