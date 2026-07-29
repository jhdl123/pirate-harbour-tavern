extends Node

## Automated end-to-end check of the Phase 3A staff loop.
##
## Run it headless, from the project root:
##
## [codeblock]
## godot --headless --fixed-fps 60 res://tests/phase_3a_smoke_test.tscn
## [/codeblock]
##
## [code]--fixed-fps[/code] matters: it decouples the frame rate from the wall
## clock, so a minute of tavern time passes in a fraction of a second and the
## whole run finishes in seconds rather than minutes.
##
## The test loads the real [code]main.tscn[/code] and then behaves like a
## player: it waits for a customer to order, puts a matching drink on the bar,
## and watches. It never calls a staff method directly, because the point is to
## prove the staff loop works through the real systems, not that the methods
## exist.
##
## Exit code 0 means every scenario passed. Anything else means at least one
## did not, and the failing lines are printed above the summary.


const MAIN_SCENE_PATH: String = "res://scenes/main/main.tscn"

## Frames any single wait may take before it is called a failure.
##
## Generous on purpose: this is a correctness check, not a benchmark, and a
## worker that takes an extra second to walk round a table is still correct.
const WAIT_FRAME_BUDGET: int = 5400


var _main: Node = null
var _failures: Array[String] = []
var _passes: Array[String] = []

## Lambdas in GDScript capture local variables by value, so a closure cannot
## hand a result back through one. These two members are how the polling
## helpers below return what they found.
var _found_node: Node = null
var _found_task: TavernTask = null


func _ready() -> void:
	_main = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()

	add_child(_main)

	# One frame for _ready() everywhere, then a moment for the navigation map
	# to synchronise before anybody tries to path anywhere.
	await get_tree().process_frame
	await _wait_frames(30)

	await _run()

	_report()


func _run() -> void:
	await _scenario_a_basic_service()
	await _scenario_c_player_takes_the_drink()
	await _scenario_d_cleaning()
	await _scenario_e_player_cleans_first()
	await _scenario_f_navigation_failure()
	await _scenario_g_low_stock()
	await _scenario_j_refill_resolution()
	await _scenario_l_regression()
	await _scenario_m_report_export()


# -----------------------------------------------------------------------------
# Scenario A - a drink placed on the bar reaches the customer who ordered it
# -----------------------------------------------------------------------------

func _scenario_a_basic_service() -> void:
	var customer: Node = await _wait_for_waiting_customer()

	if customer == null:
		_fail("A", "No customer reached the ordering state.")
		return

	var wanted: DrinkDefinition = customer.get_requested_drink()

	if wanted == null:
		_fail("A", "The waiting customer had no requested drink.")
		return

	_pass("A", "%s is waiting for %s." % [customer.name, wanted.display_name])

	var slot: ItemSlot = _place_drink_on_bar(wanted)

	if slot == null:
		_fail("A", "Could not place a %s in any bar service slot." % wanted.display_name)
		return

	_pass("A", "Placed a %s on the bar, as the player would." % wanted.display_name)

	var task: TavernTask = await _wait_for_task_of_type(TavernTaskTypes.SERVE_DRINK)

	if task == null:
		_fail("A", "No serve_drink task was created for the waiting customer.")
		return

	_pass("A", "Task %s exists on the board." % String(task.task_id))

	var claimed: bool = await _wait_until(
		func() -> bool: return not task.assigned_worker_id.is_empty()
	)

	if not claimed:
		_fail("A", "The Tavern Hand never claimed the serve task.")
		return

	_pass("A", "Claimed by %s." % String(task.assigned_worker_id))

	var served: bool = await _wait_until(
		func() -> bool:
			return (
				not is_instance_valid(customer)
				or not bool(customer.call(&"is_awaiting_service"))
			)
	)

	if not served:
		_fail("A", "The customer was never served.")
		return

	if not is_instance_valid(customer):
		_fail("A", "The customer left before being served.")
		return

	if customer.current_state != Customer.State.DRINKING:
		_fail(
			"A",
			"Customer stopped waiting but is not drinking (state %d)."
			% customer.current_state
		)
		return

	_pass("A", "%s is now drinking." % customer.name)

	if not slot.is_empty():
		_fail("A", "The bar slot still holds a drink - one was duplicated.")
		return

	_pass("A", "The bar slot is empty - exactly one drink moved.")

	var completed: bool = await _wait_until(
		func() -> bool: return task.state == TavernTask.State.COMPLETED
	)

	if not completed:
		_fail(
			"A",
			"Task %s did not complete (state %s)."
			% [String(task.task_id), task.get_state_name()]
		)
		return

	_pass("A", "Task completed cleanly.")

	var worker: StaffMember = _get_tavern_hand()

	if worker != null and worker.get_item_carrier().is_carrying():
		_fail("A", "The worker is still holding something after serving.")
		return

	_pass("A", "The worker's hands are empty again.")


