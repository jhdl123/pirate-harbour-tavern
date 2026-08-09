extends Node

## Drives the group parity pass: leisure, leader payment, real keg stock and
## staff delivery.
##
## Members are stubs again, for the same reason group_loop_test uses them: this
## suite is about the group state machine, the stock ledger and the delivery
## handshake. The stub implements exactly the member API the group calls, so a
## method that quietly disappears from Customer fails here rather than silently
## doing nothing in play.
##
## The delivery task is driven by calling the executor's own steps rather than
## by spawning a worker and waiting for it to walk. The executor is the thing
## under test; the walking is ActorNavigation's job and is covered elsewhere.

var passed: int = 0
var failed: int = 0

var registry: BeverageRegistry
var vessel_pool: VesselPool
var order_service: GroupOrderService
var manager: GroupManager
var stock_service: GroupKegStockService
var storage: StockStorage
var keg_item: ItemDefinition

var areas: Array[GroupStandingArea] = []
var activity_points: Array[TavernActivityPoint] = []

var finished_diagnostics: Dictionary = {}
var economy_credits: Array[int] = []


func _ready() -> void:
	registry = load("res://Data/beverage/beverage_registry.tres")
	registry.rebuild()

	await _build_world()

	await _test_three_member_full_loop()
	await _test_six_member_full_loop()
	await _test_leisure_relax()
	await _test_leisure_socialise()
	await _test_leisure_darts_and_return()
	await _test_recall_before_departure()
	await _test_leader_pays_once()
	await _test_failed_delivery_takes_no_payment()
	await _test_two_groups_cannot_reserve_last_keg()
	await _test_out_of_stock_group_exits_cleanly()
	await _test_cancelled_order_releases_stock()
	await _test_serving_absent_before_delivery()
	await _test_ten_consecutive_groups()
	_test_cleanup_twice_returns_nothing_twice()

	_report()


# --- World -------------------------------------------------------------------

func _build_world() -> void:
	vessel_pool = VesselPool.new()
	vessel_pool.registry = registry
	add_child(vessel_pool)

	for id: StringName in [&"pitcher", &"punch_bowl", &"table_cask"]:
		vessel_pool.set_stock(id, 4)

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

	storage = load("res://scenes/furniture/stock_storage.tscn").instantiate()
	storage.name = "StockStorage"
	add_child(storage)

	keg_item = load("res://Data/items/group_servings/small_beer_table_keg.tres")

	stock_service = GroupKegStockService.new()
	stock_service.keg_item = keg_item
	stock_service.starting_keg_count = 0
	add_child(stock_service)

	order_service = GroupOrderService.new()
	order_service.registry = registry
	order_service.vessel_pool = vessel_pool
	add_child(order_service)

	areas.append(_make_area("dock_corner", Vector2(0, 300), 2, 8))
	areas.append(_make_area("bar_end", Vector2(400, 300), 2, 8))
	areas.append(_make_area("hearth", Vector2(800, 300), 2, 8))

	activity_points.append(_make_activity_point(&"darts", Vector2(200, 600)))

	manager = GroupManager.new()
	manager.registry = registry
	manager.order_service = order_service
	manager.vessel_pool = vessel_pool
	manager.keg_stock_service = stock_service
	manager.maximum_active_groups = 4
	manager.minutes_before_ordering = 1
	manager.minutes_between_drinks = 1
	manager.first_drink_delay_minutes = 1
	manager.minutes_between_serving_attempts = 1
	manager.minutes_between_stock_attempts = 1
	manager.delivery_patience_minutes = 12
	manager.use_real_keg_stock = true
	manager.leisure_enabled = true
	add_child(manager)

	manager.group_completed.connect(_on_group_finished)
	manager.group_failed.connect(_on_group_failed)

	var economy := StubEconomy.new()
	economy.name = "StubEconomy"
	economy.sink = self
	economy.add_to_group(&"economy")
	add_child(economy)

	await get_tree().process_frame
	await get_tree().process_frame


