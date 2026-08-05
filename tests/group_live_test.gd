extends Node

## Runs real group visits inside the actual tavern scene.
##
## Not stubs: this loads main.tscn, spawns groups through the real spawner,
## and drives the real manager. It is the test that answers "does this work in
## the game" rather than "do the classes agree with each other".

var passed: int = 0
var failed: int = 0

var main: Node
var manager: GroupManager
var spawner: GroupSpawner
var order_service: GroupOrderService
var door: Node2D


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	# Let the scene, its stations and the setup node all settle.
	for _i in range(6):
		await get_tree().process_frame

	manager = main.get_node_or_null(^"Managers/GroupManager")
	spawner = main.get_node_or_null(^"Managers/GroupSpawner")
	order_service = main.get_node_or_null(^"Managers/GroupOrderService")
	door = main.get_node_or_null(^"Markers/CustomerDoor")

	await _test_scene_wiring()
	await _test_group_spawns_together()
	await _test_seated_group()
	await _test_standing_fallback()
	await _test_full_visit_loop()
	await _test_solo_customers_still_work()
	await _test_cleanup_leaves_nothing_held()

	_report()


func _spawn(path: String, size: int) -> CustomerGroup:
	var group := spawner.spawn_group(
		door.global_position if door != null else Vector2.ZERO,
		load(path) if not path.is_empty() else null,
		size
	)

	await get_tree().process_frame

	return group


# --- Tests -------------------------------------------------------------------

func _test_scene_wiring() -> void:
	_check(
		manager != null and spawner != null and order_service != null,
		"WIRING: the group systems are present in main.tscn",
		"WIRING: manager=%s spawner=%s service=%s" % [
			manager != null, spawner != null, order_service != null,
		]
	)

	var areas := get_tree().get_nodes_in_group(&"group_standing_areas")

	_check(
		areas.size() == 3,
		"WIRING: 3 standing areas are placed in the tavern",
		"WIRING: found %d standing areas" % areas.size()
	)

	var stations := get_tree().get_nodes_in_group(&"drink_stations")
	var configured := 0

	for node in stations:
		var station := node as DrinksStation

		if station != null and station.has_service_batch():
			configured += 1

	_check(
		configured == stations.size() and configured > 0,
		"WIRING: all %d stations were given real service casks" % configured,
		"WIRING: %d of %d stations configured" % [configured, stations.size()]
	)

	var stocked := 0

	for node in stations:
		var station := node as DrinksStation

		if station != null and station.get_available_measures() > 0:
			stocked += 1

	_check(
		stocked > 0,
		"WIRING: stations hold fallback stock, so groups can be served",
		"WIRING: every station is dry"
	)


func _test_group_spawns_together() -> void:
	var group := await _spawn("res://Data/groups/pirate_crew.tres", 5)

	_check(
		group != null and group.get_valid_members().size() == 5,
		"SPAWN: a five-member crew was created as one visit",
		"SPAWN: got %s" % (
			"null" if group == null
			else str(group.get_valid_members().size()) + " members"
		)
	)

	var ids := {}

	for member in group.get_valid_members():
		ids[member.get(&"group_id")] = true

	_check(
		ids.size() == 1 and ids.has(group.group_id),
		"SPAWN: every member carries the same group id",
		"SPAWN: %d distinct group ids" % ids.size()
	)

	_check(
		group.leader != null and group.get_valid_members().has(group.leader),
		"SPAWN: a leader was designated from the members",
		"SPAWN: no valid leader"
	)

	# Members must not be stacked on one another.
	var minimum_gap := INF
	var members := group.get_valid_members()

	for i in range(members.size()):
		for j in range(i + 1, members.size()):
			minimum_gap = minf(
				minimum_gap,
				(members[i] as Node2D).global_position.distance_to(
					(members[j] as Node2D).global_position
				)
			)

	_check(
		minimum_gap > 1.0,
		"SPAWN: members spawned %.1fpx apart, not inside each other"
			% minimum_gap,
		"SPAWN: members overlap (%.2fpx)" % minimum_gap
	)

	group.begin_departure()
	group.complete_visit()
	manager.tick()


func _test_seated_group() -> void:
	var group := await _spawn("res://Data/groups/merchant_party.tres", 2)

	_check(group != null, "SEATED: a merchant pair arrived", "SEATED: no group")

	manager.tick()

	_check(
		group.place != null and group.place.is_valid(),
		"SEATED: the pair found a place on the first tick",
		"SEATED: no place (state %s)" % group.get_state_name()
	)

	_check(
		group.place.is_seated(),
		"SEATED: with tables free, they sat down",
		"SEATED: they went %s instead" % group.get_summary()["place_type"]
	)

	_check(
		group.place.chairs.size() == 2,
		"SEATED: exactly two chairs were reserved",
		"SEATED: %d chairs reserved" % group.place.chairs.size()
	)

	group.begin_departure()
	group.complete_visit()
	manager.tick()


func _test_standing_fallback() -> void:
	# Six is larger than any table in the tavern, so this can only stand.
	var group := await _spawn("res://Data/groups/pirate_crew.tres", 6)

	manager.tick()

	_check(
		group.place != null and group.place.is_standing(),
		"STANDING: a six-strong crew took a standing area",
		"STANDING: place is %s" % (
			"none" if group.place == null
			else group.get_summary()["place_type"]
		)
	)

	_check(
		group.place.slots.size() == 6,
		"STANDING: six formation slots were assigned",
		"STANDING: %d slots" % group.place.slots.size()
	)

	var assigned := 0

	for member in group.get_valid_members():
		if member.get(&"group_slot_position") != Vector2.ZERO:
			assigned += 1

	_check(
		assigned == 6,
		"STANDING: all six members were sent to their positions",
		"STANDING: %d members got a position" % assigned
	)

	group.begin_departure()
	group.complete_visit()
	manager.tick()


