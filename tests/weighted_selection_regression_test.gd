extends Node

## Reproduces, then guards against, the bug found by reading individual
## customer histories in `docs/history/2026-08-25_SCORING_AUDIT.md` §7:
## `CustomerBrain._select_weighted()` could resample a candidate the
## stage-3 motivation filter had already excluded, purely because its raw
## score happened to sit within `selection_band` of the filtered winner's.
##
## Root cause, confirmed by reading rather than guessing: `_select_weighted()`
## itself is already a correctly generic selector - it knows nothing about
## motivations, needs or specific activities, only about scores and
## [member ActivityDefinition.is_mandatory]. The defect was entirely at the
## call site in `think()`: `eligible_for_report` (passed to the selector) is
## built *before* the stage-3 motivation filter's `continue`, while `best`/
## `best_score` are computed only from candidates that survive it. The
## selector was being handed the wrong list, not reaching into a broader
## collection on its own.
##
## Scenario: motivation is forced to `social` (needs shaped so `social`'s
## weight is the only nonzero one in `_select_motivation()`'s weighted pick,
## making the stage-2 draw deterministic in practice without touching
## `deterministic_decisions`, which would also disable the very selector
## this test is about). `relax_at_seat` (`satisfies = {"relaxation": 0.3}`,
## does not serve `social`) is kept scoring close enough to the correctly-
## filtered winner (`socialise_at_seat`/`visit_tavern_activity`, both of
## which do serve `social`) to fall inside `selection_band` - exactly the
## shape of the three real cases the audit found. Run many trials (each
## with a fresh, unseeded RNG) because weighted selection is probabilistic;
## the regression assertion is that the violation rate is exactly zero, not
## merely lower.


class MinimalActor extends Node2D:
	var flags: Dictionary = {}

	func get_activity_flags() -> Dictionary:
		return flags


const TRIAL_COUNT: int = 150

var passed: int = 0
var failed: int = 0

var registry: ActivityRegistry


func _ready() -> void:
	registry = load("res://Data/customer_ai/activity_registry.tres")

	_run()

	print("\n=== RESULT: %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _check(label: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("  [PASS] " + label)
	else:
		failed += 1
		print("  [FAIL] " + label)


func _make_scenario() -> Dictionary:
	var needs := CustomerNeeds.new()
	# Only `social` has nonzero weight in _select_motivation()'s dictionary,
	# so the weighted draw there always lands on `social` (the other three
	# keys contribute nothing to the running total) - deterministic in
	# practice without disabling weighted selection itself.
	needs.set_need(&"thirst", 0.0)
	needs.set_need(&"social", 1.0)
	needs.set_need(&"entertainment", 0.0)
	needs.set_need(&"relaxation", 0.0)
	needs.set_need(&"mood", 0.8)
	needs.set_need(&"intoxication", 0.0)
	needs.set_need(&"patience", 1.0)
	needs.set_need(&"energy", 1.0)
	needs.set_context_value(&"remaining_visit_minutes", 60.0)
	needs.set_context_value(&"visit_duration_minutes", 90.0)
	needs.set_context_value(&"wealth", 30.0)

	var actor := MinimalActor.new()
	actor.name = "WeightedSelectionRegressionActor"
	actor.flags = {
		&"is_settled": true,
		&"is_seated": false,
		&"is_free_to_leave_seat": true,
		&"is_transacting_at_bar": false,
		&"has_ordered_drink": false,
		&"has_drink_to_consume": false,
		&"has_social_partner": true,
		&"group_has_away_capacity": true,
		&"group_is_drinking": false,
	}
	add_child(actor)

	var brain := CustomerBrain.new()
	brain.configure(actor, needs, registry)
	add_child(brain)

	return {"actor": actor, "needs": needs, "brain": brain}


## True when [param decision]'s selected activity was actually allowed to
## compete under its own recorded motivation - mandatory and terminal
## activities are always allowed (see CustomerBrain.think()'s stage-3
## exemptions); anything else must be in the registry and its own
## ActivityDefinition.satisfies must declare the motivation.
func _selection_respects_motivation_filter(decision: DecisionRecord) -> bool:
	if decision == null or decision.selected_activity_id.is_empty():
		return true

	var definition: ActivityDefinition = registry.get_definition(
		StringName(decision.selected_activity_id)
	)

	if definition == null:
		return true

	if definition.is_mandatory or definition.is_terminal:
		return true

	return definition.serves_motivation(StringName(decision.motivation))


func _run() -> void:
	var violations: int = 0
	var relax_ever_eligible: bool = false
	var motivation_was_social_count: int = 0

	for trial: int in TRIAL_COUNT:
		var scenario: Dictionary = _make_scenario()
		var brain: CustomerBrain = scenario["brain"]

		brain.think()

		var decision: DecisionRecord = brain.get_last_decision()

		if decision != null and decision.motivation == "social":
			motivation_was_social_count += 1

			for entry: Dictionary in decision.eligible_activities:
				if String(entry.get("activity_id", "")) == "relax_at_seat":
					relax_ever_eligible = true

			if not _selection_respects_motivation_filter(decision):
				violations += 1
				print(
					"  [VIOLATION] trial ", trial, ": motivation=",
					decision.motivation, " selected=",
					decision.selected_activity_id, " candidates=",
					decision.eligible_activities
				)

		# free(), not queue_free(): these are throwaway nodes that never
		# started any deferred work of their own, and the loop needs them
		# gone before the next trial builds a fresh pair, not merely
		# scheduled to go - queue_free() left two ObjectDB entries alive at
		# process exit in earlier runs of this test.
		scenario["brain"].free()
		scenario["actor"].free()

	print(
		"  ", TRIAL_COUNT, " trials, motivation=social in ",
		motivation_was_social_count, ", relax_at_seat eligible-for-report",
		" in at least one: ", relax_ever_eligible,
		", violations: ", violations
	)

	_check(
		"scenario is well-formed: motivation resolved to social every trial",
		motivation_was_social_count == TRIAL_COUNT
	)
	_check(
		"scenario is well-formed: relax_at_seat (excluded) was reported as" +
		" an eligible candidate at least once",
		relax_ever_eligible
	)
	_check(
		"no selection ever violated the stage-3 motivation filter across " +
		str(TRIAL_COUNT) + " trials",
		violations == 0
	)
