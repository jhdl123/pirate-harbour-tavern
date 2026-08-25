class_name RepeatDecayCondition
extends ActivityCondition

## Diminishing returns: the more times this need has already gone up this
## visit, the less this activity's utility is worth.
##
## Built for Relax at Seat's repeat count, but reads any [CustomerNeeds]
## numeric field the same way [NeedThresholdCondition] does - nothing here
## is Relax-specific. Never gates (there being no hard reason repeating an
## activity should become *impossible* - see the class-level distinction
## in [ActivityCondition]) - only scores, and always in the activity's
## favour at zero repeats, eroding toward (but not past) cancelling out
## [member reference_utility] entirely.
##
## The curve: each repeat multiplies the previous multiplier by
## [code](1.0 - decay_per_repeat)[/code], so a 15% decay per repeat gives
## 100%/85%/72%/61%/... of [member reference_utility] - "roughly halved
## every five repeats" rather than a hand-authored table of percentages.


@export_category("Rule")

## Which [CustomerNeeds] field counts repeats, e.g. [code]&"relax_count"[/code].
@export var need_id: StringName = &""

## Fraction of the remaining multiplier lost per repeat (0.15 = 15%).
@export_range(0.0, 1.0, 0.01)
var decay_per_repeat: float = 0.15

## The activity's own [member ActivityDefinition.base_utility] - kept here
## rather than read back from the activity so this condition never needs a
## reference to its own owner. Set it to match; if they drift apart the
## curve just erodes toward a different ceiling than the activity's actual
## base score; see the balancing guide in docs/CUSTOMER_AI_SYSTEM.md.
@export var reference_utility: float = 6.0


func score(context: ActivityContext) -> float:
	if context.needs == null or need_id.is_empty():
		return 0.0

	# Repeat counts are always a raw context value, never a 0-1 need - see
	# CustomerNeeds.get_context_value()'s doc comment.
	var repeats: float = context.needs.get_context_value(need_id)

	if repeats <= 0.0:
		return 0.0

	var multiplier: float = pow(
		clampf(1.0 - decay_per_repeat, 0.0, 1.0),
		repeats
	)

	# Negative-only: at 0 repeats this contributes nothing (multiplier 1.0);
	# it never boosts the activity above its own base_utility, only erodes
	# it as repeats climb.
	return reference_utility * (multiplier - 1.0)
