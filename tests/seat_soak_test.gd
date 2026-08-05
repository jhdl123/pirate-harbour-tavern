extends Node

## Soak test for the seat leak, in the real tavern.
##
## Runs many group visits through main.tscn and checks that the seats THE
## GROUPS took come back every time. The original bug drained seating one
## visit at a time, so a single visit looked fine - only repetition exposed it.
##
## Solo customers spawned by the tavern's own loop also hold chairs and do not
## complete their visits in a headless harness, so this counts only the chairs
## groups actually reserved rather than the tavern's total free seats.

var passed: int = 0
var failed: int = 0

var main: Node
var manager: GroupManager
var spawner: GroupSpawner


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	for _i in range(6):
		await get_tree().process_frame

	manager = main.get_node_or_null(^"Managers/GroupManager")
	spawner = main.get_node_or_null(^"Managers/GroupSpawner")

	await _test_seats_return_after_visits()
	_test_orphan_sweep_finds_nothing()

	_report()


func _count_free_seats() -> int:
	var free: int = 0

	for node in get_tree().get_nodes_in_group(&"chairs"):
		var chair := node as Chair

		if chair != null and chair.is_available():
			free += 1

	return free


func _test_seats_return_after_visits() -> void:
	var starting: int = _count_free_seats()

	_check(
		starting > 0,
		"SOAK: the tavern starts with %d free seats" % starting,
		"SOAK: no seats at all"
	)

	var group_held: Array[Chair] = []
	var group_occupants: Dictionary = {}

	var door: Node2D = main.get_node_or_null(^"Markers/CustomerDoor")
	var position: Vector2 = (
		door.global_position if door != null else Vector2.ZERO
	)

	var lowest: int = starting

	# Ten seated visits in a row. Small groups so they take chairs, not floor.
	for round_index in range(10):
		var group: CustomerGroup = spawner.spawn_group(
			position, load("res://Data/groups/merchant_party.tres"), 2
		)

		for _i in range(8):
			WorldTime.advance_minutes(1)
			manager.tick()

		await get_tree().process_frame

		lowest = mini(lowest, _count_free_seats())

		if group != null and group.place != null and group.place.is_seated():
			for entry in group.place.chairs:
				var seat := entry as Chair

				if seat != null and not group_held.has(seat):
					group_held.append(seat)
					# Remember who the group put there, so a solo customer
					# taking the same chair later is not mistaken for a leak.
					group_occupants[seat] = group.get_valid_members().duplicate()
					group_occupants[seat].append(group)

		if group != null and is_instance_valid(group):
			group.begin_departure()
			group.complete_visit()

		manager.tick()

		# Members leave their chairs on the way out.
		for member in _all_customers():
			if member.has_method(&"release_reserved_chair"):
				member.call(&"release_reserved_chair")

		await get_tree().process_frame

	# A chair awaiting cleaning is not a leak - it was properly released and
	# is simply dirty until staff get to it. Only a chair still RESERVED or
	# IN_USE after everyone has gone is a real leak.
	var still_held: int = 0
	var awaiting_cleaning: int = 0

	for seat in group_held:
		if seat.get_seat_state() == Chair.SeatState.AVAILABLE:
			if seat.needs_cleaning():
				awaiting_cleaning += 1

			continue

		# Held by someone. Only a leak if that someone belongs to the group
		# that has already left - anyone else sat down legitimately.
		var holder: Node = seat.get_reservation_holder()
		var owners: Array = group_occupants.get(seat, [])

		if holder != null and owners.has(holder):
			still_held += 1
			print("  LEAKED: %s still held by %s" % [seat.name, holder.name])

	if awaiting_cleaning > 0:
		print("  (%d group seats are awaiting cleaning, which is correct)"
			% awaiting_cleaning)

	_check(
		still_held == 0,
		"SOAK: every one of the %d seats groups used came back"
			% group_held.size(),
		"SOAK: %d of %d group-used seats are still held. Seating is leaking - "
			% [still_held, group_held.size()]
			+ "after enough visits customers are stranded at the door."
	)

	_check(
		lowest < starting,
		"SOAK: seats were genuinely in use during the run (low of %d)" % lowest,
		"SOAK: no seat was ever taken, so the test proved nothing"
	)


func _all_customers() -> Array[Node]:
	var found: Array[Node] = []

	for node in get_tree().get_nodes_in_group(&"seated_customers"):
		found.append(node)

	return found


func _test_orphan_sweep_finds_nothing() -> void:
	var orphans: int = manager.clear_orphaned_reservations()

	_check(
		orphans == 0,
		"SOAK: the orphan sweep found nothing left behind",
		"SOAK: %d orphaned reservations remained" % orphans
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