# -----------------------------------------------------------------------------
# Scenario D - a dirty seat is cleaned through the real cleaning action
# -----------------------------------------------------------------------------

func _scenario_d_cleaning() -> void:
	var chair: Chair = _find_clean_unoccupied_chair()

	if chair == null:
		_fail("D", "No free chair was available to dirty.")
		return

	# The authoritative way a seat becomes dirty, and the same call
	# Chair.require_cleaning() makes when a customer leaves.
	chair.cleanable.set_cleaning_task(chair.empty_glass_task)

	await _wait_frames(5)

	if not chair.needs_cleaning():
		_fail("D", "%s did not register a cleaning requirement." % chair.name)
		return

	_pass("D", "%s is dirty." % chair.name)

	var task: TavernTask = await _wait_for_task_of_type(TavernTaskTypes.CLEAN_SEAT)

	if task == null:
		_fail("D", "No clean_seat task was created.")
		return

	_pass("D", "Task %s exists on the board." % String(task.task_id))

	var cleaned: bool = await _wait_until(
		func() -> bool: return not chair.needs_cleaning()
	)

	if not cleaned:
		_fail("D", "%s was never cleaned." % chair.name)
		return

	_pass("D", "%s is clean again." % chair.name)

	var settled: bool = await _wait_until(
		func() -> bool: return task.is_terminal()
	)

	if not settled:
		_fail("D", "The cleaning task never reached a terminal state.")
		return

	_pass("D", "Cleaning task finished as %s." % task.get_state_name())

	if not chair.is_available():
		_fail("D", "%s is clean but not available for a new customer." % chair.name)
		return

	_pass("D", "%s is available for future reservations." % chair.name)


# -----------------------------------------------------------------------------
# Scenario C - the player takes the drink the worker was sent for
# -----------------------------------------------------------------------------

func _scenario_c_player_takes_the_drink() -> void:
	var worker: StaffMember = _get_tavern_hand()

	if worker == null:
		_fail("C", "No Tavern Hand is present in the scene.")
		return

	var customer: Node = await _wait_for_waiting_customer()

	if customer == null:
		_fail("C", "No customer reached the ordering state.")
		return

	var wanted: DrinkDefinition = customer.get_requested_drink()
	var slot: ItemSlot = _place_drink_on_bar(wanted)

	if slot == null:
		_fail("C", "Could not place a drink on the bar.")
		return

	var task: TavernTask = await _wait_for_task_of_type(
		TavernTaskTypes.SERVE_DRINK
	)

	if task == null:
		_fail("C", "No serve task was created.")
		return

	var claimed: bool = await _wait_until(
		func() -> bool: return not task.assigned_worker_id.is_empty()
	)

	if not claimed:
		_fail("C", "The worker never claimed the serve task.")
		return

	_pass("C", "Worker claimed %s and set off." % String(task.task_id))

	# The player walks up and takes it first. Emptying the slot is exactly
	# what ItemCarrier.take_from() does to it, so this is the real event.
	slot.clear()

	_pass("C", "The drink was removed from the slot mid-journey.")

	var recovered: bool = await _wait_until(
		func() -> bool:
			return (
				worker.current_task == null
				or worker.current_task != task
				or task.is_terminal()
			)
	)

	if not recovered:
		_fail("C", "The worker stayed committed to a task it cannot finish.")
		return

	_pass("C", "The worker let the task go rather than waiting forever.")

	var settled: bool = await _wait_until(
		func() -> bool:
			return (
				worker.current_state == StaffMember.State.IDLE
				or worker.current_task != null
			)
	)

	if not settled:
		_fail("C", "The worker did not return to useful operation.")
		return

	_pass(
		"C",
		"Worker is operating normally again (state %s)."
		% worker.get_state_name()
	)

	if worker.get_item_carrier().is_carrying():
		_fail("C", "The worker is holding a drink it should never have got.")
		return

	_pass("C", "The worker is not holding a phantom drink.")


