class_name DiagnosticRunExporter
extends Node

## Writes a complete diagnostic run into the repository's `debug/` folder.
##
## The point is reviewability across commits: after a test day the reports sit
## in Git next to the code that produced them, so "did this regress?" is a diff
## rather than a memory. `debug/latest/` is always exactly the most recent run;
## `debug/archive/<stamp>/` keeps the history.
##
## This node OBSERVES. It asks the existing report managers and the live game
## systems for their state and formats the answers - it holds no counters of
## its own, so it can never disagree with the game.


## Where the repository lives, so reports can be written into it.
##
## `res://` is read-only in an exported build, which is correct: shipping
## players should not be writing diagnostics into the game. In the editor it
## resolves to the project folder, which is the repository.
const DEBUG_DIRECTORY: String = "res://debug"

## Files a run produces. Listed so stale ones can be REMOVED from latest/ when
## a run has no data for them - a mixture of two runs is worse than a gap.
const REPORT_FILES: PackedStringArray = [
	"RUN_SUMMARY.md",
	"drinks_report.txt",
	"stock_report.txt",
	"staff_report.txt",
	"customer_report.txt",
	"system_diagnostics.txt",
]


@export_category("Sources")

## Existing managers, reused rather than replaced.
@export var customer_ai_report_manager: Node
@export var staff_report_manager: Node


@export_category("Run metadata")

## Recorded in RUN_SUMMARY.md so a run says what it was for.
@export var test_purpose: String = ""

## Free-text notes from the developer.
@export_multiline var developer_notes: String = ""

## What the developer expected to happen.
@export_multiline var expected_result: String = ""

## Version string written when Git information cannot be read.
##
## The game never requires Git to run: if the commit cannot be read the report
## says so plainly rather than inventing a version.
@export var game_version: String = "0.1.0-dev"


signal run_exported(path: String)


var _stock_events: Array[Dictionary] = []
var _run_started_unix: float = 0.0


func _ready() -> void:
	add_to_group(&"diagnostic_run_exporter")
	_run_started_unix = Time.get_unix_time_from_system()


# --- Stock event log ---------------------------------------------------------

## Records a stock movement for the run's stock report.
##
## Event-driven and bounded - never polled, never per-frame. The log exists to
## separate "inventory did not change" from "inventory changed but the display
## did not", which are completely different bugs and look identical in a
## summary total.
func record_stock_event(
	kind: StringName,
	label: String,
	change: int,
	detail: String = ""
) -> void:
	_stock_events.append({
		"time": Time.get_time_string_from_system(),
		"kind": String(kind),
		"label": label,
		"change": change,
		"detail": detail,
	})

	# Bounded: a long session must not grow memory without limit.
	if _stock_events.size() > 500:
		_stock_events = _stock_events.slice(_stock_events.size() - 500)


# --- Export ------------------------------------------------------------------

## Generates every report, refreshes latest/ and writes an archive folder.
##
## Returns the archive path, or "" on failure.
func export_run() -> String:
	if not DirAccess.dir_exists_absolute(DEBUG_DIRECTORY):
		var error: int = DirAccess.make_dir_recursive_absolute(DEBUG_DIRECTORY)

		if error != OK:
			push_error(
				"DiagnosticRunExporter could not create %s. In an exported "
				% DEBUG_DIRECTORY
				+ "build res:// is read-only; run from the editor."
			)

			return ""

	var reports: Dictionary = _build_reports()
	var latest: String = "%s/latest" % DEBUG_DIRECTORY
	var stamp: String = _timestamp_folder()
	var archive: String = "%s/archive/%s" % [DEBUG_DIRECTORY, stamp]

	if not _write_report_set(latest, reports):
		return ""

	if not _write_report_set(archive, reports):
		return ""

	_write_readme()
	run_exported.emit(archive)

	return archive


## Writes every report into [param directory], removing any file this run has
## no data for so the folder never mixes two runs.
func _write_report_set(directory: String, reports: Dictionary) -> bool:
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("DiagnosticRunExporter could not create %s." % directory)

		return false

	for filename: String in REPORT_FILES:
		var path: String = "%s/%s" % [directory, filename]

		if not reports.has(filename) or String(reports[filename]).is_empty():
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)

			continue

		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)

		if file == null:
			push_error("DiagnosticRunExporter could not write %s." % path)

			return false

		file.store_string(String(reports[filename]))
		file.close()

	return true


