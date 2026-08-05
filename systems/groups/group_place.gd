class_name GroupPlace
extends RefCounted

## Where a group has settled, seated or standing.
##
## Seated and standing visits differ in how a place is FOUND and RESERVED, not
## in what a place provides. Both give a centre, a position per member, a point
## to put a shared drink, and a way to let go. Hiding the difference behind one
## object is what stops the group state machine branching on place type at
## every single step.
##
## Reservation is atomic by construction: [method reserve_seated] books every
## chair or rolls back all of them. A group never ends up holding half a table
## while its remaining members wander off to look elsewhere.


enum Kind {
	NONE,
	SEATED,
	STANDING,
}


var kind: Kind = Kind.NONE

## The table, when seated.
var table: Node2D = null

## Chairs booked for this group, in member order.
var chairs: Array = []

## The standing area, when standing.
var standing_area: GroupStandingArea = null

## Position each member should occupy, in member order.
var slots: Array[Vector2] = []

## Who holds the reservations. Released against the same node.
var holder: Node = null


func is_valid() -> bool:
	return kind != Kind.NONE


func is_seated() -> bool:
	return kind == Kind.SEATED


func is_standing() -> bool:
	return kind == Kind.STANDING


func get_capacity() -> int:
	if is_seated():
		return chairs.size()

	return slots.size()


## Middle of the place, used for facing and for shared-serving placement.
func get_centre() -> Vector2:
	if is_standing() and standing_area != null:
		return standing_area.get_centre_position()

	if is_seated() and table != null:
		return table.global_position

	if not slots.is_empty():
		var sum: Vector2 = Vector2.ZERO

		for slot: Vector2 in slots:
			sum += slot

		return sum / float(slots.size())

	return Vector2.ZERO


## Where a shared pitcher, bowl or cask is placed.
func get_serving_position() -> Vector2:
	if is_standing() and standing_area != null:
		return standing_area.get_serving_position()

	return get_centre()


## Where staff stand to put a shared keg down.
##
## Not the centre itself: a worker standing on the delivery point has nowhere
## to place the keg, and the keg's own sprite would end up underneath them.
## This picks the widest gap between the members' current positions and offers
## a spot just outside the ring, on the navigation map.
##
## [param occupied] is where the members are standing right now - during a
## delivery that is their stepped-back ring, not their drinking slots.
func get_delivery_approach_position(
	occupied: Array[Vector2],
	approach_distance: float = 30.0
) -> Vector2:
	var centre: Vector2 = get_serving_position()

	if occupied.is_empty():
		return _project_approach(centre + Vector2.RIGHT * approach_distance, centre)

	# Sort the members by angle around the centre, then take the middle of the
	# widest angular gap: that is the clearest side to walk in from.
	var angles: Array[float] = []

	for point: Vector2 in occupied:
		angles.append((point - centre).angle())

	angles.sort()

	var best_angle: float = angles[0] + PI
	var best_gap: float = 0.0

	for index: int in range(angles.size()):
		var current: float = angles[index]
		var next: float = (
			angles[(index + 1) % angles.size()]
			+ (TAU if index + 1 >= angles.size() else 0.0)
		)

		var gap: float = next - current

		if gap > best_gap:
			best_gap = gap
			best_angle = current + gap * 0.5

	var radius: float = _get_average_radius(occupied, centre)

	return _project_approach(
		centre + Vector2.RIGHT.rotated(best_angle) * (radius + approach_distance),
		centre
	)


func _get_average_radius(occupied: Array[Vector2], centre: Vector2) -> float:
	if occupied.is_empty():
		return 40.0

	var total: float = 0.0

	for point: Vector2 in occupied:
		total += point.distance_to(centre)

	return total / float(occupied.size())


func _project_approach(target: Vector2, fallback: Vector2) -> Vector2:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree

	if tree == null or tree.root == null:
		return target

	var map: RID = tree.root.world_2d.navigation_map

	if not map.is_valid():
		return target

	var closest: Vector2 = NavigationServer2D.map_get_closest_point(map, target)

	# An empty navigation map answers every query with the origin, which would
	# send staff to the far corner of the world instead of to the group.
	if closest.is_zero_approx() and not target.is_zero_approx():
		return target

	# Too far to be the same place: keep the geometric answer rather than a
	# projection onto some unrelated bit of floor.
	if closest.distance_to(target) > fallback.distance_to(target) + 64.0:
		return target

	return closest


## Where members walk to before taking their positions.
func get_entry_position() -> Vector2:
	if is_standing() and standing_area != null:
		return standing_area.get_entry_position()

	return get_centre()


## The position assigned to member [param index].
func get_slot_for(index: int) -> Vector2:
	if index < 0 or index >= slots.size():
		return get_centre()

	return slots[index]


## The chair assigned to member [param index], or null when standing.
func get_chair_for(index: int) -> Node:
	if not is_seated() or index < 0 or index >= chairs.size():
		return null

	return chairs[index]


func get_place_id() -> StringName:
	if is_standing() and standing_area != null:
		return standing_area.area_id

	if is_seated() and table != null:
		return StringName(table.name)

	return &""


