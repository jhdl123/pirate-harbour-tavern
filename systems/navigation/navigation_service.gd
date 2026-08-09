class_name NavigationService
extends RefCounted

## Shared helpers for talking to [NavigationServer2D].
##
## Every actor used to repeat the same three chores: wait for the navigation map
## to synchronise, project a requested position onto the mesh, and check whether
## a destination was reachable. Doing that per actor meant every customer span
## its own await loop on spawn.
##
## These are static, cheap, and stateless. Nothing here allocates, and nothing
## here is customer-specific.


## How far a requested point may be from the mesh before it is worth a warning.
const PROJECTION_WARNING_DISTANCE: float = 12.0


## True when [param map] has synchronised at least once.
##
## A navigation map reports iteration 0 until the server has processed it, and
## queries against it silently return nothing. Everything else in this class
## assumes the map is ready.
static func is_map_ready(
	map: RID
) -> bool:
	if not map.is_valid():
		return false

	return NavigationServer2D.map_get_iteration_id(map) != 0


## Moves [param point] onto the navigation mesh.
##
## Requested positions come from world objects - a seat, a door, an approach
## point - and are often a pixel or two off the walkable surface. Projecting
## once when the destination is set is far cheaper than discovering it later as
## an unreachable path.
static func project_to_mesh(
	map: RID,
	point: Vector2
) -> Vector2:
	if not is_map_ready(map):
		return point

	return NavigationServer2D.map_get_closest_point(map, point)


## Projects [param point] onto the mesh, stepping far enough in to stand on.
##
## map_get_closest_point() returns the nearest point ON the mesh, which for
## anything outside a polygon is a point on its EDGE. An actor cannot hold a
## boundary point - avoidance nudges it off, the arrival check never passes,
## and the executor re-issues the same move forever.
##
## The step is taken along the direction the mesh already lies in, NOT toward
## the approaching actor. Biasing toward the actor looks equivalent and is not:
## the bar counter's deposit point is deliberately on the staff side, and a
## bartender standing south of the bar dragged it across to the customer side,
## stranding him on the wrong side of his own counter.
##
## [param from_position] is used only to break ties when the object sits
## exactly between two walkable areas.
## How many directions to sample when looking for interior floor.
const SAMPLE_DIRECTIONS: int = 8

## How many rings outward to try before giving up.
const SAMPLE_RINGS: int = 4

## Ring spacing for the fallback search around an object, in pixels.
const FALLBACK_STEP: float = 12.0

## How far the fallback search will look before giving up.
const FALLBACK_RINGS: int = 12

## Directions sampled per fallback ring. Finer than the edge search because
## the usable floor may be a narrow strip.
const FALLBACK_DIRECTIONS: int = 16

## Walkable clearance required around a stand, in pixels.
##
## Roughly an actor's avoidance radius: less than this and the solver can push
## the actor off the mesh while it waits.
const INTERIOR_MARGIN: float = 12.0


static func project_to_mesh_from(
	map: RID,
	point: Vector2,
	from_position: Vector2,
	inset: float = 14.0
) -> Vector2:
	if not is_map_ready(map):
		return point

	var nearest: Vector2 = NavigationServer2D.map_get_closest_point(map, point)

	if nearest.is_zero_approx() and not point.is_zero_approx():
		return point

	# Already standable: leave it exactly where the caller asked. Moving a
	# point that is already inside a polygon only pushes actors away from the
	# thing they came to use, and can cross a counter.
	if nearest.distance_to(point) <= 1.0:
		return point

	# Step off the edge into the polygon. Which way "in" lies cannot be asked
	# of NavigationServer2D, so sample around the edge point and keep the
	# nearest candidate that is both INTERIOR and REACHABLE.
	#
	# Reachability is the half that matters most here. This tavern has a tiny
	# walkable pocket behind the bar at roughly (521, 80) - a gap in the
	# counter - which is on the mesh but connects to nothing. A stand chosen
	# there is where "the barman ended up stuck on the wrong side of the bar"
	# came from: he could be sent in and then had nowhere to path out to.
	# Nearest-to-the-request keeps the stand from wandering to another object.
	var best: Vector2 = nearest
	var best_distance: float = INF

	for ring: int in range(1, SAMPLE_RINGS + 1):
		var radius: float = inset * float(ring)

		for i: int in range(SAMPLE_DIRECTIONS):
			var angle: float = TAU * float(i) / float(SAMPLE_DIRECTIONS)
			var candidate: Vector2 = nearest + Vector2.RIGHT.rotated(angle) * radius

			if not _is_interior(map, candidate):
				continue

			if not is_reachable(map, from_position, candidate):
				continue

			var distance: float = candidate.distance_to(point)

			if distance < best_distance:
				best_distance = distance
				best = candidate

		if best_distance < INF:
			# Closest usable ring wins; wider rings only move staff further
			# from the thing they came to use.
			break

	if best_distance < INF:
		return best

	# Nothing around the object is both standable and connected to where the
	# actor is. Falling back to `nearest` here is what sent staff into the
	# pocket behind the bar. Instead, walk in from the actor's own side and
	# stop at the last spot they can actually hold.
	return _closest_approach_from(map, point, from_position)


