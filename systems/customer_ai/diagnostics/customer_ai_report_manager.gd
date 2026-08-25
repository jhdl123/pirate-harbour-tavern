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
var _total_shared_drinks_consumed: int = 0
var _total_group_slot_recoveries: int = 0
var _total_group_payments: int = 0
var _total_group_payment_amount: int = 0
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
	# Findable by group so a customer can resolve it before being configured.
	add_to_group(&"customer_ai_report_manager")

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

	# Seed the trail immediately. A customer enters its first state before the
	# report manager is attached to it, so without this the trail would start
	# empty and a customer that never moved would look like one that was never
	# recorded at all.
	record.note_state("SPAWNED", record.spawn_game_time_minutes)

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


## Records a state change for [param customer_id].
##
## The backbone of the lifecycle trace. Called from the customer's own state
## machine, so the report shows exactly where a stuck visit stopped.
func record_state(
	customer_id: int,
	state_name: String,
	world_minutes: float
) -> void:
	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record == null:
		return

	record.note_state(state_name, world_minutes)


func record_reached_inside(customer_id: int, world_minutes: float) -> void:
	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.note_reached_inside(world_minutes)


func record_seated(customer_id: int, world_minutes: float) -> void:
	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.note_seated(world_minutes)


func record_first_order(customer_id: int, world_minutes: float) -> void:
	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.note_first_order(world_minutes)


## Records where a customer is and what it is walking toward.
##
## Refreshed on demand rather than every frame - the exporter calls it when a
## report is generated, so a live position costs nothing during play.
func record_position(
	customer_id: int,
	position: Vector2,
	door_position: Vector2,
	target_position: Vector2,
	target_label: String
) -> void:
	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record == null:
		return

	record.last_position = position
	record.distance_from_door = position.distance_to(door_position)
	record.navigation_target_label = target_label
	record.distance_from_target = (
		position.distance_to(target_position)
		if target_position != Vector2.ZERO else -1.0
	)


func record_navigation_failure(customer_id: int) -> void:
	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.navigation_failures += 1


func record_activity_failure(customer_id: int) -> void:
	_total_failed_activity_starts += 1

	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.activity_failures += 1


func record_navigation_recovery(customer_id: int) -> void:
	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.navigation_recovery_count += 1


# --- Group visits ------------------------------------------------------------

## Notes which group this customer joined.
func record_group_context(customer_id: int, group_id: String) -> void:
	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.group_id = group_id


## Notes the owning group's state, normally at departure.
func record_group_state(customer_id: int, group_state: String) -> void:
	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null and not group_state.is_empty():
		record.group_state = group_state


## One portion taken from a shared serving.
##
## Counted apart from record_drink_consumed() so a report can tell keg
## drinking from individually ordered drinks.
func record_shared_drink(customer_id: int) -> void:
	_total_shared_drinks_consumed += 1

	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.shared_drinks_consumed += 1


## The one payment a group makes for its shared keg, on the member who paid.
func record_group_payment(
	customer_id: int,
	group_id: String,
	item_id: String,
	serving_format_id: String,
	amount: int
) -> void:
	_total_group_payments += 1
	_total_group_payment_amount += amount

	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record == null:
		return

	record.group_payment_made = true
	record.group_payment_amount += amount
	record.group_keg_item_id = item_id
	record.group_serving_format_id = serving_format_id

	if record.group_id.is_empty():
		record.group_id = group_id


## One bounded recovery of a member onto its group formation slot.
func record_group_slot_recovery(customer_id: int) -> void:
	_total_group_slot_recoveries += 1

	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.group_slot_recoveries += 1


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


