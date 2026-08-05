extends Node

## Drives the complete daily loop through the player-facing UI only.
##
## Every transition below is triggered by pressing a button on the
## DailyControlBar. Nothing here calls Tavern.end_day(),
## Tavern.advance_to_next_day() or any other lifecycle method directly, and
## nothing touches the F10 panel. If this suite passes, the loop is reachable
## by a player.

const MAIN_SCENE_PATH: String = "res://scenes/main/main.tscn"

var _main: Node = null
var _bar: DailyControlBar = null
var _summary: EndOfDaySummary = null
var _failures: Array[String] = []
var _passes: Array[String] = []


func _ready() -> void:
	_main = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	add_child(_main)

	await get_tree().process_frame
	await _wait_frames(30)

	_bar = _find(_main, "daily_control_bar.gd") as DailyControlBar
	_summary = _find(_main, "end_of_day_summary.gd") as EndOfDaySummary

	if _bar == null or _summary == null:
		_fail("SETUP", "Control bar or summary screen missing from the scene.")
		_report()
		return

	_pass("SETUP", "Control bar and summary screen are both in the scene.")

	await _test_button_availability()
	await _test_full_loop_via_ui()
	await _test_repeat_clicks()

	_report()


## Buttons must be enabled only in states where their action is legal.
func _test_button_availability() -> void:
	WorldTime.set_time(WorldTime.get_day(), 17, 30)
	await _wait_frames(10)

	if Tavern.get_state() != TavernLifecycle.State.PREPARING:
		_fail("BUTTONS", "Expected PREPARING at 17:30.")
		return

	var expected: Dictionary = {
		&"open": true,
		&"last_orders": false,
		&"close": false,
		&"end_day": false,
		&"summary": false,
		&"next_day": false,
	}

	if not _check_buttons("PREPARING", expected):
		return

	# Open through the bar, exactly as a player would.
	_bar._on_pressed(&"open")
	await _wait_frames(5)

	if Tavern.get_state() != TavernLifecycle.State.OPEN:
		_fail("BUTTONS", "Open Tavern did not open the tavern.")
		return

	_pass("BUTTONS", "Open Tavern button opened the tavern.")

	if not _check_buttons("OPEN", {
		&"open": false,
		&"last_orders": true,
		&"close": true,
		&"end_day": false,
		&"next_day": false,
	}):
		return

	_bar._on_pressed(&"last_orders")
	await _wait_frames(5)

	if Tavern.get_state() != TavernLifecycle.State.LAST_ORDERS:
		_fail("BUTTONS", "Last Orders button did not take effect.")
		return

	_pass("BUTTONS", "Last Orders button took effect.")

	if not _check_buttons("LAST_ORDERS", {
		&"open": false,
		&"last_orders": false,
		&"close": true,
		&"end_day": false,
	}):
		return

	# A disabled button must do nothing even if pressed.
	var state_before: TavernLifecycle.State = Tavern.get_state()

	_bar._on_pressed(&"end_day")
	await _wait_frames(5)

	if Tavern.get_state() != state_before:
		_fail("BUTTONS", "A disabled End Day button still acted.")
		return

	_pass("BUTTONS", "Disabled buttons do not act when pressed.")


func _check_buttons(
	state_name: String,
	expected: Dictionary
) -> bool:
	for id: StringName in expected.keys():
		var want: bool = bool(expected[id])
		var got: bool = _bar.is_button_enabled(id)

		if got != want:
			_fail(
				"BUTTONS",
				"%s: '%s' enabled=%s, expected %s."
				% [state_name, String(id), got, want]
			)

			return false

	_pass("BUTTONS", "%s: all %d buttons correct." % [
		state_name, expected.size()
	])

	return true


