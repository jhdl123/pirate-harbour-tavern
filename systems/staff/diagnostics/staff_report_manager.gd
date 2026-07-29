class_name StaffReportManager
extends Node

## Collects Phase 3A diagnostics and writes them to one JSON file on request.
##
## Modelled directly on [CustomerAIReportManager] so there is one habit to
## learn, not two: a node under Managers, safe to call whether or not it is
## enabled, and a single explicit
## [method finalize_and_write_report] that testers can invoke from the F10
## panel.
##
## [b]Where the report is written[/b]
##
## [code]user://staff_reports/staff_report_<timestamp>.json[/code]
##
## On Windows that is
## [code]%APPDATA%\Godot\app_userdata\PirateHarbourTavern\staff_reports\[/code],
## on Linux
## [code]~/.local/share/godot/app_userdata/PirateHarbourTavern/staff_reports/[/code].
## The full path is returned by the write call and printed into the panel's
## status line, so nobody has to guess.
##
## [b]What it does not do[/b]
##
## It does not duplicate state. Task history lives on [TavernTask], message
## history lives on [CommMessage], and worker counters live on [StaffMember].
## This node asks each of them for a dictionary at write time. A report can
## therefore never disagree with the systems it describes.


const REPORT_FORMAT_VERSION: int = 1
const PHASE_IDENTIFIER: String = "Phase 3A"
const REPORT_DIRECTORY: String = "user://staff_reports/"


@export_category("Export")

## Whether the report includes the full per-task and per-message history.
##
## Off makes the file a summary only, which is enough to answer "did anything
## go wrong?" without a multi-megabyte file after a long session.
@export var include_full_history: bool = true

@export var pretty_print_json: bool = true


@export_category("Debug")

## Prints a one-line summary whenever a task fails or an issue is recorded.
@export var console_debug_enabled: bool = false


var _session_start_unix: float = 0.0
var _session_start_minutes: float = 0.0


func _ready() -> void:
	_session_start_unix = Time.get_unix_time_from_system()
	_session_start_minutes = WorldTime.get_total_minutes_precise()

	if not console_debug_enabled:
		return

	TaskBoard.issue_reported.connect(_on_issue_reported)
	TaskBoard.task_failed.connect(_on_task_failed)


func _on_issue_reported(
	issue: Dictionary
) -> void:
	print("[StaffReport][issue] ", issue.get("issue_type"), ": ",
		issue.get("message"))


func _on_task_failed(
	task: TavernTask
) -> void:
	print("[StaffReport][failed] ", task.describe())


# -----------------------------------------------------------------------------
# Gathering
# -----------------------------------------------------------------------------

## Every worker currently in the tavern.
func get_staff() -> Array[Node]:
	var staff: Array[Node] = []

	var tree: SceneTree = get_tree()

	if tree == null:
		return staff

	for node: Node in tree.get_nodes_in_group(&"tavern_staff"):
		if node != null and is_instance_valid(node):
			staff.append(node)

	return staff


func _build_staff_section() -> Array:
	var records: Array = []

	for worker: Node in get_staff():
		if not worker.has_method(&"get_diagnostics_snapshot"):
			continue

		var snapshot: Dictionary = worker.call(&"get_diagnostics_snapshot")

		if not include_full_history:
			snapshot.erase("state_history")

		records.append(snapshot)

	return records


func _build_report_dictionary() -> Dictionary:
	var tasks: Dictionary = TaskBoard.build_report_section()
	var comms: Dictionary = Comms.build_report_section()

	if not include_full_history:
		tasks.erase("open_tasks")
		tasks.erase("finished_tasks")
		comms.erase("active")
		comms.erase("history")

	return {
		"format_version": REPORT_FORMAT_VERSION,
		"phase": PHASE_IDENTIFIER,
		"generated_unix": Time.get_unix_time_from_system(),
		"generated_iso": Time.get_datetime_string_from_system(false, true),
		"session": {
			"started_unix": _session_start_unix,
			"real_seconds": (
				Time.get_unix_time_from_system() - _session_start_unix
			),
			"started_world_minutes": _session_start_minutes,
			"world_minutes_elapsed": (
				WorldTime.get_total_minutes_precise() - _session_start_minutes
			),
			"world_time": WorldTime.get_full_text(),
		},
		"staff": _build_staff_section(),
		"state_transitions": _build_transition_section(),
		"tasks": tasks,
		"communication": comms,
	}


## State transitions counted by (from, to, reason).
##
## Phase 3A recorded the reason "transition" for almost everything, so a
## reader could see that a worker moved between two states hundreds of times
## and had no way to find out why. Grouping by reason is what turns that into
## a finding.
func _build_transition_section() -> Dictionary:
	var counts: Dictionary = {}

	for worker: Node in get_staff():
		if not worker.has_method(&"get_diagnostics_snapshot"):
			continue

		var snapshot: Dictionary = worker.call(&"get_diagnostics_snapshot")

		var history: Array = snapshot.get("state_history", [])

		for entry: Variant in history:
			var record: Dictionary = entry as Dictionary

			if record == null:
				continue

			var key: String = "%s -> %s (%s)" % [
				String(record.get("from", "?")),
				String(record.get("to", "?")),
				String(record.get("reason", "?")),
			]

			counts[key] = int(counts.get(key, 0)) + 1

	return counts


# -----------------------------------------------------------------------------
# Writing
# -----------------------------------------------------------------------------

## Writes the report and returns the path, or an empty string on failure.
##
## Always writes when asked, even if nothing interesting happened: a developer
## who presses the button should get a file, not silence.
func finalize_and_write_report() -> String:
	var directory: DirAccess = DirAccess.open("user://")

	if directory == null:
		push_error("StaffReportManager could not access user://.")
		return ""

	if not directory.dir_exists("staff_reports"):
		var make_error: int = directory.make_dir_recursive("staff_reports")

		if make_error != OK:
			push_error(
				"StaffReportManager could not create " + REPORT_DIRECTORY
			)

			return ""

	var json_text: String = JSON.stringify(
		_build_report_dictionary(),
		("\t" if pretty_print_json else "")
	)

	var path: String = (
		REPORT_DIRECTORY
		+ "staff_report_"
		+ _filename_safe_timestamp()
		+ ".json"
	)

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		push_error("StaffReportManager could not write to " + path)
		return ""

	file.store_string(json_text)
	file.close()

	return path


func _filename_safe_timestamp() -> String:
	return (
		Time.get_datetime_string_from_system(false, true)
			.replace(":", "-")
			.replace(" ", "_")
	)


# -----------------------------------------------------------------------------
# Quick reads for developer tools
# -----------------------------------------------------------------------------

## A compact summary for the F10 panel's status line.
func get_summary_text() -> String:
	var tasks: Dictionary = TaskBoard.get_summary()
	var comms: Dictionary = Comms.get_summary()

	return (
		"Tasks: %d open, %d done, %d failed. Alerts: %d active. Issues: %d."
		% [
			int(tasks.get("tasks_open", 0)),
			int(tasks.get("tasks_completed", 0)),
			int(tasks.get("tasks_failed", 0)),
			int(comms.get("active_alerts", 0)),
			int(tasks.get("issues_recorded", 0)),
		]
	)
