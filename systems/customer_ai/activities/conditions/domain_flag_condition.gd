class_name DomainFlagCondition
extends ActivityCondition

## Gate and/or score on one of [member ActivityContext.domain_flags].
##
## The generic counterpart to [NeedThresholdCondition]: where that condition
## reads a numeric need every actor type shares, this reads a boolean concept
## specific to one actor type (a customer's "is seated", a future staff
## member's "is on shift"). See [ActivityContext.domain_flags] for why this
## does not live directly on [CustomerNeeds].


@export var flag_name: StringName = &""
@export var expected_value: bool = true

## When true (default), the flag must match [member expected_value] for the
## activity to be a candidate at all. Set false to use this purely for
## [member score_bonus] without ever disqualifying the activity - e.g. Leave
## scoring higher once a drink limit is reached, without Leave itself being
## gated by that limit. Existing condition resources predate this field and
## all rely on its default (true), so nothing changes for them.
@export var gates: bool = true

## Added to the activity's utility whenever the flag currently matches
## [member expected_value], independent of [member gates]. Zero (default)
## means this condition contributes no score, matching its original,
## gate-only behaviour.
@export var score_bonus: float = 0.0


func is_satisfied(context: ActivityContext) -> bool:
	if flag_name.is_empty() or not gates:
		return true

	return bool(context.domain_flags.get(flag_name, false)) == expected_value


func score(context: ActivityContext) -> float:
	if flag_name.is_empty() or score_bonus == 0.0:
		return 0.0

	if bool(context.domain_flags.get(flag_name, false)) == expected_value:
		return score_bonus

	return 0.0


func get_rejection_reason(context: ActivityContext) -> String:
	var actual: bool = bool(context.domain_flags.get(flag_name, false))

	return "flag '%s' is %s, needed %s" % [
		String(flag_name), actual, expected_value
	]
