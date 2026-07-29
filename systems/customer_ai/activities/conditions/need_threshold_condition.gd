class_name NeedThresholdCondition
extends ActivityCondition

## Gates and/or scores an activity against one [CustomerNeeds] value.
##
## The workhorse condition: "only Sleep when energy is low", "prefer Wander
## when mood is high", "never Gamble below this wealth". Covers most future
## activities without a line of script - set [member need_id] to whichever
## field [CustomerNeeds] already exposes.
##
## [b]Phase 2B.2 fix.[/b] [member gates] used to not exist - [method
## is_satisfied] always enforced [member comparison]/[member threshold] as a
## hard gate, with no way to use this purely for [method score]. Several
## "scoring-only" condition resources from Phase 2B were quietly hard-gating
## their activity as a result - most damagingly
## [code]leave_money_scoring.tres[/code], which made Leave impossible
## whenever a customer had any money at all. See
## [code]PHASE_2B2_CHANGE_REPORT.md[/code] and [DomainFlagCondition], which
## already had this same [member gates] field from Phase 2B for exactly
## this reason - it just was not mirrored here until now.


enum Comparison {
	## Satisfied when the need is at or above [member threshold].
	AT_LEAST,

	## Satisfied when the need is at or below [member threshold].
	AT_MOST,
}


@export_category("Rule")

## Which [CustomerNeeds] field to read, e.g. [code]&"energy"[/code],
## [code]&"mood"[/code], [code]&"intoxication"[/code].
@export var need_id: StringName = &""

@export var comparison: Comparison = Comparison.AT_LEAST

@export var threshold: float = 0.5

## When true (default), [member comparison]/[member threshold] must hold for
## the activity to be a candidate at all. Set false to use this purely for
## [member score_weight] - e.g. money influencing Leave without ever making
## Leave unavailable. Every condition resource written before Phase 2B.2
## relied on the old always-gating behaviour; only ones where that gate was
## never actually intended (and was previously all-but-inert, like
## [code]order_thirst_scoring.tres[/code]'s always-true AT_LEAST 0) are
## unaffected by this field defaulting to true.
@export var gates: bool = true


@export_category("Scoring")

## Added to the activity's utility when satisfied, scaled by how far past
## [member threshold] the need is - the further past, the stronger the pull.
## Negative values make an activity less attractive as the need rises rather
## than more, for e.g. "prefer Leave as patience falls".
@export var score_weight: float = 0.0


func is_satisfied(context: ActivityContext) -> bool:
	if not gates:
		return true

	if context.needs == null or need_id.is_empty():
		return true

	var value: float = context.needs.get_need(need_id)

	match comparison:
		Comparison.AT_LEAST:
			return value >= threshold
		Comparison.AT_MOST:
			return value <= threshold

	return true


func get_rejection_reason(context: ActivityContext) -> String:
	var value: float = (
		context.needs.get_need(need_id) if context.needs != null else 0.0
	)

	var comparison_text: String = (
		"at least" if comparison == Comparison.AT_LEAST else "at most"
	)

	return "need '%s' is %.2f, needed %s %.2f" % [
		String(need_id), value, comparison_text, threshold
	]


func score(context: ActivityContext) -> float:
	if context.needs == null or need_id.is_empty() or score_weight == 0.0:
		return 0.0

	var value: float = context.needs.get_need(need_id)
	var distance: float = absf(value - threshold)

	return score_weight * distance
