extends Node

## Does the seated group path still stall?
##
## On 3 August the second member sent to a reserved chair oscillated ~10px
## short of seat_arrival_distance (2px) forever in MOVING_TO_SEAT, so
## are_members_in_position() never returned true and seated groups were
## switched off with standing_places_only. Since then
## _final_approach_radius was changed from maxf() to a sum of the three
## tolerances, which is exactly the dead band that caused it.
##
## This spawns a group in main.tscn with standing_places_only OFF and
## watches whether every member actually reaches a seat.

var main: Node
var manager: GroupManager
var spawner: GroupSpawner
var game_manager: Node


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	for _i: int in range(8):
		await get_tree().process_frame

	manager = main.get_node_or_null(^"Managers/GroupManager")
	spawner = main.get_node_or_null(^"Managers/GroupSpawner")
	game_manager = main.get_node_or_null(^"Managers/GameManager")

	await _quieten()

	if manager == null or spawner == null:
		print("RESULT: harness failed - manager or spawner missing")
		get_tree().quit(1)
		return

	# The whole point of the probe.
	manager.standing_places_only = false

	# dock_workers (the default test group) PREFERS standing, so find_place()
	# takes a standing area first and the seated path is never exercised.
	# sailor_pair prefers seating and is the definition that was actually
	# failing on 3 August.
	spawner.test_group_definition_path = "res://Data/groups/sailor_pair.tres"

	print("=== seated group probe: standing_places_only = false ===")

	await _run(2)
	await _run(4)

	get_tree().quit()


func _quieten() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"navigation_debugger"):
		node.set(&"enabled", false)

	var debugger: Node = main.get_node_or_null(^"NavigationDebugger")

	if debugger != null:
		debugger.set(&"enabled", false)

	if game_manager != null:
		game_manager.set(&"enable_automatic_group_arrivals", false)

		# Stop solo arrivals and clear the room. Eight chairs across two
		# tables is not many, and solo customers fill them before the probe
		# runs - _try_seated() then fails for a legitimate reason and the
		# group falls back to standing, which hides the thing being tested.
		var event: Variant = game_manager.get(&"_spawn_event")

		if event != null and event.has_method("cancel"):
			event.call("cancel")

		for customer: Node in get_tree().get_nodes_in_group(&"customer"):
			customer.queue_free()

		await get_tree().process_frame
		await get_tree().process_frame


func _run(size: int) -> void:
	print("\n--- group of %d ---" % size)

	var group: CustomerGroup = spawner.spawn_test_group(size)

	if group == null:
		print("  spawn returned null")
		return

	group.standing_places_only = false

	var seated_kind: String = ""
	var elapsed: float = 0.0
	var last_state: String = ""

	# 90s is well past the entry watchdog and the patience window.
	while elapsed < 90.0 and is_instance_valid(group):
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5

		var diagnostics: Dictionary = group.get_diagnostics()
		var state: String = String(diagnostics.get("state", ""))

		if state != last_state:
			print("  %5.1fs  state=%s  place=%s" % [
				elapsed, state,
				String(diagnostics.get("destination_kind", "-")),
			])
			last_state = state

		if seated_kind.is_empty():
			seated_kind = String(diagnostics.get("destination_kind", ""))

		if state == "COMPLETE" or state == "FAILED":
			print("  finished in %.1fs as %s" % [elapsed, state])
			print("    destination_kind = %s" % seated_kind)
			print("    order_failure    = %s" % String(
				diagnostics.get("order_failure_reason", "")
			))
			print("    departure_reason = %s" % String(
				diagnostics.get("departure_reason", "")
			))
			print("    keg portions     = %s" % str(
				diagnostics.get("keg_starting_portions", 0)
			))
			return

	print("  TIMED OUT after %.0fs in state '%s'" % [elapsed, last_state])
	print("    destination_kind = %s" % seated_kind)

	if is_instance_valid(group):
		var final: Dictionary = group.get_diagnostics()
		print("    members in position = %s" % str(
			final.get("members_in_position", "?")
		))
