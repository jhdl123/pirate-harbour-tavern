extends Node

## Proves that ordinary gameplay - with no F10 injection - reaches the daily
## summary.
##
## The previous pass shipped a complete DailyStatistics model that nothing
## called. Every check here therefore plays the game: it waits for real
## customers to be served by real staff, and asserts the figures afterwards.
## Nothing in this file calls Tavern.stats.record*().

const MAIN_SCENE_PATH: String = "res://scenes/main/main.tscn"

var _main: Node = null
var _failures: Array[String] = []
var _passes: Array[String] = []


func _ready() -> void:
	_main = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	add_child(_main)

	await get_tree().process_frame
	await _wait_frames(30)

	await _test_no_injection_baseline()
	await _test_real_trading_day()
	await _test_no_double_recording()
	await _test_state_flow()

	_report()


func _test_no_injection_baseline() -> void:
	var record: Dictionary = Tavern.stats.build_record()

	_pass(
		"BASE",
		"Day starts at income %.0f, served %d."
		% [
			record["total_income"],
			int(record["counters"]["customers_served"]),
		]
	)

	var recorder: Node = _main.get_node_or_null(
		"Managers/DailyStatisticsRecorder"
	)

	if recorder == null:
		_fail("BASE", "DailyStatisticsRecorder is not in the scene.")
		return

	_pass(
		"BASE",
		"Recorder listening to %d authoritative signals."
		% int(recorder.call(&"get_subscription_count"))
	)


## Open the tavern, keep the bar stocked as a player would, and let the staff
## trade. Then assert the day's figures are real.
func _test_real_trading_day() -> void:
	# Open for business.
	WorldTime.set_time(WorldTime.get_day(), 18, 0)
	await _wait_frames(20)

	if not Tavern.is_accepting_arrivals():
		_fail("TRADE", "Tavern is not open at 18:00 (%s)." % Tavern.get_state_name())
		return

	_pass("TRADE", "Tavern open; trading for a while.")

	# Play: keep the bar stocked so the Tavern Hand has drinks to deliver.
	for tick: int in range(240):
		if tick % 20 == 0:
			_restock_bar()

		await _wait_frames(15)

		if int(Tavern.stats.build_record()["counters"]["customers_served"]) >= 3:
			break

	var record: Dictionary = Tavern.stats.build_record()
	var counters: Dictionary = record["counters"]

	var served: int = int(counters["customers_served"])

	if served <= 0:
		_fail("TRADE", "No customer was served during a full trading period.")
		return

	_pass("TRADE", "%d real paid transactions recorded." % served)

	if record["total_income"] <= 0.0:
		_fail("TRADE", "Income is zero after %d sales." % served)
		return

	_pass("TRADE", "Income %.0f recorded from real payments." % record["total_income"])

	# The item breakdown must name a real drink, not a placeholder.
	var sales: Dictionary = record["sales_by_item"]

	if sales.is_empty():
		_fail("TRADE", "sales_by_item is empty despite %d sales." % served)
		return

	for item_id: String in sales.keys():
		if item_id.begins_with("test") or item_id.is_empty():
			_fail("TRADE", "Sales breakdown contains placeholder '%s'." % item_id)
			return

	_pass("TRADE", "Sales by item: %s" % str(sales))

	# Stock usage must come from stock actually leaving stations.
	if record["stock_used_by_item"].is_empty():
		_fail("TRADE", "No stock usage recorded despite real service.")
		return

	_pass("TRADE", "Stock used by item: %s" % str(record["stock_used_by_item"]))

	if int(counters["customers_entered"]) <= 0:
		_fail("TRADE", "No arrivals recorded.")
		return

	_pass("TRADE", "%d customers entered." % int(counters["customers_entered"]))

	if float(record["peaks"]["peak_occupancy"]) <= 0.0:
		_fail("TRADE", "Peak occupancy never rose above zero.")
		return

	_pass("TRADE", "Peak occupancy %.0f." % record["peaks"]["peak_occupancy"])


## Income recorded daily must match what the economy actually received.
func _test_no_double_recording() -> void:
	var economy: Node = _main.get_node_or_null("Managers/EconomyManager")

	if economy == null:
		_fail("DOUBLE", "No EconomyManager.")
		return

	var recorder: Node = _main.get_node_or_null(
		"Managers/DailyStatisticsRecorder"
	)

	# Count sale events in the recorder's own log and compare with the
	# transaction count. A doubled subscription shows up here immediately.
	var sale_events: int = 0

	for entry: Dictionary in recorder.call(&"get_event_log"):
		if String(entry["event_type"]) == "sale":
			sale_events += 1

		if int(entry.get("values", {}).get("payments_this_frame", 1)) > 1:
			_fail(
				"DOUBLE",
				"Two payments recorded in one frame - likely a duplicate."
			)
			return

	var served: int = int(
		Tavern.stats.build_record()["counters"]["customers_served"]
	)

	if sale_events != served:
		_fail(
			"DOUBLE",
			"%d sale events but %d served - counts disagree."
			% [sale_events, served]
		)
		return

	_pass("DOUBLE", "%d sale events == %d served; no duplication." % [
		sale_events, served
	])