func _on_group_finished(group: CustomerGroup) -> void:
	finished_diagnostics[String(group.group_id)] = group.get_diagnostics()


func _on_group_failed(group: CustomerGroup, _reason: String) -> void:
	finished_diagnostics[String(group.group_id)] = group.get_diagnostics()


func note_economy_credit(amount: int) -> void:
	economy_credits.append(amount)


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


func _make_activity_point(
	activity_id: StringName, position: Vector2
) -> TavernActivityPoint:
	var point := TavernActivityPoint.new()
	point.name = "Activity_" + String(activity_id)
	point.activity_id = activity_id
	point.activity_duration_minutes = 3.0
	point.return_to_seat_after_use = true

	var reservable := Reservable.new()
	reservable.name = "Reservable"
	reservable.reservation_tags = [activity_id]
	point.add_child(reservable)

	var marker := Marker2D.new()
	marker.name = "UsePosition"
	point.add_child(marker)

	add_child(point)
	point.global_position = position

	return point


func _stock_kegs(count: int) -> void:
	if count > 0:
		storage.add_item(keg_item, count)


func _clear_kegs() -> void:
	storage.clear_all()


func _make_group(size: int) -> CustomerGroup:
	var group := CustomerGroup.new()
	group.definition = load("res://Data/groups/dock_workers.tres")
	group.beverage_registry = registry
	group.vessel_pool = vessel_pool
	group.standing_places_only = true
	group.member_departure_delay = 0.0
	group.member_entry_delay = 0.0
	group.slot_arrival_timeout_minutes = 2
	group.maximum_slot_retries = 1
	group.minimum_leisure_minutes = 4
	group.maximum_leisure_minutes = 6
	group.leisure_decision_interval_minutes = 1
	group.leisure_activity_chance = 1.0
	group.recall_timeout_minutes = 3
	add_child(group)

	for index: int in range(size):
		var member := StubMember.new()
		member.name = "M%d_%s" % [index, group.group_id]
		member.starting_wealth = 60.0
		add_child(member)
		group.add_member(member)

	return group


func _run_minutes(count: int) -> void:
	for _step: int in range(count):
		WorldTime.advance_minutes(1)

		await get_tree().process_frame
		await get_tree().process_frame

		_drive_delivery_tasks()


## Runs any open group-keg task to completion, one action per world minute.
##
## Stands in for a worker walking: the executor's real steps are used, so
## collection is a real ItemCarrier transfer out of real storage and placement
## goes through the manager's real delivery completion.
func _drive_delivery_tasks() -> void:
	if _delivery_blocked:
		return

	for task: TavernTask in TaskBoard.get_open_tasks_of_type(
		TavernTaskTypes.DELIVER_GROUP_KEG
	):
		var worker: StubWorker = _get_worker()

		var executor := DeliverGroupKegExecutor.new()
		executor.task_type = TavernTaskTypes.DELIVER_GROUP_KEG

		if not executor.can_claim(worker, task):
			continue

		if not executor.on_claimed(worker, task):
			continue

		# Two actions: collect, then place. Movement is skipped by putting the
		# worker where the step asks it to be.
		for _attempt: int in range(6):
			var step: StaffTaskStep = executor.get_next_step(worker, task)

			match step.kind:
				StaffTaskStep.Kind.MOVE:
					worker.global_position = step.position

				StaffTaskStep.Kind.ACT:
					if executor.perform_action(worker, task) != \
							StaffTaskExecutor.ActionResult.DONE:
						break

				StaffTaskStep.Kind.COMPLETE:
					TaskBoard.complete(task)
					break

				_:
					break

		return


var _delivery_blocked: bool = false
var _worker: StubWorker = null


func _get_worker() -> StubWorker:
	if _worker == null or not is_instance_valid(_worker):
		_worker = StubWorker.new()
		_worker.name = "StubWorker"
		add_child(_worker)

	return _worker


