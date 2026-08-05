extends Node

## Confirms the new diagnostic fields actually populate and export.
##
## A report that silently omits the new fields would be worse than none - the
## next session would look identical to the last and tell us nothing.

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	for _i in range(8):
		await get_tree().process_frame

	var manager: Node = main.get_node_or_null(
		^"Managers/CustomerAIReportManager"
	)
	var game_manager: Node = main.get_node_or_null(^"Managers/GameManager")

	Tavern.open_early()
	await get_tree().process_frame

	for _i in range(3):
		game_manager.spawn_customer()
		await get_tree().process_frame

	for _i in range(30):
		await get_tree().process_frame

	var path: String = manager.finalize_and_write_report()

	_check(
		not path.is_empty() and FileAccess.file_exists(path),
		"REPORT: a report was written to %s" % path,
		"REPORT: no report file was produced"
	)

	var text: String = FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)

	_check(
		data is Dictionary,
		"REPORT: it parses as JSON",
		"REPORT: the file is not valid JSON"
	)

	var visits: Array = []
	visits.append_array(data.get("active_visits", []))
	visits.append_array(data.get("completed_visits", []))

	_check(
		not visits.is_empty(),
		"REPORT: %d visits were recorded" % visits.size(),
		"REPORT: no visits in the report"
	)

	var required: Array[String] = [
		"current_state", "state_trail", "reached_inside_at_minutes",
		"seated_at_minutes", "first_order_at_minutes", "never_entered",
		"last_position_x", "distance_from_door", "navigation_failures",
	]

	var first: Dictionary = visits[0]
	var missing: Array[String] = []

	for key: String in required:
		if not first.has(key):
			missing.append(key)

	_check(
		missing.is_empty(),
		"REPORT: all %d new diagnostic fields are present" % required.size(),
		"REPORT: missing fields: %s" % ", ".join(missing)
	)

	var with_trail: int = 0

	for visit: Dictionary in visits:
		if not (visit.get("state_trail", []) as Array).is_empty():
			with_trail += 1

	_check(
		with_trail > 0,
		"REPORT: %d visits carry a populated state trail" % with_trail,
		"REPORT: every state trail is empty - transitions are not recorded"
	)

	print("  SAMPLE TRAIL: %s" % str(first.get("state_trail", [])))
	print("  never_entered=%s reached_inside=%s dist_from_door=%.1f" % [
		str(first.get("never_entered")),
		str(first.get("reached_inside_at_minutes")),
		float(first.get("distance_from_door", -1.0)),
	])

	_report()


func _check(condition: bool, pass_text: String, fail_text: String) -> void:
	if condition:
		passed += 1
		print("  [PASS] " + pass_text)
	else:
		failed += 1
		print("  [FAIL] " + fail_text)


func _report() -> void:
	print("")
	print("  passed: %d  failed: %d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