func _build_reports() -> Dictionary:
	var chain: Dictionary = ServiceChainValidator.validate_all(get_tree())
	var systems: Dictionary = _evaluate_systems(chain)

	return {
		"RUN_SUMMARY.md": _build_run_summary(systems, chain),
		"drinks_report.txt": _build_drinks_report(chain),
		"stock_report.txt": _build_stock_report(),
		"staff_report.txt": _build_staff_report(),
		"customer_report.txt": _build_customer_report(),
		"system_diagnostics.txt": _build_system_diagnostics(),
	}


# --- Git ---------------------------------------------------------------------

## Git details for the run, read from .git without needing Git installed.
##
## Parsing the files directly means the game never shells out and never depends
## on a Git binary being present. Missing information is reported as "unknown"
## rather than guessed.
func _get_git_info() -> Dictionary:
	var info: Dictionary = {
		"branch": "unknown",
		"commit": "unknown",
		"short": "unknown",
	}
	var head: FileAccess = FileAccess.open("res://.git/HEAD", FileAccess.READ)

	if head == null:
		return info

	var head_text: String = head.get_as_text().strip_edges()
	head.close()

	if not head_text.begins_with("ref: "):
		# Detached HEAD: the file holds the commit itself.
		info["commit"] = head_text
		info["short"] = head_text.substr(0, 7)

		return info

	var ref: String = head_text.substr(5).strip_edges()
	info["branch"] = ref.get_file()

	var ref_file: FileAccess = FileAccess.open(
		"res://.git/%s" % ref, FileAccess.READ
	)

	if ref_file != null:
		var commit: String = ref_file.get_as_text().strip_edges()
		ref_file.close()
		info["commit"] = commit
		info["short"] = commit.substr(0, 7)

		return info

	# Packed refs: a freshly cloned repository has no loose ref file.
	var packed: FileAccess = FileAccess.open(
		"res://.git/packed-refs", FileAccess.READ
	)

	if packed == null:
		return info

	while not packed.eof_reached():
		var line: String = packed.get_line().strip_edges()

		if line.ends_with(ref):
			var commit: String = line.split(" ")[0]
			info["commit"] = commit
			info["short"] = commit.substr(0, 7)
			break

	packed.close()

	return info


# --- Report bodies -----------------------------------------------------------

func _evaluate_systems(chain: Dictionary) -> Dictionary:
	var systems: Dictionary = {}
	var broken_steps: Dictionary = {}

	for drink_id: String in chain:
		var entry: Dictionary = chain[drink_id]

		if String(entry["result"]) == "PASS":
			continue

		var step: int = int(entry["first_failure"])
		var list: Array = broken_steps.get(step, [])
		list.append(drink_id)
		broken_steps[step] = list

	# Each system's verdict is derived from the chain steps it owns, so a new
	# drink cannot pass a system silently.
	var mapping: Dictionary = {
		"Drinks": [ServiceChainValidator.Step.DRINK_DEFINITION],
		"Stations": [
			ServiceChainValidator.Step.SERVICE_STATION,
			ServiceChainValidator.Step.STATION_CONTENT,
		],
		"Ordering": [ServiceChainValidator.Step.ORDER_CATALOGUE],
		"Delivery": [ServiceChainValidator.Step.AUTHORITATIVE_STORAGE],
		"Storage": [ServiceChainValidator.Step.PHYSICAL_DISPLAY],
		"Restocking": [
			ServiceChainValidator.Step.RESTOCK_ITEM,
			ServiceChainValidator.Step.STAFF_REPLENISHMENT,
		],
		"Bar": [ServiceChainValidator.Step.BAR_COUNTER],
		"Customers": [ServiceChainValidator.Step.CUSTOMER_CONSUMPTION],
	}

	for system_name: String in mapping:
		var issues: Array[String] = []

		for step: int in mapping[system_name]:
			for drink_id: String in broken_steps.get(step, []):
				issues.append(drink_id)

		systems[system_name] = {
			"result": "PASS" if issues.is_empty() else "FAIL",
			"issue": (
				"" if issues.is_empty()
				else "%s" % ", ".join(issues)
			),
		}

	systems["Staff"] = _evaluate_staff()
	systems["Groups"] = _evaluate_groups()

	return systems


