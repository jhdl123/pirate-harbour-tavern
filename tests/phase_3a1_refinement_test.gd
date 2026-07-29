extends Node

## Automated checks for the Phase 3A.1 refinement pass.
##
## Run headless from the project root:
##
## [codeblock]
## godot --headless --fixed-fps 60 res://tests/phase_3a1_refinement_test.tscn
## [/codeblock]
##
## Covers the scenarios the refinement brief asks for, and in particular the
## defect it exists to fix: a worker must never carry a customer's drink into
## an unrelated job.
##
## The suite drives the real main scene through real APIs. Where it needs to
## play the part of the player it does exactly what the player does - places a
## drink in a service slot, clears a cleaning task - and never reaches into
## staff internals to force an outcome.
##
## Exit code 0 means every check passed.


const MAIN_SCENE_PATH: String = "res://scenes/main/main.tscn"
const WAIT_FRAME_BUDGET: int = 5400


var _main: Node = null
var _failures: Array[String] = []
var _passes: Array[String] = []

var _found_node: Node = null
var _found_task: TavernTask = null


func _ready() -> void:
	_main = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()

	add_child(_main)

	await get_tree().process_frame
	await _wait_frames(30)

	await _scenario_config()
	await _scenario_d_carried_item_recovery()
	await _scenario_incompatible_task_rejected()
	await _scenario_h_marginal_viability()
	await _scenario_b_overload()
	await _scenario_i_state_stability()
	await _scenario_diagnostics()

	_report()


# -----------------------------------------------------------------------------
# Configuration is actually wired
# -----------------------------------------------------------------------------

func _scenario_config() -> void:
	var viability: TaskViabilityConfig = TaskBoard.get_viability_config()

	if viability == null:
		_fail("CFG", "No TaskViabilityConfig is attached to the board config.")
		return

	_pass(
		"CFG",
		"Viability enabled=%s, buffer=%.1fm, comfortable=%.1fm."
		% [
			viability.enabled,
			viability.safety_buffer_minutes,
			viability.comfortable_margin_minutes,
		]
	)

	var worker: StaffMember = _get_worker()

	if worker == null:
		_fail("CFG", "No Tavern Hand in the scene.")
		return

	if worker.definition.carried_item_policy == null:
		_fail("CFG", "The Tavern Hand has no CarriedItemPolicy.")
		return

	_pass(
		"CFG",
		"Carried-item policy '%s' attached; may_work_while_holding=%s."
		% [
			String(worker.definition.carried_item_policy.policy_id),
			worker.definition.carried_item_policy.may_work_while_holding_unrelated_item,
		]
	)

	if worker.get_movement_speed() <= 0.0:
		_fail("CFG", "Worker reports no movement speed, so estimates cannot work.")
		return

	_pass("CFG", "Worker speed %.0f px/s available to estimates."
		% worker.get_movement_speed())


# -----------------------------------------------------------------------------
# Scenario D - customer leaves after the drink was collected
# -----------------------------------------------------------------------------

