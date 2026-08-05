extends Node

## Busy-tavern stress: several groups and solo customers at once.
##
## Looks for the failures that only appear under load - orphaned reservations,
## groups stuck in the registry, double-booked areas, negative portions.

var passed: int = 0
var failed: int = 0

var main: Node
var manager: GroupManager
var spawner: GroupSpawner
var game_manager: Node


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	for _i in range(6):
		await get_tree().process_frame

	manager = main.get_node_or_null(^"Managers/GroupManager")
	spawner = main.get_node_or_null(^"Managers/GroupSpawner")
	game_manager = main.get_node_or_null(^"Managers/GameManager")

	await _run_busy_tavern()
	_test_no_orphans()
	_test_no_double_booking()
	_test_portions_never_negative()
	_test_registry_drains()

	_report()


func _run_busy_tavern() -> void:
	var door: Node2D = main.get_node_or_null(^"Markers/CustomerDoor")
	var position: Vector2 = (
		door.global_position if door != null else Vector2.ZERO
	)

	var spawned: int = 0

	# Far more groups than the tavern can hold, deliberately.
	for index in range(12):
		var group: CustomerGroup = spawner.spawn_group(position)

		if group != null:
			spawned += 1

		if index % 3 == 0:
			game_manager.spawn_customer()

		for _i in range(4):
			WorldTime.advance_minutes(1)
			manager.tick()

		await get_tree().process_frame

	_check(
		spawned > 0,
		"STRESS: %d group visits were created under load" % spawned,
		"STRESS: no groups spawned at all"
	)

	_check(
		manager.get_active_group_count() <= manager.maximum_active_groups,
		"STRESS: the active-group limit held (%d <= %d)" % [
			manager.get_active_group_count(), manager.maximum_active_groups,
		],
		"STRESS: %d groups active, limit is %d" % [
			manager.get_active_group_count(), manager.maximum_active_groups,
		]
	)

	# Run the tavern on for a while so visits complete on their own.
	var peak: int = manager.get_active_group_count()

	for _i in range(200):
		WorldTime.advance_minutes(1)
		manager.tick()

	await get_tree().process_frame

	# Groups must finish without being forced. A visit that never ends would
	# hold its table for the rest of the day.
	_check(
		manager.get_active_group_count() < peak or peak == 0,
		"STRESS: groups completed unaided (%d active, was %d)" % [
			manager.get_active_group_count(), peak,
		],
		"STRESS: %d groups never finished on their own" % peak
	)


func _test_no_orphans() -> void:
	var orphans: int = manager.clear_orphaned_reservations()

	_check(
		orphans == 0,
		"STRESS: no orphaned reservations were left behind",
		"STRESS: %d orphaned reservations had to be swept" % orphans
	)


func _test_no_double_booking() -> void:
	var holders: Dictionary = {}
	var clashes: int = 0

	for node in get_tree().get_nodes_in_group(&"group_standing_areas"):
		var area := node as GroupStandingArea

		if area == null or area.is_free():
			continue

		var holder: StringName = area.get_holder_group_id()

		if holders.has(holder):
			clashes += 1

		holders[holder] = true

	_check(
		clashes == 0,
		"STRESS: no standing area was double-booked",
		"STRESS: %d double bookings" % clashes
	)


func _test_portions_never_negative() -> void:
	var negative: int = 0

	for node in get_tree().get_nodes_in_group(&"shared_servings"):
		var serving := node as SharedServing

		if serving != null and serving.remaining_portions < 0:
			negative += 1

	_check(
		negative == 0,
		"STRESS: no shared serving went below zero portions",
		"STRESS: %d servings have negative portions" % negative
	)


func _test_registry_drains() -> void:
	# Force everything out and confirm the registry empties.
	for group in manager.active_groups.duplicate():
		if is_instance_valid(group):
			group.begin_departure()
			group.complete_visit()

	manager.tick()

	_check(
		manager.get_active_group_count() == 0,
		"STRESS: every group left and the registry drained to zero",
		"STRESS: %d groups still stuck in the registry"
			% manager.get_active_group_count()
	)

	var held: int = 0

	for node in get_tree().get_nodes_in_group(&"group_standing_areas"):
		var area := node as GroupStandingArea

		if area != null and area.is_reserved():
			held += 1

	_check(
		held == 0,
		"STRESS: all standing areas were released",
		"STRESS: %d areas still held after everyone left" % held
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
	print("==================================================")
	print("GROUP STRESS TEST")
	print("  passed: %d" % passed)
	print("  failed: %d" % failed)
	print("==================================================")

	get_tree().quit(1 if failed > 0 else 0)