func _register_and_run(group: CustomerGroup, minutes: int) -> Dictionary:
	var id: String = String(group.group_id)

	manager.register_group(group)

	await get_tree().process_frame
	await _run_minutes(minutes)

	if finished_diagnostics.has(id):
		return finished_diagnostics[id]

	if is_instance_valid(group):
		return group.get_diagnostics()

	return {}


# --- Tests -------------------------------------------------------------------

func _test_three_member_full_loop() -> void:
	_stock_kegs(2)

	var before: int = storage.count_item(keg_item.item_id)
	var group: CustomerGroup = _make_group(3)

	var result: Dictionary = await _register_and_run(group, 70)

	_check(
		String(result.get("group_delivery_status", "")) == "delivered",
		"LOOP3: the keg was delivered by staff",
		"LOOP3: delivery status was '%s'" % result.get("group_delivery_status", "")
	)

	_check(
		int(result.get("shared_drinks_consumed", 0)) > 0,
		"LOOP3: the group drank %d portions"
		% int(result.get("shared_drinks_consumed", 0)),
		"LOOP3: nobody drank"
	)

	_check(
		bool(result.get("group_payment_made", false)),
		"LOOP3: the group paid for its keg",
		"LOOP3: no payment was recorded"
	)

	_check(
		storage.count_item(keg_item.item_id) == before - 1,
		"LOOP3: exactly one keg left storage",
		"LOOP3: storage went %d -> %d"
		% [before, storage.count_item(keg_item.item_id)]
	)

	_check(
		stock_service.get_outstanding_count() == 0,
		"LOOP3: no stock reservation was left behind",
		"LOOP3: %d reservation(s) still outstanding"
		% stock_service.get_outstanding_count()
	)


func _test_six_member_full_loop() -> void:
	_stock_kegs(1)

	var group: CustomerGroup = _make_group(6)
	var result: Dictionary = await _register_and_run(group, 80)

	_check(
		String(result.get("group_delivery_status", "")) == "delivered",
		"LOOP6: the keg was delivered",
		"LOOP6: delivery status was '%s'" % result.get("group_delivery_status", "")
	)

	_check(
		int(result.get("shared_drinks_consumed", 0)) > 0,
		"LOOP6: the six-member group drank",
		"LOOP6: nobody drank"
	)

	_check(
		bool(result.get("cleanup_completed", false)),
		"LOOP6: cleanup completed",
		"LOOP6: cleanup did not complete"
	)


func _test_leisure_relax() -> void:
	_stock_kegs(1)

	var group: CustomerGroup = _make_group(3)
	group.leisure_activities = [&"relax"]
	group.minimum_leisure_minutes = 10
	group.maximum_leisure_minutes = 12
	var members: Array[Node] = group.members.duplicate()

	var result: Dictionary = await _register_and_run(group, 80)

	var relaxed: int = 0

	for member: Node in members:
		if (member as StubMember).relax_count > 0:
			relaxed += 1

	_check(
		relaxed > 0,
		"LEISURE: %d member(s) relaxed at their group slot" % relaxed,
		"LEISURE: nobody relaxed during the leisure phase"
	)

	_check(
		int(result.get("group_relax_count", 0)) > 0,
		"LEISURE: the group counted %d relax activities"
		% int(result.get("group_relax_count", 0)),
		"LEISURE: the group counted no relax activities"
	)


func _test_leisure_socialise() -> void:
	_stock_kegs(1)

	var group: CustomerGroup = _make_group(4)
	group.leisure_activities = [&"socialise"]
	group.minimum_leisure_minutes = 10
	group.maximum_leisure_minutes = 12
	var members: Array[Node] = group.members.duplicate()

	var result: Dictionary = await _register_and_run(group, 80)

	var socialised: int = 0
	var had_partner: bool = false

	for member: Node in members:
		var stub := member as StubMember

		if stub.socialise_count > 0:
			socialised += 1

			if stub.last_social_partner != null:
				had_partner = true

	_check(
		socialised > 0,
		"SOCIAL: %d member(s) socialised" % socialised,
		"SOCIAL: nobody socialised"
	)

	_check(
		had_partner,
		"SOCIAL: the partner was another member of the same group",
		"SOCIAL: socialising happened with no partner"
	)


