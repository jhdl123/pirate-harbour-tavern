extends Node

## Headless verification harness for Phase 3A.
##
## Not part of the game. Run with:
##
## [codeblock]
## godot --headless --path . res://tests/phase_3a_headless_test.tscn
## [/codeblock]
##
## It loads the real main scene and drives the real systems - no mocks, no
## private state - then prints one PASS/FAIL line per checked behaviour and
## exits with a non-zero code if anything failed.


var _main: Node = null
var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame

	var main_scene: PackedScene = load("res://scenes/main/main.tscn")

	_main = main_scene.instantiate()

	get_tree().root.add_child.call_deferred(_main)

	await get_tree().create_timer(0.5).timeout

	WorldTime.set_speed(8.0)

	print("\n===== PHASE 3A HEADLESS VERIFICATION =====\n")

	await _test_board_wiring()
	await _test_serving()
	await _test_cleaning()
	await _test_stock_alerts()
	verify_report_export()

	print("\n===== %d checks, %d failed =====\n" % [_checks, _failures])

	get_tree().quit(1 if _failures > 0 else 0)


# -----------------------------------------------------------------------------
# Checks
# -----------------------------------------------------------------------------

func _check(
	label: String,
	condition: bool,
	detail: String = ""
) -> void:
	_checks += 1

	if condition:
		print("  PASS  ", label)
		return

	_failures += 1

	print("  FAIL  ", label, ("" if detail.is_empty() else "  -> " + detail))


## Waits until [param predicate] returns true, or gives up.
func _await_until(
	predicate: Callable,
	timeout_seconds: float = 12.0
) -> bool:
	var elapsed: float = 0.0

	while elapsed < timeout_seconds:
		if bool(predicate.call()):
			return true

		await get_tree().process_frame

		elapsed += get_process_delta_time()

	return false


# -----------------------------------------------------------------------------
# Scene lookups
# -----------------------------------------------------------------------------

func _get_staff() -> StaffMember:
	for node: Node in get_tree().get_nodes_in_group(&"tavern_staff"):
		var staff: StaffMember = node as StaffMember

		if staff != null:
			return staff

	return null


func _get_bar_counter() -> Node:
	var counters: Array = get_tree().get_nodes_in_group(&"bar_counters")

	return null if counters.is_empty() else counters[0]


func _get_station(
	item_id: StringName
) -> DrinksStation:
	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station == null or station.served_drink == null:
			continue

		if station.served_drink.item_id == item_id:
			return station

	return null


func _get_waiting_customer() -> Node:
	for node: Node in get_tree().get_nodes_in_group(&"tavern_customers"):
		if node.has_method(&"is_awaiting_service"):
			if bool(node.call(&"is_awaiting_service")):
				return node

	var game_manager: GameManager = _find_game_manager()

	if game_manager == null:
		return null

	for customer: Node in game_manager.active_customers:
		if customer == null or not is_instance_valid(customer):
			continue

		if not customer.has_method(&"is_awaiting_service"):
			continue

		if bool(customer.call(&"is_awaiting_service")):
			return customer

	return null


func _find_game_manager() -> GameManager:
	if _main == null:
		return null

	return _main.get_node_or_null("Managers/GameManager") as GameManager


func _find_dirty_chair() -> Chair:
	for node: Node in get_tree().get_nodes_in_group(
		Reservable.group_for_tag(&"seat")
	):
		var reservable: Reservable = node as Reservable

		if reservable == null:
			continue

		var chair: Chair = reservable.get_parent() as Chair

		if chair != null and chair.needs_cleaning():
			return chair

	return null


func _find_any_chair() -> Chair:
	for node: Node in get_tree().get_nodes_in_group(
		Reservable.group_for_tag(&"seat")
	):
		var reservable: Reservable = node as Reservable

		if reservable == null:
			continue

		var chair: Chair = reservable.get_parent() as Chair

		if chair != null and chair.is_available():
			return chair

	return null


# -----------------------------------------------------------------------------
# Wiring
# -----------------------------------------------------------------------------

