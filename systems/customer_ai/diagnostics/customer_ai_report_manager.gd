class_name CustomerAIReportManager
extends Node

## Collects Customer AI diagnostics for one play session and writes them to
## a single JSON file on request.
##
## Every public method here is safe to call whether or not reporting is
## enabled - each does the minimum bookkeeping needed for the session
## summary's simple counters unconditionally (spawned count, max active,
## departure-reason totals), and only builds the heavier per-visit/
## per-decision records when [member diagnostics_config].export_enabled is
## on. Normal gameplay never depends on any of this; see
## docs/CUSTOMER_AI_SYSTEM.md's "Diagnostic report architecture" section.


@export var diagnostics_config: CustomerAIDiagnosticsConfig

const REPORT_FORMAT_VERSION: int = 1
const PHASE_IDENTIFIER: String = "Phase 2B"
const REPORT_DIRECTORY: String = "user://customer_ai_reports/"


var _session_start_unix: float = 0.0
var _session_start_game_minutes: float = 0.0

## customer_id -> VisitRecord, only while that visit is still active.
var _active_visit_records: Dictionary = {}
var _completed_visit_records: Array[VisitRecord] = []

## customer_id -> Array[DecisionRecord]
var _decisions_by_customer: Dictionary = {}

var _issues: Array[IssueRecord] = []

var _next_customer_id: int = 1
var _customers_spawned: int = 0
var _active_customer_ids: Dictionary = {}
var _max_active_customers_observed: int = 0

var _total_drinks_ordered: int = 0
var _total_drinks_served: int = 0
var _total_drinks_consumed: int = 0
var _total_payments: int = 0
var _total_relax_activities: int = 0
var _total_patience_departures: int = 0
var _total_visit_time_departures: int = 0
var _total_normal_departures: int = 0
var _total_forced_departures: int = 0
var _total_failed_activity_starts: int = 0

## Phase 2C
var _total_socialise_activities: int = 0
var _total_tavern_activities: int = 0
var _total_activity_reservation_failures: int = 0
var _total_return_to_seat_failures: int = 0

var _visits_truncated: bool = false
var _decisions_truncated: bool = false


func _ready() -> void:
	_session_start_unix = Time.get_unix_time_from_system()
	_session_start_game_minutes = WorldTime.get_total_minutes()


func is_export_enabled() -> bool:
	return diagnostics_config != null and diagnostics_config.export_enabled


func is_console_debug_enabled() -> bool:
	return diagnostics_config != null and diagnostics_config.console_debug_enabled


## Call once per spawned customer to get a stable id for this session -
## never reused, independent of the customer's engine instance ID.
func allocate_customer_id() -> int:
	var allocated_id: int = _next_customer_id
	_next_customer_id += 1

	return allocated_id


func register_spawn(
	customer_id: int,
	customer_type_name: String,
	personality_name: String,
	starting_money: int,
	starting_thirst: float,
	starting_satisfaction: float
) -> void:
	_customers_spawned += 1
	_active_customer_ids[customer_id] = true

	_max_active_customers_observed = maxi(
		_max_active_customers_observed,
		_active_customer_ids.size()
	)

	if not is_export_enabled():
		return

	var record := VisitRecord.new()
	record.customer_id = customer_id
	record.customer_type_name = customer_type_name
	record.personality_name = personality_name
	record.spawn_game_time_minutes = WorldTime.get_total_minutes()
	record.starting_money = starting_money
	record.ending_money = starting_money
	record.starting_thirst = starting_thirst
	record.ending_thirst = starting_thirst
	record.starting_satisfaction = starting_satisfaction
	record.ending_satisfaction = starting_satisfaction

	_active_visit_records[customer_id] = record


func record_order(customer_id: int) -> void:
	_total_drinks_ordered += 1

	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.drinks_ordered += 1


func record_serve(customer_id: int) -> void:
	_total_drinks_served += 1

	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.drinks_served += 1


func record_payment(customer_id: int) -> void:
	_total_payments += 1

	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.payments_made += 1


func record_drink_consumed(
	customer_id: int,
	ending_money: int,
	ending_thirst: float,
	ending_satisfaction: float,
	intoxication: float
) -> void:
	_total_drinks_consumed += 1

	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record == null:
		return

	record.drinks_consumed += 1
	record.ending_money = ending_money
	record.ending_thirst = ending_thirst
	record.ending_satisfaction = ending_satisfaction
	record.final_intoxication = intoxication


func record_relax(customer_id: int) -> void:
	_total_relax_activities += 1

	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.relax_count += 1