func record_motivational_needs(
	customer_id: int,
	current_social: float,
	current_entertainment: float,
	current_relaxation: float
) -> void:
	var record: VisitRecord = _active_visit_records.get(customer_id)

	if record != null:
		record.maximum_social_reached = maxf(
			record.maximum_social_reached, current_social
		)
		record.maximum_entertainment_reached = maxf(
			record.maximum_entertainment_reached, current_entertainment
		)
		record.maximum_relaxation_reached = maxf(
			record.maximum_relaxation_reached, current_relaxation
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
		&"patience_expired", &"repeated_neglect":
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
	record.patience_expired = (
		reason == &"patience_expired" or reason == &"repeated_neglect"
	)
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


## The run's headline numbers, without writing a file.
##
## Exposed so DiagnosticRunExporter can put real metrics in RUN_SUMMARY.md
## while the JSON export stays the full record. Both read the same builder, so
## the two can never disagree.
func get_summary() -> Dictionary:
	return _build_report_dictionary().get("summary", {})


## Group outcomes for the run.
func get_group_summary() -> Dictionary:
	var balance: Dictionary = _build_report_dictionary().get(
		"balance_summary", {}
	)

	return balance.get("groups", {})


## Solo customer outcomes for the run.
func get_solo_summary() -> Dictionary:
	var balance: Dictionary = _build_report_dictionary().get(
		"balance_summary", {}
	)

	return balance.get("solo", {})


## Realised visit lengths in game minutes, split by how the visit ended.
##
## The distinction that matters is realised vs rolled. A customer rolls an
## intended visit duration at spawn, and those are healthily varied - roughly
## 15 to 110 minutes. What the player actually sees is how long people STAYED,
## which is a different distribution: a visit cut short by impatience never
## reaches its rolled length, so a room can read as constant churn while the
## intended durations look perfectly well spread.
##
## Splitting by outcome is what makes the two separable. "Stayed their time"
## lengths say whether the intended spread is right; "gave up" lengths say how
## much of the churn is service rather than design.
func get_visit_duration_stats() -> Dictionary:
	var completed: Array[float] = []
	var gave_up: Array[float] = []
	var ran_full: Array[float] = []

	for record: VisitRecord in _completed_visit_records:
		if record.departure_game_time_minutes < 0.0:
			continue

		var duration: float = (
			record.departure_game_time_minutes
			- record.spawn_game_time_minutes
		)

		if duration < 0.0:
			continue

		completed.append(duration)

		if record.patience_expired:
			gave_up.append(duration)
		else:
			ran_full.append(duration)

	return {
		"all": _summarise_durations(completed),
		"gave_up": _summarise_durations(gave_up),
		"stayed": _summarise_durations(ran_full),
	}


func _summarise_durations(
	durations: Array[float]
) -> Dictionary:
	if durations.is_empty():
		return {"count": 0, "min": 0.0, "max": 0.0, "mean": 0.0, "median": 0.0}

	var sorted: Array[float] = durations.duplicate()
	sorted.sort()

	var total: float = 0.0
	for value: float in sorted:
		total += value

	return {
		"count": sorted.size(),
		"min": snappedf(sorted[0], 0.1),
		"max": snappedf(sorted[sorted.size() - 1], 0.1),
		"mean": snappedf(total / float(sorted.size()), 0.1),
		"median": snappedf(sorted[sorted.size() / 2], 0.1),
	}


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


## Asks every live customer where it is, just before a report is written.
func _refresh_active_positions() -> void:
	var door_position: Vector2 = Vector2.ZERO

	for node: Node in get_tree().get_nodes_in_group(&"customer_door"):
		var door: Node2D = node as Node2D

		if door != null:
			door_position = door.global_position
			break

	for node: Node in get_tree().get_nodes_in_group(&"navigation_customers"):
		if node.has_method(&"report_position_to"):
			node.call(&"report_position_to", self, door_position)


func _build_report_dictionary() -> Dictionary:
	var now_unix: float = Time.get_unix_time_from_system()
	var now_game_minutes: float = WorldTime.get_total_minutes()

	var completed_dicts: Array = []

	for record: VisitRecord in _completed_visit_records:
		completed_dicts.append(record.to_dictionary())

	# Refresh live positions before exporting. Done here rather than every
	# frame so a live position costs nothing during normal play.
	_refresh_active_positions()

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

	var balance_summary: Dictionary = _build_balance_summary(
		completed_dicts, active_dicts
	)

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
			"total_shared_drinks_consumed": _total_shared_drinks_consumed,
			"total_group_slot_recoveries": _total_group_slot_recoveries,
			"total_group_payments": _total_group_payments,
			"total_group_payment_amount": _total_group_payment_amount,
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
		"balance_summary": balance_summary,
		"group_runs": balance_summary.get("group_runs", []),
		"completed_visits": completed_dicts,
		"active_visits": active_dicts,
		"decisions_by_customer_id": decisions_dict,
		"issues": issue_dicts,
	}