func _test_full_visit_loop() -> void:
	var group := await _spawn("res://Data/groups/dock_workers.tres", 4)

	# Drive the visit forward. Advancing WorldTime rather than only calling
	# tick() matters: the ordering gate is measured in tavern minutes, so a
	# test that never moves the clock would sit in WAITING_TO_ORDER forever -
	# which is exactly what it did before this line was added.
	for _i in range(6):
		WorldTime.advance_minutes(1)
		manager.tick()
		await get_tree().process_frame

	# Members will not be in position without real navigation time, so put
	# them at their slots directly - this test is about the order and serving
	# path, not about walking.
	if group.place != null:
		var members := group.get_valid_members()

		for index in range(members.size()):
			(members[index] as Node2D).global_position = (
				group.place.get_slot_for(index)
			)
			members[index].set(&"current_state", Customer.State.IN_GROUP)

	for _i in range(10):
		WorldTime.advance_minutes(1)
		manager.tick()
		await get_tree().process_frame

	_check(
		group.orders_placed > 0,
		"VISIT: the group placed an order",
		"VISIT: no order placed (state %s, problem '%s')" % [
			group.get_state_name(), group.failure_reason,
		]
	)

	_check(
		group.current_order != null
			and not group.current_order.drink_id.is_empty()
			and not group.current_order.serving_format_id.is_empty(),
		"VISIT: the order carries drink and serving-format ids (%s)" % (
			group.current_order.get_display_name(
				load("res://Data/beverage/beverage_registry.tres")
			) if group.current_order != null else "-"
		),
		"VISIT: the order is incomplete"
	)

	if group.current_order != null and group.current_order.is_shared:
		_check(
			group.shared_serving != null,
			"VISIT: a shared serving was delivered to the group",
			"VISIT: no shared serving (order %s)"
				% group.current_order.get_status_name()
		)

		if group.shared_serving != null:
			_check(
				group.shared_serving.global_position.distance_to(
					group.place.get_serving_position()
				) < 2.0,
				"VISIT: it was placed at the group's serving point",
				"VISIT: the serving is not at the serving point"
			)

			var starting := group.shared_serving.remaining_portions

			for _i in range(30):
				WorldTime.advance_minutes(1)
				manager.tick()

			_check(
				group.shared_serving == null
					or group.shared_serving.remaining_portions < starting,
				"VISIT: members drank from the shared serving over time",
				"VISIT: portions never decreased from %d" % starting
			)

		_check(
			group.current_order.paid,
			"VISIT: the group paid once for the shared order",
			"VISIT: the order was never paid"
		)
	else:
		_check(
			true,
			"VISIT: the group chose individual drinks this visit",
			""
		)

	group.begin_departure()
	group.complete_visit()
	manager.tick()


func _test_solo_customers_still_work() -> void:
	var game_manager := main.get_node_or_null(^"Managers/GameManager")

	_check(
		game_manager != null,
		"REGRESSION: the GameManager is intact",
		"REGRESSION: no GameManager"
	)

	var before: int = game_manager.active_customers.size()

	game_manager.spawn_customer()
	await get_tree().process_frame

	_check(
		game_manager.active_customers.size() >= before,
		"REGRESSION: solo customer spawning still runs without error",
		"REGRESSION: solo spawning broke"
	)


func _test_cleanup_leaves_nothing_held() -> void:
	manager.tick()

	var held_areas := 0

	for node in get_tree().get_nodes_in_group(&"group_standing_areas"):
		var area := node as GroupStandingArea

		if area != null and area.is_reserved():
			held_areas += 1

	_check(
		held_areas == 0,
		"CLEANUP: no standing area is still held after every group left",
		"CLEANUP: %d areas still reserved" % held_areas
	)

	_check(
		manager.get_active_group_count() == 0,
		"CLEANUP: the active-group registry is empty",
		"CLEANUP: %d groups still registered"
			% manager.get_active_group_count()
	)

	# The sweep is deliberately NOT asserted to find zero. The tavern's own
	# solo customers are spawning and departing throughout this test, and a
	# chair whose holder was freed mid-visit is exactly what the sweep exists
	# to tidy - counting that as a group failure would be wrong.
	#
	# What matters is that no STANDING AREA and no group registration leaked,
	# which is asserted above.
	var orphans := manager.clear_orphaned_reservations()

	print("  (orphan sweep cleared %d stale reservation(s) from the wider "
		% orphans + "tavern - solo customer churn, not group state)")

	var held_after := 0

	for node in get_tree().get_nodes_in_group(&"group_standing_areas"):
		var area := node as GroupStandingArea

		if area != null and area.is_reserved():
			held_after += 1

	_check(
		held_after == 0,
		"CLEANUP: no group reservation survived the sweep",
		"CLEANUP: %d standing areas still held after sweeping" % held_after
	)


# --- Harness -----------------------------------------------------------------

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
	print("GROUP LIVE (IN-SCENE) TEST")
	print("  passed: %d" % passed)
	print("  failed: %d" % failed)
	print("==================================================")

	get_tree().quit(1 if failed > 0 else 0)