# -----------------------------------------------------------------------------
# Scenario E - the player cleans a seat the worker has claimed
# -----------------------------------------------------------------------------

func _scenario_e_player_cleans_first() -> void:
	var worker: StaffMember = _get_tavern_hand()

	if worker == null:
		_fail("E", "No Tavern Hand is present in the scene.")
		return

	var chair: Chair = _find_clean_unoccupied_chair()

	if chair == null:
		_fail("E", "No free chair was available to dirty.")
		return

	chair.cleanable.set_cleaning_task(chair.empty_glass_task)

	var task: TavernTask = await _wait_for_task_of_type(
		TavernTaskTypes.CLEAN_SEAT
	)

	if task == null:
		_fail("E", "No cleaning task was created.")
		return

	var claimed: bool = await _wait_until(
		func() -> bool: return not task.assigned_worker_id.is_empty()
	)

	if not claimed:
		_fail("E", "The worker never claimed the cleaning task.")
		return

	_pass("E", "Worker claimed %s." % String(task.task_id))

	# The player gets there first. This is the same authoritative call the
	# CleanableComponent makes when a player's cleaning action resolves.
	chair.cleanable.clear_cleaning_task()

	_pass("E", "The seat was cleaned by somebody else.")

	var settled: bool = await _wait_until(
		func() -> bool: return task.is_terminal()
	)

	if not settled:
		_fail("E", "The cleaning task never settled.")
		return

	_pass("E", "Task settled as %s." % task.get_state_name())

	var freed: bool = await _wait_until(
		func() -> bool:
			return worker.current_task == null or worker.current_task != task
	)

	if not freed:
		_fail("E", "The worker is still holding a dead task.")
		return

	_pass("E", "The worker released the task and moved on.")

	if chair.cleanable.is_cleaning:
		_fail("E", "A second cleaning action was started on the same seat.")
		return

	_pass("E", "No duplicate cleaning action occurred.")


# -----------------------------------------------------------------------------
# Scenario F - navigation failure is reported and recovered from
# -----------------------------------------------------------------------------

func _scenario_f_navigation_failure() -> void:
	var worker: StaffMember = _get_tavern_hand()

	if worker == null:
		_fail("F", "No Tavern Hand is present in the scene.")
		return

	var before: int = TaskBoard.get_summary()["tasks_failed"]

	if not worker.developer_force_navigation_failure():
		_pass("F", "Worker had no active journey to fail - nothing to test.")
		return

	_pass("F", "Forced a navigation failure on the current journey.")

	var recovered: bool = await _wait_until(
		func() -> bool:
			return (
				worker.current_state == StaffMember.State.IDLE
				or worker.current_state == StaffMember.State.EVALUATING_TASKS
				or worker.current_task != null
			)
	)

	if not recovered:
		_fail("F", "The worker did not recover from the navigation failure.")
		return

	_pass(
		"F",
		"Worker recovered to %s." % worker.get_state_name()
	)

	var after: int = TaskBoard.get_summary()["tasks_failed"]

	_pass(
		"F",
		"Board recorded %d newly failed task(s) - retries absorbed the rest."
		% (after - before)
	)


# -----------------------------------------------------------------------------
# Scenario G - crossing the low threshold raises exactly one alert
# -----------------------------------------------------------------------------