## Compact derived metrics intended for balancing and first-pass debugging.
##
## This is calculated only when a report is exported, so it adds no per-frame
## simulation cost. The raw visit records remain authoritative; these values
## are a quick index into them rather than a replacement for them.
func _build_balance_summary(
	completed_visits: Array,
	active_visits: Array
) -> Dictionary:
	var solo_visits: int = 0
	var solo_orders: int = 0
	var solo_served: int = 0
	var solo_patience_departures: int = 0
	var groups: Dictionary = {}

	for raw_visit: Variant in completed_visits:
		if not raw_visit is Dictionary:
			continue

		var visit: Dictionary = raw_visit
		var group_id: String = String(visit.get("group_id", ""))

		if group_id.is_empty():
			solo_visits += 1
			solo_orders += int(visit.get("drinks_ordered", 0))
			solo_served += int(visit.get("drinks_served", 0))

			var solo_departure_reason: String = String(
				visit.get("departure_reason", "")
			)

			if (
				solo_departure_reason == "patience_expired"
				or solo_departure_reason == "repeated_neglect"
			):
				solo_patience_departures += 1

			continue

		if not groups.has(group_id):
			groups[group_id] = {
				"group_id": group_id,
				"member_count": 0,
				"members_who_drank": 0,
				"shared_drinks_consumed": 0,
				"payment_made": false,
				"payment_amount": 0,
				"payer_customer_id": -1,
				"keg_item_id": "",
				"serving_format_id": "",
				"relax_count": 0,
				"socialise_count": 0,
				"darts_count": 0,
				"tavern_activity_count": 0,
				"slot_recoveries": 0,
				"maximum_visit_duration_minutes": 0.0,
				"completed_departures": 0,
			}

		var group: Dictionary = groups[group_id]
		var shared_drinks: int = int(visit.get("shared_drinks_consumed", 0))

		group["member_count"] = int(group["member_count"]) + 1
		group["shared_drinks_consumed"] = (
			int(group["shared_drinks_consumed"]) + shared_drinks
		)

		if shared_drinks > 0:
			group["members_who_drank"] = int(group["members_who_drank"]) + 1

		group["relax_count"] = (
			int(group["relax_count"]) + int(visit.get("relax_count", 0))
		)
		group["socialise_count"] = (
			int(group["socialise_count"]) + int(visit.get("socialise_count", 0))
		)
		group["darts_count"] = (
			int(group["darts_count"]) + int(visit.get("darts_count", 0))
		)
		group["tavern_activity_count"] = (
			int(group["tavern_activity_count"])
			+ int(visit.get("tavern_activity_count", 0))
		)
		group["slot_recoveries"] = (
			int(group["slot_recoveries"])
			+ int(visit.get("group_slot_recoveries", 0))
		)
		group["maximum_visit_duration_minutes"] = maxf(
			float(group["maximum_visit_duration_minutes"]),
			float(visit.get("visit_duration_minutes", 0.0))
		)

		if String(visit.get("departure_reason", "")) == "group_departure":
			group["completed_departures"] = (
				int(group["completed_departures"]) + 1
			)

		if bool(visit.get("group_payment_made", false)):
			group["payment_made"] = true
			group["payment_amount"] = int(visit.get("group_payment_amount", 0))
			group["payer_customer_id"] = int(visit.get("customer_id", -1))
			group["keg_item_id"] = String(visit.get("group_keg_item_id", ""))
			group["serving_format_id"] = String(
				visit.get("group_serving_format_id", "")
			)

		groups[group_id] = group

	var group_runs: Array[Dictionary] = []
	var successful_groups: int = 0
	var groups_without_drinks: int = 0
	var groups_with_payment: int = 0
	var groups_with_activities: int = 0
	var group_members: int = 0
	var group_members_who_drank: int = 0
	var group_slot_recoveries: int = 0

	for group_id: String in groups:
		var group: Dictionary = groups[group_id]
		var member_count: int = int(group["member_count"])
		var drank_count: int = int(group["members_who_drank"])
		var activity_count: int = (
			int(group["relax_count"])
			+ int(group["socialise_count"])
			+ int(group["darts_count"])
			+ int(group["tavern_activity_count"])
		)

		group["all_members_departed"] = (
			int(group["completed_departures"]) == member_count
		)
		group["all_members_drank"] = (drank_count == member_count)
		group["activity_count"] = activity_count
		group["result"] = (
			"served" if int(group["shared_drinks_consumed"]) > 0
			else "no_keg_or_no_drinks"
		)

		if int(group["shared_drinks_consumed"]) > 0:
			successful_groups += 1
		else:
			groups_without_drinks += 1

		if bool(group["payment_made"]):
			groups_with_payment += 1

		if activity_count > 0:
			groups_with_activities += 1

		group_members += member_count
		group_members_who_drank += drank_count
		group_slot_recoveries += int(group["slot_recoveries"])
		group_runs.append(group)

	group_runs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["group_id"]) < String(b["group_id"])
	)

	var solo_service_rate: float = (
		(float(solo_served) / float(solo_orders)) * 100.0
		if solo_orders > 0 else 0.0
	)
	var solo_patience_rate: float = (
		(float(solo_patience_departures) / float(solo_visits)) * 100.0
		if solo_visits > 0 else 0.0
	)
	var group_success_rate: float = (
		(float(successful_groups) / float(groups.size())) * 100.0
		if not groups.is_empty() else 0.0
	)
	var group_activity_rate: float = (
		(float(groups_with_activities) / float(groups.size())) * 100.0
		if not groups.is_empty() else 0.0
	)
	var group_drinker_rate: float = (
		(float(group_members_who_drank) / float(group_members)) * 100.0
		if group_members > 0 else 0.0
	)

	return {
		"solo": {
			"completed_visits": solo_visits,
			"drinks_ordered": solo_orders,
			"drinks_served": solo_served,
			"service_rate_percent": snappedf(solo_service_rate, 0.1),
			"patience_departures": solo_patience_departures,
			"patience_departure_rate_percent": snappedf(
				solo_patience_rate, 0.1
			),
		},
		"groups": {
			"total_groups": groups.size(),
			"successful_groups": successful_groups,
			"groups_without_drinks": groups_without_drinks,
			"success_rate_percent": snappedf(group_success_rate, 0.1),
			"groups_with_payment": groups_with_payment,
			"groups_with_activities": groups_with_activities,
			"activity_participation_rate_percent": snappedf(
				group_activity_rate, 0.1
			),
			"group_members": group_members,
			"members_who_drank": group_members_who_drank,
			"member_drink_rate_percent": snappedf(
				group_drinker_rate, 0.1
			),
			"slot_recoveries": group_slot_recoveries,
			"recoveries_per_group": snappedf(
				float(group_slot_recoveries) / maxf(float(groups.size()), 1.0),
				0.1
			),
		},
		"active_visits_at_export": active_visits.size(),
		"group_runs": group_runs,
	}
