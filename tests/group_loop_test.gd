extends Node

## Drives the basic group keg loop end to end, repeatedly.
##
## Covers the ten cases the basic-loop pass asked for: normal three- and
## six-member visits, a member that cannot reach its exact slot, a transient
## shared-serving failure, an empty tavern with basic_loop_ignore_stock on,
## serving-point reuse, ten consecutive groups, the refusal to complete a
## member while it is still in a group state, shared-drink accounting, and a
## cleanup that is called twice.
##
## Members are stubs rather than full Customer nodes on purpose: this suite is
## about the group state machine, its guards and its teardown. The real
## Customer path is exercised by group_keg_loop_test, which drives main.tscn.

var passed: int = 0
var failed: int = 0

var registry: BeverageRegistry
var vessel_pool: VesselPool
var order_service: GroupOrderService
var manager: GroupManager

var areas: Array[GroupStandingArea] = []

## Diagnostics captured the moment a group finished, keyed by group id.
##
## The manager frees a finished group on the same sweep that reports it, so
## anything a test wants to assert has to be taken before the node goes.
var finished_diagnostics: Dictionary = {}


func _ready() -> void:
	registry = load("res://Data/beverage/beverage_registry.tres")
	registry.rebuild()

	await _build_world()

	await _test_three_member_group()
	await _test_six_member_group()
	await _test_slot_recovery()
	await _test_serving_retry_then_success()
	await _test_empty_stock_with_ignore_flag()
	await _test_consecutive_groups_reuse_serving_point()
	await _test_ten_consecutive_groups()
	await _test_no_unknown_completion_in_group_state()
	await _test_shared_drink_accounting()
	_test_cleanup_is_idempotent()

	_report()


# --- World -------------------------------------------------------------------

func _build_world() -> void:
	vessel_pool = VesselPool.new()
	vessel_pool.registry = registry
	add_child(vessel_pool)

	for id: StringName in [&"pitcher", &"punch_bowl", &"table_cask"]:
		vessel_pool.set_stock(id, 2)

	var station_scene: PackedScene = load(
		"res://scenes/furniture/drinks_station.tscn"
	)

	for pair: Array in [[&"small_beer", "SmallBeerStation"], [&"ale", "AleStation"], [&"kill_devil", "RumStation"]]:
		var station: DrinksStation = station_scene.instantiate()
		station.name = String(pair[1])
		station.served_drink = registry.get_drink(pair[0])
		add_child(station)

	var setup := BeverageSceneSetup.new()
	setup.registry = registry
	setup.starting_measures = 96
	add_child(setup)

	order_service = GroupOrderService.new()
	order_service.registry = registry
	order_service.vessel_pool = vessel_pool
	add_child(order_service)

	# Three areas, so consecutive groups can overlap without competing for the
	# same formation point when a test needs them to.
	areas.append(_make_area("dock_corner", Vector2(0, 300), 2, 8))
	areas.append(_make_area("bar_end", Vector2(400, 300), 2, 8))
	areas.append(_make_area("hearth", Vector2(800, 300), 2, 8))

	manager = GroupManager.new()
	manager.registry = registry
	manager.order_service = order_service
	manager.vessel_pool = vessel_pool
	manager.maximum_active_groups = 4
	manager.minutes_before_ordering = 1
	manager.minutes_between_drinks = 1
	manager.minutes_socialising_after_empty = 3
	manager.first_drink_delay_minutes = 1
	manager.minutes_between_serving_attempts = 1
	# This suite covers the basic loop mechanics - assembly, drinking, timing,
	# departure and cleanup - on a bare harness with no storage and no staff.
	# Real stock and staff delivery are covered by group_parity_test instead.
	manager.use_real_keg_stock = false
	manager.leisure_enabled = false
	add_child(manager)

	manager.group_completed.connect(_on_group_finished)
	manager.group_failed.connect(_on_group_failed)

	await get_tree().process_frame
	await get_tree().process_frame


