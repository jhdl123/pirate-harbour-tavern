class_name ReservationService
extends RefCounted

## Searching and claiming across a set of [Reservable]s.
##
## The per-reservable rules live on [Reservable]. This is the layer above:
## "find me a free one", "find me the best one", "let go of everything this
## actor holds". Seat selection, approach point selection and future queue slot
## selection are all the same problem, so they are all the same code.
##
## Static and stateless. The caller owns the list of candidates, which keeps
## this usable for a table's chairs, a station's approach points, or a global
## search, without any registry to keep in step.


## Every free reservable in [param candidates].
static func filter_free(
	candidates: Array
) -> Array[Reservable]:
	var free_reservables: Array[Reservable] = []

	for candidate: Variant in candidates:
		var reservable: Reservable = candidate as Reservable

		if reservable == null or not is_instance_valid(reservable):
			continue

		if reservable.is_free():
			free_reservables.append(reservable)

	return free_reservables


## Free reservables carrying [param tag].
static func filter_free_by_tag(
	candidates: Array,
	tag: StringName
) -> Array[Reservable]:
	var matching: Array[Reservable] = []

	for reservable: Reservable in filter_free(candidates):
		if reservable.has_tag(tag):
			matching.append(reservable)

	return matching


## The free reservable with the lowest score.
##
## [param score_function] takes a [Reservable] and returns a float; lower wins.
## Returning [code]INF[/code] rules a candidate out entirely, which is how an
## unreachable seat or an occupied table is excluded without a second list.
static func find_best_free(
	candidates: Array,
	score_function: Callable
) -> Reservable:
	var best: Reservable = null
	var best_score: float = INF

	for reservable: Reservable in filter_free(candidates):
		var score: float = float(score_function.call(reservable))

		if score >= INF:
			continue

		if best == null or score < best_score:
			best_score = score
			best = reservable

	return best


## The nearest free reservable to [param from_position].
##
## Straight-line distance, which is the right cost for choosing between a
## station's own approach points. Use [method find_best_free] with
## [method NavigationService.get_path_length] when real travel cost matters.
static func find_nearest_free(
	candidates: Array,
	from_position: Vector2
) -> Reservable:
	return find_best_free(
		candidates,
		func(reservable: Reservable) -> float:
			var subject: Node2D = reservable.get_subject() as Node2D

			if subject == null:
				return INF

			return from_position.distance_squared_to(
				subject.global_position
			)
	)


## Reserves the first free candidate for [param actor] and returns it.
static func reserve_first_free(
	candidates: Array,
	actor: Node
) -> Reservable:
	for reservable: Reservable in filter_free(candidates):
		if reservable.reserve(actor):
			return reservable

	return null


## Reserves the nearest free candidate for [param actor] and returns it.
##
## The claim is attempted on the best candidate only. If it fails - another
## actor claimed it in the same frame - the next best is tried, so two actors
## choosing simultaneously never both walk to the same spot.
static func reserve_nearest_free(
	candidates: Array,
	actor: Node,
	from_position: Vector2
) -> Reservable:
	var remaining: Array[Reservable] = filter_free(candidates)

	while not remaining.is_empty():
		var nearest: Reservable = find_nearest_free(
			remaining,
			from_position
		)

		if nearest == null:
			return null

		if nearest.reserve(actor):
			return nearest

		remaining.erase(nearest)

	return null


## Releases everything in [param candidates] held by [param actor].
##
## Cheap insurance when an actor leaves, is destroyed, or abandons a task.
static func release_all_for(
	candidates: Array,
	actor: Node
) -> void:
	for candidate: Variant in candidates:
		var reservable: Reservable = candidate as Reservable

		if reservable == null or not is_instance_valid(reservable):
			continue

		if reservable.is_held_by(actor):
			reservable.release(actor)


## Collects every [Reservable] under [param root].
##
## Convenience for objects that hold several, such as a table's chairs or a
## station's approach points.
static func collect_from(
	root: Node,
	tag: StringName = &""
) -> Array[Reservable]:
	var found: Array[Reservable] = []

	if root == null:
		return found

	for child: Node in root.get_children():
		var reservable: Reservable = child as Reservable

		if reservable != null:
			if tag.is_empty() or reservable.has_tag(tag):
				found.append(reservable)

		found.append_array(collect_from(child, tag))

	return found