func _evaluate_staff() -> Dictionary:
	if staff_report_manager == null:
		return {"result": "N/A", "issue": "no staff report manager"}

	var stuck: int = 0
	var failures: int = 0

	for node: Node in staff_report_manager.get_staff():
		var staff := node as StaffMember

		if staff == null:
			continue

		var snapshot: Dictionary = staff.get_diagnostics_snapshot()
		stuck += int(snapshot.get("stuck_recoveries", 0))
		failures += int(snapshot.get("navigation_failures", 0))

	if failures > 0:
		return {
			"result": "FAIL",
			"issue": "%d navigation failures" % failures,
		}

	if stuck > 20:
		return {"result": "WARN", "issue": "%d stuck recoveries" % stuck}

	return {"result": "PASS", "issue": ""}


func _evaluate_groups() -> Dictionary:
	if customer_ai_report_manager == null:
		return {"result": "N/A", "issue": "no customer report manager"}

	if not customer_ai_report_manager.has_method(&"get_group_summary"):
		return {"result": "N/A", "issue": "group summary unavailable"}

	var summary: Dictionary = customer_ai_report_manager.call(&"get_group_summary")
	var total: int = int(summary.get("total_groups", 0))

	if total == 0:
		return {"result": "N/A", "issue": "no groups this run"}

	var rate: float = float(summary.get("success_rate_percent", 0.0))

	if rate < 50.0:
		return {"result": "FAIL", "issue": "%.1f%% group success" % rate}

	if rate < 80.0:
		return {"result": "WARN", "issue": "%.1f%% group success" % rate}

	return {"result": "PASS", "issue": ""}


func _build_run_summary(systems: Dictionary, chain: Dictionary) -> String:
	var git: Dictionary = _get_git_info()
	var failures: Array[String] = []
	var warnings: Array[String] = []

	for system_name: String in systems:
		var entry: Dictionary = systems[system_name]

		if String(entry["result"]) == "FAIL":
			failures.append("%s — %s" % [system_name, entry["issue"]])
		elif String(entry["result"]) == "WARN":
			warnings.append("%s — %s" % [system_name, entry["issue"]])

	var overall: String = "PASS"

	if not failures.is_empty():
		overall = "FAIL"
	elif not warnings.is_empty():
		overall = "WARN"

	var lines: PackedStringArray = []
	lines.append("# Diagnostic Run")
	lines.append("")
	lines.append("## Version")
	lines.append("")
	lines.append("Date: %s" % Time.get_date_string_from_system())
	lines.append("Time: %s" % Time.get_time_string_from_system())
	lines.append("Git branch: %s" % git["branch"])
	lines.append("Git commit: %s" % git["commit"])
	lines.append("Git short commit: %s" % git["short"])
	lines.append("Game version: %s" % game_version)
	lines.append("Diagnostic run ID: %s" % _timestamp_folder())
	lines.append("")
	lines.append("## Test")
	lines.append("")
	lines.append("Test purpose: %s" % (
		test_purpose if not test_purpose.is_empty() else "(not set)"
	))
	lines.append("Duration: %s" % _format_duration())
	lines.append("Days: %d" % _get_day_number())
	lines.append("")
	lines.append("## Overall Result")
	lines.append("")
	lines.append(overall)
	lines.append("")
	lines.append("## Systems")
	lines.append("")
	lines.append("| System | Result | Key Issue |")
	lines.append("|---|---|---|")

	for system_name: String in systems:
		lines.append("| %s | %s | %s |" % [
			system_name, systems[system_name]["result"],
			systems[system_name]["issue"],
		])

	lines.append("")
	lines.append("## Critical Failures")
	lines.append("")

	if failures.is_empty():
		lines.append("None.")
	else:
		for i: int in range(failures.size()):
			lines.append("%d. %s" % [i + 1, failures[i]])

	lines.append("")
	lines.append("## Warnings")
	lines.append("")

	if warnings.is_empty():
		lines.append("None.")
	else:
		for i: int in range(warnings.size()):
			lines.append("%d. %s" % [i + 1, warnings[i]])

	lines.append("")
	lines.append("## Key Metrics")
	lines.append("")

	for key: String in _get_key_metrics():
		lines.append("%s: %s" % [key, _get_key_metrics()[key]])

	lines.append("")
	lines.append("## Drink Chain Results")
	lines.append("")

	for drink_id: String in chain:
		var entry: Dictionary = chain[drink_id]
		lines.append("- %-14s %s%s" % [
			drink_id, entry["result"],
			"" if String(entry["result"]) == "PASS"
			else " (breaks at: %s)" % entry["first_failure_name"],
		])

	lines.append("")
	lines.append("## Developer Notes")
	lines.append("")
	lines.append(
		developer_notes if not developer_notes.is_empty() else "(none)"
	)

	if not expected_result.is_empty():
		lines.append("")
		lines.append("Expected: %s" % expected_result)

	lines.append("")

	return "\n".join(lines)


