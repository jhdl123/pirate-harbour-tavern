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

	return problems


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