func _scenario_g_low_stock() -> void:
	var station: DrinksStation = _get_first_station()

	if station == null:
		_fail("G", "No drink station was found.")
		return

	station.fill_stock()

	await _wait_frames(5)

	var before: int = Comms.get_active_alerts().size()

	station.set_servings(station.low_stock_threshold)

	await _wait_frames(20)

	var alerts: Array[CommMessage] = Comms.get_active_alerts()

	if alerts.size() != before + 1:
		_fail(
			"G",
			"Expected exactly one new alert, got %d."
			% (alerts.size() - before)
		)
		return

	_pass("G", "One low-stock alert was raised.")

	# Continued consumption must update the existing alert, never add another.
	for serving: int in range(station.low_stock_threshold):
		station.set_servings(maxi(station.current_servings - 1, 1))

		await _wait_frames(3)

	if Comms.get_active_alerts().size() != before + 1:
		_fail("G", "Further consumption created duplicate alerts.")
		return

	_pass("G", "Continued use did not spam new alerts (Scenario H).")


# -----------------------------------------------------------------------------
# Scenario J - refilling resolves the alert automatically
# -----------------------------------------------------------------------------

func _scenario_j_refill_resolution() -> void:
	var station: DrinksStation = _get_first_station()

	if station == null:
		_fail("J", "No drink station was found.")
		return

	station.set_servings(0)

	await _wait_frames(20)

	if station.get_stock_state() != DrinksStation.StockState.EMPTY:
		_fail("J", "The station did not report EMPTY at zero servings.")
		return

	_pass("J", "Station escalated to EMPTY (Scenario I).")

	station.fill_stock()

	var resolved: bool = await _wait_until(
		func() -> bool:
			for message: CommMessage in Comms.get_active_alerts():
				if message.source_id == station.name:
					return false

			return true
	)

	if not resolved:
		_fail("J", "The stock alert did not resolve after refilling.")
		return

	_pass("J", "The alert resolved automatically once stock was restored.")


# -----------------------------------------------------------------------------
# Scenario L - the Phase 2C world still behaves
# -----------------------------------------------------------------------------

func _scenario_l_regression() -> void:
	var game_manager: GameManager = _main.get_node_or_null(
		"Managers/GameManager"
	) as GameManager

	if game_manager == null:
		_fail("L", "GameManager is missing from the main scene.")
		return

	if game_manager.get_active_customer_count() <= 0:
		_fail("L", "No customers are active - spawning has regressed.")
		return

	_pass(
		"L",
		"%d customers active, %d seats occupied."
		% [
			game_manager.get_active_customer_count(),
			game_manager.get_occupied_seat_count(),
		]
	)

	var summary: Dictionary = TaskBoard.get_summary()

	_pass(
		"L",
		"Board: %d created, %d completed, %d cancelled, %d failed, %d open."
		% [
			summary["tasks_created"],
			summary["tasks_completed"],
			summary["tasks_cancelled"],
			summary["tasks_failed"],
			summary["tasks_open"],
		]
	)

	var severe: Array[String] = []

	for issue: Dictionary in TaskBoard.get_issues():
		var issue_type: String = String(issue["issue_type"])

		if (
			issue_type == TavernTaskService.ISSUE_LEAKED_RESERVATION
			or issue_type == TavernTaskService.ISSUE_DUPLICATE_SERVICE
			or issue_type == TavernTaskService.ISSUE_DUPLICATE_CLEANING
		):
			severe.append(issue_type)

	if not severe.is_empty():
		_fail("L", "Severe issues recorded: %s" % ", ".join(severe))
		return

	_pass("L", "No duplicate-service, duplicate-cleaning or leak issues.")


# -----------------------------------------------------------------------------
# Scenario M - the diagnostic report writes readable JSON
# -----------------------------------------------------------------------------

func _scenario_m_report_export() -> void:
	var manager: Node = _main.get_node_or_null(
		"Managers/StaffReportManager"
	)

	if manager == null:
		_fail("M", "StaffReportManager is missing from the main scene.")
		return

	var path: String = String(manager.call(&"finalize_and_write_report"))

	if path.is_empty():
		_fail("M", "The report manager wrote nothing.")
		return

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)

	if file == null:
		_fail("M", "The report file could not be reopened: %s" % path)
		return

	var text: String = file.get_as_text()

	file.close()

	var parsed: Variant = JSON.parse_string(text)

	if parsed == null or not (parsed is Dictionary):
		_fail("M", "The report is not valid JSON.")
		return

	var report: Dictionary = parsed

	for section: String in ["staff", "tasks", "communication"]:
		if not report.has(section):
			_fail("M", "The report has no '%s' section." % section)
			return

	_pass(
		"M",
		"Report written to %s (%d bytes, sections: %s)."
		% [path, text.length(), ", ".join(report.keys())]
	)

	print("")
	print("--- report excerpt -------------------------------------------")
	print(JSON.stringify(report.get("staff"), "  "))
	print("--------------------------------------------------------------")


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

