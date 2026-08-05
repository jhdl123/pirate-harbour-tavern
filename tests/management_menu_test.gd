extends Node

## Checks that the M management menu's stock page renders and stays live.
##
## [codeblock]
## godot --headless --fixed-fps 60 res://tests/management_menu_test.tscn
## [/codeblock]
##
## The bug this exists to catch was not a data bug: the page built its rows
## perfectly and displayed nothing, because it was created in code inside a
## plain Control and therefore had a rect of zero by zero. A test that only
## counted rows would have passed throughout. This one asserts the rect too.

const MAIN_SCENE_PATH: String = "res://scenes/main/main.tscn"

var _main: Node = null
var _menu: Node = null
var _failures: Array[String] = []
var _passes: Array[String] = []


func _ready() -> void:
	_main = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	add_child(_main)

	await get_tree().process_frame
	await _wait_frames(60)

	_menu = _find_by_script(_main, "bar_management_menu.gd")

	if _menu == null:
		_fail("MENU", "Management menu not found in the main scene.")
		_report()
		return

	await _test_page_renders()
	await _test_live_updates()
	await _test_reopen_is_fresh()

	_report()


func _test_page_renders() -> void:
	_menu.call(&"open_menu")
	await _wait_frames(2)
	_menu.call(&"_show_stock_page")
	await _wait_frames(2)

	var page: Control = _menu.get("_stock_page")
	var overview: Control = _menu.get("overview_page")
	var rows: Control = _menu.get("_stock_rows")

	if rows.get_child_count() <= 0:
		_fail("RENDER", "The stock page built no rows.")
		return

	_pass("RENDER", "Stock page built %d rows." % rows.get_child_count())

	# The decisive check. A zero-sized page shows nothing however many rows
	# it contains.
	if page.size.x < 10.0 or page.size.y < 10.0:
		_fail(
			"RENDER",
			"Stock page rect is %s - it would render as nothing." % str(page.size)
		)
		return

	_pass("RENDER", "Stock page rect is %s." % str(page.size))

	if not page.size.is_equal_approx(overview.size):
		_fail(
			"RENDER",
			"Stock page %s does not match the overview page %s."
			% [str(page.size), str(overview.size)]
		)
		return

	_pass("RENDER", "Stock page occupies the same area as the overview page.")


func _test_live_updates() -> void:
	var station: DrinksStation = null

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		station = node as DrinksStation
		break

	if station == null:
		_fail("LIVE", "No drink station found.")
		return

	station.fill_stock()
	await _wait_frames(10)

	var display_name: String = String(station.get_stock_summary()["name"])

	var before: String = _row_text_for(display_name)

	station.set_servings(maxi(station.current_servings - 4, 0))
	await _wait_frames(20)

	var after: String = _row_text_for(display_name)

	if before.is_empty() or after.is_empty():
		_fail("LIVE", "Could not find a row for '%s'." % display_name)
		return

	if before == after:
		_fail("LIVE", "Row did not change while the menu was open: '%s'." % before)
		return

	_pass("LIVE", "Row updated live: '%s' -> '%s'." % [before, after])

	if not after.contains(str(station.current_servings)):
		_fail(
			"LIVE",
			"Row '%s' does not match the station's %d servings."
			% [after, station.current_servings]
		)
		return

	_pass("LIVE", "Row matches the station's authoritative value.")


func _test_reopen_is_fresh() -> void:
	var station: DrinksStation = null

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		station = node as DrinksStation
		break

	_menu.call(&"close_menu")
	await _wait_frames(5)

	# Change stock while the menu is shut, then reopen.
	station.fill_stock()
	await _wait_frames(5)

	_menu.call(&"open_menu")
	await _wait_frames(2)
	_menu.call(&"_show_stock_page")
	await _wait_frames(5)

	var text: String = _row_text_for(
		String(station.get_stock_summary()["name"])
	)

	if not text.contains(str(station.current_servings)):
		_fail(
			"REOPEN",
			"Reopened menu shows '%s' but the station holds %d."
			% [text, station.current_servings]
		)
		return

	_pass("REOPEN", "Reopened menu shows current stock: '%s'." % text)

	_menu.call(&"close_menu")


## The first stock row mentioning [param fragment].
func _row_text_for(
	fragment: String
) -> String:
	var rows: Control = _menu.get("_stock_rows")

	if rows == null:
		return ""

	for child: Node in rows.get_children():
		var label: Label = child as Label

		if label == null:
			continue

		if label.text.contains(fragment):
			return label.text

	return ""


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
	print("MANAGEMENT MENU TEST")
	print("  passed: %d" % _passes.size())
	print("  failed: %d" % _failures.size())
	for line: String in _failures:
		print(line)
	print("==================================================")
	get_tree().quit(0 if _failures.is_empty() else 1)