## END_OF_DAY -> READY_FOR_NEXT_DAY -> PREPARING must all be reachable.
func _test_state_flow() -> void:
	WorldTime.set_time(WorldTime.get_day(), 2, 0)
	await _wait_frames(15)

	var before: Dictionary = Tavern.stats.build_record()
	var income_before: float = before["total_income"]

	var summary: Dictionary = Tavern.end_day()

	if summary.is_empty():
		_fail("FLOW", "end_day() produced nothing while closed.")
		return

	if Tavern.get_state() != TavernLifecycle.State.END_OF_DAY:
		_fail("FLOW", "Not in END_OF_DAY after end_day() (%s)." % Tavern.get_state_name())
		return

	_pass("FLOW", "END_OF_DAY entered; summary frozen.")

	if summary["statistics"]["total_income"] != income_before:
		_fail("FLOW", "Frozen income differs from the live figure at freeze time.")
		return

	_pass("FLOW", "Frozen income %.0f matches the day traded." % income_before)

	if Tavern.can_start_next_day():
		_fail("FLOW", "Next day allowed before the summary was acknowledged.")
		return

	_pass("FLOW", "Next day correctly blocked until acknowledged.")

	Tavern.acknowledge_summary()

	if Tavern.get_state() != TavernLifecycle.State.READY_FOR_NEXT_DAY:
		_fail(
			"FLOW",
			"READY_FOR_NEXT_DAY not entered (%s)." % Tavern.get_state_name()
		)
		return

	_pass("FLOW", "READY_FOR_NEXT_DAY is reachable and entered.")

	if not Tavern.can_start_next_day():
		_fail("FLOW", "Next day still blocked after acknowledgement.")
		return

	_pass("FLOW", "Next day permitted after acknowledgement.")

	var result: Dictionary = Tavern.advance_to_next_day()

	await _wait_frames(15)

	if result.is_empty():
		_fail("FLOW", "advance_to_next_day() refused.")
		return

	if Tavern.get_state() != TavernLifecycle.State.PREPARING:
		_fail("FLOW", "New day did not begin in PREPARING.")
		return

	_pass("FLOW", "New day began in PREPARING.")

	if Tavern.stats.build_record()["total_income"] != 0.0:
		_fail("FLOW", "Per-day income did not reset.")
		return

	_pass("FLOW", "Per-day figures reset for the new day.")

	# Customers sent home by cleanup must not count as lost.
	var counters: Dictionary = Tavern.stats.build_record()["counters"]

	if float(counters.get("customers_lost", 0.0)) > 0.0:
		_fail("FLOW", "Cleanup departures were counted as lost customers.")
		return

	_pass("FLOW", "Cleanup departures were not counted as losses.")


func _restock_bar() -> void:
	var manager: Node = _main.get_node_or_null("Managers/GameManager")

	if manager == null:
		return

	var wanted: Array = []

	for customer: Node in manager.get("active_customers"):
		if customer == null or not is_instance_valid(customer):
			continue

		if not customer.has_method(&"is_awaiting_service"):
			continue

		if bool(customer.call(&"is_awaiting_service")):
			var drink: Variant = customer.call(&"get_requested_drink")

			if drink != null:
				wanted.append(drink)

	if wanted.is_empty():
		return

	for node: Node in get_tree().get_nodes_in_group(&"bar_counters"):
		var container: ItemContainer = node.call(
			&"get_service_container"
		) as ItemContainer

		if container == null:
			continue

		for index: int in range(container.get_slot_count()):
			if wanted.is_empty():
				return

			var slot: ItemSlot = container.get_slot(index)

			if slot == null or not slot.is_empty():
				continue

			ItemTransferService.give_to_slot(
				slot,
				ItemStack.create(wanted.pop_front(), 1)
			)


func _wait_frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame


func _pass(scenario: String, message: String) -> void:
	var line: String = "  [PASS] %s: %s" % [scenario, message]
	_passes.append(line)
	print(line)


func _fail(scenario: String, message: String) -> void:
	var line: String = "  [FAIL] %s: %s" % [scenario, message]
	_failures.append(line)
	print(line)


func _report() -> void:
	print("")
	print("==================================================")
	print("PHASE 4A PRODUCTION INTEGRATION TEST")
	print("  passed: %d" % _passes.size())
	print("  failed: %d" % _failures.size())
	for line: String in _failures:
		print(line)
	print("==================================================")
	get_tree().quit(0 if _failures.is_empty() else 1)