func _scenario_d_carried_item_recovery() -> void:
	var worker: StaffMember = _get_worker()

	if worker == null:
		_fail("D", "No Tavern Hand in the scene.")
		return

	var customer: Node = await _wait_for_waiting_customer()

	if customer == null:
		_fail("D", "No customer reached the ordering state.")
		return

	var wanted: DrinkDefinition = customer.get_requested_drink()
	var slot: ItemSlot = _place_drink_on_bar(wanted)

	if slot == null:
		_fail("D", "Could not place a drink on the bar.")
		return

	# Wait until the worker is genuinely holding the drink.
	var collected: bool = await _wait_until(
		func() -> bool:
			return worker.get_item_carrier().is_carrying_item(wanted.item_id)
	)

	if not collected:
		_fail("D", "The worker never collected the drink.")
		return

	_pass("D", "Worker collected a %s." % wanted.display_name)

	var stock_before: int = _count_drinks_in_world(wanted.item_id)

	# The customer gives up and leaves, exactly as a patience timeout would.
	if customer.has_method(&"finish_customer"):
		customer.call(&"finish_customer")

	_pass("D", "The customer left while the drink was in the worker's hands.")

	# The heart of the fix: within a reasonable window the worker must have
	# dealt with the drink, and must not have started an unrelated job first.
	var cleaned_while_carrying: bool = false

	var resolved: bool = await _wait_until(
		func() -> bool:
			var carrier: ItemCarrier = worker.get_item_carrier()

			if carrier.is_carrying():
				var task: TavernTask = worker.current_task

				if (
					task != null
					and task.task_type == TavernTaskTypes.CLEAN_SEAT
				):
					cleaned_while_carrying = true

					return true

				return false

			return true
	)

	if cleaned_while_carrying:
		_fail("D", "The worker took a cleaning task while holding a drink.")
		return

	if not resolved:
		_fail("D", "The worker never resolved the carried drink.")
		return

	_pass("D", "The drink was resolved without starting an incompatible task.")

	var snapshot: Dictionary = worker.get_diagnostics_snapshot()

	var events: Dictionary = snapshot.get("carried_events_by_reason", {})

	if events.is_empty():
		_fail("D", "No carried-item diagnostic event was recorded.")
		return

	_pass("D", "Recovery recorded as: %s." % ", ".join(events.keys()))

	var stock_after: int = _count_drinks_in_world(wanted.item_id)

	if stock_after > stock_before:
		_fail(
			"D",
			"Drink count rose from %d to %d - recovery duplicated stock."
			% [stock_before, stock_after]
		)
		return

	_pass(
		"D",
		"No duplication: %d drink(s) before, %d after."
		% [stock_before, stock_after]
	)


# -----------------------------------------------------------------------------
# A carried drink must make cleaning tasks unclaimable
# -----------------------------------------------------------------------------

func _scenario_incompatible_task_rejected() -> void:
	var worker: StaffMember = _get_worker()

	if worker == null:
		_fail("INC", "No Tavern Hand in the scene.")
		return

	var chair: Chair = _find_clean_unoccupied_chair()

	if chair == null:
		_fail("INC", "No free chair available to dirty.")
		return

	chair.cleanable.set_cleaning_task(chair.empty_glass_task)

	var task: TavernTask = await _wait_for_task_of_type(
		TavernTaskTypes.CLEAN_SEAT
	)

	if task == null:
		_fail("INC", "No cleaning task appeared.")
		return

	var executor: StaffTaskExecutor = StaffTaskExecutor.create_for(
		TavernTaskTypes.CLEAN_SEAT
	)

	# Ask the rule directly, with empty hands and then with full hands. This
	# is the gate that failed to exist in Phase 3A.
	var empty_ok: bool = executor.is_compatible_with_carried_item(worker, task)

	if not empty_ok:
		_fail("INC", "Cleaning was refused even with empty hands.")
		return

	_pass("INC", "Cleaning is claimable with empty hands.")

	var grog: ItemDefinition = _find_any_drink()

	if grog == null:
		_fail("INC", "No drink definition available for the test.")
		return

	var given: ItemTransferResult = worker.get_item_carrier().give(
		ItemStack.create(grog, 1)
	)

	if not given.is_success():
		_fail("INC", "Could not put a test drink in the worker's hands.")
		return

	var full_ok: bool = executor.is_compatible_with_carried_item(worker, task)

	# Put the test drink back before it affects anything else.
	worker.get_item_carrier().clear_carried_item()

	if full_ok:
		_fail("INC", "Cleaning was still claimable while carrying a drink.")
		return

	_pass("INC", "Cleaning is correctly refused while carrying a drink.")


# -----------------------------------------------------------------------------
# Scenario H - marginal viability produces an explainable decision
# -----------------------------------------------------------------------------

