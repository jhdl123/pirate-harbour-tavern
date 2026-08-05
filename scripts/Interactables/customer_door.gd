class_name CustomerDoor
extends Node2D

## The way in and out of the tavern.
##
## Positions are spread over a small area rather than being one exact point.
## That matters more than it sounds: every arrival used to spawn on the same
## coordinate and every departure used to walk to the same coordinate, so
## arrivals and leavers converged on one spot, avoidance jammed them together,
## and nobody could reach their arrival tolerance. Groups made it far worse by
## putting several customers there at once.
##
## Offsets are derived from the actor rather than randomised per call, so a
## customer keeps the same target for its whole walk. A jittering destination
## would cause constant re-pathing, which is the problem this is meant to fix.


@onready var outside_point: Marker2D = $OutsidePoint
@onready var inside_point: Marker2D = $InsidePoint


func _ready() -> void:
	# Findable by group rather than by scene path, so it still resolves when
	# the tavern is nested inside another scene - as it is under test.
	add_to_group(&"customer_door")


@export_category("Spacing")

## How far apart arrivals may spawn, in pixels.
@export_range(0.0, 128.0, 1.0)
var spawn_spread: float = 18.0

## How far apart customers may stand at the inside of the door.
##
## The important one. Leavers and arrivals both pass through here, so giving
## each a slightly different point is what stops the doorway gridlocking.
@export_range(0.0, 128.0, 1.0)
var inside_spread: float = 24.0

## How far apart customers may walk to when leaving.
@export_range(0.0, 128.0, 1.0)
var exit_spread: float = 20.0


## Stable queue point outside the tavern. The queue extends away from the
## inside marker so waiting members never surround or block the doorway.
func get_queue_position(index: int, spacing: float) -> Vector2:
	var outward: Vector2 = (
		outside_point.global_position - inside_point.global_position
	).normalized()

	if outward.length_squared() < 0.001:
		outward = Vector2.DOWN

	return outside_point.global_position + outward * spacing * float(index + 1)


## Compact waiting formation for a group. Members appear as one party rather
## than a long single-file queue, while still keeping enough centre-to-centre
## separation for their 12 px avoidance radii. Entry remains one-at-a-time.
func get_group_queue_position(
	index: int,
	spacing: float,
	columns: int = 2
) -> Vector2:
	var outward: Vector2 = (
		outside_point.global_position - inside_point.global_position
	).normalized()

	if outward.length_squared() < 0.001:
		outward = Vector2.DOWN

	var lateral: Vector2 = Vector2(-outward.y, outward.x)
	var safe_columns: int = maxi(columns, 1)
	var row: int = floori(float(index) / float(safe_columns))
	var column: int = index % safe_columns
	var lateral_offset: float = (
		float(column) - (float(safe_columns - 1) * 0.5)
	) * spacing

	# Keep the first row one spacing outside the marker and build backwards.
	return (
		outside_point.global_position
		+ outward * spacing * float(row + 1)
		+ lateral * lateral_offset
	)


func get_spawn_position() -> Vector2:
	return _scatter(outside_point.global_position, spawn_spread, randi())


## The inside of the door, offset per actor.
##
## Pass the customer so its point stays put for the whole walk. Called without
## one it returns the exact centre, which keeps older callers working.
func get_inside_position(actor: Node = null) -> Vector2:
	if actor == null:
		return inside_point.global_position

	return _scatter(
		inside_point.global_position,
		inside_spread,
		_seed_for(actor)
	)


func get_exit_position(actor: Node = null) -> Vector2:
	if actor == null:
		return outside_point.global_position

	return _scatter(
		outside_point.global_position,
		exit_spread,
		_seed_for(actor)
	)


## A point within [param spread] of [param centre], stable for [param seed_value].
func _scatter(
	centre: Vector2,
	spread: float,
	seed_value: int
) -> Vector2:
	if spread <= 0.0:
		return centre

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value

	var angle: float = rng.randf() * TAU
	# Square root keeps points evenly spread over the disc instead of
	# clustering them in the middle, which would defeat the purpose.
	var distance: float = sqrt(rng.randf()) * spread

	return centre + Vector2(cos(angle), sin(angle)) * distance


func _seed_for(actor: Node) -> int:
	return int(actor.get_instance_id())
