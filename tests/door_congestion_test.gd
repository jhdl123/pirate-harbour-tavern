extends Node

## Checks the doorway does not gridlock.
##
## Every arrival used to spawn on one coordinate and every departure used to
## walk to that same coordinate, so customers piled up at the door and stopped
## moving. This asserts each actor gets its own nearby point instead.

var passed: int = 0
var failed: int = 0

var main: Node


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	for _i in range(6):
		await get_tree().process_frame

	_test_points_are_distinct()
	_test_points_are_stable()
	_test_points_stay_near_the_door()
	await _test_group_members_get_door_targets()

	_report()


func _door() -> CustomerDoor:
	return main.get_node_or_null(^"Markers/CustomerDoor") as CustomerDoor


func _test_points_are_distinct() -> void:
	var door := _door()

	_check(door != null, "DOOR: the door node exists", "DOOR: no door")

	var actors: Array[Node] = []
	var points: Array[Vector2] = []

	for index in range(8):
		var actor := Node.new()
		actor.name = "Actor%d" % index
		add_child(actor)
		actors.append(actor)
		points.append(door.get_inside_position(actor))

	var minimum_gap := INF

	for i in range(points.size()):
		for j in range(i + 1, points.size()):
			minimum_gap = minf(minimum_gap, points[i].distance_to(points[j]))

	_check(
		minimum_gap > 0.5,
		"DOOR: eight customers get eight distinct points (closest %.1fpx)"
			% minimum_gap,
		"DOOR: two customers share a point - the doorway will gridlock"
	)


func _test_points_are_stable() -> void:
	var door := _door()
	var actor := Node.new()
	add_child(actor)

	var first := door.get_inside_position(actor)
	var second := door.get_inside_position(actor)

	_check(
		first.distance_to(second) < 0.01,
		"DOOR: an actor's point does not move between calls",
		"DOOR: the point jitters, which would cause constant re-pathing"
	)


func _test_points_stay_near_the_door() -> void:
	var door := _door()
	var centre := door.inside_point.global_position
	var worst := 0.0

	for index in range(20):
		var actor := Node.new()
		add_child(actor)
		worst = maxf(worst, door.get_inside_position(actor).distance_to(centre))

	_check(
		worst <= door.inside_spread + 0.1,
		"DOOR: every point stays within %.0fpx of the doorway" % door.inside_spread,
		"DOOR: a point was %.1fpx away, outside the configured spread" % worst
	)


func _test_group_members_get_door_targets() -> void:
	var spawner: GroupSpawner = main.get_node_or_null(
		^"Managers/GroupSpawner"
	)
	var door := _door()

	var group: CustomerGroup = spawner.spawn_group(
		door.get_spawn_position(),
		load("res://Data/groups/pirate_crew.tres"),
		4
	)

	await get_tree().process_frame

	_check(group != null, "DOOR: a group spawned", "DOOR: no group")

	var targets: Array[Vector2] = []

	for member in group.get_valid_members():
		var target: Variant = member.get(&"entrance_inside_position")

		if target != null:
			targets.append(target)

	_check(
		targets.size() == 4,
		"DOOR: all four members were given a door target",
		"DOOR: only %d members have a door target" % targets.size()
	)

	var duplicates := 0

	for i in range(targets.size()):
		for j in range(i + 1, targets.size()):
			if targets[i].distance_to(targets[j]) < 0.5:
				duplicates += 1

	_check(
		duplicates == 0,
		"DOOR: group members leave toward different points, not one spot",
		"DOOR: %d members share an exit point" % duplicates
	)


func _check(condition: bool, pass_text: String, fail_text: String) -> void:
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
