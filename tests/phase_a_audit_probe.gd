extends Node

## Phase A audit: WHY do customers not linger?
##
## Counting chosen activities tells you what won. It does not tell you what
## was never a candidate. This probe evaluates every ActivityDefinition's
## conditions INDIVIDUALLY against live customers and tallies which specific
## condition blocked it, which is the only way the darts-at-0% and
## social-chicken-and-egg causes were ever found.

const SAMPLE_SECONDS: float = 1.0
const RUN_SECONDS: float = 180.0
const SPAWN_UNTIL: float = 120.0

var block_tally: Dictionary = {}
var available_tally: Dictionary = {}
var evaluations: Dictionary = {}
var state_tally: Dictionary = {}
var state_samples: int = 0
var drinks_per_customer: Dictionary = {}
var visit_seconds: Dictionary = {}


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
	for customer: Node in get_tree().get_nodes_in_group(&"navigation_customers"):
		_sample_state(customer)

		var brain: Variant = customer.get(&"_brain")

		if brain == null:
			brain = customer.get(&"_brain")

		if brain == null or not is_instance_valid(brain):
			continue

		var registry: Variant = brain.get(&"registry")

		if registry == null:
			continue

		var context: Variant = brain.call(&"_build_context")

		if context == null:
			continue

		for definition: ActivityDefinition in registry.definitions:
			if definition == null:
				continue

			_evaluate(definition, context)


func _sample_state(customer: Node) -> void:
	var state: Variant = customer.get(&"current_state")

	if state == null:
		return

	var key: String = str(state)

	state_tally[key] = int(state_tally.get(key, 0)) + 1
	state_samples += 1

	var id: Variant = customer.get(&"runtime_customer_id")

	if id != null:
		visit_seconds[id] = float(visit_seconds.get(id, 0.0)) + SAMPLE_SECONDS

		var consumed: Variant = customer.get(&"drinks_consumed_this_visit")

		if consumed != null:
			drinks_per_customer[id] = int(consumed)


## The whole point: not "was it chosen" but "which condition said no".
func _evaluate(definition: ActivityDefinition, context: Variant) -> void:
	var id: String = String(definition.activity_id)

	evaluations[id] = int(evaluations.get(id, 0)) + 1
	context.activity = definition

	var blocked_by: String = ""

	for condition: ActivityCondition in definition.conditions:
		if condition == null:
			continue

		if not condition.is_satisfied(context):
			var script_resource: Script = condition.get_script()
			var name: String = "unknown"

			if script_resource != null:
				name = script_resource.get_global_name()

			# The resource path distinguishes two DomainFlagConditions that
			# share a class but gate on different flags.
			var path: String = condition.resource_path.get_file()

			blocked_by = "%s (%s)" % [path, name]
			break

	if blocked_by.is_empty():
		available_tally[id] = int(available_tally.get(id, 0)) + 1
		return

	if not block_tally.has(id):
		block_tally[id] = {}

	var per_activity: Dictionary = block_tally[id]

	per_activity[blocked_by] = int(per_activity.get(blocked_by, 0)) + 1


func _report() -> void:
	print("")
	print("=========== PHASE A AUDIT ===========")
	print("")
	print("--- ACTIVITY AVAILABILITY (share of evaluations where it was a candidate) ---")

	var ids: Array = evaluations.keys()
	ids.sort()

	for id: String in ids:
		var total: int = int(evaluations[id])
		var available: int = int(available_tally.get(id, 0))
		var pct: float = 0.0

		if total > 0:
			pct = (float(available) / float(total)) * 100.0

		print("  %-24s %6.2f%%  (%d / %d)" % [id, pct, available, total])

	print("")
	print("--- WHAT BLOCKED EACH ACTIVITY (top reasons) ---")

	for id: String in ids:
		if not block_tally.has(id):
			continue

		print("  %s:" % id)

		var reasons: Dictionary = block_tally[id]
		var sorted: Array = reasons.keys()

		sorted.sort_custom(
			func(a: String, b: String) -> bool:
				return int(reasons[a]) > int(reasons[b])
		)

		var total: int = int(evaluations[id])

		for reason: String in sorted:
			var count: int = int(reasons[reason])
			var pct: float = (float(count) / float(total)) * 100.0

			print("      %6.2f%%  %s" % [pct, reason])

	print("")
	print("--- STATE DISTRIBUTION ---")

	var state_keys: Array = state_tally.keys()

	state_keys.sort_custom(
		func(a: String, b: String) -> bool:
			return int(state_tally[a]) > int(state_tally[b])
	)

	for key: String in state_keys:
		var pct: float = (float(state_tally[key]) / float(maxi(state_samples, 1))) * 100.0

		print("  state %-6s %6.2f%%" % [key, pct])

	print("")
	print("--- DRINKS PER CUSTOMER ---")

	var histogram: Dictionary = {}

	for id: Variant in drinks_per_customer:
		var n: int = int(drinks_per_customer[id])

		histogram[n] = int(histogram.get(n, 0)) + 1

	var counts: Array = histogram.keys()
	counts.sort()

	var total_customers: int = drinks_per_customer.size()

	for n: int in counts:
		print("  %d drink(s): %d customers" % [n, int(histogram[n])])

	print("  tracked customers: %d" % total_customers)

	var longest: float = 0.0
	var sum: float = 0.0

	for id: Variant in visit_seconds:
		var v: float = float(visit_seconds[id])

		sum += v
		longest = maxf(longest, v)

	if visit_seconds.size() > 0:
		print(
			"  mean tracked visit: %.1fs   longest: %.1fs"
			% [sum / float(visit_seconds.size()), longest]
		)

	print("")
	print("=========== END AUDIT ===========")
