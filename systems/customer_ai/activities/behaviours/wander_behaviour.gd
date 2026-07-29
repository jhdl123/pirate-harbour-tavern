class_name WanderBehaviour
extends ActivityBehaviour

## Does nothing. On purpose.
##
## The brief is explicit that a real "look around, mill about" behaviour
## comes later - what matters for this pass is that [CustomerBrain] always
## has *something* available to fall back to, so an empty candidate list is
## never a special case anywhere in [ActivityDefinition] or [CustomerBrain].
## [Data/customer_ai/activities/wander.tres] has no conditions beyond a
## [ProbabilityCondition], so it is always a candidate and never wins unless
## every real activity has disqualified itself - giving a genuinely idle
## customer a documented, inspectable "why" (Wander won) instead of the
## brain quietly doing nothing.
