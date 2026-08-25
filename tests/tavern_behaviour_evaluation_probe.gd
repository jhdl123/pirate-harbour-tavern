extends Node

## Read-only behavioural evaluation instrument. Does not test pass/fail -
## produces the raw material for a human (or an agent) to judge "do these
## customers behave like plausible tavern visitors", per this session's
## evaluation request. No customer_ai/gameplay code is touched by this
## file; it only reads data CustomerAIReportManager (VisitRecord,
## DecisionRecord) already records, plus a light periodic sample of live
## customers' CustomerNeeds.visit_purpose (not otherwise captured in either
## record) and CustomerBrain.get_current_activity() for a time-in-activity
## trace independent of decision timestamps.
##
## Same run shape as phase_b_measurement_probe.tscn (proven to produce a
## 70-100 completed-visit population at this length) - reused rather than
## re-derived.

const RUN_SECONDS: float = 420.0
const SAMPLE_SECONDS: float = 2.0
const SPAWN_UNTIL: float = 360.0

var samples: int = 0

## runtime_customer_id -> String, last live-sampled CustomerNeeds.visit_purpose.
var _visit_purpose_by_customer: Dictionary = {}

## runtime_customer_id -> Array[Dictionary] {"t": float, "activity_id": String},
## one entry per sample tick where the current activity changed - an
## independent cross-check on DecisionRecord's own timestamps.
var _activity_trace_by_customer: Dictionary = {}
var _last_seen_activity_by_customer: Dictionary = {}


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

	for customer: Node in get_tree().get_nodes_in_group(&"navigation_customers"):
		if not is_instance_valid(customer):
			continue

		var runtime_id: Variant = customer.get("runtime_customer_id")

		if runtime_id == null:
			continue

		var needs: Object = customer.get("needs")

		if needs != null:
			_visit_purpose_by_customer[runtime_id] = String(
				needs.get("visit_purpose")
			)

		var brain: Object = customer.get("_brain")

		if brain == null:
			continue

		var current: Object = brain.call("get_current_activity")
		var activity_id: String = (
			String(current.get("activity_id")) if current != null else ""
		)

		if _last_seen_activity_by_customer.get(runtime_id, "") != activity_id:
			_last_seen_activity_by_customer[runtime_id] = activity_id

			if not _activity_trace_by_customer.has(runtime_id):
				_activity_trace_by_customer[runtime_id] = []

			_activity_trace_by_customer[runtime_id].append({
				"t": WorldTime.get_total_minutes(),
				"activity_id": activity_id,
			})


func _report(main: Node) -> void:
	var report_manager: Object = main.get_node_or_null(
		^"Managers/CustomerAIReportManager"
	)

	print("")
	print("=== TAVERN BEHAVIOUR EVALUATION PROBE ===")
	print("samples=", samples, "  run_seconds=", RUN_SECONDS)

	if report_manager == null:
		print("no CustomerAIReportManager found - stopping here")
		print("=== END TAVERN BEHAVIOUR EVALUATION PROBE ===")
		return

	var completed: Array = report_manager.get("_completed_visit_records")

	if completed == null:
		completed = []

	var decisions_by_customer: Dictionary = report_manager.get(
		"_decisions_by_customer"
	)

	if decisions_by_customer == null:
		decisions_by_customer = {}

	print("")
	print("AGGREGATE (context only - see individual histories for the real answer)")
	print("  completed visits: ", completed.size())
	print("  distinct customer ids with decision history: ", decisions_by_customer.size())

	var summary: Dictionary = report_manager.call("get_summary")
	print("  peak active customers: ", summary.get("maximum_active_customers_observed", "?"))

	# Longest decision sequences first - the same "read complete visits, not
	# fragments" principle every prior pass in this session used.
	var customer_ids: Array = decisions_by_customer.keys()
	customer_ids.sort_custom(
		func(a, b) -> bool:
			return (
				decisions_by_customer[a].size()
				> decisions_by_customer[b].size()
			)
	)

	var visit_by_customer: Dictionary = {}
	for record: Object in completed:
		visit_by_customer[int(record.get("customer_id"))] = record

	var sample_size: int = mini(25, customer_ids.size())

	print("")
	print(
		"=== ", sample_size,
		" COMPLETE CUSTOMER HISTORIES (by decision count, richest first) ==="
	)

	for i: int in range(sample_size):
		_print_customer_history(int(customer_ids[i]), decisions_by_customer, visit_by_customer)

	print("=== END TAVERN BEHAVIOUR EVALUATION PROBE ===")


