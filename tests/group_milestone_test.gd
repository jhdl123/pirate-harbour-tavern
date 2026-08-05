extends Node

## Covers the group milestone pass: delivery clearance, the leader's order
## icon, the Captain customer type and the keg-delivery role restriction.
##
## Members are stubs, as in the two suites before this. They implement exactly
## the member API the group calls, so a method quietly disappearing from
## Customer fails an assertion here rather than doing nothing in play.
##
## The bartender/tavern-hand check goes through TaskBoard.claim() itself, not
## through a comparison of two resource files: claim() is the chokepoint the
## real game uses, so that is the thing worth testing.

var passed: int = 0
var failed: int = 0

var registry: BeverageRegistry
var vessel_pool: VesselPool
var order_service: GroupOrderService
var manager: GroupManager
var stock_service: GroupKegStockService
var storage: StockStorage
var keg_item: ItemDefinition
var icon_texture: Texture2D

var areas: Array[GroupStandingArea] = []
var finished_diagnostics: Dictionary = {}
var economy_credits: Array[int] = []

var _delivery_blocked: bool = false
var _worker: StubWorker = null


func _ready() -> void:
	registry = load("res://Data/beverage/beverage_registry.tres")
	registry.rebuild()

	await _build_world()

	await _test_ordinary_group_icon()
	await _test_captain_group_icon()
	await _test_icon_persists_through_waits()
	await _test_icon_hidden_after_delivery()
	await _test_icon_hidden_on_cleanup()
	_test_leader_replacement_transfers_icon()
	await _test_members_step_outward()
	await _test_delivery_places_and_reforms()
	await _test_blocked_member_does_not_freeze()
	await _test_delivery_timeout_releases()
	_test_bartender_cannot_claim_keg_task()
	await _test_captain_pays_once()
	await _test_ten_consecutive_groups()

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

	for pair: Array in [[&"ale", "AleStation"], [&"kill_devil", "RumStation"]]:
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

	keg_item = load("res://Data/items/group_servings/ale_table_keg.tres")
	icon_texture = load("res://Data/items/drinks/ale.tres").order_icon_texture

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
	manager.delivery_patience_minutes = 14
	manager.use_real_keg_stock = true
	manager.leisure_enabled = true
	add_child(manager)

	manager.group_completed.connect(_on_group_finished)
	manager.group_failed.connect(_on_group_failed)

	var economy := StubEconomy.new()
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


func _stock_kegs(count: int) -> void:
	if count > 0:
		storage.add_item(keg_item, count)


func _clear_kegs() -> void:
	storage.clear_all()


func _make_group(size: int, with_captain: bool = false) -> CustomerGroup:
	var group := CustomerGroup.new()
	group.definition = load("res://Data/groups/dock_workers.tres")
	group.beverage_registry = registry
	group.vessel_pool = vessel_pool
	group.standing_places_only = true
	group.member_departure_delay = 0.0
	group.member_entry_delay = 0.0
	group.slot_arrival_timeout_minutes = 2
	group.maximum_slot_retries = 1
	group.group_order_icon_texture = icon_texture
	group.delivery_clearance_timeout = 3
	group.delivery_reform_timeout = 3
	group.minimum_leisure_minutes = 3
	group.maximum_leisure_minutes = 4
	group.recall_timeout_minutes = 2
	add_child(group)

	for index: int in range(size):
		var member := StubMember.new()
		member.name = "M%d_%s" % [index, group.group_id]
		member.starting_wealth = 90.0

		if with_captain and index == 0:
			member.customer_type = load("res://resources/CustomerTypes/captain.tres")
		else:
			member.customer_type = load("res://resources/CustomerTypes/sailor.tres")

		add_child(member)
		group.add_member(member)

	group.set_leader(group.members[0])

	return group


func _run_minutes(count: int) -> void:
	for _step: int in range(count):
		WorldTime.advance_minutes(1)

		await get_tree().process_frame
		await get_tree().process_frame

		_drive_delivery_tasks()


