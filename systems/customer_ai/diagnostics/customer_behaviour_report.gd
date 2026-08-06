class_name CustomerBehaviourReport
extends RefCounted

## Run-level aggregates for balancing customer behaviour.
##
## The existing [CustomerAIReportManager] records what each individual
## customer did. This answers the different question the brief asks: across a
## whole run, does the crowd look varied? Per-customer records cannot show
## that - "this sailor relaxed twice" is unremarkable until you notice every
## sailor relaxed twice.
##
## [b]The three metrics that matter[/b] are
## [code]repeat_action_percentage[/code],
## [code]most_common_sequence_percentage[/code] and
## [code]average_distinct_activities_per_visit[/code]. Those are the direct
## measurements of "do customers look scripted", and they are the numbers to
## watch when tuning selection_band, cooldowns or intent offsets. The rest is
## context for reading them.
##
## Fed by [CustomerBehaviourEvents], so nothing needs to call into this from
## gameplay code - see [method attach].


## customer_id -> per-visit accumulator.
var _visits: Dictionary = {}

## Ordered activity ids per customer, for sequence analysis.
var _sequences: Dictionary = {}

var _decisions_with_no_action: int = 0
var _fallback_selections: int = 0
var _errors: Array[String] = []
var _warnings: Array[String] = []

var _attached: bool = false


## Subscribes to the behaviour event bus. Idempotent - calling twice does
## not double-count, which matters because a test harness and the developer
## menu may both want a report alive at once.
func attach() -> void:
	if _attached:
		return

	_attached = true

	CustomerBehaviourEvents.customer_identity_initialized.connect(
		_on_identity_initialised
	)
	CustomerBehaviourEvents.customer_visit_intention_selected.connect(
		_on_intention_selected
	)
	CustomerBehaviourEvents.customer_action_selected.connect(
		_on_action_selected
	)
	CustomerBehaviourEvents.customer_decision_evaluated.connect(
		_on_decision_evaluated
	)
	CustomerBehaviourEvents.customer_reordered.connect(_on_reordered)
	CustomerBehaviourEvents.customer_departed.connect(_on_departed)
	CustomerBehaviourEvents.customer_social_interaction_started.connect(
		_on_social_started
	)


func detach() -> void:
	if not _attached:
		return

	_attached = false

	for connection: Dictionary in [
		{"signal": CustomerBehaviourEvents.customer_identity_initialized,
		 "method": _on_identity_initialised},
		{"signal": CustomerBehaviourEvents.customer_visit_intention_selected,
		 "method": _on_intention_selected},
		{"signal": CustomerBehaviourEvents.customer_action_selected,
		 "method": _on_action_selected},
		{"signal": CustomerBehaviourEvents.customer_decision_evaluated,
		 "method": _on_decision_evaluated},
		{"signal": CustomerBehaviourEvents.customer_reordered,
		 "method": _on_reordered},
		{"signal": CustomerBehaviourEvents.customer_departed,
		 "method": _on_departed},
		{"signal": CustomerBehaviourEvents.customer_social_interaction_started,
		 "method": _on_social_started},
	]:
		var target: Signal = connection["signal"]

		if target.is_connected(connection["method"]):
			target.disconnect(connection["method"])


func clear() -> void:
	_visits.clear()
	_sequences.clear()
	_decisions_with_no_action = 0
	_fallback_selections = 0
	_errors.clear()
	_warnings.clear()


func record_error(message: String) -> void:
	_errors.append(message)


func record_warning(message: String) -> void:
	_warnings.append(message)


## Notes a customer left in a state they should not have been in. Surfaced
## as [code]customers_stuck_in_invalid_states[/code].
func record_stuck(customer_id: int, state_name: String) -> void:
	var visit: Dictionary = _ensure_visit(customer_id)

	visit["stuck"] = true
	visit["stuck_state"] = state_name


func record_group_failure(group_id: String, reason: String) -> void:
	_warnings.append(
		"group coordination failure in '%s': %s" % [group_id, reason]
	)


func _ensure_visit(customer_id: int) -> Dictionary:
	if not _visits.has(customer_id):
		_visits[customer_id] = {
			"customer_id": customer_id,
			"type_id": "",
			"intent_id": "",
			"activities": {},
			"activity_count": 0,
			"repeat_count": 0,
			"reorders": 0,
			"social_interactions": 0,
			"visit_duration_minutes": 0.0,
			"drinks_consumed": 0,
			"departure_reason": "",
			"stuck": false,
			"stuck_state": "",
		}

		_sequences[customer_id] = []

	return _visits[customer_id]


