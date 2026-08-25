extends Node

## Stage 4 measurement instrument for
## docs/history/2026-08-25_CUSTOMER_ARCHITECTURE_AUDIT.md's implementation
## pass - produces the before/after table PHASE_B_BRIEF.md asks for.
##
## Two techniques, combined in one run: periodic occupancy sampling (the
## same method darts_score_probe.gd already uses for "occupies X% of
## customer time") for activity-time-share numbers, and a real diagnostic
## export plus direct VisitRecord inspection (the same records the JSON
## export is built from) for visit-length/departure/service/group numbers
## and the "did no activity at all" count, which no existing report line
## already answers.

const RUN_SECONDS: float = 420.0
const SAMPLE_SECONDS: float = 2.0
const SPAWN_UNTIL: float = 360.0

var samples: int = 0
var occupancy_tally: Dictionary = {}
var no_activity_tally: int = 0


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

	var exporter: Node = main.get_node_or_null(
		^"Managers/DiagnosticRunExporter"
	)

	if exporter != null:
		exporter.test_purpose = "Phase B Stage 4 measurement"
		exporter.developer_notes = (
			"docs/history/2026-08-25_CUSTOMER_ARCHITECTURE_AUDIT.md Stage 4"
		)
		exporter.export_run()
		await get_tree().process_frame

	_report(main)
	get_tree().quit()


func _sample() -> void:
	samples += 1

	for customer: Node in get_tree().get_nodes_in_group(&"navigation_customers"):
		if not is_instance_valid(customer):
			continue

		var brain: Object = customer.get("_brain")

		if brain == null:
			continue

		var current: Object = brain.call("get_current_activity")
		var aid: StringName = (
			current.get("activity_id") if current != null else &"<none>"
		)

		occupancy_tally[aid] = int(occupancy_tally.get(aid, 0)) + 1


func _report(main: Node) -> void:
	print("")
	print("=== PHASE B MEASUREMENT PROBE ===")
	print("samples=", samples, "  run_seconds=", RUN_SECONDS)
	print("")
	print("ACTIVITY TIME SHARE (fraction of samples any customer was in)")

	var total: int = 0
	for v: int in occupancy_tally.values():
		total += v

	for k: StringName in occupancy_tally:
		var n: int = int(occupancy_tally[k])
		print(
			"  ", k, ": ", n, "  (",
			"%.1f%%" % (100.0 * float(n) / float(maxi(total, 1))), ")"
		)

	var report_manager: Object = main.get_node_or_null(
		^"Managers/CustomerAIReportManager"
	)

	if report_manager == null:
		print("")
		print("no CustomerAIReportManager found - stopping here")
		print("=== END PHASE B MEASUREMENT PROBE ===")
		return

	var completed: Array = report_manager.get("_completed_visit_records")

	if completed == null:
		completed = []

	print("")
	print("VISITS")
	print("  completed visits: ", completed.size())

	var chose_to_leave: int = 0
	var visit_time_ended: int = 0
	var out_of_patience: int = 0
	var other_forced: int = 0
	var lengths: Array[float] = []
	var solo_completed: int = 0
	var solo_drinks_ordered: int = 0
	var solo_drinks_served: int = 0
	var group_completed: int = 0
	var group_ids: Dictionary = {}
	var group_with_activity: int = 0
	var no_activity: int = 0
	var total_activity_starts: int = 0
	var order_drink_time_samples: int = 0

	for record: Object in completed:
		var reason: String = String(record.get("departure_reason"))

		match reason:
			"utility_decision":
				chose_to_leave += 1
			"visit_time_expired":
				visit_time_ended += 1
			"patience_expired", "repeated_neglect":
				out_of_patience += 1
			_:
				other_forced += 1

		lengths.append(float(record.call("get_visit_duration_minutes")))

		var group_id: String = String(record.get("group_id"))

		if group_id.is_empty():
			solo_completed += 1
			solo_drinks_ordered += int(record.get("drinks_ordered"))
			solo_drinks_served += int(record.get("drinks_served"))
		else:
			group_completed += 1
			group_ids[group_id] = true

			var g_relax: int = int(record.get("relax_count"))
			var g_social: int = int(record.get("socialise_count"))
			var g_tavern: int = int(record.get("tavern_activity_count"))

			if g_relax > 0 or g_social > 0 or g_tavern > 0:
				group_with_activity += 1

		var relax_n: int = int(record.get("relax_count"))
		var social_n: int = int(record.get("socialise_count"))
		var tavern_n: int = int(record.get("tavern_activity_count"))

		if relax_n == 0 and social_n == 0 and tavern_n == 0:
			no_activity += 1

		total_activity_starts += relax_n + social_n + tavern_n

	print(
		"  departure - chose to leave: ", chose_to_leave,
		"  visit time ended: ", visit_time_ended,
		"  out of patience: ", out_of_patience,
		"  other forced: ", other_forced
	)

	lengths.sort()

	if not lengths.is_empty():
		var mid: int = lengths.size() / 2
		var median: float = (
			lengths[mid] if lengths.size() % 2 == 1
			else (lengths[mid - 1] + lengths[mid]) / 2.0
		)
		print(
			"  realised visit length - median: ", "%.1f" % median,
			"  max: ", "%.1f" % lengths[lengths.size() - 1]
		)

	print("")
	print("SOLO")
	print("  completed: ", solo_completed)

	if solo_drinks_ordered > 0:
		print(
			"  service rate (served/ordered): ",
			"%.1f%%" % (
				100.0 * float(solo_drinks_served)
				/ float(solo_drinks_ordered)
			)
		)

	print("")
	print("GROUPS")
	print("  distinct groups: ", group_ids.size())
	print("  member-visits completed: ", group_completed)

	if group_completed > 0:
		print(
			"  group activity participation: ",
			"%.1f%%" % (
				100.0 * float(group_with_activity) / float(group_completed)
			)
		)

	print("")
	print("NO ACTIVITY AT ALL (relax + socialise + tavern all zero)")
	print(
		"  ", no_activity, " / ", completed.size(),
		"  (", (
			"%.1f%%" % (
				100.0 * float(no_activity) / float(maxi(completed.size(), 1))
			)
		), ")"
	)

	print("")
	print("ACTIVITY STARTS PER CUSTOMER (relax + socialise + tavern, mean)")
	print(
		"  ", total_activity_starts, " starts / ", completed.size(),
		" completed visits  =  ",
		"%.2f" % (
			float(total_activity_starts) / float(maxi(completed.size(), 1))
		),
		" per customer"
	)

	_report_individual_histories(report_manager, completed)

	print("=== END PHASE B MEASUREMENT PROBE ===")


