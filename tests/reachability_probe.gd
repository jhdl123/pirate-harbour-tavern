extends Node2D

## Answers two questions from the 9 Aug session reports:
##
## 1. bartender_02 logged 207 stuck_recoveries and 29 navigation failures, all
##    "could not reach Port Wine Station / Canary Wine Station / Stock Storage
##    (blocked)", and refill_station was 3 created / 0 claimed. A task nobody
##    can walk to is indistinguishable from a task nobody wants.
## 2. Casks appear in the storeroom but wine and bottles do not.
##
## Both are measured against the live navmesh and the live props, because a
## service position that reads fine in the scene file can still sit inside a
## collider or off the mesh entirely.

const MAX_OFF_MESH: float = 8.0

var passed: int = 0
var failed: int = 0
var main: Node = null


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout

	_check_station_reachability()
	_check_storage_reachability()
	_check_bottle_storage_wiring()

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
	var region: NavigationRegion2D = main.get_node(^"NavigationRegion2D")

	return region.get_navigation_map()


## Distance from [param point] to the nearest walkable spot.
func _off_mesh(point: Vector2) -> float:
	var nearest: Vector2 = NavigationServer2D.map_get_closest_point(_map(), point)

	if nearest.is_zero_approx():
		return 9999.0

	return nearest.distance_to(point)


## Whether a staff member standing on the floor could path to [param point].
func _is_reachable(point: Vector2) -> bool:
	var floor_point := Vector2(600, 400)
	var path: PackedVector2Array = NavigationServer2D.map_get_path(
		_map(), floor_point, point, true
	)

	if path.size() < 2:
		return false

	return path[path.size() - 1].distance_to(point) < 32.0


func _check_station_reachability() -> void:
	print("--- station service positions ---")

	for node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation
		# Staff approach via the Interactable, not the station body.
		var point: Vector2 = (
			station.interactable.get_interaction_position(Vector2(600, 400))
			if station.interactable != null
			else station.global_position
		)
		var off: float = _off_mesh(point)

		print("  %-20s at %s  off-mesh %.1fpx  reachable %s" % [
			station.name, str(point), off, _is_reachable(point),
		])

		_ok("%s service point is on the navmesh" % station.name,
			off <= MAX_OFF_MESH, "%.1fpx off" % off)
		_ok("%s is reachable from the floor" % station.name,
			_is_reachable(point))


func _check_storage_reachability() -> void:
	print("--- storage service positions ---")

	for node in get_tree().get_nodes_in_group(&"stock_storage"):
		var storage: Node2D = node as Node2D
		var point: Vector2 = (
			storage.get_interaction_position()
			if storage.has_method("get_interaction_position")
			else storage.global_position
		)
		var off: float = _off_mesh(point)

		print("  %-20s at %s  off-mesh %.1fpx  reachable %s" % [
			storage.name, str(point), off, _is_reachable(point),
		])

		_ok("%s is reachable from the floor" % storage.name,
			_is_reachable(point), "%.1fpx off mesh" % off)


func _check_bottle_storage_wiring() -> void:
	print("--- storeroom props ---")

	var registry: BeverageRegistry = main.get_node(^"Managers/Cellar").registry

	for node in get_tree().get_nodes_in_group(&"stocked_display"):
		var prop: StockedDisplay = node as StockedDisplay

		if prop == null or not prop.storage_backed:
			continue

		var container: ContainerDefinition = registry.get_container(
			prop.container_id
		)
		var capacity: int = prop.get_unit_capacity()

		print("  %-22s content=%-12s container=%-10s units=%d" % [
			prop.name, String(prop.content_id), String(prop.container_id), capacity,
		])

		_ok("%s resolves its container" % prop.name, container != null,
			"container_id '%s' not in the registry" % String(prop.container_id))

		# A prop with one unit offset can only ever show "some" or "none",
		# which is why casks read clearly and crates do not.
		_ok("%s can show more than one unit" % prop.name, capacity > 1,
			"only %d unit offset(s) - stock level is invisible" % capacity)

		var point: Vector2 = prop.global_position
		_ok("%s sits on reachable floor" % prop.name,
			_off_mesh(point) < 64.0, "%.1fpx from the mesh" % _off_mesh(point))