func _test_leisure_darts_and_return() -> void:
	_stock_kegs(1)

	var group: CustomerGroup = _make_group(4)
	group.leisure_activities = [&"darts"]
	group.minimum_leisure_minutes = 10
	group.maximum_leisure_minutes = 12

	var members: Array[Node] = group.members.duplicate()

	var result: Dictionary = await _register_and_run(group, 90)

	var played: int = 0
	var returned: int = 0

	for member: Node in members:
		var stub := member as StubMember

		if stub.darts_count > 0:
			played += 1

			if stub.returned_to_slot:
				returned += 1

	_check(
		played > 0,
		"DARTS: %d member(s) played darts" % played,
		"DARTS: nobody used the darts point"
	)

	_check(
		played == 0 or returned > 0,
		"DARTS: players came back to their group slot",
		"DARTS: a player never returned to its slot"
	)

	_check(
		_all_activity_points_free(),
		"DARTS: the darts point was released",
		"DARTS: the darts point is still reserved"
	)


func _test_recall_before_departure() -> void:
	_stock_kegs(1)

	var group: CustomerGroup = _make_group(4)
	var members: Array[Node] = group.members.duplicate()

	# One member refuses to come back, which is exactly the case that must not
	# hold the party in the tavern forever.
	(members[0] as StubMember).ignores_recall = true

	var result: Dictionary = await _register_and_run(group, 100)

	_check(
		_all_activity_points_free(),
		"RECALL: every activity reservation was released",
		"RECALL: an activity point is still held after departure"
	)

	_check(
		String(result.get("group_departure", "")) == "group_departure",
		"RECALL: the departure reason stayed group_departure",
		"RECALL: departure reason was '%s'" % result.get("group_departure", "")
	)

	_check(
		bool(result.get("cleanup_completed", false)),
		"RECALL: a member that would not return did not block cleanup",
		"RECALL: the group never finished"
	)


func _test_leader_pays_once() -> void:
	_stock_kegs(1)
	economy_credits.clear()

	var group: CustomerGroup = _make_group(3)
	var members: Array[Node] = group.members.duplicate()
	var leader: StubMember = group.leader as StubMember
	var leader_wealth_before: float = leader.needs.wealth

	var result: Dictionary = await _register_and_run(group, 80)

	_check(
		economy_credits.size() == 1,
		"PAYMENT: the tavern was credited exactly once",
		"PAYMENT: the tavern was credited %d time(s)" % economy_credits.size()
	)

	_check(
		leader.needs.wealth < leader_wealth_before,
		"PAYMENT: the leader's money went down",
		"PAYMENT: the leader paid nothing"
	)

	var payers: int = 0

	for member: Node in members:
		if (member as StubMember).needs.wealth < 60.0:
			payers += 1

	_check(
		payers == 1,
		"PAYMENT: exactly one member paid, not the whole party",
		"PAYMENT: %d members were charged" % payers
	)

	_check(
		String(result.get("group_paid_by", "")) == leader.name,
		"PAYMENT: the report names the leader as the payer",
		"PAYMENT: the report names '%s'" % result.get("group_paid_by", "")
	)