func _build_drinks_report(chain: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("DRINK INTEGRITY REPORT")
	lines.append("Generated %s %s" % [
		Time.get_date_string_from_system(),
		Time.get_time_string_from_system(),
	])
	lines.append("")

	for drink_id: String in chain:
		var entry: Dictionary = chain[drink_id]
		var identities: Dictionary = entry["identities"]
		var steps: Dictionary = entry["steps"]
		var detail: Dictionary = entry["detail"]

		lines.append("=== %s ===" % drink_id.to_upper())
		lines.append("")

		for key: String in identities:
			lines.append("%-22s %s" % [key, identities[key]])

		lines.append("")

		for step: int in ServiceChainValidator.Step.values():
			if not steps.has(step):
				continue

			var passed: bool = bool(steps[step])
			var line: String = "%-30s %s" % [
				ServiceChainValidator.STEP_NAMES[step],
				"PASS" if passed else "FAIL",
			]

			if not passed and detail.has(step):
				line += " — %s" % detail[step]

			lines.append(line)

		lines.append("")
		lines.append("RESULT: %s" % entry["result"])
		lines.append("")

	return "\n".join(lines)


func _build_stock_report() -> String:
	var lines: PackedStringArray = []
	lines.append("STOCK REPORT")
	lines.append("")
	lines.append("PHYSICAL DISPLAY VALIDATION")
	lines.append("")

	# The comparison that separates "inventory did not change" from "inventory
	# changed but the display did not".
	for node: Node in get_tree().get_nodes_in_group(&"stocked_display"):
		var display := node as StockedDisplay

		if display == null or not display.storage_backed:
			continue

		var stored: int = display.get_stored_measures()
		var shown: int = display.get_visible_units()
		var stock_item: ItemDefinition = _find_stock_item_for(display)
		var held: int = (
			0 if stock_item == null
			else display.count_item(stock_item.item_id)
		)
		var capacity: int = display.get_unit_capacity()

		# A prop holding more than it can draw is correct, not broken: the
		# pile shows what fits and the rest is still in storage.
		var expected: int = mini(held, capacity)

		lines.append("Display:              %s" % display.name)
		lines.append("Expected content:     %s" % String(display.content_id))
		lines.append("Stock item:           %s" % (
			"UNRESOLVED" if stock_item == null else String(stock_item.item_id)
		))
		lines.append("Authoritative units:  %d" % held)
		lines.append("Displayed units:      %d" % shown)
		lines.append("Stored measures:      %d" % stored)
		lines.append("Capacity:             %d" % capacity)
		lines.append("Result:               %s" % (
			"FAIL — no stock item declares this content" if stock_item == null
			else "PASS" if expected == shown
			else "FAIL — %d units stored but %d shown" % [expected, shown]
		))
		lines.append("")

	lines.append("STOCK CHANGE EVENTS")
	lines.append("")

	if _stock_events.is_empty():
		lines.append("(none recorded this run)")
	else:
		for event: Dictionary in _stock_events:
			lines.append("%s  %-16s %-24s %+d  %s" % [
				event["time"], event["kind"], event["label"],
				event["change"], event["detail"],
			])

	lines.append("")

	return "\n".join(lines)


## The stock item whose content this display holds.
##
## count_item() keys on the STOCK ITEM id, not the content id - passing the
## content silently returns 0.
func _find_stock_item_for(display: StockedDisplay) -> ItemDefinition:
	var registry: ItemRegistry = load("res://Data/items/item_registry.tres")

	if registry == null:
		return null

	for item: ItemDefinition in registry.definitions:
		if item != null and item.provides_content_id == display.content_id:
			return item

	return null


func _build_staff_report() -> String:
	if staff_report_manager == null:
		return ""

	var lines: PackedStringArray = []
	lines.append("STAFF REPORT")
	lines.append("")

	if staff_report_manager.has_method(&"get_summary_text"):
		lines.append(String(staff_report_manager.call(&"get_summary_text")))
		lines.append("")

	lines.append("NAVIGATION TROUBLE BY DESTINATION")
	lines.append("")

	for node: Node in staff_report_manager.get_staff():
		var staff := node as StaffMember

		if staff == null:
			continue

		var snapshot: Dictionary = staff.get_diagnostics_snapshot()
		lines.append("%s" % staff.staff_id)
		lines.append("  state           %s" % snapshot.get("state", "?"))
		lines.append("  carrying        %s" % snapshot.get("carrying", "nothing"))
		lines.append("  stuck           %s" % snapshot.get("stuck_recoveries", 0))
		lines.append("  nav failures    %s" % snapshot.get("navigation_failures", 0))
		lines.append("  recoveries      %s" % snapshot.get(
			"carried_item_recoveries", 0
		))

		var trouble: Dictionary = snapshot.get(
			"navigation_trouble_by_destination", {}
		)

		for destination: String in trouble:
			lines.append("    %-30s stuck %d, failed %d" % [
				destination,
				int(trouble[destination].get("stuck", 0)),
				int(trouble[destination].get("failed", 0)),
			])

		lines.append("")

	return "\n".join(lines)


func _build_customer_report() -> String:
	if customer_ai_report_manager == null:
		return ""

	var lines: PackedStringArray = []
	lines.append("CUSTOMER REPORT")
	lines.append("")

	for key: String in _get_key_metrics():
		lines.append("%-24s %s" % [key, _get_key_metrics()[key]])

	# Everything below was already being computed by
	# CustomerAIReportManager and then discarded - the committed report
	# carried seven summary lines while every behavioural number lived only
	# in the uncommitted JSON export. That made a committed run unable to
	# answer "are customers lingering, socialising and re-ordering", which
	# is the whole question Phase A is trying to move.
	var summary: Dictionary = customer_ai_report_manager.get_summary()
	var solo: Dictionary = customer_ai_report_manager.get_solo_summary()
	var groups: Dictionary = customer_ai_report_manager.get_group_summary()

	lines.append("")
	lines.append("VISIT OUTCOMES")
	lines.append("")
	lines.append("  active at report time   %s" % summary.get(
		"active_visits_at_report_time", 0
	))
	lines.append("  game minutes elapsed    %s" % summary.get(
		"game_time_duration_minutes", 0
	))
	lines.append("  peak active customers   %s" % summary.get(
		"maximum_active_customers_observed", 0
	))
	lines.append("")
	lines.append("  DEPARTURE REASON")

	# total_forced_departures is a SUPERSET, not a sibling category:
	# record_departure() increments it for patience_expired and
	# visit_time_expired as well as for everything that is not
	# utility_decision. Printing the four side by side double-counts and
	# makes "forced" look like a huge separate failure mode. Only
	# utility_decision is the customer actually choosing, so the useful
	# split is: chose / ran out of time / ran out of patience / everything
	# else forced.
	var forced_total: int = int(summary.get("total_forced_departures", 0))
	var by_patience: int = int(summary.get("total_patience_departures", 0))
	var by_visit_time: int = int(summary.get("total_visit_time_departures", 0))
	var by_choice: int = int(summary.get(
		"total_normal_utility_departures", 0
	))
	var other_forced: int = maxi(
		0, forced_total - by_patience - by_visit_time
	)

	lines.append("    chose to leave        %s" % by_choice)
	lines.append("    visit time ended      %s" % by_visit_time)
	lines.append("    out of patience       %s" % by_patience)
	lines.append("    other forced          %s" % other_forced)
	lines.append("      (out of money, tavern closing, group departure)")
	lines.append("    ---")
	lines.append("    not a free choice     %s  (the three above)" % forced_total)

	lines.append("")
	lines.append("LINGERING AND ACTIVITY")
	lines.append("")
	lines.append("  relax activities        %s" % summary.get(
		"total_relax_activities", 0
	))
	lines.append("  socialise activities    %s" % summary.get(
		"total_socialise_activities", 0
	))
	lines.append("  tavern activities       %s" % summary.get(
		"total_tavern_activities", 0
	))
	lines.append("  failed activity starts  %s" % summary.get(
		"total_failed_activity_starts", 0
	))
	lines.append("  reservation failures    %s" % summary.get(
		"total_activity_reservation_failures", 0
	))
	lines.append("  return-to-seat failures %s" % summary.get(
		"total_return_to_seat_failures", 0
	))

	lines.append("")
	lines.append("SOLO CUSTOMERS")
	lines.append("")
	lines.append("  completed visits        %s" % solo.get(
		"completed_visits", 0
	))
	lines.append("  drinks ordered          %s" % solo.get(
		"drinks_ordered", 0
	))
	lines.append("  drinks served           %s" % solo.get("drinks_served", 0))
	lines.append("  service rate            %s%%" % solo.get(
		"service_rate_percent", 0.0
	))
	lines.append("  patience departures     %s (%s%%)" % [
		solo.get("patience_departures", 0),
		solo.get("patience_departure_rate_percent", 0.0),
	])

	lines.append("")
	lines.append("GROUPS")
	lines.append("")
	lines.append("  total groups            %s" % groups.get(
		"total_groups", 0
	))
	lines.append("  successful              %s (%s%%)" % [
		groups.get("successful_groups", 0),
		groups.get("success_rate_percent", 0.0),
	])
	lines.append("  without drinks          %s" % groups.get(
		"groups_without_drinks", 0
	))
	lines.append("  with activities         %s (%s%%)" % [
		groups.get("groups_with_activities", 0),
		groups.get("activity_participation_rate_percent", 0.0),
	])
	lines.append("  members                 %s" % groups.get(
		"group_members", 0
	))
	lines.append("  members who drank       %s (%s%%)" % [
		groups.get("members_who_drank", 0),
		groups.get("member_drink_rate_percent", 0.0),
	])
	lines.append("  slot recoveries         %s (%s per group)" % [
		groups.get("slot_recoveries", 0),
		groups.get("recoveries_per_group", 0.0),
	])

	# Cancellation REASONS, not just the count. A bare "19 cancelled" reads
	# as 19 failures; the reasons are what say whether it was churn or lost
	# service, and TaskBoard has tallied them all along without printing.
	var task_board: Node = get_node_or_null("/root/TaskBoard")
	if task_board != null and task_board.has_method(
		"get_cancellation_reason_counts"
	):
		var reasons: Dictionary = task_board.get_cancellation_reason_counts()
		lines.append("")
		lines.append("TASK CANCELLATION REASONS")
		lines.append("")

		if reasons.is_empty():
			lines.append("  (none recorded)")
		else:
			var reason_keys: Array = reasons.keys()
			reason_keys.sort_custom(
				func(a: Variant, b: Variant) -> bool:
					return int(reasons[a]) > int(reasons[b])
			)

			for reason_key: Variant in reason_keys:
				lines.append("  %-30s %s" % [
					reason_key, reasons[reason_key]
				])

	lines.append("")
	lines.append(
		"Full per-visit detail remains in the JSON export "
		+ "(Export Customer AI Report)."
	)
	lines.append("")

	return "\n".join(lines)


func _build_system_diagnostics() -> String:
	var lines: PackedStringArray = []
	lines.append("SYSTEM DIAGNOSTICS")
	lines.append("")
	lines.append("NAVIGATION SCAN")
	lines.append("")

	var problems: Array[Dictionary] = (
		NavigationValidator.find_unreachable_points(get_tree())
	)

	if problems.is_empty():
		lines.append("All seats, slots and props are approachable.")
	else:
		for problem: Dictionary in problems:
			lines.append("FAIL %-24s %-30s %.1fpx" % [
				problem["kind"], problem["node_path"],
				problem["off_mesh_distance"],
			])

	lines.append("")
	lines.append("STATION CONFIGURATION")
	lines.append("")

	var items: ItemRegistry = load("res://Data/items/item_registry.tres")
	var beverages: BeverageRegistry = (
		ServiceChainValidator._find_beverage_registry(get_tree())
	)

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station := node as DrinksStation
		var plan: StationStockPlan = StationStockPlan.for_station(
			station, beverages, items
		)
		lines.append("%-22s %s" % [station.name, plan.describe()])

	lines.append("")

	return "\n".join(lines)


# --- Helpers -----------------------------------------------------------------

func _get_key_metrics() -> Dictionary:
	var metrics: Dictionary = {}

	if (
		customer_ai_report_manager != null
		and customer_ai_report_manager.has_method(&"get_summary")
	):
		var summary: Dictionary = customer_ai_report_manager.call(&"get_summary")

		for key: String in [
			"customers_spawned", "completed_visits",
			"total_drinks_ordered", "total_drinks_consumed",
		]:
			if summary.has(key):
				metrics[key] = summary[key]

	if staff_report_manager != null and staff_report_manager.has_method(&"get_summary"):
		var staff_summary: Dictionary = staff_report_manager.call(&"get_summary")

		for key: String in ["tasks_created", "tasks_completed", "tasks_cancelled"]:
			if staff_summary.has(key):
				metrics[key] = staff_summary[key]

	if metrics.is_empty():
		metrics["(no metrics available)"] = ""

	return metrics


func _get_day_number() -> int:
	var world_time: Node = get_node_or_null(^"/root/WorldTime")

	if world_time == null or not world_time.has_method(&"get_day"):
		return 0

	return int(world_time.call(&"get_day"))


func _format_duration() -> String:
	var seconds: int = int(Time.get_unix_time_from_system() - _run_started_unix)

	return "%d min %d sec" % [seconds / 60, seconds % 60]


func _timestamp_folder() -> String:
	var now: Dictionary = Time.get_datetime_dict_from_system()

	return "%04d-%02d-%02d-%02d%02d" % [
		now["year"], now["month"], now["day"], now["hour"], now["minute"],
	]


func _write_readme() -> void:
	var path: String = "%s/README.md" % DEBUG_DIRECTORY

	if FileAccess.file_exists(path):
		return

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		return

	file.store_string(
		"# Debug Reports\n\n"
		+ "## latest\n\n"
		+ "The most recent exported diagnostic run. Always inspect this first.\n"
		+ "It is overwritten on every export and never mixes two runs.\n\n"
		+ "## archive\n\n"
		+ "Historical runs, one folder per export, named `YYYY-MM-DD-HHMM`.\n"
		+ "Use these to compare regressions between commits.\n\n"
		+ "## Recommended review order\n\n"
		+ "1. `RUN_SUMMARY.md` — overall result and which systems failed\n"
		+ "2. `drinks_report.txt` — the full service chain per drink\n"
		+ "3. `stock_report.txt` — authoritative vs displayed quantities\n"
		+ "4. `staff_report.txt` — tasks and navigation trouble by destination\n"
		+ "5. `customer_report.txt` — service outcomes\n"
		+ "6. `system_diagnostics.txt` — navigation scan and station config\n\n"
		+ "## How to export a run\n\n"
		+ "Press F10 in a debug build and choose **Export Diagnostic Run**.\n"
		+ "This refreshes `latest/` and writes an archive folder.\n\n"
		+ "## Git\n\n"
		+ "Every `RUN_SUMMARY.md` records the branch and commit that produced\n"
		+ "it, read from `.git` directly — Git does not need to be installed\n"
		+ "for the game to run. If the commit reads `unknown`, the run was\n"
		+ "made outside a Git checkout.\n\n"
		+ "These reports are intended to be committed.\n"
	)
	file.close()