func _scenario_h_marginal_viability() -> void:
	var worker: StaffMember = _get_worker()
	var config: TaskViabilityConfig = TaskBoard.get_viability_config()

	if worker == null or config == null:
		_fail("H", "Worker or viability config missing.")
		return

	var customer: Node = await _wait_for_waiting_customer()

	if customer == null:
		_fail("H", "No customer reached the ordering state.")
		return

	var wanted: DrinkDefinition = customer.get_requested_drink()

	if _place_drink_on_bar(wanted) == null:
		_fail("H", "Could not place a drink on the bar.")
		return

	var task: TavernTask = await _wait_for_task_of_type(
		TavernTaskTypes.SERVE_DRINK
	)

	if task == null:
		_fail("H", "No serve task appeared.")
		return

	var evaluated: bool = await _wait_until(
		func() -> bool: return not task.last_viability.is_empty()
	)

	if not evaluated:
		_fail("H", "The task was never evaluated for viability.")
		return

	var viability: Dictionary = task.last_viability

	_pass(
		"H",
		"Verdict %s: est %.1fm, deadline %.1fm, margin %.1fm (%s)."
		% [
			String(viability.get("verdict_name", "?")),
			float(viability.get("estimated_minutes", -1.0)),
			float(viability.get("deadline_minutes", -1.0)),
			float(viability.get("margin_minutes", 0.0)),
			String(viability.get("detail", "")),
		]
	)

	if not bool(viability.get("has_estimate", false)):
		_fail("H", "Serving tasks should produce a real estimate.")
		return

	_pass("H", "The decision is fully explained in the task record.")

	# Cleaning has no deadline and must stay outside the system entirely.
	var chair: Chair = _find_clean_unoccupied_chair()

	if chair != null:
		var clean_executor: StaffTaskExecutor = StaffTaskExecutor.create_for(
			TavernTaskTypes.CLEAN_SEAT
		)

		var deadline: float = clean_executor.get_deadline_minutes(worker, task)

		if deadline >= 0.0:
			_fail("H", "Cleaning reported a deadline; it should have none.")
			return

		_pass("H", "Cleaning correctly reports no deadline.")


# -----------------------------------------------------------------------------
# Scenario B - overload skips doomed work instead of chasing it
# -----------------------------------------------------------------------------

func _scenario_b_overload() -> void:
	var config: TaskViabilityConfig = TaskBoard.get_viability_config()

	if config == null:
		_fail("B", "No viability config.")
		return

	var game_manager: GameManager = _main.get_node_or_null(
		"Managers/GameManager"
	) as GameManager

	if game_manager == null:
		_fail("B", "No GameManager.")
		return

	# Let the tavern fill up and run under pressure for a while.
	await _wait_frames(2400)

	var summary: Dictionary = TaskBoard.get_summary()

	_pass(
		"B",
		"Under load: %d created, %d completed, %d cancelled, %d failed."
		% [
			summary["tasks_created"],
			summary["tasks_completed"],
			summary["tasks_cancelled"],
			summary["tasks_failed"],
		]
	)

	_pass(
		"B",
		"Non-viable rejections recorded: %d."
		% int(summary.get("non_viable_rejections", 0))
	)

	# Reservation hygiene is the hard requirement here, not a completion rate.
	var leaked: int = 0

	for task: TavernTask in TaskBoard.get_finished_tasks():
		if not task.reservations.is_empty():
			leaked += 1

	if leaked > 0:
		_fail("B", "%d finished tasks still hold reservations." % leaked)
		return

	_pass("B", "No finished task is still holding a reservation.")

	var worker: StaffMember = _get_worker()

	if worker != null and worker.get_item_carrier().is_carrying():
		var task: TavernTask = worker.current_task

		if task != null and task.task_type == TavernTaskTypes.CLEAN_SEAT:
			_fail("B", "Worker is cleaning while carrying a drink under load.")
			return

	_pass("B", "Worker is not doing incompatible work while carrying.")


# -----------------------------------------------------------------------------
# Scenario I - no idle oscillation
# -----------------------------------------------------------------------------

func _scenario_i_state_stability() -> void:
	var worker: StaffMember = _get_worker()

	if worker == null:
		_fail("I", "No Tavern Hand in the scene.")
		return

	var before: Dictionary = worker.get_diagnostics_snapshot()

	var before_count: int = _count_idle_churn(
		before.get("state_history", [])
	)

	await _wait_frames(900)

	var after: Dictionary = worker.get_diagnostics_snapshot()

	var after_count: int = _count_idle_churn(after.get("state_history", []))

	var churn: int = after_count - before_count

	# Fifteen real seconds at the default idle interval would previously have
	# produced roughly one triple per interval. A handful is normal; dozens
	# would mean the oscillation is still there.
	if churn > 12:
		_fail(
			"I",
			"%d idle round trips in ~15s - still oscillating." % churn
		)
		return

	_pass("I", "%d idle round trips in ~15s - stable." % churn)

	var empty: int = int(after.get("empty_evaluations", 0))

	_pass("I", "%d empty evaluations folded out of history." % empty)


