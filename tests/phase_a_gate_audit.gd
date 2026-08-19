extends Node

## Phase A audit: WHY activities are not chosen, not just how often.
##
## Drives main.tscn, then on every sample builds a real ActivityContext from
## each live customer's own brain and evaluates every registered activity's
## conditions INDIVIDUALLY, recording which condition gated it. A tally of
## "order_drink blocked 400 times, 390 of them by under_drink_limit" is the
## answer a behaviour-mix percentage cannot give.
##
## Static reading has given the wrong answer on this project repeatedly; this
## measures the live gates instead.

const SAMPLE_SECONDS: float = 1.0
const RUN_SECONDS: float = 180.0
const SPAWN_UNTIL: float = 120.0

## activity_id -> { "eligible": int, "blocked": int, "by": { reason: count } }
var gates: Dictionary = {}
## activity_id -> times it was the customer's CURRENT activity on a sample
var occupancy: Dictionary = {}
var state_tally: Dictionary = {}
var samples: int = 0
var customers_seen: Dictionary = {}
var drinks_by_customer: Dictionary = {}
var remaining_buckets: Dictionary = {}
var visit_total_by_customer: Dictionary = {}
var clock_state: Dictionary = {}
var unstarted_by_state: Dictionary = {}


func _ready() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	for _i: int in range(10):
		await get_tree().process_frame

	for node: Node in get_tree().get_nodes_in_group(&"navigation_debugger"):
		node.set(&"enabled", false)

	var debugger: Node = main.get_node_or_null(^"NavigationDebugger")

	if debugger != null:
		debugger.set(&"enabled", false)

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

	_report()
	get_tree().quit()


func _sample() -> void:
	samples += 1

	for customer: Node in get_tree().get_nodes_in_group(&"navigation_customers"):
		if not is_instance_valid(customer):
			continue

		var brain: Object = customer.get("_brain")

		if brain == null:
			continue

		customers_seen[customer.get_instance_id()] = true

		var state_name: String = _state_name(customer)
		state_tally[state_name] = int(state_tally.get(state_name, 0)) + 1

		var needs: Object = brain.get("needs")

		if needs != null:
			drinks_by_customer[customer.get_instance_id()] = customer.get(
				"drinks_consumed_this_visit"
			)

			var remaining: float = float(needs.get("remaining_visit_minutes"))
			var total: float = float(needs.get("visit_duration_minutes"))

			visit_total_by_customer[customer.get_instance_id()] = total

			var bucket: String = "0-2"

			if remaining >= 30.0:
				bucket = "30+"
			elif remaining >= 16.0:
				bucket = "16-30"
			elif remaining >= 8.0:
				bucket = "8-16"
			elif remaining >= 2.0:
				bucket = "2-8"

			remaining_buckets[bucket] = int(
				remaining_buckets.get(bucket, 0)
			) + 1

			# "Never started" and "expired" are indistinguishable in
			# remaining_visit_minutes alone - both read 0.0. Split them.
			var started: float = float(
				needs.get("_visit_started_at_minutes")
			)
			var key: String = (
				"clock_started" if started > 0.0 else "CLOCK_NEVER_STARTED"
			)
			clock_state[key] = int(clock_state.get(key, 0)) + 1

			if started <= 0.0:
				var sn: String = _state_name(customer)
				unstarted_by_state[sn] = int(
					unstarted_by_state.get(sn, 0)
				) + 1

		var current: Object = brain.call("get_current_activity")

		if current != null:
			var cid: StringName = current.get("activity_id")
			occupancy[cid] = int(occupancy.get(cid, 0)) + 1

		var registry: Object = brain.get("registry")

		if registry == null:
			continue

		var context: Object = brain.call("_build_context")

		if context == null:
			continue

		for definition: Object in registry.get("definitions"):
			if definition == null:
				continue

			_evaluate(definition, context)


func _evaluate(definition: Object, context: Object) -> void:
	var activity_id: StringName = definition.get("activity_id")

	if not gates.has(activity_id):
		gates[activity_id] = {
			"eligible": 0,
			"blocked": 0,
			"by": {},
		}

	var record: Dictionary = gates[activity_id]

	context.activity = definition

	var blockers: Array[String] = []

	for condition: Object in definition.get("conditions"):
		if condition == null:
			continue

		if not condition.call("is_satisfied", context):
			blockers.append(_condition_label(condition, context))

	if blockers.is_empty():
		record["eligible"] = int(record["eligible"]) + 1
		return

	record["blocked"] = int(record["blocked"]) + 1

	var by: Dictionary = record["by"]

	for blocker: String in blockers:
		by[blocker] = int(by.get(blocker, 0)) + 1