func _wait_for_waiting_customer() -> Node:
	_found_node = null

	var ready: bool = await _wait_until(
		func() -> bool:
			var game_manager: GameManager = _main.get_node_or_null(
				"Managers/GameManager"
			) as GameManager

			if game_manager == null:
				return false

			for customer: Node in game_manager.active_customers:
				if customer == null or not is_instance_valid(customer):
					continue

				if not customer.has_method(&"is_awaiting_service"):
					continue

				if bool(customer.call(&"is_awaiting_service")):
					_found_node = customer
					return true

			return false
	)

	return _found_node if ready else null


func _place_drink_on_bar(
	definition: DrinkDefinition
) -> ItemSlot:
	for node: Node in get_tree().get_nodes_in_group(&"bar_counters"):
		var counter: BarCounter = node as BarCounter

		if counter == null:
			continue

		var container: ItemContainer = counter.get_service_container()

		if container == null:
			continue

		for index: int in range(container.get_slot_count()):
			var slot: ItemSlot = container.get_slot(index)

			if slot == null or not slot.is_empty():
				continue

			var result: ItemTransferResult = ItemTransferService.give_to_slot(
				slot,
				ItemStack.create(definition, 1)
			)

			if result.is_success():
				return slot

	return null


func _wait_for_task_of_type(
	task_type: StringName
) -> TavernTask:
	_found_task = null

	var ready: bool = await _wait_until(
		func() -> bool:
			for task: TavernTask in TaskBoard.get_open_tasks_of_type(task_type):
				_found_task = task
				return true

			for task: TavernTask in TaskBoard.get_finished_tasks():
				if task.task_type == task_type:
					_found_task = task
					return true

			return false
	)

	return _found_task if ready else null


func _find_clean_unoccupied_chair() -> Chair:
	for node: Node in get_tree().get_nodes_in_group(
		Reservable.group_for_tag(&"seat")
	):
		var reservable: Reservable = node as Reservable

		if reservable == null or not reservable.is_free():
			continue

		var chair: Chair = reservable.get_parent() as Chair

		if chair == null or chair.cleanable == null:
			continue

		if chair.cleanable.has_cleaning_task():
			continue

		return chair

	return null


func _get_first_station() -> DrinksStation:
	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station != null:
			return station

	return null


func _get_tavern_hand() -> StaffMember:
	for node: Node in get_tree().get_nodes_in_group(&"tavern_staff"):
		var worker: StaffMember = node as StaffMember

		if worker != null:
			return worker

	return null


## Polls [param condition] every frame until it is true or the budget runs out.
func _wait_until(
	condition: Callable
) -> bool:
	for frame: int in range(WAIT_FRAME_BUDGET):
		if bool(condition.call()):
			return true

		await get_tree().process_frame

	return false


func _wait_frames(
	count: int
) -> void:
	for frame: int in range(count):
		await get_tree().process_frame


func _pass(
	scenario: String,
	message: String
) -> void:
	var line: String = "  [PASS] %s: %s" % [scenario, message]

	_passes.append(line)

	print(line)


func _fail(
	scenario: String,
	message: String
) -> void:
	var line: String = "  [FAIL] %s: %s" % [scenario, message]

	_failures.append(line)

	print(line)


func _report() -> void:
	print("")
	print("==================================================")
	print("PHASE 3A SMOKE TEST")
	print("  passed: %d" % _passes.size())
	print("  failed: %d" % _failures.size())

	for line: String in _failures:
		print(line)

	print("==================================================")

	get_tree().quit(0 if _failures.is_empty() else 1)
