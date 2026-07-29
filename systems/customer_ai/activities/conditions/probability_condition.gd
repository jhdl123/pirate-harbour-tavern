class_name ProbabilityCondition
extends ActivityCondition

## A soft, re-rolled random nudge - not a hard gate.
##
## Deliberately never overrides [method is_satisfied]: a condition that could
## disqualify an activity based on a coin flip would make that activity
## flicker in and out of contention every think cycle, fighting
## [CustomerBrain]'s stickiness instead of complementing it. Add this to a
## filler activity like Wander so it does not always win by default, without
## ever making Wander unpredictably unavailable.


## Multiplies a fresh [method randf] roll each time this is scored. Two
## activities both carrying one of these compete on chance, scaled by how
## much each cares about it.
@export var score_weight: float = 1.0


func score(_context: ActivityContext) -> float:
	return randf() * score_weight