func _on_group_finished(group: CustomerGroup) -> void:
	finished_diagnostics[String(group.group_id)] = group.get_diagnostics()


func _on_group_failed(group: CustomerGroup, _reason: String) -> void:
	finished_diagnostics[String(group.group_id)] = group.get_diagnostics()


func _make_area(
	id: String, position: Vector2, minimum: int, maximum: int
) -> GroupStandingArea:
	var area := GroupStandingArea.new()
	area.area_id = StringName(id)
	area.display_name = id
	area.minimum_group_size = minimum
	area.maximum_group_size = maximum
	area.formation_radius = 40.0
	add_child(area)
	area.global_position = position

	return area


func _make_group(size: int, stuck_members: int = 0) -> CustomerGroup:
	var group := CustomerGroup.new()
	group.definition = load("res://Data/groups/dock_workers.tres")
	group.beverage_registry = registry
	group.vessel_pool = vessel_pool
	group.standing_places_only = true
	group.member_departure_delay = 0.0
	group.member_entry_delay = 0.0
	group.slot_arrival_timeout_minutes = 2
	group.maximum_slot_retries = 1
	add_child(group)

	for index: int in range(size):
		var member := StubMember.new()
		member.name = "M%d_%s" % [index, group.group_id]
		member.is_stuck = index < stuck_members
		add_child(member)
		group.add_member(member)

	return group


## Runs the world forward, one world minute per step.
##
## Uses the real driver - WorldTime plus GroupManager._process - rather than
## calling tick() directly, so the guards that stop a minute being applied
## twice are exercised the same way they are in play.
func _run_minutes(count: int) -> void:
	for _step: int in range(count):
		WorldTime.advance_minutes(1)

		await get_tree().process_frame
		await get_tree().process_frame


## Runs a whole visit and returns the diagnostics captured when it finished.
func _register_and_run(group: CustomerGroup, minutes: int) -> Dictionary:
	var id: String = String(group.group_id)

	manager.register_group(group)

	await get_tree().process_frame

	await _run_minutes(minutes)

	if finished_diagnostics.has(id):
		return finished_diagnostics[id]

	# Still running: report what the live group says, so a stalled visit
	# fails its assertions rather than crashing the suite.
	if is_instance_valid(group):
		return group.get_diagnostics()

	return {}


# --- Tests -------------------------------------------------------------------

func _test_three_member_group() -> void:
	var group: CustomerGroup = _make_group(3)
	var members: Array[Node] = group.members.duplicate()

	var result: Dictionary = await _register_and_run(group, 60)

	_check(
		_keg(result) > 0,
		"THREE: the group got a keg (%d portions)" % _keg(result),
		"THREE: no keg was ever created (%s)" % _reason(result)
	)

	_check(
		_drinks(result) > 0,
		"THREE: %d shared drinks were taken" % _drinks(result),
		"THREE: nobody drank from the keg"
	)

	_check(
		_state(result) == "COMPLETE",
		"THREE: the visit finished in %s" % _state(result),
		"THREE: the visit ended as %s" % _state(result)
	)

	_check(
		_all_departed(members),
		"THREE: every member was sent to the door",
		"THREE: %d member(s) never got a departure command"
			% _count_not_departed(members)
	)

	_check(
		bool(result.get("cleanup_completed", false)),
		"THREE: cleanup ran",
		"THREE: cleanup never ran"
	)


func _test_six_member_group() -> void:
	var group: CustomerGroup = _make_group(6)
	var members: Array[Node] = group.members.duplicate()

	var result: Dictionary = await _register_and_run(group, 60)

	_check(
		_keg(result) > 0,
		"SIX: the group got a keg",
		"SIX: no keg was created (%s)" % _reason(result)
	)

	_check(
		_state(result) == "COMPLETE" and _all_departed(members),
		"SIX: the six-strong crew finished and left",
		"SIX: state %s, %d member(s) still in the group"
			% [_state(result), _count_not_departed(members)]
	)