func _test_failed_delivery_takes_no_payment() -> void:
	_stock_kegs(1)
	economy_credits.clear()

	# Nobody delivers anything for this visit.
	_delivery_blocked = true

	var group: CustomerGroup = _make_group(3)
	var result: Dictionary = await _register_and_run(group, 60)

	_delivery_blocked = false

	_check(
		economy_credits.is_empty(),
		"NO-PAY: an undelivered keg was never charged for",
		"NO-PAY: the tavern was credited %d time(s)" % economy_credits.size()
	)

	_check(
		not bool(result.get("group_payment_made", false)),
		"NO-PAY: no group payment was recorded",
		"NO-PAY: a payment was recorded without a keg"
	)

	_check(
		int(result.get("shared_drinks_consumed", 0)) == 0,
		"NO-PAY: nobody drank from a keg that never arrived",
		"NO-PAY: drinking happened without a delivery"
	)

	_check(
		stock_service.get_outstanding_count() == 0,
		"NO-PAY: the stock claim was handed back",
		"NO-PAY: %d claim(s) left outstanding"
		% stock_service.get_outstanding_count()
	)

	TaskBoard.get_open_tasks_of_type(TavernTaskTypes.DELIVER_GROUP_KEG)

	_check(
		TaskBoard.get_open_tasks_of_type(
			TavernTaskTypes.DELIVER_GROUP_KEG
		).is_empty(),
		"NO-PAY: no orphan delivery task remains",
		"NO-PAY: a delivery task outlived its group"
	)


func _test_two_groups_cannot_reserve_last_keg() -> void:
	_clear_kegs()
	_stock_kegs(1)

	var first: Dictionary = stock_service.reserve_keg(null)
	var second: Dictionary = stock_service.reserve_keg(null)

	_check(
		not first.is_empty(),
		"CONTENTION: the first group claimed the last keg",
		"CONTENTION: the first claim failed"
	)

	_check(
		second.is_empty(),
		"CONTENTION: the second group could not claim the same keg",
		"CONTENTION: the last keg was claimed twice"
	)

	stock_service.release_reservation(
		StringName(String(first.get("reservation_id", "")))
	)

	_check(
		stock_service.count_available_everywhere() == 1,
		"CONTENTION: releasing put the keg back on offer",
		"CONTENTION: %d keg(s) available after release"
		% stock_service.count_available_everywhere()
	)


func _test_out_of_stock_group_exits_cleanly() -> void:
	_clear_kegs()
	economy_credits.clear()

	var group: CustomerGroup = _make_group(3)
	var result: Dictionary = await _register_and_run(group, 60)

	_check(
		String(result.get("group_order_failure_reason", ""))
			== "group_keg_out_of_stock",
		"NO-STOCK: the failure reason was group_keg_out_of_stock",
		"NO-STOCK: reason was '%s'"
			% result.get("group_order_failure_reason", "")
	)

	_check(
		economy_credits.is_empty(),
		"NO-STOCK: nothing was charged",
		"NO-STOCK: money changed hands with no keg"
	)

	_check(
		bool(result.get("cleanup_completed", false)),
		"NO-STOCK: the group left and cleaned up",
		"NO-STOCK: the group did not finish"
	)

	_check(
		manager.get_active_group_count() == 0,
		"NO-STOCK: no active group was left behind",
		"NO-STOCK: %d group(s) still active" % manager.get_active_group_count()
	)


func _test_cancelled_order_releases_stock() -> void:
	_clear_kegs()
	_stock_kegs(1)
	_delivery_blocked = true

	var group: CustomerGroup = _make_group(3)

	manager.register_group(group)

	await get_tree().process_frame
	await _run_minutes(8)

	var claimed: bool = stock_service.get_outstanding_count() > 0

	# The party gives up part-way through, which is the case that must not
	# strand a keg as permanently spoken for.
	group.begin_departure("test_cancelled")

	await _run_minutes(6)

	_delivery_blocked = false

	_check(
		claimed,
		"CANCEL: a claim existed before the group gave up",
		"CANCEL: no claim was ever made"
	)

	_check(
		stock_service.get_outstanding_count() == 0,
		"CANCEL: the claim was released when the order was cancelled",
		"CANCEL: %d claim(s) still outstanding"
		% stock_service.get_outstanding_count()
	)

	_check(
		storage.count_item(keg_item.item_id) == 1,
		"CANCEL: the keg is still on the shelf, unclaimed",
		"CANCEL: storage holds %d keg(s)"
		% storage.count_item(keg_item.item_id)
	)