## Walks any open keg task through its real executor steps.
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

		for _attempt: int in range(8):
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


## Runs until the group reaches one of [param states], or the budget is spent.
func _run_until_state(
	group: CustomerGroup, states: Array, budget: int
) -> bool:
	for _step: int in range(budget):
		if not is_instance_valid(group):
			return false

		if states.has(group.state):
			return true

		await _run_minutes(1)

	return is_instance_valid(group) and states.has(group.state)


func _count_icons(group: CustomerGroup) -> int:
	var shown: int = 0

	for member: Node in group.members:
		if is_instance_valid(member) and bool(member.get(&"icon_visible")):
			shown += 1

	return shown


# --- Tests -------------------------------------------------------------------

func _test_ordinary_group_icon() -> void:
	_clear_kegs()
	_stock_kegs(1)
	_delivery_blocked = true

	var group: CustomerGroup = _make_group(3)

	manager.register_group(group)

	await get_tree().process_frame
	await _run_minutes(6)

	_check(
		_count_icons(group) == 1,
		"ICON: exactly one order icon is shown",
		"ICON: %d icons were shown" % _count_icons(group)
	)

	_check(
		bool(group.leader.get(&"icon_visible")),
		"ICON: the icon is above the leader",
		"ICON: the icon is not above the leader"
	)

	_delivery_blocked = false

	await _run_minutes(40)


func _test_captain_group_icon() -> void:
	_clear_kegs()
	_stock_kegs(1)
	_delivery_blocked = true

	var group: CustomerGroup = _make_group(4, true)
	var captain: Node = group.members[0]

	manager.register_group(group)

	await get_tree().process_frame
	await _run_minutes(6)

	_check(
		group.has_captain(),
		"CAPTAIN: the group reports a Captain leader",
		"CAPTAIN: has_captain() was false"
	)

	_check(
		bool(captain.get(&"icon_visible")) and _count_icons(group) == 1,
		"CAPTAIN: the icon is above the Captain, and only the Captain",
		"CAPTAIN: %d icons shown, captain=%s"
		% [_count_icons(group), captain.get(&"icon_visible")]
	)

	_delivery_blocked = false

	await _run_minutes(40)


func _test_icon_persists_through_waits() -> void:
	_clear_kegs()

	# No stock at all, so the group sits in the stock wait with the icon up.
	var group: CustomerGroup = _make_group(3)

	manager.register_group(group)

	await get_tree().process_frame
	await _run_minutes(4)

	var during_stock_wait: int = _count_icons(group)

	_stock_kegs(1)
	_delivery_blocked = true

	await _run_minutes(4)

	var during_delivery_wait: int = _count_icons(group)

	_check(
		during_stock_wait == 1,
		"ICON-WAIT: the icon stayed up during the stock wait",
		"ICON-WAIT: %d icons during the stock wait" % during_stock_wait
	)

	_check(
		during_delivery_wait == 1,
		"ICON-WAIT: the icon stayed up during the delivery wait",
		"ICON-WAIT: %d icons during the delivery wait" % during_delivery_wait
	)

	_delivery_blocked = false

	await _run_minutes(40)


func _test_icon_hidden_after_delivery() -> void:
	_clear_kegs()
	_stock_kegs(1)

	var group: CustomerGroup = _make_group(3)

	manager.register_group(group)

	await get_tree().process_frame

	var delivered: bool = await _run_until_state(
		group,
		[
			CustomerGroup.State.REFORMING,
			CustomerGroup.State.CONSUMING,
		],
		30
	)

	_check(
		delivered,
		"ICON-OFF: the group reached the post-delivery phase",
		"ICON-OFF: the group never received its keg"
	)

	if delivered:
		_check(
			_count_icons(group) == 0,
			"ICON-OFF: the icon went as soon as the keg landed",
			"ICON-OFF: %d icon(s) survived the delivery" % _count_icons(group)
		)

		_check(
			String(group.order_icon_hidden_reason) == "keg_delivered",
			"ICON-OFF: the hide reason was keg_delivered",
			"ICON-OFF: the hide reason was '%s'"
			% group.order_icon_hidden_reason
		)

	await _run_minutes(40)