func _test_slot_recovery() -> void:
	# One member never moves. Assembly must recover it rather than waiting.
	var group: CustomerGroup = _make_group(3, 1)
	var stuck: StubMember = group.members[0] as StubMember

	var result: Dictionary = await _register_and_run(group, 60)
	var recoveries: int = int(result.get("group_slot_recoveries", 0))

	_check(
		recoveries > 0,
		"RECOVERY: %d slot recoveries were needed" % recoveries,
		"RECOVERY: the group never recovered a member"
	)

	_check(
		stuck.accepted_at_slot,
		"RECOVERY: the stuck member was placed at its slot",
		"RECOVERY: the stuck member was never placed"
	)

	_check(
		is_instance_valid(stuck) and not stuck.was_finished,
		"RECOVERY: the stuck member was not abandoned",
		"RECOVERY: the stuck member was removed from the visit"
	)

	_check(
		_keg(result) > 0 and _state(result) == "COMPLETE",
		"RECOVERY: the group still ordered, drank and left",
		"RECOVERY: the group did not complete its loop (%s)" % _state(result)
	)


func _test_serving_retry_then_success() -> void:
	# Every table cask is out on loan, so the first request must fail. Handing
	# one back mid-visit must let the retry succeed rather than the group
	# having already gone home.
	var before: int = vessel_pool.get_available(&"table_cask")
	vessel_pool.reserve(&"table_cask", before)

	var group: CustomerGroup = _make_group(3)

	manager.register_group(group)

	await get_tree().process_frame

	# Short enough that the group still has a retry left when the vessel
	# comes back - the point is that a transient failure is survivable, not
	# that the group waits forever.
	await _run_minutes(4)

	var attempts_while_dry: int = group.serving_attempts

	_check(
		attempts_while_dry > 0
		and attempts_while_dry < manager.maximum_serving_attempts
		and not group.is_finished(),
		"RETRY: the group retried instead of leaving (%d attempts)"
			% attempts_while_dry,
		"RETRY: the group gave up after %d attempt(s), state %s"
			% [attempts_while_dry, group.get_state_name()]
	)

	vessel_pool.release(&"table_cask", before)

	var id: String = String(group.group_id)

	await _run_minutes(60)

	var result: Dictionary = finished_diagnostics.get(id, {})

	_check(
		_keg(result) > 0,
		"RETRY: the retry succeeded once a vessel came back",
		"RETRY: no keg after the vessel was returned (%s)" % _reason(result)
	)

	_check(
		vessel_pool.get_available(&"table_cask") == before,
		"RETRY: the vessel pool balanced (%d)"
			% vessel_pool.get_available(&"table_cask"),
		"RETRY: vessels leaked - %d available, expected %d"
			% [vessel_pool.get_available(&"table_cask"), before]
	)


func _test_empty_stock_with_ignore_flag() -> void:
	_check(
		order_service.basic_loop_ignore_stock,
		"STOCK: basic_loop_ignore_stock is preserved and on",
		"STOCK: basic_loop_ignore_stock was lost"
	)

	var drained: Array[int] = []

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station == null:
			continue

		var measures: int = station.get_available_measures()
		drained.append(measures)
		station.draw_measures(measures)

	var group: CustomerGroup = _make_group(3)

	var result: Dictionary = await _register_and_run(group, 60)

	_check(
		_keg(result) > 0,
		"STOCK: a dry tavern still served the group its milestone keg",
		"STOCK: the group failed with an empty cellar (%s)" % _reason(result)
	)

	_check(
		_state(result) == "COMPLETE",
		"STOCK: the visit completed with no stock",
		"STOCK: the visit ended as %s" % _state(result)
	)

	var index: int = 0

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station == null:
			continue

		station.grant_service_stock(drained[index])
		index += 1