# --- Building ----------------------------------------------------------------

## Books [param required] seats at [param candidate_table], all or nothing.
##
## Returns a valid place, or an invalid one having released anything it took.
## The rollback is the whole point: a partially-reserved table is worse than no
## table, because the seats are unavailable to everyone including the group
## that half-booked them.
static func reserve_seated(
	candidate_table: Node2D,
	required: int,
	reserving_holder: Node
) -> GroupPlace:
	var place: GroupPlace = GroupPlace.new()

	if candidate_table == null or required <= 0 or reserving_holder == null:
		return place

	if not candidate_table.has_method(&"get_available_chairs"):
		return place

	var available: Array = candidate_table.call(&"get_available_chairs")

	if available.size() < required:
		return place

	var booked: Array = []

	for index: int in range(required):
		var chair: Node = available[index]

		if chair == null or not chair.has_method(&"assign_customer"):
			_rollback(booked, reserving_holder)
			return place

		if not chair.call(&"assign_customer", reserving_holder):
			_rollback(booked, reserving_holder)
			return place

		booked.append(chair)

	place.kind = Kind.SEATED
	place.table = candidate_table
	place.chairs = booked
	place.holder = reserving_holder

	var positions: Array[Vector2] = []

	for chair: Variant in booked:
		var chair_node: Node2D = chair as Node2D

		positions.append(
			chair_node.global_position if chair_node != null else Vector2.ZERO
		)

	place.slots = positions

	return place


## Books [param area] for a group of [param size].
static func reserve_standing(
	area: GroupStandingArea,
	size: int,
	reserving_holder: Node,
	group_id: StringName
) -> GroupPlace:
	var place: GroupPlace = GroupPlace.new()

	if area == null or size <= 0 or reserving_holder == null:
		return place

	if not area.reserve_for(reserving_holder, group_id):
		return place

	place.kind = Kind.STANDING
	place.standing_area = area
	place.holder = reserving_holder
	place.slots = area.get_formation_slots(size)

	return place


## Releases everything this place holds. Safe to call more than once.
##
## [param members] are the customers the chairs were handed to. They must be
## passed in, because a transferred chair is owned by its member and a release
## from the group alone is silently ignored - which is exactly how seating
## drained away one visit at a time.
func release(members: Array = []) -> void:
	if holder == null:
		kind = Kind.NONE
		return

	if is_seated():
		_release_chairs(members)
		chairs.clear()
		table = null

	if is_standing() and standing_area != null:
		standing_area.release_for(holder)
		standing_area = null

	slots.clear()
	holder = null
	kind = Kind.NONE


## Frees every chair, whoever ended up holding it.
##
## Tries the group first, then each member, then forces it. The force is not a
## shortcut: by the time a group is releasing its place the visit is over, so a
## chair still booked to a member who never got up is a leak, not a claim worth
## respecting.
func _release_chairs(members: Array) -> void:
	for entry: Variant in chairs:
		var chair: Node = entry as Node

		if chair == null:
			continue

		if chair.has_method(&"release_reservation"):
			chair.call(&"release_reservation", holder)

			for member: Variant in members:
				var member_node: Node = member as Node

				if member_node != null:
					chair.call(&"release_reservation", member_node)

		if chair.has_method(&"is_available") and chair.call(&"is_available"):
			continue

		# Still held. A chair the group booked belongs to nobody once the
		# group is gone.
		if chair.has_method(&"force_release_reservation"):
			chair.call(&"force_release_reservation")


static func _rollback(booked: Array, reserving_holder: Node) -> void:
	for chair: Variant in booked:
		var node: Node = chair as Node

		if node == null:
			continue

		# Chair exposes release_reservation(holder); fall back to a plain
		# Reservable for anything else that might be booked as a seat.
		if node.has_method(&"release_reservation"):
			node.call(&"release_reservation", reserving_holder)
		elif node.has_method(&"release"):
			node.call(&"release", reserving_holder)


## Finds a table that can seat [param required] and books it.
##
## Prefers the table with the fewest spare seats that still fits, so a pair
## does not take the only four-seater a foursome could have used.
static func find_and_reserve_table(
	tree: SceneTree,
	required: int,
	reserving_holder: Node
) -> GroupPlace:
	var candidates: Array[Node2D] = []

	for node: Node in tree.get_nodes_in_group(&"tables"):
		var candidate: Node2D = node as Node2D

		if candidate == null or not candidate.has_method(&"get_available_chairs"):
			continue

		if candidate.call(&"get_available_chairs").size() >= required:
			candidates.append(candidate)

	candidates.sort_custom(
		func(a: Node2D, b: Node2D) -> bool:
			return (
				a.call(&"get_available_chairs").size()
				< b.call(&"get_available_chairs").size()
			)
	)

	for candidate: Node2D in candidates:
		var place: GroupPlace = reserve_seated(
			candidate, required, reserving_holder
		)

		if place.is_valid():
			return place

	return GroupPlace.new()
