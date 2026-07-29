extends Node

## Headless functional harness for Phase 3A.
##
## Not shipped gameplay and not part of the test checklist a human follows -
## this is the automated proof that the serve loop, the clean loop and the
## stock-alert lifecycle really run against the real main scene, rather than
## merely compiling. Run it with:
##
## [codeblock]
## godot --headless --path . tests/phase_3a_harness.tscn
## [/codeblock]
##
## It instances main.tscn unchanged, waits for the world to reach the state
## each scenario needs, and prints one PASS or FAIL line per check.


const MAIN_SCENE: String = "res://scenes/main/main.tscn"

const STEP_TIMEOUT_SECONDS: float = 45.0


var _main: Node = null

var _step: int = 0
var _step_elapsed: float = 0.0
var _failures: int = 0
var _checks: int = 0

var _served_customer: Node = null
var _dirty_chair: Chair = null
var _alert_station: DrinksStation = null


func _ready() -> void:
	print("=== PHASE 3A HARNESS ===")

	var packed: PackedScene = load(MAIN_SCENE) as PackedScene

	if packed == null:
		_fail("could not load " + MAIN_SCENE)
		_finish()
		return

	_main = packed.instantiate()

	add_child(_main)

	# Fast-forward a little so customers reach the ordering state in a few real
	# seconds, and switch patience off. Patience is measured in world minutes,
	# so at any speed above 1x it expires faster than a worker can physically
	# walk across the room - which would test the clock, not the staff system.
	WorldTime.set_speed(3.0)

	var manager: Node = _main.get_node_or_null("Managers/GameManager")

	if manager != null:
		var config: GameConfig = manager.get(&"game_config") as GameConfig

		if config != null:
			config.disable_patience = true


func _process(
	delta: float
) -> void:
	if _main == null:
		return

	_step_elapsed += delta

	if _step_elapsed > STEP_TIMEOUT_SECONDS:
		_fail("step %d timed out" % _step)
		_advance()
		return

	match _step:
		0:
			_step_world_ready()
		1:
			_step_worker_present()
		2:
			_step_wait_for_order()
		3:
			_step_place_drink()
		4:
			_step_expect_serve_task()
		5:
			_step_expect_served()
		6:
			_step_make_seat_dirty()
		7:
			_step_expect_clean_task()
		8:
			_step_expect_cleaned()
		9:
			_step_trigger_low_stock()
		10:
			_step_expect_alert()
		11:
			_step_refill_station()
		12:
			_step_expect_alert_resolved()
		13:
			_step_export_reports()
		_:
			_finish()


# -----------------------------------------------------------------------------
# Steps
# -----------------------------------------------------------------------------

func _step_world_ready() -> void:
	if TaskBoard == null:
		_fail("TaskBoard autoload missing")
		_advance()
		return

	if Comms == null:
		_fail("Comms autoload missing")
		_advance()
		return

	_pass("autoloads TaskBoard and Comms are present")
	_advance()


func _step_worker_present() -> void:
	var workers: Array = get_tree().get_nodes_in_group(&"tavern_staff")

	if workers.is_empty():
		if _step_elapsed < 2.0:
			return

		_fail("no node in the tavern_staff group - is TavernHand in main.tscn?")
		_advance()
		return

	_pass("tavern hand present: %s" % String((workers[0] as Node).name))
	_advance()


func _step_wait_for_order() -> void:
	var customer: Node = _find_waiting_customer()

	if customer == null:
		return

	_served_customer = customer

	_pass(
		"customer %s is waiting for %s"
		% [
			String(customer.name),
			customer.call(&"get_requested_drink").display_name,
		]
	)

	_advance()


func _step_place_drink() -> void:
	if _served_customer == null or not is_instance_valid(_served_customer):
		_fail("customer left before a drink could be placed")
		_advance()
		return

	var counter: Node = _find_bar_counter()

	if counter == null:
		_fail("no node in the bar_counters group")
		_advance()
		return

	var drink: DrinkDefinition = _served_customer.call(&"get_requested_drink")
	var slot: ItemSlot = counter.call(&"get_service_slot", 0) as ItemSlot

	if slot == null:
		_fail("bar counter has no service slot 0")
		_advance()
		return

	var result: ItemTransferResult = ItemTransferService.give_to_slot(
		slot,
		ItemStack.create(drink, 1)
	)

	if not result.is_success():
		_fail("could not place a drink in the service slot")
		_advance()
		return

	_pass("placed %s in the bar service slot" % drink.display_name)
	_advance()


func _step_expect_serve_task() -> void:
	for task: TavernTask in TaskBoard.get_open_tasks():
		if task.task_type != TavernTaskTypes.SERVE_DRINK:
			continue

		if task.get_target() != _served_customer:
			continue

		if task.state == TavernTask.State.AVAILABLE:
			continue

		_pass(
			"serve task %s reached state %s"
			% [String(task.task_id), task.get_state_name()]
		)

		_advance()
		return