## Several COMPLETE customer histories, not just aggregates - the item-10
## ask ("customers look like people spending time there... rather than
## agents completing enter -> drink -> leave") cannot be judged from a
## table. Reuses CustomerAIReportManager's existing per-decision records
## (_decisions_by_customer, already populated every run - see
## record_decision()'s doc comment) rather than adding a second tracking
## mechanism; this is exactly the needs -> motivation -> candidates ->
## selected -> execution -> resulting need change -> next decision trace
## CUSTOMER_INSPECTOR.md's diagnostics requirement asks for, read from
## history instead of live.
func _report_individual_histories(
	report_manager: Object, completed: Array
) -> void:
	var decisions_by_customer: Dictionary = report_manager.get(
		"_decisions_by_customer"
	)

	if decisions_by_customer == null or decisions_by_customer.is_empty():
		return

	# Longest decision sequences first - a customer who left after one
	# decision has no story to read; the point is to inspect a full visit.
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

	print("")
	print("=== INDIVIDUAL CUSTOMER HISTORIES (top 20 by decision count) ===")

	for i: int in range(mini(20, customer_ids.size())):
		var customer_id: int = int(customer_ids[i])
		var decisions: Array = decisions_by_customer[customer_id]
		var visit: Object = visit_by_customer.get(customer_id)

		print("")
		print(
			"--- customer ", customer_id, " (", decisions.size(),
			" decisions)",
			(
				"  departed: %s after %.1f min" % [
					String(visit.get("departure_reason")),
					visit.call("get_visit_duration_minutes"),
				]
			) if visit != null else "  (visit still active at report time)"
		)

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
			print(
				(
					"          needs: thirst=%.2f social=%.2f"
					+ " entertainment=%.2f relaxation=%.2f mood=%.2f"
					+ " intox=%.2f money=£%d"
				) % [
					decision.thirst, decision.social, decision.entertainment,
					decision.relaxation, decision.satisfaction,
					decision.intoxication, decision.money,
				]
			)

			if not candidate_summary.is_empty():
				print("          candidates: ", candidate_summary)

	print("=== END INDIVIDUAL CUSTOMER HISTORIES ===")