func _test_icon_hidden_on_cleanup() -> void:
	_clear_kegs()
	_delivery_blocked = true

	var group: CustomerGroup = _make_group(3)
	var members: Array[Node] = group.members.duplicate()

	manager.register_group(group)

	await get_tree().process_frame
	await _run_minutes(4)

	group.cleanup()

	var remaining: int = 0

	for member: Node in members:
		if bool(member.get(&"icon_visible")):
			remaining += 1

	_check(
		remaining == 0,
		"ICON-CLEANUP: cleanup left no orphan icon",
		"ICON-CLEANUP: %d icon(s) survived cleanup" % remaining
	)

	_delivery_blocked = false

	await _run_minutes(6)


func _test_leader_replacement_transfers_icon() -> void:
	var group: CustomerGroup = _make_group(3)

	group.show_order_icon()

	var original: Node = group.leader

	_check(
		bool(original.get(&"icon_visible")),
		"LEADER: the icon started above the original leader",
		"LEADER: the icon never appeared"
	)

	# The leader walks off mid-order, which used to lose the icon entirely.
	group.remove_member(original)

	group.show_order_icon()

	_check(
		is_instance_valid(group.leader) and group.leader != original,
		"LEADER: a replacement leader was chosen",
		"LEADER: no replacement leader"
	)

	_check(
		bool(group.leader.get(&"icon_visible")) and _count_icons(group) == 1,
		"LEADER: the icon moved to the new leader, and only there",
		"LEADER: %d icon(s) after the handover" % _count_icons(group)
	)

	group.cleanup()
	group.queue_free()


func _test_members_step_outward() -> void:
	_clear_kegs()
	_stock_kegs(1)
	_delivery_blocked = true

	var group: CustomerGroup = _make_group(4)

	manager.register_group(group)

	await get_tree().process_frame
	await _run_minutes(6)

	# Capture the drinking slots before anybody is asked to move.
	var original_slots: Dictionary = {}

	for member: Node in group.get_valid_members():
		original_slots[member] = group.place.get_slot_for(
			group.get_slot_index_for(member)
		)

	var centre: Vector2 = group.place.get_centre()
	var started: bool = group.begin_delivery_clearance()

	_check(
		started,
		"STEP-BACK: clearance started",
		"STEP-BACK: clearance could not start"
	)

	var moved_out: int = 0
	var slots_intact: int = 0

	for member: Node in group.get_valid_members():
		var temporary: Vector2 = member.get(&"delivery_slot_position")
		var original: Vector2 = original_slots[member]

		if temporary.distance_to(centre) > original.distance_to(centre) + 1.0:
			moved_out += 1

		if group.place.get_slot_for(group.get_slot_index_for(member)) == original:
			slots_intact += 1

	_check(
		moved_out == group.get_valid_members().size(),
		"STEP-BACK: every member's temporary position is farther out",
		"STEP-BACK: only %d of %d moved outward"
		% [moved_out, group.get_valid_members().size()]
	)

	_check(
		slots_intact == group.get_valid_members().size(),
		"STEP-BACK: the normal drinking slots were left untouched",
		"STEP-BACK: %d slot(s) were overwritten"
		% [group.get_valid_members().size() - slots_intact]
	)

	_check(
		group.delivery_approach_position != Vector2.ZERO
		and group.delivery_approach_position.distance_to(centre) > 1.0,
		"STEP-BACK: a delivery approach off the keg point was chosen",
		"STEP-BACK: no usable approach position was chosen"
	)

	# The manual call above consumed the group's one-shot clearance guard, so
	# reset it and let the real flow run this group to completion.
	group.reset_delivery_phase()

	_delivery_blocked = false

	await _run_minutes(45)


