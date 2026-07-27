class_name ApproachPoint
extends Marker2D

## "Stand here to use me." A world object's declared standing spot.
##
## The interaction framework already answers "where does the interaction
## happen" through [method Interactable.get_interaction_position]. That is a
## point on the object - a service slot, the middle of a keg - and is exactly
## where an actor must NOT stand.
##
## An approach point is the other half: the walkable spot an actor occupies in
## order to reach that interaction point. Placing them in a scene means a
## designer decides where staff queue at the cellar door, rather than the
## navigation code guessing an offset and hoping.
##
## Each one carries a [Reservable], so two bartenders never share a spot at the
## same barrel. Objects may have as many as they like; [ApproachPoint] provides
## the helpers for choosing between them.
##
## Nothing uses these yet - the chair still has its own staging position and the
## drinks station is reached by walking at it. They exist now so that storage,
## kegs, cleaning stations and crafting benches can be built without touching
## navigation again.


## Tag applied to the auto-created [Reservable].
const APPROACH_TAG: StringName = &"approach"


@export_category("Arrival")

## How close an actor must get before it counts as standing here.
@export_range(1.0, 64.0, 1.0)
var arrival_distance: float = 6.0

## Direction the actor should face on arrival, in degrees.
##
## Read by future animation and interaction code. Navigation does not use it,
## because facing is not implemented yet in the interaction framework either.
@export_range(-180.0, 180.0, 1.0)
var facing_degrees: float = 0.0


@export_category("Reservation")

## Whether a [Reservable] is created automatically when none is present.
##
## Off for decorative or shared spots that any number of actors may use.
@export var is_reservable: bool = true

## Seconds before an unclaimed reservation here expires.
@export_range(0.0, 300.0, 1.0)
var reservation_timeout_seconds: float = 30.0


var _reservable: Reservable = null


func _ready() -> void:
	_resolve_reservable()


func _resolve_reservable() -> void:
	for child: Node in get_children():
		var existing: Reservable = child as Reservable

		if existing != null:
			_reservable = existing
			return

	if not is_reservable:
		return

	# Created in code rather than required in every scene, so adding an approach
	# point to a new object is dropping in one node, not two.
	var reservable: Reservable = Reservable.new()

	reservable.name = "Reservable"
	reservable.reservation_tags = [APPROACH_TAG]
	reservable.reservation_timeout_seconds = reservation_timeout_seconds

	add_child(reservable)

	_reservable = reservable


## Where the actor should stand, in world space.
func get_navigation_position() -> Vector2:
	return global_position


## Which way the actor should face once here.
func get_facing_direction() -> Vector2:
	return Vector2.RIGHT.rotated(
		deg_to_rad(facing_degrees)
	)


## This point's claim, or null when it is shared.
func get_reservable() -> Reservable:
	return _reservable


func is_free() -> bool:
	if _reservable == null:
		return true

	return _reservable.is_free()


func is_held_by(
	actor: Node
) -> bool:
	if _reservable == null:
		return true

	return _reservable.is_held_by(actor)


## Claims this point for [param actor].
func reserve(
	actor: Node
) -> bool:
	if _reservable == null:
		return true

	return _reservable.reserve(actor)


func release(
	actor: Node = null
) -> void:
	if _reservable != null:
		_reservable.release(actor)


# -----------------------------------------------------------------------------
# Finding
# -----------------------------------------------------------------------------

## Every approach point under [param root].
##
## An object exposes its points by simply parenting them; there is no list to
## keep in step and no registration step to forget.
static func collect_from(
	root: Node
) -> Array[ApproachPoint]:
	var points: Array[ApproachPoint] = []

	if root == null:
		return points

	for child: Node in root.get_children():
		var point: ApproachPoint = child as ApproachPoint

		if point != null:
			points.append(point)

		points.append_array(collect_from(child))

	return points


## The nearest free approach point on [param root], claimed for [param actor].
##
## The single call a future bartender makes to walk up to a keg:
## reserve a spot, or find out there is not one.
static func reserve_nearest(
	root: Node,
	actor: Node,
	from_position: Vector2
) -> ApproachPoint:
	var points: Array[ApproachPoint] = collect_from(root)

	var remaining: Array[ApproachPoint] = []

	for point: ApproachPoint in points:
		if point.is_free():
			remaining.append(point)

	while not remaining.is_empty():
		var nearest: ApproachPoint = null
		var nearest_distance: float = INF

		for point: ApproachPoint in remaining:
			var distance: float = from_position.distance_squared_to(
				point.get_navigation_position()
			)

			if distance < nearest_distance:
				nearest_distance = distance
				nearest = point

		if nearest == null:
			return null

		if nearest.reserve(actor):
			return nearest

		remaining.erase(nearest)

	return null