## The nearest standable spot to [param point] that the actor can reach.
##
## Searches outward from the OBJECT, not along the actor's approach line. That
## distinction matters: walking in from the actor gives a different answer for
## every starting position, so two bartenders - or the same one arriving from
## a different direction - would work the same slot from spots 80px apart.
## Sampling around the object is deterministic, and reachability still keeps
## the answer on the actor's side of any wall.
static func _closest_approach_from(
	map: RID,
	point: Vector2,
	from_position: Vector2
) -> Vector2:
	var best: Vector2 = from_position
	var best_distance: float = INF

	for ring: int in range(1, FALLBACK_RINGS + 1):
		var radius: float = FALLBACK_STEP * float(ring)

		for i: int in range(FALLBACK_DIRECTIONS):
			var angle: float = TAU * float(i) / float(FALLBACK_DIRECTIONS)
			var candidate: Vector2 = point + Vector2.RIGHT.rotated(angle) * radius

			if not _is_interior(map, candidate):
				continue

			if not is_reachable(map, from_position, candidate):
				continue

			var distance: float = candidate.distance_to(point)

			if distance < best_distance:
				best_distance = distance
				best = candidate

		if best_distance < INF:
			break

	return best


## Whether [param point] is on the mesh with walkable room all around it.
##
## A point ON the mesh is not necessarily a point an actor can HOLD: avoidance
## pushes it a few pixels and a boundary point ends up outside. Probing a small
## ring around it is the difference between "walkable" and "standable".
static func _is_interior(
	map: RID,
	point: Vector2
) -> bool:
	for i: int in range(SAMPLE_DIRECTIONS):
		var angle: float = TAU * float(i) / float(SAMPLE_DIRECTIONS)
		var probe: Vector2 = point + Vector2.RIGHT.rotated(angle) * INTERIOR_MARGIN
		var closest: Vector2 = NavigationServer2D.map_get_closest_point(map, probe)

		if closest.distance_to(probe) > 0.5:
			return false

	return true


## Distance between a requested point and where it actually landed.
##
## A large value means the caller asked for somewhere the actor cannot stand,
## which is usually a mis-placed marker rather than a navigation problem.
static func get_projection_error(
	map: RID,
	point: Vector2
) -> float:
	return point.distance_to(
		project_to_mesh(map, point)
	)


## True when a straight navigation path exists between the two points.
##
## Uses a path query rather than the agent, so it can be asked before an actor
## commits to a destination - useful for scoring seats or workstations.
static func is_reachable(
	map: RID,
	from_position: Vector2,
	to_position: Vector2
) -> bool:
	if not is_map_ready(map):
		return false

	var path: PackedVector2Array = NavigationServer2D.map_get_path(
		map,
		from_position,
		to_position,
		true
	)

	return not path.is_empty()


## Rough path length, for scoring destinations without walking them.
##
## Returns [code]INF[/code] when there is no path, so callers can sort by this
## value and have unreachable options fall to the bottom naturally.
static func get_path_length(
	map: RID,
	from_position: Vector2,
	to_position: Vector2
) -> float:
	if not is_map_ready(map):
		return INF

	var path: PackedVector2Array = NavigationServer2D.map_get_path(
		map,
		from_position,
		to_position,
		true
	)

	if path.size() < 2:
		return INF

	var total: float = 0.0

	for index: int in range(1, path.size()):
		total += path[index - 1].distance_to(path[index])

	return total


## A walkable point near [param around_position], for spreading actors out.
##
## Used for queue slots and for nudging an actor that has wedged itself against
## geometry. Falls back to the projected centre when no offset works.
static func find_free_point_near(
	map: RID,
	around_position: Vector2,
	search_radius: float,
	attempts: int = 8
) -> Vector2:
	var centre: Vector2 = project_to_mesh(map, around_position)

	if not is_map_ready(map) or search_radius <= 0.0:
		return centre

	for attempt: int in range(attempts):
		var angle: float = TAU * float(attempt) / float(attempts)

		var candidate: Vector2 = (
			around_position
			+ Vector2.RIGHT.rotated(angle) * search_radius
		)

		var projected: Vector2 = project_to_mesh(map, candidate)

		if projected.distance_to(candidate) <= 1.0:
			return projected

	return centre
