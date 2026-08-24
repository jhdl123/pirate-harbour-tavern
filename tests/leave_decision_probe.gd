extends Node

## Why does 'leave' never win?
##
## Four tuning attempts moved the chosen-departure count between 0 and 2. That
## pattern says the mechanism is blocked, not mis-weighted, so this stops
## turning dials and prints the actual score.
##
## For every seated customer inside the end-of-visit window it dumps leave's
## full utility breakdown next to the winning activity's score, so the
## comparison is visible rather than inferred.

const RUN_SECONDS: float = 240.0
const SAMPLE_SECONDS: float = 5.0

var dumped: int = 0
var leave_wins: int = 0
var leave_eligible: int = 0
var leave_blocked_by: Dictionary = {}
var score_gap_samples: Array[float] = []


func _ready() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var tavern: Node = get_node_or_null("/root/Tavern")
	if tavern != null and tavern.has_method("open_early"):
		tavern.open_early()

	var elapsed: float = 0.0
	while elapsed < RUN_SECONDS:
		await get_tree().create_timer(SAMPLE_SECONDS).timeout
		elapsed += SAMPLE_SECONDS
		_sample()

	_report()
	get_tree().quit()


func _sample() -> void:
	var customers: Array = get_tree().get_nodes_in_group("navigation_customers")
	if customers.is_empty():
		customers = get_tree().get_nodes_in_group("customer")

	for c: Node in customers:
		if not is_instance_valid(c):
			continue

		var brain: Node = c.get("_brain")
		if brain == null:
			continue

		var needs: Object = c.get("needs")
		if needs == null:
			continue

		# Only customers actually inside the pressure window matter.
		var remaining: float = float(needs.get("remaining_visit_minutes"))
		if remaining <= 0.0 or remaining > 30.0:
			continue

		var registry: Object = brain.get("registry")
		if registry == null:
			continue

		var context: Object = null
		context = brain._build_context()

		if context == null:
			continue

		var leave_def: Object = null
		var best_id: String = ""
		var best_score: float = -99999.0
		var leave_score: float = -99999.0

		for definition: Object in registry.get("definitions"):
			if definition == null:
				continue

			var aid: String = String(definition.get("activity_id"))
			var eligible: bool = definition.is_available(context)
			var score: float = (
				definition.get_utility(context) if eligible else -99999.0
			)

			if aid == "leave":
				leave_def = definition
				leave_score = score

				if eligible:
					leave_eligible += 1
				else:
					var reason: String = definition.get_rejection_reason(
						context
					)
					leave_blocked_by[reason] = int(
						leave_blocked_by.get(reason, 0)
					) + 1

			if eligible and score > best_score:
				best_score = score
				best_id = aid

		if leave_def == null or leave_score <= -99998.0:
			continue

		if best_id == "leave":
			leave_wins += 1

		score_gap_samples.append(best_score - leave_score)

		if dumped < 6:
			dumped += 1
			print("")
			print("--- ", c.name, "  remaining=", snappedf(remaining, 0.1), "m ---")
			print("  winner: ", best_id, " @ ", snappedf(best_score, 0.01))
			print("  leave:  ", snappedf(leave_score, 0.01))

			if leave_def.has_method("get_utility_breakdown"):
				var breakdown: Dictionary = leave_def.get_utility_breakdown(
					context
				)
				for key: Variant in breakdown.keys():
					print("     ", key, " = ", breakdown[key])


func _report() -> void:
	print("")
	print("=== LEAVE DECISION PROBE ===")
	print("  samples in window : ", score_gap_samples.size())
	print("  leave eligible    : ", leave_eligible)
	print("  leave was winner  : ", leave_wins)

	if not score_gap_samples.is_empty():
		var total: float = 0.0
		var worst: float = -99999.0
		for g: float in score_gap_samples:
			total += g
			worst = maxf(worst, g)
		print("  mean gap to winner: ", snappedf(
			total / float(score_gap_samples.size()), 0.01
		))
		print("  largest gap       : ", snappedf(worst, 0.01))

	if not leave_blocked_by.is_empty():
		print("  leave GATED by:")
		for k: Variant in leave_blocked_by.keys():
			print("     ", k, ": ", leave_blocked_by[k])

	print("=== END LEAVE DECISION PROBE ===")
