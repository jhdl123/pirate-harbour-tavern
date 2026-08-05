class_name GroupFormation
extends RefCounted

## Where each member of a group stands.
##
## Pure functions: a centre, a count and a layout in, world positions out. No
## state, no nodes, no navigation. That keeps formations testable on their own
## and means a new layout is a new branch here rather than a change to the
## group controller.
##
## Slots are computed ONCE when a group arrives and then held. Recomputing them
## as members shuffle is what produces the jitter the brief warns about.


enum Layout {
	## An informal ring. The default for a standing group.
	LOOSE_CIRCLE,

	## A partial ring facing one point, for gathering round a cask.
	ARC,

	## Tighter and less even. A crew that knows each other.
	CLUSTER,

	## Evenly spaced and orderly. Merchants and officers.
	FORMAL,
}


## Positions for [param count] members around [param centre].
##
## [param variation] adds a small deterministic offset so the ring never looks
## machine-drawn. It is seeded from the slot index rather than randomised each
## call, so the same group always gets the same shape - which is what stops
## members drifting between frames.
static func build_slots(
	centre: Vector2,
	count: int,
	radius: float,
	layout: Layout = Layout.LOOSE_CIRCLE,
	variation: float = 6.0,
	seed_value: int = 0
) -> Array[Vector2]:
	var slots: Array[Vector2] = []

	if count <= 0:
		return slots

	if count == 1:
		slots.append(centre)
		return slots

	match layout:
		Layout.ARC:
			slots = _build_arc(centre, count, radius)
		Layout.CLUSTER:
			slots = _build_cluster(centre, count, radius)
		Layout.FORMAL:
			slots = _build_circle(centre, count, radius)
		_:
			slots = _build_circle(centre, count, radius)

	if is_zero_approx(variation) or layout == Layout.FORMAL:
		return slots

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value

	for index: int in range(slots.size()):
		slots[index] += Vector2(
			rng.randf_range(-variation, variation),
			rng.randf_range(-variation, variation)
		)

	return slots


static func _build_circle(
	centre: Vector2,
	count: int,
	radius: float
) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	var step: float = TAU / float(count)

	for index: int in range(count):
		var angle: float = step * float(index)

		slots.append(centre + Vector2(cos(angle), sin(angle)) * radius)

	return slots


## A partial ring, leaving the far side open so staff can reach the centre.
static func _build_arc(
	centre: Vector2,
	count: int,
	radius: float
) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	var span: float = PI * 1.2
	var start: float = -span * 0.5
	var step: float = span / float(maxi(count - 1, 1))

	for index: int in range(count):
		var angle: float = start + step * float(index)

		slots.append(centre + Vector2(cos(angle), sin(angle)) * radius)

	return slots


## Two loose rings, so a big crew does not become one enormous circle.
static func _build_cluster(
	centre: Vector2,
	count: int,
	radius: float
) -> Array[Vector2]:
	var slots: Array[Vector2] = []

	if count <= 4:
		return _build_circle(centre, count, radius * 0.8)

	var inner_count: int = int(ceil(float(count) * 0.4))
	var outer_count: int = count - inner_count

	slots.append_array(_build_circle(centre, inner_count, radius * 0.55))
	slots.append_array(_build_circle(centre, outer_count, radius))

	return slots


## Assigns [param members] to [param slots], nearest first.
##
## Greedy nearest-match rather than index order: members arrive from the door in
## no particular sequence, and pairing each to its closest free slot keeps them
## from crossing through each other to reach an arbitrary position.
static func assign_slots(
	members: Array,
	slots: Array[Vector2]
) -> Dictionary:
	var assignment: Dictionary = {}
	var taken: Array[int] = []

	for member: Variant in members:
		var node: Node2D = member as Node2D

		if node == null:
			continue

		var best_index: int = -1
		var best_distance: float = INF

		for index: int in range(slots.size()):
			if taken.has(index):
				continue

			var distance: float = node.global_position.distance_squared_to(
				slots[index]
			)

			if distance < best_distance:
				best_distance = distance
				best_index = index

		if best_index < 0:
			continue

		taken.append(best_index)
		assignment[node] = slots[best_index]

	return assignment


## The direction a member at [param position] should face.
##
## Toward the centre, but never exactly - a group all staring dead centre looks
## like a ritual. The offset is derived from the position so it is stable.
static func get_facing(
	position: Vector2,
	centre: Vector2,
	wobble_degrees: float = 18.0
) -> Vector2:
	var to_centre: Vector2 = centre - position

	if to_centre.length_squared() < 0.001:
		return Vector2.DOWN

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(position.x) * 73856093 ^ int(position.y) * 19349663

	return to_centre.normalized().rotated(
		deg_to_rad(rng.randf_range(-wobble_degrees, wobble_degrees))
	)