func _test_delivery_places_and_reforms() -> void:
	_clear_kegs()
	_stock_kegs(1)

	var group: CustomerGroup = _make_group(4)

	manager.register_group(group)

	await get_tree().process_frame

	var cleared: bool = await _run_until_state(
		group,
		[
			CustomerGroup.State.CLEARING_DELIVERY_SPACE,
			CustomerGroup.State.DELIVERY_IN_PROGRESS,
		],
		25
	)

	_check(
		cleared,
		"DELIVER: the group entered the clearance phase",
		"DELIVER: the clearance phase never started"
	)

	var drinking: bool = await _run_until_state(
		group, [CustomerGroup.State.CONSUMING], 30
	)

	_check(
		drinking,
		"DELIVER: the keg was placed and the group reformed into drinking",
		"DELIVER: the group never reached drinking"
	)

	if drinking:
		_check(
			group.delivery_completed and group.reform_completed_at_minutes >= 0,
			"DELIVER: delivery and reform were both recorded",
			"DELIVER: delivered=%s reform_at=%d"
			% [group.delivery_completed, group.reform_completed_at_minutes]
		)

		var stale: int = 0

		for member: Node in group.get_valid_members():
			if bool(member.get(&"is_stepped_back_for_delivery")):
				stale += 1

		_check(
			stale == 0,
			"DELIVER: no temporary delivery position survived reforming",
			"DELIVER: %d member(s) still marked stepped back" % stale
		)

	await _run_minutes(45)


func _test_blocked_member_does_not_freeze() -> void:
	_clear_kegs()
	_stock_kegs(1)

	var group: CustomerGroup = _make_group(4)

	# One member refuses to move at all, which is the case that used to leave
	# the tavern hand standing outside a closed ring until patience ran out.
	# Set before the group starts, so it is already true when clearance runs.
	(group.members[1] as StubMember).refuses_to_move = true

	manager.register_group(group)

	await get_tree().process_frame

	var drinking: bool = await _run_until_state(
		group, [CustomerGroup.State.CONSUMING], 40
	)

	_check(
		drinking,
		"BLOCKED: one immovable member did not freeze the delivery",
		"BLOCKED: the group stalled in %s" % group.get_state_label()
	)

	_check(
		group.delivery_clearance_recoveries > 0,
		"BLOCKED: the clearance recovery ran (%d recoveries)"
		% group.delivery_clearance_recoveries,
		"BLOCKED: no recovery was recorded for the blocked member"
	)

	await _run_minutes(45)


func _test_delivery_timeout_releases() -> void:
	_clear_kegs()
	_stock_kegs(1)
	_delivery_blocked = true
	economy_credits.clear()

	var group: CustomerGroup = _make_group(3)
	var result: Dictionary = await _register_and_run(group, 55)

	_delivery_blocked = false

	_check(
		stock_service.get_outstanding_count() == 0,
		"TIMEOUT: the stock reservation was released",
		"TIMEOUT: %d reservation(s) outstanding"
		% stock_service.get_outstanding_count()
	)

	_check(
		TaskBoard.get_open_tasks_of_type(
			TavernTaskTypes.DELIVER_GROUP_KEG
		).is_empty(),
		"TIMEOUT: no orphan delivery task remains",
		"TIMEOUT: a delivery task outlived its group"
	)

	_check(
		economy_credits.is_empty(),
		"TIMEOUT: nothing was charged for a keg that never arrived",
		"TIMEOUT: %d payment(s) were taken" % economy_credits.size()
	)

	_check(
		not bool(result.get("order_icon_shown", false)),
		"TIMEOUT: the icon was hidden on final failure",
		"TIMEOUT: the icon was still shown at the end"
	)