func _test_consecutive_groups_reuse_serving_point() -> void:
	var first: CustomerGroup = _make_group(3)

	var first_result: Dictionary = await _register_and_run(first, 60)
	var first_place: String = String(first_result.get("destination_id", ""))

	var second: CustomerGroup = _make_group(3)

	var second_result: Dictionary = await _register_and_run(second, 60)
	var second_place: String = String(second_result.get("destination_id", ""))

	_check(
		_keg(second_result) > 0,
		"REUSE: the second group also got a keg",
		"REUSE: the second group failed (%s)" % _reason(second_result)
	)

	_check(
		not first_place.is_empty() and second_place == first_place,
		"REUSE: the released formation point was taken again (%s)" % first_place,
		"REUSE: the second group used %s, not %s" % [second_place, first_place]
	)

	_check(
		_count_servings() == 0,
		"REUSE: no shared serving was left behind",
		"REUSE: %d serving node(s) survived" % _count_servings()
	)


func _test_ten_consecutive_groups() -> void:
	var completed: int = 0
	var drank: int = 0

	for run: int in range(10):
		var group: CustomerGroup = _make_group(2 + (run % 5))

		var result: Dictionary = await _register_and_run(group, 60)

		if _state(result) == "COMPLETE":
			completed += 1

		if _drinks(result) > 0:
			drank += 1

	_check(
		completed == 10,
		"TEN: all ten groups completed",
		"TEN: only %d of 10 groups completed" % completed
	)

	_check(
		drank == 10,
		"TEN: all ten groups drank from their keg",
		"TEN: only %d of 10 groups drank" % drank
	)

	_check(
		manager.get_active_group_count() == 0,
		"TEN: no stale active groups remain",
		"TEN: %d group(s) are still active" % manager.get_active_group_count()
	)

	_check(
		_count_servings() == 0,
		"TEN: no abandoned serving nodes remain",
		"TEN: %d serving node(s) survived" % _count_servings()
	)

	_check(
		vessel_pool.get_count(&"table_cask", VesselPool.State.IN_USE) == 0,
		"TEN: every shared vessel came back",
		"TEN: %d vessel(s) are still out"
			% vessel_pool.get_count(&"table_cask", VesselPool.State.IN_USE)
	)

	var free_areas: int = 0

	for area: GroupStandingArea in areas:
		if area.is_free():
			free_areas += 1

	_check(
		free_areas == areas.size(),
		"TEN: every formation point was released",
		"TEN: only %d of %d areas are free" % [free_areas, areas.size()]
	)


func _test_no_unknown_completion_in_group_state() -> void:
	var group: CustomerGroup = _make_group(3, 3)

	manager.register_group(group)

	await get_tree().process_frame
	await _run_minutes(4)

	var members: Array[Node] = group.members.duplicate()

	group.fail_visit("test forced failure")

	var wrongly_finished: int = 0
	var unknown_reasons: int = 0

	for member: Node in members:
		var stub: StubMember = member as StubMember

		if stub == null:
			continue

		if stub.was_finished and stub.state_when_finished in [
			int(Customer.State.IN_GROUP),
			int(Customer.State.MOVING_TO_GROUP_SLOT),
		]:
			wrongly_finished += 1

		if stub.was_finished and stub.departure_reason.is_empty():
			unknown_reasons += 1

	_check(
		wrongly_finished == 0,
		"UNKNOWN: no member was completed while still in a group state",
		"UNKNOWN: %d member(s) were completed mid-group" % wrongly_finished
	)

	_check(
		unknown_reasons == 0,
		"UNKNOWN: every removed member carried a real reason",
		"UNKNOWN: %d member(s) had no departure reason" % unknown_reasons
	)

	_check(
		_all_departed(members),
		"UNKNOWN: members inside the tavern were walked out instead",
		"UNKNOWN: %d member(s) were left in the group"
			% _count_not_departed(members)
	)


