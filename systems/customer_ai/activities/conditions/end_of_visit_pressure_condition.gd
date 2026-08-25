class_name EndOfVisitPressureCondition
extends ActivityCondition

## A nonlinear pressure ramp in the final stretch of a visit.
##
## [NeedThresholdCondition]'s visit-time scoring is linear across the whole
## visit - fine as a gradual pull, but the brief specifically wants the last
## 10-15 minutes to feel noticeably stronger than "a bit more of the same
## linear slope". This condition contributes nothing until
## [member remaining_visit_minutes] drops inside [member pressure_window_minutes],
## then ramps up as the square of how far into that window the customer is -
## configurable, and additive on top of (not a replacement for) the existing
## linear conditions. Never gates - see [ActivityCondition]'s own note on
## why a condition that only wants to influence scoring should not override
## [method is_satisfied].


@export_category("Rule")

@export var need_id: StringName = &"remaining_visit_minutes"

## World minutes before the hard visit expiry where pressure starts
## ramping - the brief's "final 10-15 in-game minutes".
@export_range(1.0, 60.0, 1.0)
var pressure_window_minutes: float = 12.0

## The contribution at the very end of the visit (remaining time at or
## below 0). Ramps from 0 at the window's start to this value, following
## a squared curve so the last couple of minutes matter far more than the
## first few of the window - see the class doc comment.
@export var maximum_bonus: float = 8.0


func score(context: ActivityContext) -> float:
	if context.needs == null:
		return 0.0

	# Always a raw minute count, never a 0-1 need - see
	# CustomerNeeds.get_context_value()'s doc comment.
	var remaining: float = context.needs.get_context_value(need_id)

	if remaining >= pressure_window_minutes or pressure_window_minutes <= 0.0:
		return 0.0

	var fraction_into_window: float = clampf(
		1.0 - (remaining / pressure_window_minutes),
		0.0,
		1.0
	)

	return maximum_bonus * fraction_into_window * fraction_into_window