func _test_serving_absent_before_delivery() -> void:
	_clear_kegs()
	_stock_kegs(1)
	_delivery_blocked = true

	var group: CustomerGroup = _make_group(3)

	manager.register_group(group)

	await get_tree().process_frame
	await _run_minutes(8)

	_check(
		group.shared_serving == null,
		"NO-EARLY-KEG: no shared serving exists before delivery",
		"NO-EARLY-KEG: a keg appeared without being carried over"
	)

	_check(
		get_tree().get_nodes_in_group(&"shared_servings").is_empty(),
		"NO-EARLY-KEG: no serving node was spawned early",
		"NO-EARLY-KEG: a serving node exists before delivery"
	)

	_delivery_blocked = false

	await _run_minutes(50)


func _test_ten_consecutive_groups() -> void:
	_clear_kegs()
	_stock_kegs(12)
	economy_credits.clear()

	var completed: int = 0

	for _index: int in range(10):
		var group: CustomerGroup = _make_group(3)
		var result: Dictionary = await _register_and_run(group, 70)

		if String(result.get("group_delivery_status", "")) == "delivered":
			completed += 1

	_check(
		completed >= 9,
		"SOAK: %d of 10 consecutive groups received a keg" % completed,
		"SOAK: only %d of 10 groups received a keg" % completed
	)

	_check(
		manager.get_active_group_count() == 0,
		"SOAK: no active groups remain",
		"SOAK: %d group(s) still active" % manager.get_active_group_count()
	)

	_check(
		stock_service.get_outstanding_count() == 0,
		"SOAK: no stock reservations remain",
		"SOAK: %d reservation(s) remain" % stock_service.get_outstanding_count()
	)

	_check(
		TaskBoard.get_open_tasks_of_type(
			TavernTaskTypes.DELIVER_GROUP_KEG
		).is_empty(),
		"SOAK: no delivery tasks remain",
		"SOAK: delivery tasks were left open"
	)

	_check(
		get_tree().get_nodes_in_group(&"shared_servings").is_empty(),
		"SOAK: no shared-serving nodes remain",
		"SOAK: serving nodes were left in the scene"
	)

	_check(
		_all_activity_points_free(),
		"SOAK: no activity reservations remain",
		"SOAK: an activity point is still reserved"
	)

	_check(
		economy_credits.size() == completed,
		"SOAK: one payment per delivered keg (%d)" % completed,
		"SOAK: %d payments for %d kegs"
		% [economy_credits.size(), completed]
	)


func _test_cleanup_twice_returns_nothing_twice() -> void:
	_clear_kegs()
	_stock_kegs(1)

	var group: CustomerGroup = _make_group(3)

	manager.register_group(group)

	var reservation: Dictionary = stock_service.reserve_keg(group)

	group.stock_reservation_id = StringName(
		String(reservation.get("reservation_id", ""))
	)

	var available_before: int = vessel_pool.get_available(&"table_cask")

	group.cleanup()
	group.cleanup()
	group.cleanup()

	_check(
		stock_service.get_outstanding_count() == 0,
		"IDEMPOTENT: three cleanups released the stock claim exactly once",
		"IDEMPOTENT: %d claim(s) outstanding"
		% stock_service.get_outstanding_count()
	)

	_check(
		vessel_pool.get_available(&"table_cask") == available_before,
		"IDEMPOTENT: no vessel was returned twice",
		"IDEMPOTENT: vessels went %d -> %d"
		% [available_before, vessel_pool.get_available(&"table_cask")]
	)

	_check(
		group.members.is_empty() and group.place == null,
		"IDEMPOTENT: members and place references were cleared",
		"IDEMPOTENT: references survived cleanup"
	)


