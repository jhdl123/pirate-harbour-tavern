class_name ActorMovement
extends Node

## Owns an actor's velocity and the single call to [method
## CharacterBody2D.move_and_slide].
##
## Everything that wants an actor to move asks this component for it. Nothing
## else in the project writes [member CharacterBody2D.velocity] on an AI actor,
## which is the whole point: the old customer wrote velocity from four different
## methods and from an avoidance callback, so "why did it stop" had four
## possible answers.
##
## This component knows nothing about paths, destinations or navigation. It
## converts "I would like to be moving this way at this speed" into a smooth,
## framerate-independent change to the body's actual velocity.
##
## Reusable by any [CharacterBody2D]: customers today, staff and NPCs later.
## Attach it, give it an [ActorMovementProfile], and drive it.


## Emitted when the actor starts moving after being stopped, and vice versa.
##
## Animation and footstep systems can hang off this without polling.
signal movement_state_changed(is_moving: bool)


@export_category("Wiring")

## The body to move. Defaults to this node's parent.
@export var body: CharacterBody2D

## Speed, acceleration and arrival tuning. A default is built when left empty.
@export var profile: ActorMovementProfile

## Whether this actor's motion is scaled by world time speed.
##
## True for anything the simulation drives - customers, staff, NPCs, animals.
## False for the player, who keeps walking at a constant real-world pace no
## matter how fast the tavern around them is running.
@export var follows_world_time: bool = true


var _desired_velocity: Vector2 = Vector2.ZERO
var _has_request_this_frame: bool = false
var _is_moving: bool = false


func _ready() -> void:
	if body == null:
		body = get_parent() as CharacterBody2D

	if body == null:
		push_error(
			"ActorMovement '%s' has no CharacterBody2D to move."
			% get_path()
		)

	if profile == null:
		profile = ActorMovementProfile.new()


# -----------------------------------------------------------------------------
# Driving
# -----------------------------------------------------------------------------

## Asks for a velocity this physics frame.
##
## The body will accelerate towards [param desired_velocity] rather than snap to
## it. Call every physics frame while moving; stop calling and the actor coasts
## to a halt through [method apply].
func request_velocity(
	desired_velocity: Vector2
) -> void:
	_desired_velocity = desired_velocity
	_has_request_this_frame = true


## Asks to move in a direction at a fraction of top speed.
##
## The common case, and the one that keeps callers out of the speed maths.
func request_direction(
	direction: Vector2,
	speed_ratio: float = 1.0
) -> void:
	request_velocity(
		direction.normalized()
		* profile.maximum_speed
		* clampf(speed_ratio, 0.0, 1.0)
	)


## Applies the pending request and moves the body.
##
## Must be called exactly once per physics frame, after any
## [method request_velocity]. When no request was made the actor decelerates to
## a stop, so an actor whose controller goes quiet slows down naturally instead
## of freezing mid-stride.
func apply(
	delta: float
) -> void:
	if body == null:
		return

	var target_velocity: Vector2 = _desired_velocity

	if not _has_request_this_frame:
		target_velocity = Vector2.ZERO

	var is_slowing: bool = (
		target_velocity.length_squared()
		< body.velocity.length_squared()
	)

	var rate: float = (
		profile.deceleration if is_slowing else profile.acceleration
	)

	# All of the acceleration and settling maths below runs in unscaled
	# "logical" space, so thresholds like settle_speed keep meaning the same
	# thing at any time speed. Only the movement actually applied to the body
	# is scaled, and it is restored immediately afterwards.
	var time_scale: float = _get_time_scale()

	body.velocity = body.velocity.move_toward(
		target_velocity,
		rate * delta * time_scale
	)

	# An avoidance solver will happily hand back a velocity of two pixels per
	# second forever. Treating that as stopped is what removes the shimmer of
	# an actor that has arrived but will not settle.
	if (
		body.velocity.length() < profile.settle_speed
		and target_velocity.length() < profile.settle_speed
	):
		body.velocity = Vector2.ZERO

	var logical_velocity: Vector2 = body.velocity

	body.velocity = logical_velocity * time_scale
	body.move_and_slide()
	body.velocity = logical_velocity

	_update_movement_state()

	_has_request_this_frame = false
	_desired_velocity = Vector2.ZERO


## Stops immediately, without deceleration.
##
## For state changes that must not be smoothed, such as being seated. Prefer
## simply not calling [method request_velocity] when a natural stop is wanted.
func stop() -> void:
	_desired_velocity = Vector2.ZERO
	_has_request_this_frame = false

	if body != null:
		body.velocity = Vector2.ZERO

	_update_movement_state()


## How fast the world is running for this actor.
##
## Returns 1.0 for an actor that opts out, so the player and any future
## real-time actor need no special case anywhere else in the framework.
func _get_time_scale() -> float:
	if not follows_world_time:
		return 1.0

	return WorldTime.get_world_time_scale()


func _update_movement_state() -> void:
	var moving_now: bool = (
		body != null
		and body.velocity.length() > profile.settle_speed
	)

	if moving_now == _is_moving:
		return

	_is_moving = moving_now

	movement_state_changed.emit(_is_moving)


# -----------------------------------------------------------------------------
# Reading
# -----------------------------------------------------------------------------

func is_moving() -> bool:
	return _is_moving


func get_velocity() -> Vector2:
	if body == null:
		return Vector2.ZERO

	return body.velocity


func get_speed() -> float:
	return get_velocity().length()


## Current speed as a fraction of the profile's top speed.
##
## Useful for driving walk animation blend or footstep rate.
func get_speed_ratio() -> float:
	if profile.maximum_speed <= 0.0:
		return 0.0

	return clampf(
		get_speed() / profile.maximum_speed,
		0.0,
		1.0
	)


func get_maximum_speed() -> float:
	return profile.maximum_speed
