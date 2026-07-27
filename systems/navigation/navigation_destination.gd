class_name NavigationDestination
extends RefCounted

## One "go here" request, as a value object.
##
## Making the destination data rather than a bare [Vector2] is what lets a
## single [method ActorNavigation.move_to] serve every case the game will ever
## have: walk to a door, shuffle into a seat, stand at a drink station's
## approach point, hold a queue slot, reach a future crafting bench.
##
## Adding a new kind of destination later - a patrol node, a fleeing point, a
## position that must be faced a certain way - means adding a field here and a
## constructor, not another movement method on another actor.
##
## The destination also carries the [Reservable] it was granted from, so that
## whatever released or invalidated that reservation automatically invalidates
## the journey towards it.


## How the actor should treat reaching the destination.
enum ArrivalMode {
	## Stop as soon as the actor is within the arrival distance. Normal travel.
	NEAR,

	## Keep closing until the actor is genuinely on the spot.
	## Used for seats, where sitting slightly off the chair looks wrong.
	EXACT,
}


## Where to go, in world space.
var position: Vector2 = Vector2.ZERO

## How close counts as arrived, in pixels.
var arrival_distance: float = 8.0

## See [enum ArrivalMode].
var arrival_mode: ArrivalMode = ArrivalMode.NEAR

## Fraction of the profile's top speed used for this journey.
##
## The careful shuffle into a seat is the same navigation code at a lower
## number, not a separate movement routine.
var speed_scale: float = 1.0

## Optional node the destination tracks.
##
## When set, the destination position is refreshed from the node, so an actor
## can follow something that moves. Held weakly: a freed target invalidates the
## destination rather than crashing the actor.
var target_node: WeakRef = null

## Optional reservation backing this destination.
##
## When the reservation is lost - it expired, or something else claimed it - the
## destination is no longer valid and the actor recovers instead of walking to
## somewhere it can no longer use.
var reservation: Reservable = null

## Human-readable tag for debug output.
var label: String = ""


## A plain position.
static func to_position(
	world_position: Vector2,
	arrival: float = 8.0,
	destination_label: String = ""
) -> NavigationDestination:
	var destination: NavigationDestination = NavigationDestination.new()

	destination.position = world_position
	destination.arrival_distance = arrival
	destination.label = destination_label

	return destination


## A position that must be reached precisely and approached slowly.
##
## The seat case, and later the "stand exactly on this workstation spot" case.
static func to_exact_position(
	world_position: Vector2,
	arrival: float = 3.0,
	speed: float = 0.4,
	destination_label: String = ""
) -> NavigationDestination:
	var destination: NavigationDestination = to_position(
		world_position,
		arrival,
		destination_label
	)

	destination.arrival_mode = ArrivalMode.EXACT
	destination.speed_scale = speed

	return destination


## An [ApproachPoint] on a world object, with its reservation attached.
##
## This is the constructor that future staff will use for nearly everything:
## stations, storage, kegs and crafting benches all expose approach points.
static func to_approach_point(
	approach_point: ApproachPoint
) -> NavigationDestination:
	if approach_point == null:
		return null

	var destination: NavigationDestination = to_position(
		approach_point.get_navigation_position(),
		approach_point.arrival_distance,
		approach_point.name
	)

	destination.reservation = approach_point.get_reservable()
	destination.target_node = weakref(approach_point)

	return destination


## Refreshes [member position] from [member target_node], if there is one.
##
## Returns false when the tracked node has gone, which the actor treats as the
## destination becoming invalid.
func refresh() -> bool:
	if target_node == null:
		return true

	var node: Node2D = target_node.get_ref() as Node2D

	if node == null or not is_instance_valid(node):
		return false

	if node is ApproachPoint:
		position = (node as ApproachPoint).get_navigation_position()
	else:
		position = node.global_position

	return true


## True when this destination can still be walked to.
##
## Checks the tracked node and the reservation together, so an actor never
## continues towards a seat that was taken from it or an object that was
## removed from the world.
func is_valid(
	actor: Node
) -> bool:
	if not refresh():
		return false

	if reservation == null:
		return true

	if not is_instance_valid(reservation):
		return false

	return reservation.is_held_by(actor)


func get_label() -> String:
	if label.is_empty():
		return str(position)

	return label