# --- Helpers -----------------------------------------------------------------

func _set_activity_points_enabled(value: bool) -> void:
	for point: TavernActivityPoint in activity_points:
		if is_instance_valid(point):
			point.set_enabled(value)


func _all_activity_points_free() -> bool:
	for point: TavernActivityPoint in activity_points:
		if not is_instance_valid(point) or point.reservable == null:
			continue

		if not point.enabled:
			continue

		if not point.reservable.is_free():
			return false

	return true


func _check(condition: bool, pass_text: String, fail_text: String) -> void:
	if condition:
		passed += 1
		print("  [PASS] ", pass_text)
	else:
		failed += 1
		print("  [FAIL] ", fail_text)


func _report() -> void:
	print("\n==================================================")
	print("GROUP PARITY TEST")
	print("  passed: ", passed)
	print("  failed: ", failed)
	print("==================================================")

	get_tree().quit(1 if failed > 0 else 0)


# --- Stubs -------------------------------------------------------------------

class StubNeeds extends RefCounted:
	var wealth: float = 60.0
	var thirst: float = 0.8
	var mood: float = 0.5
	var engagement: float = 0.5
	var intoxication: float = 0.0
	var relax_count: float = 0.0
	var socialise_count: float = 0.0
	var darts_count: float = 0.0

	func adjust(need_id: StringName, amount: float) -> void:
		match need_id:
			&"wealth": wealth += amount
			&"thirst": thirst = clampf(thirst + amount, 0.0, 1.0)
			&"mood": mood = clampf(mood + amount, 0.0, 1.0)
			&"engagement": engagement = clampf(engagement + amount, 0.0, 1.0)
			&"intoxication": intoxication = clampf(
				intoxication + amount, 0.0, 1.0
			)


class StubEconomy extends Node:
	var sink: Node = null

	func add_money(amount: int, _reason: StringName = &"") -> void:
		if sink != null:
			sink.call(&"note_economy_credit", amount)


class StubWorker extends Node2D:
	var carrier: ItemCarrier = null

	func _ready() -> void:
		carrier = ItemCarrier.new()
		carrier.name = "ItemCarrier"
		add_child(carrier)

	func get_item_carrier() -> ItemCarrier:
		return carrier