func _print_customer_history(
	customer_id: int,
	decisions_by_customer: Dictionary,
	visit_by_customer: Dictionary
) -> void:
	var decisions: Array = decisions_by_customer[customer_id]
	var visit: Object = visit_by_customer.get(customer_id)

	print("")
	print("################################################################")
	print("customer ", customer_id)

	if visit != null:
		print(
			"  type=", visit.get("customer_type_name"),
			"  personality=", visit.get("personality_name"),
			"  group=", (
				visit.get("group_id") if not String(visit.get("group_id")).is_empty()
				else "solo"
			)
		)
		print(
			"  visit purpose (last sampled): ",
			_visit_purpose_by_customer.get(customer_id, "unknown")
		)
		print(
			"  spawned t=", visit.get("spawn_game_time_minutes"),
			"  reached_inside t=", visit.get("reached_inside_at_minutes"),
			"  seated t=", visit.get("seated_at_minutes"),
			"  first_order t=", visit.get("first_order_at_minutes")
		)
		print(
			"  starting: money=£", visit.get("starting_money"),
			" thirst=", "%.0f%%" % (float(visit.get("starting_thirst")) * 100.0),
			" satisfaction=", "%.0f%%" % (float(visit.get("starting_satisfaction")) * 100.0)
		)
		print(
			"  ending:   money=£", visit.get("ending_money"),
			" thirst=", "%.0f%%" % (float(visit.get("ending_thirst")) * 100.0),
			" satisfaction=", "%.0f%%" % (float(visit.get("ending_satisfaction")) * 100.0),
			" intoxication=", "%.0f%%" % (float(visit.get("final_intoxication")) * 100.0)
		)
		print(
			"  departed: ", visit.get("departure_reason"),
			"  after ", "%.1f" % visit.call("get_visit_duration_minutes"), " min"
		)
		print(
			"  activity counts: relax=", visit.get("relax_count"),
			" socialise=", visit.get("socialise_count"),
			" darts=", visit.get("darts_count"),
			" drinks_consumed=", visit.get("drinks_consumed")
		)
		var reservation_failures: int = int(visit.get("activity_reservation_failures"))
		var return_failures: int = int(visit.get("return_to_seat_failures"))
		var nav_failures: int = int(visit.get("navigation_failures"))
		var activity_failures: int = int(visit.get("activity_failures"))
		if reservation_failures + return_failures + nav_failures + activity_failures > 0:
			print(
				"  FAILURES: reservation=", reservation_failures,
				" return_to_seat=", return_failures,
				" navigation=", nav_failures,
				" activity=", activity_failures
			)
		var state_trail: Array = visit.get("state_trail")
		if state_trail != null and not state_trail.is_empty():
			print("  state trail: ", " -> ".join(state_trail))
	else:
		print("  (no completed VisitRecord - visit still active at report time)")

	print("  --- decision timeline (", decisions.size(), " decisions) ---")

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

		var awareness_note: String = ""
		for breakdown: Dictionary in decision.utility_contributions:
			var aware: float = float(breakdown.get("awareness_contribution", 0.0))
			if aware > 0.01:
				awareness_note += "%s:awareness=+%.2f " % [
					breakdown.get("activity_id", "?"), aware
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
		print(
			(
				"          needs: thirst=%.2f social=%.2f entertainment=%.2f"
				+ " relaxation=%.2f mood=%.2f intox=%.2f money=£%d"
			) % [
				decision.thirst, decision.social, decision.entertainment,
				decision.relaxation, decision.satisfaction,
				decision.intoxication, decision.money,
			]
		)

		if not candidate_summary.is_empty():
			print("          candidates: ", candidate_summary)

		if not awareness_note.is_empty():
			print("          ", awareness_note)

	var trace: Array = _activity_trace_by_customer.get(customer_id, [])
	if not trace.is_empty():
		var trace_text: String = ""
		for entry: Dictionary in trace:
			trace_text += "t=%.0f:%s  " % [
				entry["t"],
				entry["activity_id"] if not String(entry["activity_id"]).is_empty()
					else "<none>",
			]
		print("  --- sampled activity trace (independent of decisions above) ---")
		print("  ", trace_text)