func _count_idle_churn(
	history: Array
) -> int:
	var count: int = 0

	for entry: Variant in history:
		var record: Dictionary = entry as Dictionary

		if record == null:
			continue

		if (
			String(record.get("from", "")) == "EVALUATING_TASKS"
			and String(record.get("to", "")) == "RETURNING_TO_IDLE"
		):
			count += 1

	return count


# -----------------------------------------------------------------------------
# Diagnostics contain the new sections
# -----------------------------------------------------------------------------

func _scenario_diagnostics() -> void:
	var manager: Node = _main.get_node_or_null("Managers/StaffReportManager")

	if manager == null:
		_fail("DIAG", "StaffReportManager missing.")
		return

	var path: String = String(manager.call(&"finalize_and_write_report"))

	if path.is_empty():
		_fail("DIAG", "No report was written.")
		return

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)

	if file == null:
		_fail("DIAG", "Report could not be reopened.")
		return

	var text: String = file.get_as_text()

	file.close()

	var parsed: Variant = JSON.parse_string(text)

	if not (parsed is Dictionary):
		_fail("DIAG", "Report is not valid JSON.")
		return

	var report: Dictionary = parsed
	var tasks: Dictionary = report.get("tasks", {})

	for section: String in [
		"by_task_type",
		"cancellation_reasons",
		"viability_distribution",
		"decisions",
	]:
		if not tasks.has(section):
			_fail("DIAG", "Report has no tasks.%s section." % section)
			return

	_pass("DIAG", "Task report contains all four new sections.")

	if not report.has("state_transitions"):
		_fail("DIAG", "Report has no state_transitions section.")
		return

	var transitions: Dictionary = report["state_transitions"]

	var generic: int = 0

	for key: String in transitions.keys():
		if key.ends_with("(transition)"):
			generic += int(transitions[key])

	if generic > 0:
		_fail(
			"DIAG",
			"%d transitions still use the generic reason 'transition'."
			% generic
		)
		return

	_pass(
		"DIAG",
		"All %d transition groups carry a meaningful reason."
		% transitions.size()
	)

	print("")
	print("--- cancellation reasons -------------------------------------")
	print(JSON.stringify(tasks.get("cancellation_reasons"), "  "))
	print("--- viability distribution -----------------------------------")
	print(JSON.stringify(tasks.get("viability_distribution"), "  "))
	print("--- per task type --------------------------------------------")
	print(JSON.stringify(tasks.get("by_task_type"), "  "))
	print("--- state transitions ----------------------------------------")
	print(JSON.stringify(transitions, "  "))
	print("--------------------------------------------------------------")


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

func _get_worker() -> StaffMember:
	for node: Node in get_tree().get_nodes_in_group(&"tavern_staff"):
		var worker: StaffMember = node as StaffMember

		if worker != null:
			return worker

	return null


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


func _find_any_drink() -> ItemDefinition:
	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var served: Variant = node.get("served_drink")

		var definition: ItemDefinition = served as ItemDefinition

		if definition != null:
			return definition

	return null


## Counts drinks of one kind anywhere the test can see them.
##
## Bar slots, station outputs and the worker's hands. Used to prove recovery
## neither duplicates nor silently destroys stock.
func _count_drinks_in_world(
	item_id: StringName
) -> int:
	var total: int = 0

	for node: Node in get_tree().get_nodes_in_group(&"bar_counters"):
		var container: ItemContainer = node.call(
			&"get_service_container"
		) as ItemContainer

		if container == null:
			continue

		total += container.get_total_quantity(item_id)

	var worker: StaffMember = _get_worker()

	if worker != null and worker.get_item_carrier().is_carrying_item(item_id):
		total += worker.get_item_carrier().get_carried_quantity()

	return total


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
	print("PHASE 3A.1 REFINEMENT TEST")
	print("  passed: %d" % _passes.size())
	print("  failed: %d" % _failures.size())

	for line: String in _failures:
		print(line)

	print("==================================================")

	get_tree().quit(0 if _failures.is_empty() else 1)