## A group member that implements exactly the API CustomerGroup calls.
##
## Activities finish on a world-minute countdown rather than through
## WorldTime.schedule_in(), so the suite can step time deterministically.
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
	var group_activity_reservation: Reservable = null
	var last_group_activity_id: StringName = &""
	var departure_reason: StringName = &""
	var runtime_customer_id: int = -1
	var needs: StubNeeds = StubNeeds.new()
	var starting_wealth: float = 60.0

	var relax_count: int = 0
	var socialise_count: int = 0
	var darts_count: int = 0
	var last_social_partner: Node = null
	var returned_to_slot: bool = false
	var ignores_recall: bool = false
	var was_finished: bool = false

	var _busy_until_minutes: int = -1
	var _busy_activity: StringName = &""

	func _ready() -> void:
		needs.wealth = starting_wealth
		set_process(true)

	func _process(_delta: float) -> void:
		if _busy_until_minutes < 0:
			return

		if WorldTime.get_total_minutes() < _busy_until_minutes:
			return

		_finish_activity()

	func join_group(new_group_id: StringName, controller: Node) -> void:
		group_id = new_group_id
		group_controller = controller

	func leave_group() -> void:
		group_id = &""
		group_controller = null

	func assign_group_position(target: Vector2, centre: Vector2) -> void:
		group_slot_position = target
		group_centre_position = centre
		global_position = target
		current_state = int(Customer.State.IN_GROUP)
		next_group_drink_minutes = -1

	func refresh_group_slot() -> void:
		group_slot_recoveries += 1
		assign_group_position(group_slot_position, group_centre_position)

	func accept_group_slot_arrival(snap_to_slot: bool = false) -> void:
		if snap_to_slot:
			global_position = group_slot_position

		current_state = int(Customer.State.IN_GROUP)

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
		needs.adjust(&"thirst", -0.35)

		if drink != null:
			needs.adjust(&"intoxication", drink.alcohol_strength * 0.1)

		next_group_drink_minutes = (
			WorldTime.get_total_minutes() + minutes_between
		)

	# --- Leisure ---

	func is_group_member_idle() -> bool:
		return (
			not group_id.is_empty()
			and current_state == int(Customer.State.IN_GROUP)
		)

	func is_group_member_busy() -> bool:
		return current_state in [
			int(Customer.State.RELAXING),
			int(Customer.State.SOCIALISING),
			int(Customer.State.MOVING_TO_ACTIVITY),
			int(Customer.State.USING_ACTIVITY),
			int(Customer.State.RETURNING_TO_SEAT),
		]

	func begin_group_relax(
		minimum_minutes: float,
		_maximum_minutes: float
	) -> void:
		last_group_activity_id = &"relax"
		current_state = int(Customer.State.RELAXING)
		_start_busy(&"relax", int(minimum_minutes))

	func begin_group_socialise(
		partner: Node,
		minimum_minutes: float,
		_maximum_minutes: float,
		_satisfaction: float,
		_partner_satisfaction: float,
		_engagement: float
	) -> void:
		last_group_activity_id = &"socialise"
		last_social_partner = partner
		current_state = int(Customer.State.SOCIALISING)
		_start_busy(&"socialise", int(minimum_minutes))

	func begin_group_activity(point: TavernActivityPoint) -> bool:
		if point == null or point.reservable == null:
			return false

		if not point.reservable.reserve(self):
			return false

		group_activity_reservation = point.reservable
		last_group_activity_id = point.activity_id
		current_state = int(Customer.State.USING_ACTIVITY)
		global_position = point.get_use_position()

		_start_busy(point.activity_id, 3)

		return true

	func _start_busy(activity_id: StringName, minutes: int) -> void:
		_busy_activity = activity_id
		_busy_until_minutes = WorldTime.get_total_minutes() + maxi(1, minutes)

	func _finish_activity() -> void:
		var activity_id: StringName = _busy_activity

		_busy_until_minutes = -1
		_busy_activity = &""

		match activity_id:
			&"relax": relax_count += 1
			&"socialise": socialise_count += 1
			&"darts": darts_count += 1

		if is_instance_valid(group_controller):
			if group_controller.has_method(&"on_member_activity_finished"):
				group_controller.call(
					&"on_member_activity_finished", self, activity_id
				)

		begin_returning_to_group_slot()

	func begin_returning_to_group_slot() -> void:
		release_group_activity_reservation()

		if ignores_recall:
			# Deliberately wedged: the group must move on without it.
			current_state = int(Customer.State.RETURNING_TO_SEAT)
			return

		global_position = group_slot_position
		current_state = int(Customer.State.IN_GROUP)
		returned_to_slot = true

		if is_instance_valid(group_controller):
			if group_controller.has_method(&"on_member_returned_to_slot"):
				group_controller.call(&"on_member_returned_to_slot", self)

	func cancel_group_activity() -> void:
		_busy_until_minutes = -1
		_busy_activity = &""
		release_group_activity_reservation()

	func release_group_activity_reservation() -> void:
		if group_activity_reservation == null:
			return

		var held: Reservable = group_activity_reservation
		group_activity_reservation = null

		if is_instance_valid(held) and held.is_held_by(self):
			held.release(self)

	func begin_group_departure() -> void:
		cancel_group_activity()
		departure_reason = &"group_departure"
		current_state = int(Customer.State.LEAVING_TO_DOOR)

	func finish_customer() -> void:
		was_finished = true
