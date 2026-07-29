extends Node

## Phase 3A smoke test: drives the staff loop with no player at the keyboard.
##
## Loads the real main scene and then stands in for the player's hands at the
## two moments a human would normally act: putting a prepared drink on the bar,
## and dirtying a seat. Everything after that - task creation, claiming,
## walking, collecting, serving, cleaning, alert lifecycle - is the game's own
## code, unassisted.
##
## Run it headless:
##
## [codeblock]
## godot --headless --path . res://tests/staff_system_tests.tscn --quit-after 4000
## [/codeblock]
##
## It is a smoke test, not a unit test: it proves the wiring is live and the
## loop closes. The manual checklist in TEST_CHECKLIST.md is still the real
## verification, because most of what matters here is whether it looks right.


const MAIN_SCENE_PATH: String = "res://scenes/main/main.tscn"

## Give up rather than hang if the tavern never reaches a stage.
const STAGE_TIMEOUT_SECONDS: float = 45.0


var _main: Node = null

var _stage: StringName = &"waiting_for_order"
var _stage_elapsed: float = 0.0

var _results: Array[String] = []
var _failures: Array[String] = []

var _served_customer_name: String = ""
var _serve_task_seen: bool = false
var _clean_task_seen: bool = false
var _dirtied_chair: Chair = null
var _alert_raised: bool = false
var _alert_resolved: bool = false


func _ready() -> void:
	var packed: PackedScene = load(MAIN_SCENE_PATH) as PackedScene

	if packed == null:
		_fail("Could not load " + MAIN_SCENE_PATH)
		_finish()
		return

	_main = packed.instantiate()

	add_child(_main)

	TaskBoard.task_created.connect(_on_task_created)
	TaskBoard.task_completed.connect(_on_task_completed)
	TaskBoard.task_failed.connect(_on_task_failed)

	Comms.message_posted.connect(_on_message_posted)
	Comms.message_resolved.connect(_on_message_resolved)

	_pass("Main scene loaded with TaskBoard and Comms autoloads present.")


func _process(
	delta: float
) -> void:
	if _main == null:
		return

	_stage_elapsed += delta

	if _stage_elapsed > STAGE_TIMEOUT_SECONDS:
		_fail("Stage '%s' timed out after %.0f seconds." % [
			String(_stage),
			STAGE_TIMEOUT_SECONDS,
		])

		_finish()
		return

	match _stage:
		&"waiting_for_order":
			_tick_waiting_for_order()

		&"waiting_for_service":
			_tick_waiting_for_service()

		&"waiting_for_clean":
			_tick_waiting_for_clean()

		&"waiting_for_alert":
			_tick_waiting_for_alert()

		&"waiting_for_resolution":
			_tick_waiting_for_resolution()


# -----------------------------------------------------------------------------
# Stage 1 - a customer orders, we put the drink on the bar
# -----------------------------------------------------------------------------

func _tick_waiting_for_order() -> void:
	var customer: Node = _find_waiting_customer()

	if customer == null:
		return

	var drink: DrinkDefinition = customer.call(&"get_requested_drink")

	if drink == null:
		return

	var counter: BarCounter = _find_bar_counter()

	if counter == null:
		_fail("No object in the 'bar_counters' group - staff cannot find drinks.")
		_finish()
		return

	# Stand in for the player placing a prepared drink in a service slot.
	# This is the only shortcut in the test, and it uses the same container
	# and the same transfer service the player's interaction uses.
	var slot: ItemSlot = counter.get_service_slot(0)

	if slot == null:
		_fail("Bar counter has no service slot 0.")
		_finish()
		return

	var result: ItemTransferResult = ItemTransferService.give_to_slot(
		slot,
		ItemStack.create(drink, 1)
	)

	if not result.is_success():
		_fail("Could not place a %s on the bar: %s" % [
			drink.display_name,
			result.get_message(),
		])

		_finish()
		return

	_served_customer_name = String(customer.name)

	_pass("Placed a %s on the bar for %s." % [
		drink.display_name,
		_served_customer_name,
	])

	_advance(&"waiting_for_service")


# -----------------------------------------------------------------------------
# Stage 2 - the worker should deliver it without further help
# -----------------------------------------------------------------------------

func _tick_waiting_for_service() -> void:
	var customer: Node = _find_customer_by_name(_served_customer_name)

	if customer == null:
		_fail("%s left before being served." % _served_customer_name)
		_finish()
		return

	if bool(customer.call(&"is_awaiting_service")):
		return

	_pass("Tavern Hand served %s without player input." % _served_customer_name)

	if not _serve_task_seen:
		_fail("The customer was served but no serve_drink task was created.")

	_dirty_a_chair()


# -----------------------------------------------------------------------------
# Stage 3 - a dirty seat should be cleaned
# -----------------------------------------------------------------------------

func _dirty_a_chair() -> void:
	for node: Node in get_tree().get_nodes_in_group(
		Reservable.group_for_tag(&"seat")
	):
		var reservable: Reservable = node as Reservable

		if reservable == null or not reservable.is_free():
			continue

		var chair: Chair = reservable.get_parent() as Chair

		if chair == null or chair.cleanable == null:
			continue

		if chair.cleanable.has_cleaning_task() or chair.empty_glass_task == null:
			continue

		chair.cleanable.set_cleaning_task(chair.empty_glass_task)

		_dirtied_chair = chair

		_pass("Dirtied %s to test the cleaning loop." % String(chair.name))

		_advance(&"waiting_for_clean")
		return

	_fail("No free clean chair available to dirty.")
	_finish()


