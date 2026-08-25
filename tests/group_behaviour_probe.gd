extends Node

## Part 3 of the final diagnostic pass: the prior evaluation's "25 richest
## histories" all happened to be solo customers by chance, leaving group
## behaviour unproven. Same read-only method (VisitRecord/DecisionRecord
## data CustomerAIReportManager already collects), but this time grouped
## by group_id and printed together, so one group's members can be read
## side by side - the only way to judge "bias, not dictate; peel off; come
## back" from a transcript.
##
## No customer_ai/group code touched. group_id is sampled live (like
## tavern_behaviour_evaluation_probe.gd already does for visit_purpose)
## because VisitRecord is only finalised for visits that have already
## completed, and a still-in-progress group member is exactly the case
## most likely to show a mid-visit peel-off.

const RUN_SECONDS: float = 420.0
const SAMPLE_SECONDS: float = 2.0
const SPAWN_UNTIL: float = 360.0

var samples: int = 0

## runtime_customer_id -> String group_id, last live-sampled.
var _group_id_by_customer: Dictionary = {}

## runtime_customer_id -> Array[Dictionary] {"t": float, "state": String},
## every time this customer's current_state changed - independent of
## VisitRecord's own (also available) state_trail, and available even for
## a still-active customer.
var _state_trace_by_customer: Dictionary = {}
var _last_state_by_customer: Dictionary = {}


func _ready() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	for _i: int in range(10):
		await get_tree().process_frame

	for node: Node in get_tree().get_nodes_in_group(&"navigation_debugger"):
		node.set(&"enabled", false)

	var game_manager: Node = main.get_node_or_null(^"Managers/GameManager")

	if not Tavern.is_accepting_arrivals():
		Tavern.open_early()

	var elapsed: float = 0.0

	while elapsed < RUN_SECONDS:
		if (
			game_manager != null
			and game_manager.has_method("spawn_customer")
			and elapsed < SPAWN_UNTIL
		):
			game_manager.call("spawn_customer")

		await get_tree().create_timer(SAMPLE_SECONDS).timeout
		elapsed += SAMPLE_SECONDS
		_sample()

	_report(main)
	get_tree().quit()


func _sample() -> void:
	samples += 1
	var world_minutes: float = WorldTime.get_total_minutes()

	for customer: Node in get_tree().get_nodes_in_group(&"navigation_customers"):
		if not is_instance_valid(customer):
			continue

		var runtime_id: Variant = customer.get("runtime_customer_id")

		if runtime_id == null:
			continue

		var group_id: String = String(customer.get("group_id"))

		if not group_id.is_empty():
			_group_id_by_customer[runtime_id] = group_id

		var state_value: Variant = customer.get("current_state")

		if state_value == null:
			continue

		var state_name: String = (
			Customer.State.keys()[int(state_value)]
			if int(state_value) < Customer.State.keys().size() else "?"
		)

		if _last_state_by_customer.get(runtime_id, "") != state_name:
			_last_state_by_customer[runtime_id] = state_name

			if not _state_trace_by_customer.has(runtime_id):
				_state_trace_by_customer[runtime_id] = []

			_state_trace_by_customer[runtime_id].append({
				"t": world_minutes,
				"state": state_name,
			})


func _report(main: Node) -> void:
	var report_manager: Object = main.get_node_or_null(
		^"Managers/CustomerAIReportManager"
	)

	print("")
	print("=== GROUP BEHAVIOUR PROBE ===")
	print("samples=", samples, "  run_seconds=", RUN_SECONDS)
	print("distinct group ids observed (any member, any point): ", _group_id_by_customer.values().size())

	var groups: Dictionary = {}
	for customer_id: Variant in _group_id_by_customer:
		var gid: String = _group_id_by_customer[customer_id]
		if not groups.has(gid):
			groups[gid] = []
		groups[gid].append(customer_id)

	print("distinct groups: ", groups.size())

	if report_manager == null:
		print("no CustomerAIReportManager found - stopping here")
		print("=== END GROUP BEHAVIOUR PROBE ===")
		return

	var completed: Array = report_manager.get("_completed_visit_records")
	if completed == null:
		completed = []

	var decisions_by_customer: Dictionary = report_manager.get("_decisions_by_customer")
	if decisions_by_customer == null:
		decisions_by_customer = {}

	var visit_by_customer: Dictionary = {}
	for record: Object in completed:
		visit_by_customer[int(record.get("customer_id"))] = record

	# Pick the largest group with at least one member that has real
	# decision history to show - the whole point is reading several
	# members of the SAME group side by side.
	var group_ids_sorted: Array = groups.keys()
	group_ids_sorted.sort_custom(
		func(a, b) -> bool: return groups[a].size() > groups[b].size()
	)

	print("")
	print("group sizes: ")
	for gid: String in group_ids_sorted:
		print("  ", gid, ": ", groups[gid].size(), " members seen")

	var groups_to_print: int = group_ids_sorted.size()

	for g: int in range(groups_to_print):
		var gid: String = group_ids_sorted[g]
		var member_ids: Array = groups[gid]

		print("")
		print("################################################################")
		print("GROUP ", gid, " (", member_ids.size(), " members)")

		for customer_id: Variant in member_ids:
			_print_member_history(
				int(customer_id), decisions_by_customer, visit_by_customer
			)

	print("=== END GROUP BEHAVIOUR PROBE ===")


func _print_member_history(
	customer_id: int,
	decisions_by_customer: Dictionary,
	visit_by_customer: Dictionary
) -> void:
	var decisions: Array = decisions_by_customer.get(customer_id, [])
	var visit: Object = visit_by_customer.get(customer_id)

	print("")
	print("--- member ", customer_id, " ---")

	if visit != null:
		print(
			"  type=", visit.get("customer_type_name"),
			"  personality=", visit.get("personality_name")
		)
		print(
			"  departed: ", visit.get("departure_reason"),
			"  after ", "%.1f" % visit.call("get_visit_duration_minutes"), " min"
		)
		print(
			"  activity counts: relax=", visit.get("relax_count"),
			" socialise=", visit.get("socialise_count"),
			" darts=", visit.get("darts_count")
		)
	else:
		print("  (still active at report time)")

	var trace: Array = _state_trace_by_customer.get(customer_id, [])
	if not trace.is_empty():
		var trace_text: String = ""
		for entry: Dictionary in trace:
			trace_text += "t=%.0f:%s  " % [entry["t"], entry["state"]]
		print("  state trace: ", trace_text)

	if decisions.is_empty():
		print("  (no individual brain decisions recorded)")
		return

	print("  --- decisions (", decisions.size(), ") ---")

	for decision: DecisionRecord in decisions:
		var candidate_summary: String = ""

		for entry: Dictionary in decision.eligible_activities:
			var mark: String = (
				"*" if String(entry.get("activity_id", ""))
					== decision.selected_activity_id
				else ""
			)
			candidate_summary += "%s%s=%.1f " % [
				mark, entry.get("activity_id", ""), entry.get("score", 0.0)
			]

		print(
			"  t=%6.1f  motivation=%-13s selected=%-20s%s"
			% [
				decision.game_time_minutes,
				decision.motivation if not decision.motivation.is_empty()
					else ("forced:" + decision.forced_reason),
				decision.selected_activity_id,
				("  [" + decision.execution_outcome + "]")
					if not decision.execution_outcome.is_empty() else "",
			]
		)

		if not candidate_summary.is_empty():
			print("          candidates: ", candidate_summary)
