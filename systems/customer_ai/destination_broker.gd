class_name DestinationBroker
extends RefCounted

## Turns "I need a chair" into a real [Reservable], tavern-wide.
##
## An [ActivityDefinition] names a destination only by tag
## ([code]&"seat"[/code], [code]&"bar"[/code], [code]&"fireplace"[/code]) -
## see the brief's "Destinations" section. This is the layer that resolves a
## tag into an actual candidate list and hands the search to
## [ReservationService], which already does distance scoring and safe
## claiming. Adding a new destination type needs nothing here: tag a
## [Reservable] with the new tag (a [Chair] already carries
## [code]&"seat"[/code]) and it is found automatically, because
## [method Reservable._ready] joins a group per tag.
##
## Static and stateless, the same shape as [ReservationService] itself - this
## is a thin adapter in front of it, not a second system.


## Every [Reservable] anywhere in the tree carrying [param tag], whatever
## state it is in. Prefer [method find_available] or
## [method reserve_nearest] unless you specifically need occupied ones too.
static func get_candidates(
	tag: StringName,
	tree: SceneTree
) -> Array[Reservable]:
	var typed: Array[Reservable] = []

	if tree == null:
		return typed

	for node: Node in tree.get_nodes_in_group(
		Reservable.group_for_tag(tag)
	):
		var reservable: Reservable = node as Reservable

		if reservable != null and is_instance_valid(reservable):
			typed.append(reservable)

	return typed


## Whether at least one free [Reservable] carrying [param tag] exists right
## now. What [DestinationAvailableCondition] calls - it needs an answer, not
## a claim, so scoring an activity never accidentally reserves anything.
static func has_available(
	tag: StringName,
	tree: SceneTree
) -> bool:
	for reservable: Reservable in get_candidates(tag, tree):
		if reservable.is_free():
			return true

	return false


## Claims the nearest free [Reservable] carrying [param tag] for
## [param actor], or null if none is free. The only method here that
## actually reserves anything.
static func reserve_nearest(
	tag: StringName,
	actor: Node,
	from_position: Vector2,
	tree: SceneTree
) -> Reservable:
	return ReservationService.reserve_nearest_free(
		get_candidates(tag, tree),
		actor,
		from_position
	)