func _tick_waiting_for_clean() -> void:
	if _dirtied_chair == null or not is_instance_valid(_dirtied_chair):
		_fail("The chair under test was removed.")
		_finish()
		return

	if _dirtied_chair.cleanable.has_cleaning_task():
		return

	_pass("Tavern Hand cleaned %s." % String(_dirtied_chair.name))

	if not _clean_task_seen:
		_fail("The chair was cleaned but no clean_seat task was created.")

	_empty_a_station()


# -----------------------------------------------------------------------------
# Stage 4 - stock alerts raise once and resolve on refill
# -----------------------------------------------------------------------------

func _empty_a_station() -> void:
	var station: DrinksStation = _find_station()

	if station == null:
		_fail("No drink stations found.")
		_finish()
		return

	station.empty_stock()

	_pass("Emptied %s." % station.get_interaction_display_name())

	_advance(&"waiting_for_alert")


func _tick_waiting_for_alert() -> void:
	if not _alert_raised:
		return

	var alerts: Array[CommMessage] = Comms.get_active_alerts()

	var stock_alerts: int = 0

	for message: CommMessage in alerts:
		if message.category == CommMessage.Category.STOCK:
			stock_alerts += 1

	if stock_alerts == 0:
		return

	if stock_alerts > 1:
		_fail("%d stock alerts are active - expected exactly one." % stock_alerts)
	else:
		_pass("Exactly one stock alert is active, as expected.")

	var station: DrinksStation = _find_station()

	if station != null:
		station.fill_stock()

		_pass("Refilled %s." % station.get_interaction_display_name())

	_advance(&"waiting_for_resolution")


func _tick_waiting_for_resolution() -> void:
	for message: CommMessage in Comms.get_active_alerts():
		if message.category == CommMessage.Category.STOCK:
			return

	if _alert_resolved:
		_pass("The stock alert resolved automatically after the refill.")
	else:
		_pass("No stock alert remains active after the refill.")

	_finish()


# -----------------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------------

func _on_task_created(
	task: TavernTask
) -> void:
	if task.task_type == TavernTaskTypes.SERVE_DRINK:
		_serve_task_seen = true

	if task.task_type == TavernTaskTypes.CLEAN_SEAT:
		_clean_task_seen = true


func _on_task_completed(
	task: TavernTask
) -> void:
	print("[test] completed ", task.describe())


func _on_task_failed(
	task: TavernTask
) -> void:
	_fail("Task failed: %s (%s)" % [
		String(task.task_id),
		String(task.last_failure_reason),
	])


func _on_message_posted(
	message: CommMessage
) -> void:
	if message.category == CommMessage.Category.STOCK:
		_alert_raised = true


func _on_message_resolved(
	message: CommMessage
) -> void:
	if message.category == CommMessage.Category.STOCK:
		_alert_resolved = true


# -----------------------------------------------------------------------------
# Finding
# -----------------------------------------------------------------------------

func _find_waiting_customer() -> Node:
	for node: Node in get_tree().get_nodes_in_group(&"interactable"):
		var provider: Node = node.get_parent()

		if provider == null or not provider.has_method(&"is_awaiting_service"):
			continue

		if bool(provider.call(&"is_awaiting_service")):
			return provider

	return null


func _find_customer_by_name(
	customer_name: String
) -> Node:
	for node: Node in get_tree().get_nodes_in_group(&"interactable"):
		var provider: Node = node.get_parent()

		if provider == null or not provider.has_method(&"is_awaiting_service"):
			continue

		if String(provider.name) == customer_name:
			return provider

	return null


func _find_bar_counter() -> BarCounter:
	for node: Node in get_tree().get_nodes_in_group(&"bar_counters"):
		var counter: BarCounter = node as BarCounter

		if counter != null:
			return counter

	return null


func _find_station() -> DrinksStation:
	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station != null:
			return station

	return null


# -----------------------------------------------------------------------------
# Reporting
# -----------------------------------------------------------------------------

func _advance(
	next_stage: StringName
) -> void:
	_stage = next_stage
	_stage_elapsed = 0.0


func _pass(
	message: String
) -> void:
	_results.append("  PASS  " + message)

	print("[test] PASS ", message)


func _fail(
	message: String
) -> void:
	_failures.append(message)
	_results.append("  FAIL  " + message)

	push_error("[test] FAIL " + message)


func _finish() -> void:
	print("\n===== PHASE 3A SMOKE TEST =====")

	for line: String in _results:
		print(line)

	print("\nTask board: ", TaskBoard.get_summary())
	print("Communication: ", Comms.get_summary())

	if _failures.is_empty():
		print("\nRESULT: all checks passed.")
	else:
		print("\nRESULT: %d check(s) failed." % _failures.size())

	print("===============================\n")

	get_tree().quit(0 if _failures.is_empty() else 1)
