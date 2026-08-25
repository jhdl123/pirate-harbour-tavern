class_name NearbyActivityInUseCondition
extends ActivityCondition

## Score-only: raises an activity's utility when it is already in use nearby.
##
## CUSTOMER_MODEL.md §3's Awareness layer, scoped exactly as
## `docs/PHASE_B_BRIEF.md` asks for it - "proximity plus 'is this activity
## already in use' is enough to start". Reuses
## [DestinationBroker.get_occupied] and the same falloff-by-
## [member CustomerNeeds.travel_willingness] formula
## [NearestPointDistanceCondition] already uses for the mirror-image
## question (how close is the nearest *free* point) - this asks how close
## the nearest *occupied* one is instead, so "someone is already playing
## darts" makes joining more attractive without any new distance
## infrastructure.
##
## Never gates: an activity nobody is doing yet must stay exactly as
## available and exactly as scored as before this condition existed - it
## only ever adds.


@export_category("Rule")

## Tags to search - usually just the activity's own [member
## ActivityDefinition.destination_tag].
@export var tags: Array[StringName] = []

## Contribution when an occupied point is right on top of the actor,
## decaying to roughly 0 by [member falloff_distance] world pixels away.
@export var maximum_bonus: float = 2.0

@export_range(16.0, 4000.0, 16.0)
var falloff_distance: float = 300.0


func score(context: ActivityContext) -> float:
	if tags.is_empty() or context.actor == null:
		return 0.0

	var tree: SceneTree = context.actor.get_tree()

	if tree == null:
		return 0.0

	var nearest_distance: float = INF

	for tag: StringName in tags:
		for reservable: Reservable in DestinationBroker.get_occupied(
			tag, tree
		):
			var owner_node: Node2D = reservable.get_parent() as Node2D

			if owner_node == null:
				continue

			var distance: float = context.actor_position.distance_to(
				owner_node.global_position
			)

			if distance < nearest_distance:
				nearest_distance = distance

	if is_inf(nearest_distance):
		return 0.0

	var willingness: float = 1.0

	if context.needs != null:
		willingness = maxf(0.1, context.needs.travel_willingness)

	var effective_falloff: float = maxf(falloff_distance * willingness, 1.0)

	var fraction: float = clampf(
		1.0 - (nearest_distance / effective_falloff),
		0.0,
		1.0
	)

	return maximum_bonus * fraction