## The role restriction, tested at TaskBoard.claim() - the real chokepoint.
func _test_bartender_cannot_claim_keg_task() -> void:
	var task: TavernTask = TaskBoard.create_task(
		TavernTaskTypes.DELIVER_GROUP_KEG,
		"group_keg:role_test",
		{
			"required_item": keg_item,
			"required_quantity": 1,
			"metadata": { "group_id": "role_test" },
		}
	)

	_check(
		task != null,
		"ROLE: a keg-delivery task was created",
		"ROLE: the task board refused to create the task"
	)

	if task == null:
		return

	var bartender := StubRoleWorker.new()
	bartender.name = "StubBartender"
	bartender.capabilities = _load_capabilities("res://Data/staff/bartender.tres")
	add_child(bartender)

	var hand := StubRoleWorker.new()
	hand.name = "StubTavernHand"
	hand.capabilities = _load_capabilities("res://Data/staff/tavern_hand.tres")
	add_child(hand)

	_check(
		not TaskBoard.claim(task, bartender, &"stub_bartender"),
		"ROLE: the bartender was refused the keg task",
		"ROLE: the bartender claimed a keg task"
	)

	_check(
		task.state == TavernTask.State.AVAILABLE,
		"ROLE: the task stayed available after the refusal",
		"ROLE: the refused task is now %s" % task.get_state_name()
	)

	_check(
		TaskBoard.claim(task, hand, &"stub_tavern_hand"),
		"ROLE: the tavern hand claimed the same task",
		"ROLE: the tavern hand could not claim the keg task"
	)

	TaskBoard.cancel(task, &"role_test_finished")


func _load_capabilities(path: String) -> Array[StringName]:
	var definition: Resource = load(path)
	var typed: Array[StringName] = []

	if definition == null:
		return typed

	for entry: Variant in definition.get(&"capabilities"):
		typed.append(StringName(entry))

	return typed


func _test_captain_pays_once() -> void:
	_clear_kegs()
	_stock_kegs(1)
	economy_credits.clear()

	var group: CustomerGroup = _make_group(4, true)
	var captain: StubMember = group.members[0] as StubMember
	var wealth_before: float = captain.needs.wealth

	var result: Dictionary = await _register_and_run(group, 70)

	_check(
		economy_credits.size() == 1,
		"CAPTAIN-PAY: the tavern was credited exactly once",
		"CAPTAIN-PAY: %d credit(s)" % economy_credits.size()
	)

	_check(
		captain.needs.wealth < wealth_before,
		"CAPTAIN-PAY: the Captain's money went down",
		"CAPTAIN-PAY: the Captain paid nothing"
	)

	_check(
		String(result.get("group_paid_by", "")) == captain.name,
		"CAPTAIN-PAY: the report names the Captain as payer",
		"CAPTAIN-PAY: the report names '%s'" % result.get("group_paid_by", "")
	)

	_check(
		bool(result.get("has_captain", false)),
		"CAPTAIN-PAY: the report records the group as Captain-led",
		"CAPTAIN-PAY: has_captain was not recorded"
	)


func _test_ten_consecutive_groups() -> void:
	_clear_kegs()
	_stock_kegs(12)
	economy_credits.clear()

	var delivered: int = 0
	var captain_groups: int = 0

	for index: int in range(10):
		var group: CustomerGroup = _make_group(3, index % 4 == 0)

		if index % 4 == 0:
			captain_groups += 1

		var result: Dictionary = await _register_and_run(group, 70)

		if bool(result.get("delivery_completed", false)):
			delivered += 1

	_check(
		delivered >= 9,
		"SOAK: %d of 10 consecutive groups received a keg" % delivered,
		"SOAK: only %d of 10 groups received a keg" % delivered
	)

	_check(
		captain_groups > 0,
		"SOAK: the mix included %d Captain group(s)" % captain_groups,
		"SOAK: no Captain groups were run"
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
		economy_credits.size() == delivered,
		"SOAK: one payment per delivered keg (%d)" % delivered,
		"SOAK: %d payments for %d kegs" % [economy_credits.size(), delivered]
	)

	var stale_icons: int = 0

	for node: Node in get_children():
		var stub := node as StubMember

		if stub != null and stub.icon_visible:
			stale_icons += 1

	_check(
		stale_icons == 0,
		"SOAK: no order icon was left showing",
		"SOAK: %d stale icon(s)" % stale_icons
	)


# --- Harness -----------------------------------------------------------------