func _test_shared_drink_accounting() -> void:
	var group: CustomerGroup = _make_group(4)
	var members: Array[Node] = group.members.duplicate()

	var diagnostics: Dictionary = await _register_and_run(group, 60)

	var total: int = 0
	var with_drinks: int = 0
	var with_drink_definition: int = 0

	for member: Node in members:
		var stub: StubMember = member as StubMember

		if stub == null:
			continue

		total += stub.drinks_consumed_this_visit

		if stub.drinks_consumed_this_visit > 0:
			with_drinks += 1

		if stub.last_drink_definition != null:
			with_drink_definition += 1

	_check(
		total == _drinks(diagnostics),
		"DRINKS: the group and its members agree on %d portions" % total,
		"DRINKS: members counted %d, the group counted %d"
			% [total, _drinks(diagnostics)]
	)

	_check(
		with_drinks > 1,
		"DRINKS: %d of 4 members took a turn" % with_drinks,
		"DRINKS: only %d member(s) ever drank - the rotation is not fair"
			% with_drinks
	)

	_check(
		with_drink_definition == with_drinks,
		"DRINKS: every portion carried its drink, so intoxication can apply",
		"DRINKS: %d of %d portions had no drink definition"
			% [with_drinks - with_drink_definition, with_drinks]
	)

	_check(
		diagnostics.has("shared_drinks_consumed")
		and diagnostics.has("group_slot_recoveries")
		and diagnostics.has("post_drink_started_at_minutes")
		and String(diagnostics.get("departure_reason", "")) != "unknown",
		"DRINKS: the group diagnostics carry the new fields",
		"DRINKS: the group diagnostics are missing fields (%s)"
			% str(diagnostics)
	)

	var emptied: int = int(diagnostics.get("keg_emptied_at_minutes", -1))
	var post_started: int = int(
		diagnostics.get("post_drink_started_at_minutes", -1)
	)

	_check(
		emptied > 0 and post_started >= emptied,
		"DRINKS: the post-keg wait was measured from the keg emptying",
		"DRINKS: keg_emptied_at=%d, post_drink_started_at=%d"
			% [emptied, post_started]
	)


func _test_cleanup_is_idempotent() -> void:
	var group := CustomerGroup.new()
	group.definition = load("res://Data/groups/dock_workers.tres")
	group.beverage_registry = registry
	group.vessel_pool = vessel_pool
	group.standing_places_only = true
	add_child(group)

	for index: int in range(3):
		var member := StubMember.new()
		member.name = "Cleanup%d" % index
		add_child(member)
		group.add_member(member)

	var found: bool = group.find_place()

	_check(
		found,
		"IDEMPOTENT: the group booked a formation point",
		"IDEMPOTENT: no formation point was free"
	)

	var area: GroupStandingArea = group.place.standing_area
	var vessels_before: int = vessel_pool.get_available(&"table_cask")

	group.cleanup()
	group.cleanup()
	group.cleanup()

	_check(
		area != null and area.is_free(),
		"IDEMPOTENT: three cleanups released the area exactly once",
		"IDEMPOTENT: the area is still held after cleanup"
	)

	_check(
		vessel_pool.get_available(&"table_cask") == vessels_before,
		"IDEMPOTENT: no vessel was returned twice (%d)" % vessels_before,
		"IDEMPOTENT: vessel count moved from %d to %d"
			% [vessels_before, vessel_pool.get_available(&"table_cask")]
	)

	_check(
		group.members.is_empty() and group.place == null,
		"IDEMPOTENT: members and place references were cleared",
		"IDEMPOTENT: %d member(s) and place=%s remain"
			% [group.members.size(), str(group.place)]
	)

	group.queue_free()


# --- Helpers -----------------------------------------------------------------

func _keg(result: Dictionary) -> int:
	return int(result.get("keg_starting_portions", 0))


func _drinks(result: Dictionary) -> int:
	return int(result.get("shared_drinks_consumed", 0))


func _state(result: Dictionary) -> String:
	return String(result.get("state", "MISSING"))