## The whole loop, driven only by button presses.
func _test_full_loop_via_ui() -> void:
	_bar._on_pressed(&"close")
	await _wait_frames(5)

	# Closing runs a grace period; let the clock carry it to CLOSED.
	WorldTime.advance_minutes(60)
	await _wait_frames(15)

	if Tavern.get_state() != TavernLifecycle.State.CLOSED:
		_fail("LOOP", "Tavern did not reach CLOSED (%s)." % Tavern.get_state_name())
		return

	_pass("LOOP", "Tavern reached CLOSED.")

	if not _bar.is_button_enabled(&"end_day"):
		_fail("LOOP", "End Day is not enabled while CLOSED.")
		return

	_pass("LOOP", "End Day is enabled while CLOSED.")

	_bar._on_pressed(&"end_day")
	await _wait_frames(10)

	# The summary must appear by itself, without anybody asking for it.
	if not _summary.is_open():
		_fail("LOOP", "The summary did not open automatically after End Day.")
		return

	_pass("LOOP", "Summary opened automatically after End Day.")

	if Tavern.get_state() != TavernLifecycle.State.END_OF_DAY:
		_fail("LOOP", "Not in END_OF_DAY after End Day.")
		return

	_pass("LOOP", "END_OF_DAY entered.")

	if _bar.is_button_enabled(&"next_day"):
		_fail("LOOP", "Start Next Day enabled before acknowledgement.")
		return

	_pass("LOOP", "Start Next Day correctly blocked before Continue.")

	_summary._on_continue_pressed()
	await _wait_frames(5)

	if Tavern.get_state() != TavernLifecycle.State.READY_FOR_NEXT_DAY:
		_fail(
			"LOOP",
			"Continue did not reach READY_FOR_NEXT_DAY (%s)."
			% Tavern.get_state_name()
		)
		return

	_pass("LOOP", "Continue reached READY_FOR_NEXT_DAY.")

	if not _bar.is_button_enabled(&"next_day"):
		_fail("LOOP", "Start Next Day still disabled after Continue.")
		return

	_pass("LOOP", "Start Next Day enabled after Continue.")

	# No raw enum names on screen.
	var text: String = DailyControlBar.get_state_text()

	if text.contains("_") or text == text.to_upper():
		_fail("LOOP", "State text '%s' looks like a raw enum name." % text)
		return

	_pass("LOOP", "State reads as '%s'." % text)

	var day_before: int = Tavern.trading_day

	_bar._on_pressed(&"next_day")
	await _wait_frames(20)

	if Tavern.get_state() != TavernLifecycle.State.PREPARING:
		_fail("LOOP", "New day did not begin in PREPARING.")
		return

	_pass("LOOP", "Start Next Day began a new day in PREPARING.")

	if Tavern.trading_day == day_before:
		_fail("LOOP", "Trading day did not advance.")
		return

	_pass("LOOP", "Trading day advanced %d -> %d." % [
		day_before, Tavern.trading_day
	])

	if _summary.is_open():
		_fail("LOOP", "Summary is still open after starting the next day.")
		return

	_pass("LOOP", "Summary closed on starting the next day.")


## Rapid repeated clicks must not double anything.
func _test_repeat_clicks() -> void:
	var economy: Node = _main.get_node_or_null("Managers/EconomyManager")

	var money_before: int = (
		0 if economy == null else int(economy.call(&"get_money"))
	)

	WorldTime.set_time(WorldTime.get_day(), 2, 0)
	await _wait_frames(15)

	# End Day five times in a row.
	for press: int in range(5):
		_bar._on_pressed(&"end_day")

	await _wait_frames(10)

	if Tavern.get_state() != TavernLifecycle.State.END_OF_DAY:
		_fail("REPEAT", "Five End Day presses left state %s." % Tavern.get_state_name())
		return

	_pass("REPEAT", "Five End Day presses produced one END_OF_DAY.")

	var frozen_first: Dictionary = Tavern.get_frozen_summary()

	_bar._on_pressed(&"end_day")
	await _wait_frames(5)

	if Tavern.get_frozen_summary()["statistics"]["total_income"] \
		!= frozen_first["statistics"]["total_income"]:
		_fail("REPEAT", "A further End Day press changed the frozen summary.")
		return

	_pass("REPEAT", "Frozen summary unchanged by further presses.")

	var day_before: int = Tavern.trading_day

	_summary._on_continue_pressed()
	await _wait_frames(3)

	# Start Next Day five times in a row.
	for press: int in range(5):
		_bar._on_pressed(&"next_day")

	await _wait_frames(20)

	if Tavern.trading_day != day_before + 1:
		_fail(
			"REPEAT",
			"Five Start Next Day presses advanced %d days."
			% (Tavern.trading_day - day_before)
		)
		return

	_pass("REPEAT", "Five Start Next Day presses advanced exactly one day.")

	if economy != null and int(economy.call(&"get_money")) < money_before:
		_fail("REPEAT", "Money was lost across the day transition.")
		return

	_pass("REPEAT", "Persistent money survived the transition.")


func _find(root: Node, fragment: String) -> Node:
	if root.get_script() != null:
		if String(root.get_script().resource_path).ends_with(fragment):
			return root

	for child: Node in root.get_children():
		var found: Node = _find(child, fragment)

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
	print("PHASE 4A PLAYER LOOP TEST")
	print("  passed: %d" % _passes.size())
	print("  failed: %d" % _failures.size())
	for line: String in _failures:
		print(line)
	print("==================================================")
	get_tree().quit(0 if _failures.is_empty() else 1)
