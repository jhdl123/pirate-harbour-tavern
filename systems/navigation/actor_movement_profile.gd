class_name ActorMovementProfile
extends Resource

## How one kind of actor accelerates, turns and stops.
##
## Separated from [ActorNavigation] so that "how fast a body moves" and "where
## it is going" are tuned independently. A customer, a bartender carrying a full
## tray, a cellar hand pushing a barrel and a tavern cat can share every line of
## navigation code and differ only in this resource.
##
## Nothing here knows about paths. Feed [ActorMovement] a desired velocity and
## these values decide how the body actually gets there.


@export_category("Speed")

## Top speed in pixels per second.
@export_range(0.0, 1000.0, 1.0)
var maximum_speed: float = 120.0

## Speed used for the last leg of a move, such as shuffling into a seat.
##
## Applied through [member NavigationDestination.speed_scale] rather than
## automatically, so the actor decides when a careful approach is wanted.
@export_range(0.0, 1000.0, 1.0)
var careful_speed: float = 45.0


@export_category("Acceleration")

## Pixels per second squared while speeding up or changing direction.
##
## This is what removes twitching. The old code assigned velocity directly, so
## a path corner produced an instant reversal; ramping means a direction change
## is always a curve, however sharp the path is.
@export_range(1.0, 4000.0, 1.0)
var acceleration: float = 900.0

## Pixels per second squared while slowing down.
##
## Normally higher than [member acceleration]: stopping late looks like an
## overshoot, stopping early just looks careful.
@export_range(1.0, 4000.0, 1.0)
var deceleration: float = 1400.0


@export_category("Arrival")

## Distance from the destination at which the actor begins slowing.
##
## Speed falls off smoothly across this radius rather than being cut at the
## final step, which is what stops the overshoot-and-circle behaviour.
@export_range(0.0, 256.0, 1.0)
var slowing_radius: float = 48.0

## Lowest fraction of speed the slowing curve will produce.
##
## Without a floor an actor creeps towards its destination for a long time.
@export_range(0.0, 1.0, 0.01)
var minimum_slowing_ratio: float = 0.18


@export_category("Settling")

## Speeds below this are treated as stopped, in pixels per second.
##
## Kills the residual jitter that comes from an avoidance solver returning tiny
## non-zero velocities to an actor that has already arrived.
@export_range(0.0, 50.0, 0.5)
var settle_speed: float = 6.0


## The slowing multiplier for a given distance from the destination.
func get_arrival_speed_ratio(
	distance_to_destination: float
) -> float:
	if slowing_radius <= 0.0:
		return 1.0

	var ratio: float = clampf(
		distance_to_destination / slowing_radius,
		0.0,
		1.0
	)

	return maxf(ratio, minimum_slowing_ratio)
