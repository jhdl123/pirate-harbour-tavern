class_name DestinationAvailableCondition
extends ActivityCondition

## Hard gate: is there anywhere free to actually do this activity?
##
## Add this to any [ActivityDefinition] whose [member ActivityDefinition.
## destination_tag] is not empty, so [CustomerBrain] never chooses "Play
## Darts" when every dartboard is taken. Uses [DestinationBroker], so it
## reuses whatever tag [Reservable]s already exist - no separate list of
## "how many dartboards are there" to maintain.


## Usually left empty - when empty, reads
## [member ActivityDefinition.destination_tag] from the activity being
## scored instead, which is right for the common case of one condition per
## activity. Set explicitly only if a condition needs to check a *different*
## tag than the activity it's attached to (uncommon).
@export var tag_override: StringName = &""


func is_satisfied(context: ActivityContext) -> bool:
	var tag: StringName = tag_override

	if tag.is_empty() and context.activity != null:
		tag = context.activity.destination_tag

	if tag.is_empty():
		return true

	if context.actor == null or context.actor.get_tree() == null:
		return false

	return DestinationBroker.has_available(tag, context.actor.get_tree())


func get_rejection_reason(context: ActivityContext) -> String:
	var tag: StringName = tag_override

	if tag.is_empty() and context.activity != null:
		tag = context.activity.destination_tag

	return "no free destination available for tag '%s'" % String(tag)
