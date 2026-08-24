class_name PreviousActivityAffinityCondition
extends ActivityCondition

## Soft "what I just did" bias - the cross-activity counterpart to
## [RepeatDecayCondition]'s same-activity decay.
##
## Never gates: a customer who just finished drinking is not required to
## socialise next, only nudged toward it competing more strongly against
## Leave/Relax/another Drink. Reads [member ActivityContext.last_activity_id],
## which only ever holds the immediately-preceding activity, so the bonus
## naturally stops applying the moment the customer does anything else - no
## decay curve or expiry timer is needed here the way [RepeatDecayCondition]
## needs one for repeated same-activity use.


@export_category("Rule")

## last_activity_id values that trigger [member bonus], e.g.
## [code][&"drink"][/code] on Socialise at Seat's conditions, or several ids
## if more than one prior activity should make this one more attractive.
@export var trigger_activity_ids: Array[StringName] = []

## Added to score() when the actor's last activity is in
## [member trigger_activity_ids]. Zero otherwise.
@export var bonus: float = 0.0


func score(context: ActivityContext) -> float:
	if trigger_activity_ids.is_empty():
		return 0.0

	if trigger_activity_ids.has(context.last_activity_id):
		return bonus

	return 0.0
