extends Node

## Why is the dartboard never used?
##
## The gate audit already showed visit_tavern_activity is ELIGIBLE ~37% of
## samples but occupies ~1% of customer time. Eligibility is therefore not the
## answer. This prints the actual competitive score next to the winner, and
## separately counts cooldown blocks (which the gate audit never evaluated).
##
## Phase B added a stage-2 motivation filter inside CustomerBrain.think()
## (docs/history/2026-08-25_CUSTOMER_ARCHITECTURE_AUDIT.md's "ALSO DO") -
## this probe still walks registry.definitions directly rather than calling
## think() itself, so "eligible" below is condition-eligibility only, same
## as before that change, and would silently stop meaning what a reader
## expects if left alone. The MOTIVATION GATE section reproduces the actual
## think()-equivalent filter (motivation selected, non-mandatory candidates
## without a matching ActivityDefinition.satisfies entry excluded) as a
## second, explicit column - "eligible" alone is the pre-two-stage number,
## "motivation-gated" is what think() would actually do with it.

const RUN_SECONDS: float = 240.0
const SAMPLE_SECONDS: float = 2.0
const SPAWN_UNTIL: float = 160.0
const DARTS: StringName = &"visit_tavern_activity"

var samples: int = 0
var darts_eligible: int = 0
var darts_cooling: int = 0
var darts_blocked: int = 0
var darts_would_win: int = 0
var darts_scores: Array[float] = []
var winner_tally: Dictionary = {}
var beaten_by: Dictionary = {}
var gap_samples: Array[float] = []
var mean_score: Dictionary = {}
var score_count: Dictionary = {}
var think_calls: Dictionary = {}
var entered_tally: Dictionary = {}
var darts_dumped: int = 0
var contrib: Dictionary = {}
var contrib_n: Dictionary = {}

# MOTIVATION GATE (second column) - see the class doc comment above.
var darts_motivation_matched: int = 0
var darts_motivation_excluded: int = 0
var darts_would_win_gated: int = 0
var beaten_by_gated: Dictionary = {}
var winner_tally_gated: Dictionary = {}
var motivation_tally: Dictionary = {}


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

		var registry: Object = brain.get("registry")
		var context: Object = brain.call("_build_context")

		if registry == null or context == null:
			continue

		var current: Object = brain.call("get_current_activity")

		if current != null:
			var cid: StringName = current.get("activity_id")
			entered_tally[cid] = int(entered_tally.get(cid, 0)) + 1

		var identity: Object = brain.get("identity")
		var world_minutes: float = float(context.get("world_minutes"))

		# Stage 2 (CUSTOMER_MODEL.md §4) - the real think()-equivalent
		# motivation this sample would have selected. Computed once per
		# sample, same as CustomerBrain.think() does.
		var motivation: StringName = brain.call("_select_motivation", context)
		motivation_tally[motivation] = int(motivation_tally.get(motivation, 0)) + 1

		var best_id: StringName = &""
		var best_score: float = -INF
		var darts_score: float = -INF
		var darts_state: String = "blocked"

		var best_id_gated: StringName = &""
		var best_score_gated: float = -INF
		var darts_matches_motivation: bool = false

		for definition: Object in registry.get("definitions"):
			if definition == null:
				continue

			var aid: StringName = definition.get("activity_id")
			context.activity = definition

			if not definition.call("is_available", context):
				if aid == DARTS:
					darts_state = "blocked"
				continue

			if brain.call("is_on_cooldown", definition, world_minutes):
				if aid == DARTS:
					darts_state = "cooling"
				continue

			var score: float = float(definition.call("get_utility", context))

			if identity != null:
				score += float(
					identity.call("get_activity_bias", aid)
				)

			if aid == DARTS or aid == &"relax_at_seat":
				var bd: Dictionary = definition.call(
					"get_utility_breakdown", context
				)
				if not contrib.has(aid):
					contrib[aid] = {}
					contrib_n[aid] = 0
				contrib_n[aid] = int(contrib_n[aid]) + 1
				var acc: Dictionary = contrib[aid]
				for k: String in bd:
					if bd[k] is float or bd[k] is int:
						acc[k] = float(acc.get(k, 0.0)) + float(bd[k])

			mean_score[aid] = float(mean_score.get(aid, 0.0)) + score
			score_count[aid] = int(score_count.get(aid, 0)) + 1

			if aid == DARTS:
				darts_state = "eligible"
				darts_score = score

			if score > best_score:
				best_score = score
				best_id = aid

			# MOTIVATION GATE: the same exclusion CustomerBrain.think()
			# applies at stage 3 - a non-mandatory candidate whose
			# ActivityDefinition.satisfies does not serve the chosen
			# motivation never enters the contest at all.
			var is_mandatory: bool = bool(definition.get("is_mandatory"))
			var serves: bool = bool(
				definition.call("serves_motivation", motivation)
			)

			if aid == DARTS:
				darts_matches_motivation = is_mandatory or serves

			if not is_mandatory and not serves:
				continue

			if score > best_score_gated:
				best_score_gated = score
				best_id_gated = aid

		if best_id != &"":
			winner_tally[best_id] = int(winner_tally.get(best_id, 0)) + 1

		if best_id_gated != &"":
			winner_tally_gated[best_id_gated] = int(
				winner_tally_gated.get(best_id_gated, 0)
			) + 1

		match darts_state:
			"eligible":
				darts_eligible += 1
				darts_scores.append(darts_score)

				if best_id == DARTS:
					darts_would_win += 1
				else:
					beaten_by[best_id] = int(beaten_by.get(best_id, 0)) + 1
					gap_samples.append(best_score - darts_score)

					if darts_dumped < 6:
						darts_dumped += 1
						_dump(customer, context, registry, best_id, best_score, darts_score)

				if darts_matches_motivation:
					darts_motivation_matched += 1

					if best_id_gated == DARTS:
						darts_would_win_gated += 1
					else:
						beaten_by_gated[best_id_gated] = int(
							beaten_by_gated.get(best_id_gated, 0)
						) + 1
				else:
					darts_motivation_excluded += 1
			"cooling":
				darts_cooling += 1
			_:
				darts_blocked += 1