func _test_board_wiring() -> void:
	print("-- Wiring --")

	_check("TaskBoard autoload exists", TaskBoard != null)
	_check("Comms autoload exists", Comms != null)

	_check(
		"serve_drink definition registered",
		TaskBoard.config.find_definition(TavernTaskTypes.SERVE_DRINK) != null
	)

	_check(
		"clean_seat definition registered",
		TaskBoard.config.find_definition(TavernTaskTypes.CLEAN_SEAT) != null
	)

	_check(
		"serve_drink executor registered",
		StaffTaskExecutor.has_executor_for(TavernTaskTypes.SERVE_DRINK)
	)

	_check(
		"clean_seat executor registered",
		StaffTaskExecutor.has_executor_for(TavernTaskTypes.CLEAN_SEAT)
	)

	var staff: StaffMember = _get_staff()

	_check("Tavern Hand present in main scene", staff != null)

	if staff == null:
		return

	_check(
		"Tavern Hand has serve capability",
		staff.get_staff_capabilities().has(StaffCapabilities.SERVE_DRINKS)
	)

	_check(
		"Tavern Hand has clean capability",
		staff.get_staff_capabilities().has(StaffCapabilities.CLEAN_SEATS)
	)

	_check("Tavern Hand has a carrier", staff.get_item_carrier() != null)
	_check("Tavern Hand has an action runner", staff.get_action_runner() != null)

	var bar: Node = _get_bar_counter()

	_check("Bar counter is discoverable by staff", bar != null)


# -----------------------------------------------------------------------------
# Scenario A - basic service
# -----------------------------------------------------------------------------

func _test_serving() -> void:
	print("\n-- Scenario A: serving --")

	var found_customer: bool = await _await_until(
		func() -> bool: return _get_waiting_customer() != null,
		40.0
	)

	_check("a customer reaches the waiting-to-be-served state", found_customer)

	if not found_customer:
		return

	var customer: Node = _get_waiting_customer()
	var wanted: DrinkDefinition = customer.call(&"get_requested_drink")

	_check("waiting customer exposes its requested drink", wanted != null)

	if wanted == null:
		return

	var serve_task_created: bool = await _await_until(
		func() -> bool:
			return not TaskBoard.get_open_tasks_of_type(
				TavernTaskTypes.SERVE_DRINK
			).is_empty(),
		6.0
	)

	_check("a serve_drink task exists for the waiting customer", serve_task_created)

	# Stand in for the player: put the correct prepared drink on the bar.
	var bar: Node = _get_bar_counter()
	var container: ItemContainer = bar.call(&"get_service_container")
	var placed: bool = false

	for index: int in range(container.get_slot_count()):
		var slot: ItemSlot = container.get_slot(index)

		if slot == null or not slot.is_empty():
			continue

		placed = ItemTransferService.give_to_slot(
			slot,
			ItemStack.create(wanted, 1)
		).is_success()

		if placed:
			break

	_check("a prepared drink can be placed in a bar service slot", placed)

	if not placed:
		return

	var drinks_on_bar_before: int = _count_drinks_on_bar()

	var served: bool = await _await_until(
		func() -> bool:
			return not bool(customer.call(&"is_awaiting_service")),
		60.0
	)

	_check("the Tavern Hand delivers the drink to the customer", served)

	if served:
		_check(
			"the customer moved on to drinking",
			customer.get("current_state") == Customer.State.DRINKING,
			"state was " + str(customer.get("current_state"))
		)

	_check(
		"exactly one drink left the bar",
		_count_drinks_on_bar() == drinks_on_bar_before - 1,
		"before %d, after %d" % [drinks_on_bar_before, _count_drinks_on_bar()]
	)

	var staff: StaffMember = _get_staff()

	if staff != null:
		_check(
			"the worker is not left holding the drink",
			not staff.get_item_carrier().is_carrying()
		)

	var summary: Dictionary = TaskBoard.get_summary()

	_check(
		"at least one task completed",
		int(summary["tasks_completed"]) >= 1,
		str(summary)
	)


func _count_drinks_on_bar() -> int:
	var total: int = 0

	for node: Node in get_tree().get_nodes_in_group(&"bar_counters"):
		var container: ItemContainer = node.call(
			&"get_service_container"
		) as ItemContainer

		if container == null:
			continue

		for index: int in range(container.get_slot_count()):
			var slot: ItemSlot = container.get_slot(index)

			if slot != null and not slot.is_empty():
				total += slot.get_quantity()

	return total


# -----------------------------------------------------------------------------
# Scenario D - cleaning
# -----------------------------------------------------------------------------