func _check(condition: bool, pass_text: String, fail_text: String) -> void:
	if condition:
		passed += 1
		print("  [PASS] ", pass_text)
	else:
		failed += 1
		print("  [FAIL] ", fail_text)


func _report() -> void:
	print("\n==================================================")
	print("GROUP MILESTONE TEST")
	print("  passed: ", passed)
	print("  failed: ", failed)
	print("==================================================")

	get_tree().quit(1 if failed > 0 else 0)


# --- Stubs -------------------------------------------------------------------

class StubNeeds extends RefCounted:
	var wealth: float = 90.0
	var thirst: float = 0.8
	var mood: float = 0.5
	var engagement: float = 0.5
	var intoxication: float = 0.0

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


## A worker that reports a role's capabilities and nothing else.
class StubRoleWorker extends Node2D:
	var capabilities: Array[StringName] = []

	func get_staff_capabilities() -> Array[StringName]:
		return capabilities


class StubMember extends Node2D:
	var group_id: StringName = &""
	var group_controller: Node = null
	var group_slot_position: Vector2 = Vector2.ZERO
	var group_centre_position: Vector2 = Vector2.ZERO
	var delivery_slot_position: Vector2 = Vector2.ZERO
	var is_stepped_back_for_delivery: bool = false
	var current_state: int = int(Customer.State.GROUP_INSIDE_STAGING)
	var next_group_drink_minutes: int = -1
	var drinks_consumed_this_visit: int = 0
	var shared_drinks_consumed: int = 0
	var group_slot_recoveries: int = 0
	var group_activity_reservation: Reservable = null
	var last_group_activity_id: StringName = &""
	var departure_reason: StringName = &""
	var runtime_customer_id: int = -1
	var customer_type: CustomerType = null
	var needs: StubNeeds = StubNeeds.new()
	var starting_wealth: float = 90.0

	var icon_visible: bool = false
	var refuses_to_move: bool = false
	var was_finished: bool = false

	func _ready() -> void:
		needs.wealth = starting_wealth

	func join_group(new_group_id: StringName, controller: Node) -> void:
		group_id = new_group_id
		group_controller = controller

	func leave_group() -> void:
		group_id = &""
		group_controller = null
		icon_visible = false

	func assign_group_position(target: Vector2, centre: Vector2) -> void:
		group_slot_position = target
		group_centre_position = centre

		if not refuses_to_move:
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

	# --- Delivery clearance ---

	func begin_delivery_step_back(target: Vector2) -> void:
		delivery_slot_position = target
		is_stepped_back_for_delivery = true

		if not refuses_to_move:
			global_position = target

	func refresh_delivery_step_back() -> void:
		group_slot_recoveries += 1
		begin_delivery_step_back(delivery_slot_position)

	func accept_delivery_clearance(snap_to_slot: bool = false) -> void:
		if snap_to_slot:
			# Placement is the fallback, so it works even on a member that
			# refuses to walk anywhere.
			global_position = delivery_slot_position

	func end_delivery_step_back() -> void:
		is_stepped_back_for_delivery = false
		delivery_slot_position = Vector2.ZERO

		if not refuses_to_move:
			global_position = group_slot_position

	# --- Order icon ---

	func show_group_order_icon(_texture: Texture2D) -> void:
		icon_visible = true

	func hide_group_order_icon() -> void:
		icon_visible = false

	func is_showing_group_order_icon() -> bool:
		return icon_visible

	# --- Drinking ---

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
		return false

	func begin_group_relax(_minimum: float, _maximum: float) -> void:
		pass

	func begin_returning_to_group_slot() -> void:
		current_state = int(Customer.State.IN_GROUP)

	func cancel_group_activity() -> void:
		pass

	func release_group_activity_reservation() -> void:
		pass

	func begin_group_departure() -> void:
		icon_visible = false
		is_stepped_back_for_delivery = false
		delivery_slot_position = Vector2.ZERO
		departure_reason = &"group_departure"
		current_state = int(Customer.State.LEAVING_TO_DOOR)

	func finish_customer() -> void:
		was_finished = true
		icon_visible = false