func _on_identity_initialised(payload: Dictionary) -> void:
	var visit: Dictionary = _ensure_visit(int(payload.get("customer_id", -1)))

	visit["type_id"] = String(payload.get("customer_type_id", ""))


func _on_intention_selected(payload: Dictionary) -> void:
	var visit: Dictionary = _ensure_visit(int(payload.get("customer_id", -1)))

	visit["intent_id"] = String(payload.get("visit_intent_id", ""))


func _on_action_selected(payload: Dictionary) -> void:
	var customer_id: int = int(payload.get("customer_id", -1))
	var visit: Dictionary = _ensure_visit(customer_id)
	var activity_id: String = String(payload.get("activity_id", ""))

	if activity_id.is_empty():
		return

	var sequence: Array = _sequences[customer_id]

	# A repeat is the same activity selected twice in a row - the specific
	# thing cooldowns and the selection band exist to suppress.
	if not sequence.is_empty() and sequence[sequence.size() - 1] == activity_id:
		visit["repeat_count"] = int(visit["repeat_count"]) + 1

	sequence.append(activity_id)

	var activities: Dictionary = visit["activities"]

	activities[activity_id] = int(activities.get(activity_id, 0)) + 1
	visit["activity_count"] = int(visit["activity_count"]) + 1


func _on_decision_evaluated(payload: Dictionary) -> void:
	if String(payload.get("selected_activity_id", "")).is_empty():
		_decisions_with_no_action += 1


func _on_reordered(payload: Dictionary) -> void:
	var visit: Dictionary = _ensure_visit(int(payload.get("customer_id", -1)))

	visit["reorders"] = int(visit["reorders"]) + 1


func _on_social_started(payload: Dictionary) -> void:
	var visit: Dictionary = _ensure_visit(int(payload.get("customer_id", -1)))

	visit["social_interactions"] = int(visit["social_interactions"]) + 1


func _on_departed(payload: Dictionary) -> void:
	var visit: Dictionary = _ensure_visit(int(payload.get("customer_id", -1)))

	visit["visit_duration_minutes"] = float(
		payload.get("visit_duration_minutes", 0.0)
	)
	visit["drinks_consumed"] = int(payload.get("drinks_consumed", 0))
	visit["departure_reason"] = String(payload.get("reason", ""))


## The full aggregate report. Shaped as plain Dictionaries and Arrays so it
## drops straight into the existing JSON exporter without conversion.
func build_report() -> Dictionary:
	var by_type: Dictionary = {}
	var intent_distribution: Dictionary = {}
	var activity_frequency_by_type: Dictionary = {}

	var total_visits: int = _visits.size()
	var total_repeat_visits: int = 0
	var total_distinct: int = 0
	var voluntary_departures: int = 0
	var patience_departures: int = 0
	var stuck_customers: int = 0
	var total_reorders: int = 0

	for customer_id: int in _visits:
		var visit: Dictionary = _visits[customer_id]
		var type_id: String = String(visit["type_id"])

		if type_id.is_empty():
			type_id = "unknown"

		if not by_type.has(type_id):
			by_type[type_id] = {
				"count": 0,
				"total_visit_minutes": 0.0,
				"total_drinks": 0,
				"total_distinct_activities": 0,
				"total_reorders": 0,
			}

		var bucket: Dictionary = by_type[type_id]
		var activities: Dictionary = visit["activities"]

		bucket["count"] = int(bucket["count"]) + 1
		bucket["total_visit_minutes"] = (
			float(bucket["total_visit_minutes"])
			+ float(visit["visit_duration_minutes"])
		)
		bucket["total_drinks"] = (
			int(bucket["total_drinks"]) + int(visit["drinks_consumed"])
		)
		bucket["total_distinct_activities"] = (
			int(bucket["total_distinct_activities"]) + activities.size()
		)
		bucket["total_reorders"] = (
			int(bucket["total_reorders"]) + int(visit["reorders"])
		)

		total_distinct += activities.size()
		total_reorders += int(visit["reorders"])

		if int(visit["repeat_count"]) > 0:
			total_repeat_visits += 1

		if bool(visit["stuck"]):
			stuck_customers += 1

		var reason: String = String(visit["departure_reason"])

		if reason == "patience" or reason == "patience_expired":
			patience_departures += 1
		elif not reason.is_empty():
			voluntary_departures += 1

		var intent_id: String = String(visit["intent_id"])

		if intent_id.is_empty():
			intent_id = "none"

		intent_distribution[intent_id] = int(
			intent_distribution.get(intent_id, 0)
		) + 1

		if not activity_frequency_by_type.has(type_id):
			activity_frequency_by_type[type_id] = {}

		var frequency: Dictionary = activity_frequency_by_type[type_id]

		for activity_id: String in activities:
			frequency[activity_id] = int(
				frequency.get(activity_id, 0)
			) + int(activities[activity_id])

	var per_type: Dictionary = {}

	for type_id: String in by_type:
		var bucket: Dictionary = by_type[type_id]
		var count: float = maxf(1.0, float(bucket["count"]))

		per_type[type_id] = {
			"customers": bucket["count"],
			"average_visit_minutes": float(
				bucket["total_visit_minutes"]
			) / count,
			"average_drinks": float(bucket["total_drinks"]) / count,
			"average_distinct_activities": float(
				bucket["total_distinct_activities"]
			) / count,
			"reorder_rate": float(bucket["total_reorders"]) / count,
		}

	var safe_total: float = maxf(1.0, float(total_visits))

	return {
		"total_customers": total_visits,
		"customers_by_type": per_type,
		"intention_distribution": intent_distribution,
		"activity_frequency_by_type": activity_frequency_by_type,
		"average_distinct_activities_per_visit": (
			float(total_distinct) / safe_total
		),
		"repeat_action_percentage": (
			float(total_repeat_visits) / safe_total
		) * 100.0,
		"most_common_sequence_percentage": _most_common_sequence_percentage(),
		"most_common_sequence": _most_common_sequence(),
		"reorder_rate": float(total_reorders) / safe_total,
		"voluntary_departure_rate": (
			float(voluntary_departures) / safe_total
		) * 100.0,
		"patience_departure_rate": (
			float(patience_departures) / safe_total
		) * 100.0,
		"customers_stuck_in_invalid_states": stuck_customers,
		"decisions_with_no_valid_action": _decisions_with_no_action,
		"fallback_action_usage": _fallback_selections,
		"errors": _errors.duplicate(),
		"warnings": _warnings.duplicate(),
	}


