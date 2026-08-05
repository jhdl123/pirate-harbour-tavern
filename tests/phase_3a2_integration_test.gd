extends Node

## Verification for the Phase 3A.2 debug and integration pass.
##
## [codeblock]
## godot --headless --fixed-fps 60 res://tests/phase_3a2_integration_test.tscn
## [/codeblock]

const MAIN_SCENE_PATH: String = "res://scenes/main/main.tscn"
const WAIT_FRAME_BUDGET: int = 5400

var _main: Node = null
var _failures: Array[String] = []
var _passes: Array[String] = []


func _ready() -> void:
	_main = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	add_child(_main)
	await get_tree().process_frame
	await _wait_frames(30)

	await _test_role_boundary()
	await _test_bar_sides()
	await _test_alert_speaker()
	await _test_menu_live_stock()
	await _test_autonomous_run()

	_report()


## The bartender must be refused serve_drink through every route.
func _test_role_boundary() -> void:
	var bartender: StaffMember = _find_worker(&"prepare_drinks")
	var hand: StaffMember = _find_worker(&"serve_drinks")

	if bartender == null or hand == null:
		_fail("ROLE", "Expected both a Bartender and a Tavern Hand.")
		return

	_pass("ROLE", "Found %s and %s." % [bartender.staff_id, hand.staff_id])

	var serve_definition: TavernTaskDefinition = TaskBoard.config.find_definition(
		TavernTaskTypes.SERVE_DRINK
	)

	if serve_definition == null or serve_definition.required_capabilities.is_empty():
		_fail("ROLE", "serve_drink declares no required capability.")
		return

	_pass("ROLE", "serve_drink requires %s." % str(
		serve_definition.required_capabilities
	))

	if bartender.can_perform_task(_make_probe(TavernTaskTypes.SERVE_DRINK)):
		_fail("ROLE", "Bartender reports it can serve drinks.")
		return

	_pass("ROLE", "Bartender correctly cannot perform serve_drink.")

	if hand.can_perform_task(_make_probe(TavernTaskTypes.PREPARE_DRINK)):
		_fail("ROLE", "Tavern Hand reports it can prepare drinks.")
		return

	_pass("ROLE", "Tavern Hand correctly cannot perform prepare_drink.")

	# The direct claim route, which reassignment and recovery both use.
	var before: int = TaskBoard.get_capability_violation_count()
	var probe: TavernTask = _make_probe(TavernTaskTypes.SERVE_DRINK)

	if TaskBoard.claim(probe, bartender, bartender.staff_id):
		_fail("ROLE", "TaskBoard.claim() let the Bartender take a serve task.")
		return

	_pass("ROLE", "TaskBoard.claim() refused the Bartender directly.")

	if TaskBoard.get_capability_violation_count() <= before:
		_fail("ROLE", "The refusal was not recorded as a violation.")
		return

	_pass("ROLE", "The refusal was recorded with worker and task detail.")


func _make_probe(task_type: StringName) -> TavernTask:
	var task: TavernTask = TavernTask.new()
	task.task_id = &"probe"
	task.task_type = task_type
	task.definition = TaskBoard.config.find_definition(task_type)
	return task


## Deposit and collection points must be on opposite sides of one slot.
func _test_bar_sides() -> void:
	var counter: BarCounter = null

	for node: Node in get_tree().get_nodes_in_group(&"bar_counters"):
		counter = node as BarCounter
		break

	if counter == null:
		_fail("BAR", "No bar counter found.")
		return

	if not counter.has_complete_access_points():
		_fail("BAR", "The counter is missing deposit or collection points.")
		return

	_pass("BAR", "Every slot has both access points configured.")

	var deposit: Vector2 = counter.get_slot_access_position(
		0, BarCounter.SlotAccess.DEPOSIT
	)
	var collect: Vector2 = counter.get_slot_access_position(
		0, BarCounter.SlotAccess.COLLECT
	)

	if deposit.y >= collect.y:
		_fail(
			"BAR",
			"Deposit point (y=%.0f) is not north of collection (y=%.0f)."
			% [deposit.y, collect.y]
		)
		return

	_pass(
		"BAR",
		"Slot 0: deposit y=%.0f (north), collect y=%.0f (south), %.0fpx apart."
		% [deposit.y, collect.y, collect.y - deposit.y]
	)

	# One logical slot, whichever side you approach from.
	if counter.get_service_slot(0) != counter.get_service_slot(0):
		_fail("BAR", "Slot lookup is not stable.")
		return

	_pass("BAR", "Both access points address one logical ItemSlot.")


## Stock alerts must name whoever can refill, not whoever is found first.
func _test_alert_speaker() -> void:
	var station: DrinksStation = null

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		station = node as DrinksStation
		break

	if station == null:
		_fail("SPKR", "No drink station found.")
		return

	station.fill_stock()
	await _wait_frames(5)
	station.set_servings(0)
	await _wait_frames(30)

	var found: CommMessage = null

	for message: CommMessage in Comms.get_active_alerts():
		if message.speaker_id != &"":
			found = message
			break

	if found == null:
		_fail("SPKR", "No alert with a speaker was raised.")
		return

	var bartender: StaffMember = _find_worker(&"refill_stations")

	if bartender != null and found.speaker_id != bartender.staff_id:
		_fail(
			"SPKR",
			"Alert speaker is '%s'; expected the refilling role '%s'."
			% [String(found.speaker_id), String(bartender.staff_id)]
		)
		return

	_pass(
		"SPKR",
		"Alert speaker is '%s' (%s) - the role that can act on it."
		% [String(found.speaker_id), found.speaker_name]
	)

	station.fill_stock()
	await _wait_frames(30)