func _step_expect_served() -> void:
	if _served_customer == null or not is_instance_valid(_served_customer):
		_fail("customer disappeared before being served")
		_advance()
		return

	if bool(_served_customer.call(&"is_awaiting_service")):
		return

	# "No longer waiting" is not the same as "was served" - a customer that
	# gave up also stops waiting. Check the state the serve actually produces.
	if _served_customer.get(&"current_state") != Customer.State.DRINKING:
		_fail(
			"customer stopped waiting without being served (state %d)"
			% int(_served_customer.get(&"current_state"))
		)

		_advance()
		return

	var counter: Node = _find_bar_counter()
	var slot: ItemSlot = counter.call(&"get_service_slot", 0) as ItemSlot

	if slot != null and not slot.is_empty():
		_fail("customer was served but the service slot still holds a drink")
		_advance()
		return

	_pass("tavern hand delivered the drink and the service slot is empty")
	_advance()


func _step_make_seat_dirty() -> void:
	var chair: Chair = _find_clean_unreserved_chair()

	if chair == null:
		_fail("no chair available to dirty")
		_advance()
		return

	_dirty_chair = chair

	# The authoritative component API - exactly what a departing customer's
	# Chair.require_cleaning() ends up calling.
	chair.cleanable.set_cleaning_task(chair.empty_glass_task)

	_pass("marked %s as needing cleaning" % String(chair.name))
	_advance()


func _step_expect_clean_task() -> void:
	for task: TavernTask in TaskBoard.get_open_tasks():
		if task.task_type != TavernTaskTypes.CLEAN_SEAT:
			continue

		if task.get_target() != _dirty_chair:
			continue

		_pass(
			"clean task %s created in state %s"
			% [String(task.task_id), task.get_state_name()]
		)

		_advance()
		return


func _step_expect_cleaned() -> void:
	if _dirty_chair == null or not is_instance_valid(_dirty_chair):
		_fail("chair disappeared")
		_advance()
		return

	if _dirty_chair.cleanable.has_cleaning_task():
		return

	_pass("tavern hand cleaned %s" % String(_dirty_chair.name))
	_advance()


func _step_trigger_low_stock() -> void:
	var stations: Array = get_tree().get_nodes_in_group(&"drink_stations")

	if stations.is_empty():
		_fail("no drink stations found")
		_advance()
		return

	_alert_station = stations[0] as DrinksStation

	_alert_station.set_servings(
		maxi(_alert_station.low_stock_threshold - 1, 0)
	)

	_pass(
		"set %s to %d servings"
		% [String(_alert_station.name), _alert_station.current_servings]
	)

	_advance()


func _step_expect_alert() -> void:
	var alerts: Array[CommMessage] = Comms.get_active_alerts()

	if alerts.is_empty():
		return

	var count: int = alerts.size()

	# Drop the stock further: this must update the existing alert, not add a
	# second one. That is the anti-spam requirement, checked directly.
	_alert_station.set_servings(
		maxi(_alert_station.current_servings - 1, 0)
	)

	await get_tree().process_frame

	if Comms.get_active_alerts().size() > count:
		_fail("a second alert appeared for the same station condition")
	else:
		_pass(
			"one alert for %s, and further consumption did not duplicate it"
			% String(_alert_station.name)
		)

	_advance()


func _step_refill_station() -> void:
	_alert_station.fill_stock()

	_pass("refilled %s" % String(_alert_station.name))
	_advance()


func _step_expect_alert_resolved() -> void:
	if not Comms.get_active_alerts().is_empty():
		return

	_pass("stock alert resolved automatically after the refill")
	_advance()


func _step_export_reports() -> void:
	var manager: Node = _main.get_node_or_null(
		"Managers/StaffReportManager"
	)

	if manager == null:
		_fail("StaffReportManager is not in main.tscn")
		_advance()
		return

	var path: String = String(manager.call(&"finalize_and_write_report"))

	if path.is_empty():
		_fail("the staff report could not be written")
	else:
		_pass("report written to " + path)

	_advance()


# -----------------------------------------------------------------------------
# Finding things
# -----------------------------------------------------------------------------

func _find_waiting_customer() -> Node:
	for node: Node in get_tree().get_nodes_in_group(&"seated_customers"):
		if node.has_method(&"is_awaiting_service"):
			if bool(node.call(&"is_awaiting_service")):
				return node

	var manager: Node = _main.get_node_or_null("Managers/GameManager")

	if manager == null:
		return null

	for node: Node in manager.get(&"active_customers"):
		if node == null or not is_instance_valid(node):
			continue

		if node.has_method(&"is_awaiting_service"):
			if bool(node.call(&"is_awaiting_service")):
				return node

	return null


func _find_bar_counter() -> Node:
	var counters: Array = get_tree().get_nodes_in_group(&"bar_counters")

	return null if counters.is_empty() else counters[0] as Node


func _find_clean_unreserved_chair() -> Chair:
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

		if chair.empty_glass_task == null:
			continue

		return chair

	return null


# -----------------------------------------------------------------------------
# Reporting
# -----------------------------------------------------------------------------

func _advance() -> void:
	_step += 1
	_step_elapsed = 0.0


func _pass(
	message: String
) -> void:
	_checks += 1

	print("PASS  ", message)


func _fail(
	message: String
) -> void:
	_checks += 1
	_failures += 1

	print("FAIL  ", message)


func _finish() -> void:
	print("=== SUMMARY: %d checks, %d failures ===" % [_checks, _failures])
	print("task board: ", TaskBoard.get_summary())
	print("communication: ", Comms.get_summary())

	get_tree().quit(1 if _failures > 0 else 0)