func _test_cleaning() -> void:
	print("\n-- Scenario D: cleaning --")

	var chair: Chair = _find_dirty_chair()

	if chair == null:
		chair = _find_any_chair()

		if chair == null:
			_check("a chair is available to dirty", false)
			return

		# Stand in for a customer that finished a drink and left.
		chair.cleanable.set_cleaning_task(chair.empty_glass_task)

	_check("the chair reports that it needs cleaning", chair.needs_cleaning())

	var clean_task_created: bool = await _await_until(
		func() -> bool:
			return not TaskBoard.get_open_tasks_of_type(
				TavernTaskTypes.CLEAN_SEAT
			).is_empty(),
		8.0
	)

	_check("a clean_seat task appears for the dirty chair", clean_task_created)

	if not clean_task_created:
		return

	var claimed: bool = await _await_until(
		func() -> bool:
			for task: TavernTask in TaskBoard.get_open_tasks_of_type(
				TavernTaskTypes.CLEAN_SEAT
			):
				if task.is_active():
					return true

			return false,
		30.0
	)

	_check("the Tavern Hand claims the cleaning task", claimed)

	# Cleaning an empty glass can break it, which is existing gameplay: the
	# seat then legitimately needs a second, different clean. The worker must
	# see that through too, so this waits for genuinely clean rather than for
	# one action to finish.
	var cleaned: bool = await _await_until(
		func() -> bool: return not chair.needs_cleaning(),
		120.0
	)

	_check(
		"the seat ends up clean, complications included",
		cleaned,
		"still needs: " + (
			"nothing" if chair.cleanable.current_task == null
			else chair.cleanable.current_task.display_name
		)
	)

	if cleaned:
		_check(
			"the cleaned seat is available to customers again",
			chair.is_available()
		)

	# No duplicate task for the same chair.
	var duplicate_count: int = 0

	for task: TavernTask in TaskBoard.get_open_tasks_of_type(
		TavernTaskTypes.CLEAN_SEAT
	):
		if task.get_target() == chair:
			duplicate_count += 1

	_check(
		"no duplicate cleaning task remains for that chair",
		duplicate_count == 0,
		"found %d" % duplicate_count
	)


# -----------------------------------------------------------------------------
# Scenarios G, H, I, J - stock alerts
# -----------------------------------------------------------------------------

func _test_stock_alerts() -> void:
	print("\n-- Scenarios G-J: stock alerts --")

	var station: DrinksStation = _get_station(&"grog")

	_check("a grog station exists", station != null)

	if station == null:
		return

	station.fill_stock()

	await get_tree().process_frame

	var alerts_before: int = Comms.get_active_alerts().size()

	# G: cross the low threshold.
	station.set_servings(station.low_stock_threshold)

	var low_raised: bool = await _await_until(
		func() -> bool:
			return Comms.get_active_alerts().size() > alerts_before,
		5.0
	)

	_check("crossing the low threshold raises one alert", low_raised)

	var low_count: int = Comms.get_active_alerts().size()

	# H: keep consuming - must not create more alerts.
	station.set_servings(station.low_stock_threshold - 1)

	await get_tree().create_timer(0.4).timeout

	station.set_servings(station.low_stock_threshold - 2)

	await get_tree().create_timer(0.4).timeout

	_check(
		"further servings do not create duplicate alerts",
		Comms.get_active_alerts().size() == low_count,
		"was %d, now %d" % [low_count, Comms.get_active_alerts().size()]
	)

	# I: empty - should escalate the same alert, not add a second one.
	station.empty_stock()

	await get_tree().create_timer(0.6).timeout

	_check(
		"running out escalates rather than adding a second alert",
		Comms.get_active_alerts().size() == low_count,
		"now %d" % Comms.get_active_alerts().size()
	)

	var has_critical: bool = false

	for message: CommMessage in Comms.get_active_alerts():
		if message.severity == CommMessage.Severity.CRITICAL:
			has_critical = true

	_check("the out-of-stock alert is CRITICAL", has_critical)

	# J: refill - the alert should resolve itself.
	station.fill_stock()

	var resolved: bool = await _await_until(
		func() -> bool:
			return Comms.get_active_alerts().size() <= alerts_before,
		6.0
	)

	_check("refilling resolves the alert automatically", resolved)

	_check(
		"the resolved alert is recorded in history",
		not Comms.get_history().is_empty()
	)


## Appended verification: the exported diagnostic report.
func verify_report_export() -> void:
	print("\n-- Diagnostics export --")

	var manager: Node = _main.get_node_or_null(
		"Managers/StaffReportManager"
	)

	_check("StaffReportManager is present", manager != null)

	if manager == null:
		return

	var path: String = String(manager.call(&"finalize_and_write_report"))

	_check("a report file is written", not path.is_empty(), path)

	if path.is_empty():
		return

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)

	_check("the report file can be read back", file != null)

	if file == null:
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())

	file.close()

	_check("the report is valid JSON", parsed is Dictionary)

	if not (parsed is Dictionary):
		return

	var report: Dictionary = parsed

	for section: String in ["staff", "tasks", "communication"]:
		_check(
			"the report contains a '%s' section" % section,
			report.has(section)
		)

	print("  report written to: ", path)