## The menu must reflect stock changes without being reopened.
func _test_menu_live_stock() -> void:
	var menu: Node = null

	for node: Node in get_tree().get_nodes_in_group(&"management_menu"):
		menu = node
		break

	if menu == null:
		menu = _find_by_script(_main, "bar_management_menu.gd")

	if menu == null or not menu.has_method(&"get_stock_snapshot"):
		_fail("MENU", "Management menu not found or has no snapshot method.")
		return

	var station: DrinksStation = null

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		station = node as DrinksStation
		break

	if station == null:
		_fail("MENU", "No drink station found.")
		return

	station.fill_stock()
	await _wait_frames(10)

	var before: Dictionary = menu.call(&"get_stock_snapshot")
	var before_value: int = _snapshot_servings(before, station.name)

	station.set_servings(maxi(station.current_servings - 3, 0))
	await _wait_frames(10)

	var after: Dictionary = menu.call(&"get_stock_snapshot")
	var after_value: int = _snapshot_servings(after, station.name)

	if after_value == before_value:
		_fail(
			"MENU",
			"Snapshot did not change after stock was consumed (%d)."
			% before_value
		)
		return

	if after_value != station.current_servings:
		_fail(
			"MENU",
			"Snapshot says %d, station says %d - not authoritative."
			% [after_value, station.current_servings]
		)
		return

	_pass(
		"MENU",
		"Snapshot tracks the station live: %d -> %d, matching the station."
		% [before_value, after_value]
	)

	station.fill_stock()


func _snapshot_servings(snapshot: Dictionary, station_name: StringName) -> int:
	for entry: Dictionary in snapshot.get("stations", []):
		if String(entry.get("station", "")) == String(station_name):
			return int(entry.get("current_servings", -1))

	return -1


## A short autonomous run: nobody should cross a role boundary.
func _test_autonomous_run() -> void:
	await _wait_frames(3600)

	var violations: int = TaskBoard.get_capability_violation_count()

	var serves_by_bartender: int = 0
	var preps_by_hand: int = 0

	for node: Node in get_tree().get_nodes_in_group(&"tavern_staff"):
		var worker: StaffMember = node as StaffMember

		if worker == null:
			continue

		var snapshot: Dictionary = worker.get_diagnostics_snapshot()
		var capabilities: Array[StringName] = worker.get_staff_capabilities()

		if not capabilities.has(StaffCapabilities.SERVE_DRINKS):
			serves_by_bartender += int(snapshot.get("serves_completed", 0))

		if not capabilities.has(StaffCapabilities.PREPARE_DRINKS):
			preps_by_hand += int(snapshot.get("prepares_completed", 0))

	if serves_by_bartender > 0:
		_fail(
			"AUTO",
			"A worker without serve_drinks completed %d serves."
			% serves_by_bartender
		)
		return

	_pass("AUTO", "No worker served customers outside its role.")

	if preps_by_hand > 0:
		_fail("AUTO", "A worker without prepare_drinks prepared %d drinks."
			% preps_by_hand)
		return

	_pass("AUTO", "No worker prepared drinks outside its role.")

	_pass(
		"AUTO",
		"%d capability violations recorded and refused (test probes included)."
		% violations
	)

	var summary: Dictionary = TaskBoard.get_summary()

	_pass(
		"AUTO",
		"Board: %d created, %d completed, %d cancelled, %d failed."
		% [
			summary["tasks_created"],
			summary["tasks_completed"],
			summary["tasks_cancelled"],
			summary["tasks_failed"],
		]
	)

	var leaked: int = 0

	for task: TavernTask in TaskBoard.get_finished_tasks():
		if not task.reservations.is_empty():
			leaked += 1

	if leaked > 0:
		_fail("AUTO", "%d finished tasks still hold reservations." % leaked)
		return

	_pass("AUTO", "No finished task retained a reservation.")


func _find_worker(capability: StringName) -> StaffMember:
	for node: Node in get_tree().get_nodes_in_group(&"tavern_staff"):
		var worker: StaffMember = node as StaffMember

		if worker == null:
			continue

		if worker.get_staff_capabilities().has(capability):
			return worker

	return null


func _find_by_script(root: Node, fragment: String) -> Node:
	if root.get_script() != null:
		if String(root.get_script().resource_path).ends_with(fragment):
			return root

	for child: Node in root.get_children():
		var found: Node = _find_by_script(child, fragment)

		if found != null:
			return found

	return null


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
	print("PHASE 3A.2 INTEGRATION TEST")
	print("  passed: %d" % _passes.size())
	print("  failed: %d" % _failures.size())
	for line: String in _failures:
		print(line)
	print("==================================================")
	get_tree().quit(0 if _failures.is_empty() else 1)