func _reason(result: Dictionary) -> String:
	var reason: String = String(result.get("order_failure_reason", ""))

	if reason.is_empty():
		reason = String(result.get("departure_reason", "no diagnostics"))

	return reason


func _all_departed(members: Array[Node]) -> bool:
	return _count_not_departed(members) == 0


func _count_not_departed(members: Array[Node]) -> int:
	var remaining: int = 0

	for member: Node in members:
		var stub: StubMember = member as StubMember

		if stub == null or not is_instance_valid(stub):
			continue

		if not stub.departing and not stub.was_finished:
			remaining += 1

	return remaining


func _count_servings() -> int:
	var total: int = 0

	for node: Node in get_tree().get_nodes_in_group(&"shared_servings"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			total += 1

	return total


# --- Stubs -------------------------------------------------------------------

## A group member with just enough Customer surface to run the group loop.
##
## Walks toward its slot a fixed amount per assembly check, unless is_stuck is
## set - which is how the "cannot reach its exact slot" case is produced.
class StubMember extends Node2D:
	var group_id: StringName = &""
	var group_controller: Node = null
	var group_slot_position: Vector2 = Vector2.ZERO
	var group_centre_position: Vector2 = Vector2.ZERO
	var current_state: int = int(Customer.State.GROUP_INSIDE_STAGING)
	var next_group_drink_minutes: int = -1
	var drinks_consumed_this_visit: int = 0
	var shared_drinks_consumed: int = 0
	var group_slot_recoveries: int = 0
	var departure_reason: StringName = &""

	var is_stuck: bool = false
	var departing: bool = false
	var was_finished: bool = false
	var accepted_at_slot: bool = false
	var state_when_finished: int = -1
	var last_drink_definition: DrinkDefinition = null

	func join_group(new_group_id: StringName, controller: Node) -> void:
		group_id = new_group_id
		group_controller = controller

	func leave_group() -> void:
		group_id = &""
		group_controller = null

	func assign_group_position(target: Vector2, centre: Vector2) -> void:
		group_slot_position = target
		group_centre_position = centre
		current_state = int(Customer.State.MOVING_TO_GROUP_SLOT)

		if not is_stuck:
			# A working member simply arrives; navigation itself is not what
			# this suite is testing.
			global_position = target
			current_state = int(Customer.State.IN_GROUP)
			next_group_drink_minutes = -1

	func refresh_group_slot() -> void:
		group_slot_recoveries += 1
		assign_group_position(group_slot_position, group_centre_position)

	func accept_group_slot_arrival(snap_to_slot: bool = false) -> void:
		if current_state == int(Customer.State.IN_GROUP):
			return

		if snap_to_slot:
			global_position = group_slot_position

		accepted_at_slot = true
		group_slot_recoveries += 1
		current_state = int(Customer.State.IN_GROUP)
		next_group_drink_minutes = -1

	func get_effective_drink_limit() -> int:
		return 3

	func is_ready_for_group_drink() -> bool:
		if current_state != int(Customer.State.IN_GROUP):
			return false

		if drinks_consumed_this_visit >= get_effective_drink_limit():
			return false

		return WorldTime.get_total_minutes() >= next_group_drink_minutes

	func on_group_drink_taken(
		minutes_between: int,
		drink: DrinkDefinition = null
	) -> void:
		drinks_consumed_this_visit += 1
		shared_drinks_consumed += 1
		last_drink_definition = drink
		next_group_drink_minutes = (
			WorldTime.get_total_minutes() + minutes_between
		)

	func begin_group_departure() -> void:
		departing = true
		departure_reason = &"group_departure"
		current_state = int(Customer.State.LEAVING_TO_DOOR)

	func finish_customer() -> void:
		was_finished = true
		state_when_finished = current_state


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
	print("GROUP LOOP TEST")
	print("  passed: %d" % passed)
	print("  failed: %d" % failed)
	print("==================================================")

	get_tree().quit(1 if failed > 0 else 0)