## Percentage of visits that followed the single most common activity
## sequence. High means customers are still walking one script - this is the
## headline number for "does the crowd look varied".
func _most_common_sequence_percentage() -> float:
	if _sequences.is_empty():
		return 0.0

	var counts: Dictionary = _sequence_counts()
	var highest: int = 0

	for key: String in counts:
		highest = maxi(highest, int(counts[key]))

	return (float(highest) / float(_sequences.size())) * 100.0


func _most_common_sequence() -> String:
	var counts: Dictionary = _sequence_counts()
	var highest: int = 0
	var best: String = ""

	for key: String in counts:
		if int(counts[key]) > highest:
			highest = int(counts[key])
			best = key

	return best


func _sequence_counts() -> Dictionary:
	var counts: Dictionary = {}

	for customer_id: int in _sequences:
		var sequence: Array = _sequences[customer_id]

		if sequence.is_empty():
			continue

		var key: String = " -> ".join(sequence)

		counts[key] = int(counts.get(key, 0)) + 1

	return counts


## Human-readable summary for the console and the developer menu.
func format_summary() -> String:
	var report: Dictionary = build_report()
	var lines: Array[String] = []

	lines.append("=== Customer Behaviour Report ===")
	lines.append("Customers: %d" % report["total_customers"])
	lines.append(
		"Distinct activities per visit: %.2f"
		% report["average_distinct_activities_per_visit"]
	)
	lines.append(
		"Visits with an immediate repeat: %.1f%%"
		% report["repeat_action_percentage"]
	)
	lines.append(
		"Following the most common sequence: %.1f%%"
		% report["most_common_sequence_percentage"]
	)
	lines.append("Most common sequence: %s" % report["most_common_sequence"])
	lines.append("")
	lines.append("By type:")

	for type_id: String in report["customers_by_type"]:
		var stats: Dictionary = report["customers_by_type"][type_id]

		lines.append(
			"  %-16s n=%-4d visit %.1fm  drinks %.2f  distinct %.2f"
			% [
				type_id, stats["customers"],
				stats["average_visit_minutes"], stats["average_drinks"],
				stats["average_distinct_activities"],
			]
		)

	lines.append("")
	lines.append("Intentions:")

	for intent_id: String in report["intention_distribution"]:
		lines.append(
			"  %-22s %d" % [intent_id, report["intention_distribution"][intent_id]]
		)

	if int(report["customers_stuck_in_invalid_states"]) > 0:
		lines.append(
			"WARNING: %d customers stuck in invalid states"
			% report["customers_stuck_in_invalid_states"]
		)

	return "\n".join(lines)


## Writes the report to [param path] as JSON. Returns true on success.
func export_json(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		push_warning(
			"CustomerBehaviourReport could not write to '%s'." % path
		)
		return false

	file.store_string(JSON.stringify(build_report(), "\t"))
	file.close()

	return true