## [param chair_id] is a stable label (e.g. the Chair node's name), not an
## instance ID, so it stays meaningful after the visit ends.
func record_chair(customer_id: int, chair_id: String) -> void:
	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record == null:
		return

	if record.chair_id == "":
		record.chair_id = chair_id
	elif record.chair_id != chair_id:
		record.kept_same_chair_for_visit = false


func record_activity_failure(customer_id: int) -> void:
	_total_failed_activity_starts += 1

	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.activity_failures += 1


func record_navigation_recovery(customer_id: int) -> void:
	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.navigation_recovery_count += 1


## Recent-activity history length is fixed rather than configurable - it
## exists purely so a report reader can see a short recent sequence, not
## as a tunable balancing value.
const RECENT_ACTIVITY_HISTORY_LENGTH: int = 6


func record_socialise(customer_id: int, partner_customer_id: int) -> void:
	_total_socialise_activities += 1

	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record == null:
		return

	record.socialise_count += 1
	record.social_partner_ids.append(partner_customer_id)
	record.note_activity_entered(
		"socialise_at_seat", RECENT_ACTIVITY_HISTORY_LENGTH
	)


func record_tavern_activity(customer_id: int, activity_id: String) -> void:
	_total_tavern_activities += 1

	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record == null:
		return

	record.tavern_activity_count += 1

	if activity_id == "darts":
		record.darts_count += 1

	record.note_activity_entered(activity_id, RECENT_ACTIVITY_HISTORY_LENGTH)


func record_activity_reservation_failure(customer_id: int) -> void:
	_total_activity_reservation_failures += 1

	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.activity_reservation_failures += 1


func record_return_to_seat_failure(customer_id: int) -> void:
	_total_return_to_seat_failures += 1

	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.return_to_seat_failures += 1


func record_engagement(customer_id: int, current_engagement: float) -> void:
	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.maximum_engagement_reached = maxf(
			record.maximum_engagement_reached, current_engagement
		)


## A shallow copy of the visit's recent-activity history so far, or an
## empty array if there is no active visit record for this customer (no
## export enabled, or the customer has already departed).
func get_recent_activity_history(customer_id: int) -> Array[String]:
	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record == null:
		return []

	return record.recent_activity_history.duplicate()


func record_departure(
	customer_id: int,
	reason: StringName,
	ending_money: int,
	ending_thirst: float,
	ending_satisfaction: float,
	intoxication: float,
	maximum_drinks_reached: bool
) -> void:
	_active_customer_ids.erase(customer_id)

	match reason:
		&"patience_expired":
			_total_patience_departures += 1
			_total_forced_departures += 1
		&"visit_time_expired":
			_total_visit_time_departures += 1
			_total_forced_departures += 1
		&"utility_decision":
			_total_normal_departures += 1
		_:
			# Any other reason (out_of_money, and any future forced reason)
			# is a forced departure by construction - see
			# CustomerBrain.force_activity()'s doc comment. Only
			# &"utility_decision" (begin_leaving()'s own default when
			# nothing forced it) counts as a normal decision.
			_total_forced_departures += 1

	if not is_export_enabled():
		return

	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record == null:
		return

	record.departure_game_time_minutes = WorldTime.get_total_minutes()
	record.is_completed = true
	record.departure_reason = reason
	record.patience_expired = (reason == &"patience_expired")
	record.visit_time_expired = (reason == &"visit_time_expired")
	record.maximum_drinks_reached = maximum_drinks_reached
	record.ending_money = ending_money
	record.ending_thirst = ending_thirst
	record.ending_satisfaction = ending_satisfaction
	record.final_intoxication = intoxication

	_active_visit_records.erase(customer_id)

	if (
		diagnostics_config != null
		and _completed_visit_records.size()
		>= diagnostics_config.maximum_completed_visits_retained
	):
		_visits_truncated = true
		_completed_visit_records.pop_front()

	_completed_visit_records.append(record)


func record_decision(record: DecisionRecord) -> void:
	if (
		not is_export_enabled()
		or diagnostics_config == null
		or not diagnostics_config.record_decision_history
	):
		return

	if not _decisions_by_customer.has(record.customer_id):
		_decisions_by_customer[record.customer_id] = []

	var decisions: Array = _decisions_by_customer[record.customer_id]

	if decisions.size() >= diagnostics_config.maximum_decisions_per_customer:
		_decisions_truncated = true
		decisions.pop_front()

	decisions.append(record)


## [param state_snapshot] should contain only ordinary serialisable values
## (numbers, strings, bools) - see IssueRecord's doc comment.
func report_issue(
	customer_id: int,
	issue_type: StringName,
	message: String,
	state_snapshot: Dictionary = {}
) -> void:
	if not is_export_enabled():
		return

	var issue := IssueRecord.new()
	issue.customer_id = customer_id
	issue.game_time_minutes = WorldTime.get_total_minutes()
	issue.issue_type = issue_type
	issue.message = message
	issue.state_snapshot = state_snapshot

	_issues.append(issue)