func _dump(
	customer: Node,
	context: Object,
	registry: Object,
	winner: StringName,
	winner_score: float,
	darts_score: float
) -> void:
	print("")
	print("  --- ", customer.name, " darts=", "%.2f" % darts_score,
		" loses to ", winner, "=", "%.2f" % winner_score)

	for definition: Object in registry.get("definitions"):
		if definition == null:
			continue

		var aid: StringName = definition.get("activity_id")

		if aid != DARTS and aid != winner:
			continue

		context.activity = definition
		var breakdown: Dictionary = definition.call(
			"get_utility_breakdown", context
		)
		print("      ", aid, ": ", breakdown)


func _report() -> void:
	print("")
	print("=== DARTS SCORE PROBE ===")
	print("samples=", samples)
	print("")
	print("DARTS AVAILABILITY (per customer-sample)")
	print("  eligible          ", darts_eligible)
	print("  on cooldown       ", darts_cooling)
	print("  condition-blocked ", darts_blocked)
	print("")
	print("WHEN DARTS IS ELIGIBLE")
	print("  would be top scorer ", darts_would_win)
	print("  beaten by:")

	for k: StringName in beaten_by:
		print("      ", k, ": ", beaten_by[k])

	if not darts_scores.is_empty():
		var total: float = 0.0
		for s: float in darts_scores:
			total += s
		print("  mean darts score  ", "%.2f" % (total / float(darts_scores.size())))

	if not gap_samples.is_empty():
		var g: float = 0.0
		for s: float in gap_samples:
			g += s
		print("  mean gap to winner ", "%.2f" % (g / float(gap_samples.size())))

	print("")
	print("MOTIVATION GATE (stage 2/3, think()-equivalent - see class doc)")
	print("  motivation chosen this run:")

	for k: StringName in motivation_tally:
		print("      ", k, ": ", motivation_tally[k])

	print(
		"  darts eligible AND matches chosen motivation: ",
		darts_motivation_matched
	)
	print(
		"  darts eligible BUT motivation-excluded: ",
		darts_motivation_excluded
	)

	if darts_motivation_matched > 0:
		print(
			"  would be top scorer (motivation-gated pool): ",
			darts_would_win_gated,
			" / ", darts_motivation_matched
		)
		print("  beaten by (motivation-gated pool):")

		for k: StringName in beaten_by_gated:
			print("      ", k, ": ", beaten_by_gated[k])

	print("")
	print("TOP SCORER TALLY (motivation-gated pool)")

	for k: StringName in winner_tally_gated:
		print("  ", k, ": ", winner_tally_gated[k])

	print("")
	print("MEAN SCORE WHEN ELIGIBLE (all activities)")

	for k: StringName in mean_score:
		var n: int = int(score_count[k])
		print("  ", k, "  mean=", "%.2f" % (float(mean_score[k]) / float(n)),
			"  eligible_samples=", n)

	print("")
	print("MEAN CONTRIBUTIONS (relax vs darts, when eligible)")

	for k: StringName in contrib:
		var n: int = int(contrib_n[k])
		print("  ", k, " over ", n, " samples:")
		var acc: Dictionary = contrib[k]
		for f: String in acc:
			print("      ", f, " = ", "%.2f" % (float(acc[f]) / float(n)))

	print("")
	print("TOP SCORER TALLY (who would win if think() ran now)")

	for k: StringName in winner_tally:
		print("  ", k, ": ", winner_tally[k])

	print("")
	print("ACTUAL CURRENT ACTIVITY OCCUPANCY")

	for k: StringName in entered_tally:
		print("  ", k, ": ", entered_tally[k])

	print("=== END DARTS SCORE PROBE ===")