func _condition_label(condition: Object, context: Object) -> String:
	# Prefer the resource filename - two DomainFlagConditions on different
	# flags are otherwise indistinguishable, which is exactly the detail
	# this probe exists to surface.
	var path: String = String(condition.get("resource_path"))

	if not path.is_empty():
		return path.get_file().get_basename()

	return String(condition.call("get_rejection_reason", context))


func _state_name(customer: Node) -> String:
	var value: Variant = customer.get("current_state")

	if value == null:
		return "unknown"

	return str(value)


func _report() -> void:
	print("")
	print("=== PHASE A GATE AUDIT ===")
	print("samples=", samples, " customers_seen=", customers_seen.size())
	print("")

	print("--- ACTIVITY ELIGIBILITY (per customer-sample) ---")

	var ids: Array = gates.keys()
	ids.sort()

	for activity_id: StringName in ids:
		var record: Dictionary = gates[activity_id]
		var eligible: int = int(record["eligible"])
		var blocked: int = int(record["blocked"])
		var total: int = eligible + blocked
		var pct: float = 0.0

		if total > 0:
			pct = 100.0 * float(eligible) / float(total)

		print("")
		print(
			"  ", String(activity_id),
			"  eligible=", eligible,
			"  blocked=", blocked,
			"  (", "%.1f" % pct, "%% eligible)"
		)

		var by: Dictionary = record["by"]
		var reasons: Array = by.keys()

		reasons.sort_custom(
			func(a: Variant, b: Variant) -> bool:
				return int(by[a]) > int(by[b])
		)

		for reason: String in reasons:
			print("      blocked by ", reason, ": ", int(by[reason]))

	print("")
	print("--- TIME SPENT IN ACTIVITY (per customer-sample) ---")

	var occ_ids: Array = occupancy.keys()
	occ_ids.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			return int(occupancy[a]) > int(occupancy[b])
	)

	for activity_id: StringName in occ_ids:
		print("  ", String(activity_id), ": ", int(occupancy[activity_id]))

	print("")
	print("--- STATE OCCUPANCY ---")

	var st: Array = state_tally.keys()
	st.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			return int(state_tally[a]) > int(state_tally[b])
	)

	for state_name: String in st:
		print("  state ", state_name, ": ", int(state_tally[state_name]))

	print("")
	print("--- DRINKS PER CUSTOMER (last observed) ---")

	var histogram: Dictionary = {}

	for key: int in drinks_by_customer:
		var count: Variant = drinks_by_customer[key]

		if count == null:
			continue

		var bucket: int = int(count)
		histogram[bucket] = int(histogram.get(bucket, 0)) + 1

	var buckets: Array = histogram.keys()
	buckets.sort()

	for bucket: int in buckets:
		print("  ", bucket, " drinks: ", int(histogram[bucket]), " customers")

	print("")
	print("--- REMAINING VISIT MINUTES (per customer-sample) ---")

	for bucket: String in ["30+", "16-30", "8-16", "2-8", "0-2"]:
		print(
			"  ", bucket, " min left: ",
			int(remaining_buckets.get(bucket, 0))
		)

	print("")
	print("--- ROLLED VISIT DURATION (per customer) ---")

	var totals: Array = visit_total_by_customer.values()

	if not totals.is_empty():
		var sum_total: float = 0.0
		var lowest: float = totals[0]
		var highest: float = totals[0]

		for value: float in totals:
			sum_total += value
			lowest = minf(lowest, value)
			highest = maxf(highest, value)

		print(
			"  min=", "%.1f" % lowest,
			"  max=", "%.1f" % highest,
			"  mean=", "%.1f" % (sum_total / float(totals.size()))
		)

	print("")
	print("--- VISIT CLOCK STARTED? ---")

	for key: String in clock_state:
		print("  ", key, ": ", int(clock_state[key]))

	print("")
	print("--- SAMPLES WITH NO CLOCK, BY STATE ---")

	var us: Array = unstarted_by_state.keys()
	us.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			return int(unstarted_by_state[a]) > int(unstarted_by_state[b])
	)

	for sn: String in us:
		print("  state ", sn, ": ", int(unstarted_by_state[sn]))

	print("")
	print("=== END GATE AUDIT ===")
