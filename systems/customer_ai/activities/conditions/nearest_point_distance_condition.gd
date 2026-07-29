class_name NearestPointDistanceCondition
extends ActivityCondition

## Scores an activity by how close the nearest available tagged point is.
##
## Built for Visit Tavern Activity's distance consideration (the brief's
## "Tavern activity utility should consider: ... distance"), but reads
## whichever tag(s) it is configured with via [DestinationBroker] - the
## same tree-wide lookup [CustomerBrain] itself uses to actually reserve a
## destination, so this condition's opinion of "is anything close" can
## never disagree with what reservation will actually find. Never gates:
## a far-away point should score worse, not make the activity impossible -
## [DestinationAvailableCondition] is the existing, separate condition for
## "is there truly nothing at all".


@export_category("Rule")

## Tags to search - usually just the activity's own [member
## ActivityDefinition.destination_tag], but kept separate in case a future
## activity wants to search several tags before choosing where to go, per
## docs/CUSTOMER_AI_SYSTEM.md's Phase 2C section on adding new activities.
@export var tags: Array[StringName] = []

## Contribution at distance 0, decaying to roughly 0 by [member
## falloff_distance] world pixels away.
@export var maximum_bonus: float = 4.0

@export_range(16.0, 4000.0, 16.0)
var falloff_distance: float = 600.0


func score(context: ActivityContext) -> float:
	if tags.is_empty() or context.actor == null:
		return 0.0

	var tree: SceneTree = context.actor.get_tree()

	if tree == null:
		return 0.0

	var nearest_distance: float = INF

	for tag: StringName in tags:
		for reservable: Reservable in DestinationBroker.get_candidates(
			tag, tree
		):
			if not reservable.is_free():
				continue

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

	# A less travel-willing customer (impatient, hurried) perceives the
	# same physical distance as further than it is, rather than needing a
	# second, parallel distance formula.
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
