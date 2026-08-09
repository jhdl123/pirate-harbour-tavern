class_name NavigationValidator
extends RefCounted

## Finds destinations actors can never quite reach.
##
## [b]Why this exists.[/b] A seat, service slot or formation position sitting
## a few pixels off the navigation mesh does not throw anything. The agent
## projects the target onto the mesh, walks to the projection, and stops
## short of where the gameplay code is waiting for it - so the symptom is an
## actor that appears to arrive but never triggers arrival, which reads as a
## navigation bug rather than a level-data one. `chairRight` on both tables
## was exactly this for weeks.
##
## Static and read-only: this measures, it never moves anything. Fixing a
## reported point is a deliberate edit to the scene, because nudging a seat
## automatically would silently change where customers sit.


## Distance beyond which a point is treated as off-mesh. Anything under a
## couple of pixels is projection noise rather than a real gap.
const OFF_MESH_TOLERANCE: float = 2.0


## Every problem point in the tree. Each entry has node_path, position,
## off_mesh_distance and kind.
##
## [param tree] supplies the navigation map. Groups are used rather than a
## recursive walk because the reservation and formation systems already
## register their points, and a full tree walk would also pick up decorative
## markers nothing ever navigates to.
static func find_unreachable_points(tree: SceneTree) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []

	if tree == null:
		return problems

	var map: RID = tree.root.world_2d.navigation_map

	if not map.is_valid():
		return problems

	if NavigationServer2D.map_get_regions(map).is_empty():
		# No regions means map_get_closest_point() returns the origin for
		# every query, which would report the entire tavern as broken.
		push_warning(
			"NavigationValidator ran before the navigation map had regions."
		)
		return problems

	_check_seats(tree, map, problems)
	_check_group_places(tree, map, problems)
	_check_service_slots(tree, map, problems)
	_check_approachable(tree, map, problems)

	return problems


## Checks that staff can actually STAND at everything they must walk to.
##
## Distinct from the off-mesh checks above, which ask "is this point walkable".
## A storeroom cask stack is meant to sit off the mesh - it is furniture. The
## question that matters is whether the approach the executors compute lands
## somewhere an actor can hold position, and whether that spot is within reach
## of the object. Both storeroom restock stalls came from a stand the worker
## could touch but never settle on.
static func _check_approachable(
	tree: SceneTree,
	map: RID,
	problems: Array[Dictionary]
) -> void:
	var groups: Array[StringName] = [
		&"drink_stations", &"stocked_display", &"stock_storage",
		&"bar_counters", &"tavern_activity_points",
	]

	var floor_point: Vector2 = _floor_reference(map)

	for group: StringName in groups:
		for node: Node in tree.get_nodes_in_group(group):
			var node_2d: Node2D = node as Node2D

			if node_2d == null:
				continue

			var stand: Vector2 = NavigationService.project_to_mesh_from(
				map, node_2d.global_position, floor_point
			)

			# The question is not how far the stand is from the object - a
			# cask stack is furniture and staff are meant to stand beside it.
			# It is whether an actor can PATH there and HOLD it. A point on a
			# polygon edge fails both, silently, forever.
			if _is_standable(map, stand, floor_point):
				continue

			problems.append({
				"node_path": String(node_2d.get_path()),
				"kind": "approach for %s" % String(group),
				"position": node_2d.global_position,
				"nearest_navmesh": stand,
				"off_mesh_distance": stand.distance_to(node_2d.global_position),
			})


## Whether an actor could walk to [param point] and stay on it.
static func _is_standable(
	map: RID,
	point: Vector2,
	from_position: Vector2
) -> bool:
	if NavigationServer2D.map_get_closest_point(map, point).distance_to(point) > 1.0:
		return false

	var path: PackedVector2Array = NavigationServer2D.map_get_path(
		map, from_position, point, true
	)

	if path.size() < 2:
		return false

	return path[path.size() - 1].distance_to(point) <= APPROACH_ARRIVAL_TOLERANCE


## A point known to be on the mesh, used to bias approach projections.
static func _floor_reference(map: RID) -> Vector2:
	var regions: Array[RID] = NavigationServer2D.map_get_regions(map)

	if regions.is_empty():
		return Vector2.ZERO

	return NavigationServer2D.map_get_closest_point(map, Vector2(600, 400))


static func _check_seats(
	tree: SceneTree,
	map: RID,
	problems: Array[Dictionary]
) -> void:
	for node: Node in tree.get_nodes_in_group(&"interactable"):
		var owner_node: Node = node.get_parent()

		if owner_node == null or not owner_node.has_method("get_seat_position"):
			continue

		_test_point(
			map,
			owner_node.call("get_seat_position"),
			owner_node.get_path(),
			"seat",
			problems
		)


static func _check_group_places(
	tree: SceneTree,
	map: RID,
	problems: Array[Dictionary]
) -> void:
	for node: Node in tree.get_nodes_in_group(&"group_standing_area"):
		if not node.has_method("get_formation_positions"):
			continue

		var positions: Variant = node.call("get_formation_positions", 6)

		if not (positions is Array):
			continue

		var index: int = 0

		for position: Variant in positions:
			if position is Vector2:
				_test_point(
					map,
					position,
					node.get_path(),
					"formation slot %d" % index,
					problems
				)

			index += 1


static func _check_service_slots(
	tree: SceneTree,
	map: RID,
	problems: Array[Dictionary]
) -> void:
	for node: Node in tree.get_nodes_in_group(&"drink_stations"):
		if not node.has_method("get_serving_position"):
			continue

		_test_point(
			map,
			node.call("get_serving_position"),
			node.get_path(),
			"serving position",
			problems
		)


static func _test_point(
	map: RID,
	position: Vector2,
	path: NodePath,
	kind: String,
	problems: Array[Dictionary]
) -> void:
	if not (position is Vector2):
		return

	var closest: Vector2 = NavigationServer2D.map_get_closest_point(
		map, position
	)

	# A zero result means the query failed, not that the point is at 0,0.
	if closest.is_zero_approx() and not position.is_zero_approx():
		return

	var distance: float = position.distance_to(closest)

	if distance <= OFF_MESH_TOLERANCE:
		return

	problems.append({
		"node_path": String(path),
		"kind": kind,
		"position": position,
		"nearest_navmesh": closest,
		"off_mesh_distance": distance,
	})


## How close a computed path must end to the stand for it to count as reached.
##
## Matches StaffTaskExecutor.ARRIVAL_TOLERANCE. A path that stops further away
## than this means the actor never satisfies its arrival check and the executor
## re-issues the same move forever.
const APPROACH_ARRIVAL_TOLERANCE: float = 16.0


## Logs every problem as a warning. Returns true when the level is clean.
##
## Called from the navigation region once the mesh is baked, so a level
## edit that strands a seat is reported the first time the scene runs
## rather than the first time a customer tries to sit in it.
static func report(tree: SceneTree) -> bool:
	var problems: Array[Dictionary] = find_unreachable_points(tree)

	if problems.is_empty():
		return true

	for problem: Dictionary in problems:
		push_warning(
			"Navigation: %s '%s' is %.1fpx off the navmesh at %s - actors will stop short of it."
			% [
				problem["kind"],
				problem["node_path"],
				problem["off_mesh_distance"],
				str(problem["position"]),
			]
		)

	return false