## Writes the full report to user://customer_ai_reports/ and returns the
## path written, or "" on failure. Safe to call even when export is
## disabled - it still writes (manual generation should not silently do
## nothing if a developer explicitly asks for it), but the report will
## simply be mostly empty, since nothing was being recorded. Callable at
## any time, including mid-session; active (not-yet-departed) visits are
## included as incomplete records - see VisitRecord.is_completed.
func finalize_and_write_report() -> String:
	var directory_access: DirAccess = DirAccess.open("user://")

	if directory_access == null:
		push_error("CustomerAIReportManager could not access user://.")
		return ""

	if not directory_access.dir_exists("customer_ai_reports"):
		var make_error: int = directory_access.make_dir_recursive(
			"customer_ai_reports"
		)

		if make_error != OK:
			push_error(
				"CustomerAIReportManager could not create "
				+ REPORT_DIRECTORY
			)

			return ""

	var report: Dictionary = _build_report_dictionary()

	var indent: String = "\t" if (
		diagnostics_config == null or diagnostics_config.pretty_print_json
	) else ""

	var json_text: String = JSON.stringify(report, indent)

	var filename: String = (
		"customer_ai_report_"
		+ _filename_safe_timestamp()
		+ ".json"
	)

	var file: FileAccess = FileAccess.open(
		REPORT_DIRECTORY + filename,
		FileAccess.WRITE
	)

	if file == null:
		push_error(
			"CustomerAIReportManager could not write to "
			+ REPORT_DIRECTORY + filename
		)

		return ""

	file.store_string(json_text)
	file.close()

	return REPORT_DIRECTORY + filename


func _filename_safe_timestamp() -> String:
	var now: Dictionary = Time.get_datetime_dict_from_system()

	return "%04d-%02d-%02d_%02d%02d%02d" % [
		now.year, now.month, now.day,
		now.hour, now.minute, now.second,
	]


func _build_report_dictionary() -> Dictionary:
	var now_unix: float = Time.get_unix_time_from_system()
	var now_game_minutes: float = WorldTime.get_total_minutes()

	var completed_dicts: Array = []

	for record: VisitRecord in _completed_visit_records:
		completed_dicts.append(record.to_dictionary())

	var active_dicts: Array = []

	for record: VisitRecord in _active_visit_records.values():
		active_dicts.append(record.to_dictionary())

	var decisions_dict: Dictionary = {}

	for customer_id: int in _decisions_by_customer:
		var decisions: Array = _decisions_by_customer[customer_id]
		var decision_dicts: Array = []

		for decision: DecisionRecord in decisions:
			decision_dicts.append(decision.to_dictionary())

		decisions_dict[str(customer_id)] = decision_dicts

	var issue_dicts: Array = []

	for issue: IssueRecord in _issues:
		issue_dicts.append(issue.to_dictionary())

	return {
		"summary": {
			"report_format_version": REPORT_FORMAT_VERSION,
			"phase_identifier": PHASE_IDENTIFIER,
			"session_start_unix": _session_start_unix,
			"session_end_unix": now_unix,
			"real_session_duration_seconds": (
				now_unix - _session_start_unix
			),
			"game_time_duration_minutes": (
				now_game_minutes - _session_start_game_minutes
			),
			"maximum_active_customers_observed": (
				_max_active_customers_observed
			),
			"customers_spawned": _customers_spawned,
			"completed_visits": _completed_visit_records.size(),
			"active_visits_at_report_time": _active_visit_records.size(),
			"total_drinks_ordered": _total_drinks_ordered,
			"total_drinks_served": _total_drinks_served,
			"total_drinks_consumed": _total_drinks_consumed,
			"total_payments": _total_payments,
			"total_relax_activities": _total_relax_activities,
			"total_patience_departures": _total_patience_departures,
			"total_visit_time_departures": _total_visit_time_departures,
			"total_normal_utility_departures": _total_normal_departures,
			"total_forced_departures": _total_forced_departures,
			"total_failed_activity_starts": _total_failed_activity_starts,
			"total_socialise_activities": _total_socialise_activities,
			"total_tavern_activities": _total_tavern_activities,
			"total_activity_reservation_failures": (
				_total_activity_reservation_failures
			),
			"total_return_to_seat_failures": _total_return_to_seat_failures,
			"visits_truncated": _visits_truncated,
			"decisions_truncated": _decisions_truncated,
		},
		"completed_visits": completed_dicts,
		"active_visits": active_dicts,
		"decisions_by_customer_id": decisions_dict,
		"issues": issue_dicts,
	}
