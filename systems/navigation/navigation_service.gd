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
