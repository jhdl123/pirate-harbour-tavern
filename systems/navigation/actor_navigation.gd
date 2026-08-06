class_name ActorNavigation
extends Node

## Turns "go to this destination" into smooth, avoidant, recoverable movement.
##
## This is the reusable brain of the navigation framework. It owns the actor's
## [NavigationAgent2D], follows the path, steers around other actors, slows into
## an arrival, and digs itself out when it gets stuck. It hands the resulting
## velocity to [ActorMovement], which is the only thing that touches the body.
##
## It knows nothing about customers, seats, drinks or tables. It is driven
## entirely through [method move_to] and reports back through signals, so a
## customer, a bartender, a cellar hand and a tavern cat differ only in which
## destinations they ask for and what they do when they arrive.
##
## [b]What this fixes[/b]
##
## [codeblock]
## unexpected pauses    setting a destination no longer awaits physics frames
##                      while the actor stands still
## twitching            steering direction is smoothed, so a path corner flip
##                      is a curve rather than an instant reversal
## overshooting         speed falls off across a slowing radius instead of
##                      being cut at the final step
## clipping             avoidance stays on for the whole journey, including the
##                      final approach, which used to disable it
## getting stuck        recovery escalates sidestep -> repath -> fail, rather
##                      than immediately re-planning the whole route
## fighting             a parked actor becomes a high-priority obstacle that
##                      others flow around instead of shoving
## cost                 repathing is throttled, so a busy room does not
##                      re-plan every actor every frame
## [/codeblock]


## The actor reached its destination.
signal destination_reached(destination: NavigationDestination)

## The actor gave up. [param reason] is one of
## [code]unreachable[/code], [code]blocked[/code] or [code]invalid[/code].
signal destination_failed(
	destination: NavigationDestination,
	reason: StringName
)

## Recovery began. Useful for debug overlays and for AI that wants to re-plan.
signal recovery_started(attempt: int)

## A new path was calculated.
signal path_recalculated(destination: NavigationDestination)


enum NavigationState {
	## No destination. The body coasts to a stop.
	IDLE,

	## Following a path.
	TRAVELLING,

	## Temporarily steering sideways to clear a jam.
	SIDESTEPPING,

	## Deliberately stopped somewhere permanent, such as a seat.
	PARKED,
}


## Reason codes emitted with [signal destination_failed].
const REASON_UNREACHABLE: StringName = &"unreachable"
const REASON_BLOCKED: StringName = &"blocked"
const REASON_INVALID: StringName = &"invalid"

## Seconds the avoidance solver may return nothing while the actor wants to
## move, before its output is ignored.
##
## Godot's NavigationAgent2D stops producing a useful safe velocity once it
## considers itself arrived, which is exactly when the actor still has a few
## pixels left to cover. Without this guard the actor stalls short of every
## destination forever.
const SOLVER_STALL_GRACE: float = 0.15

## How far past the final approach radius a finished path is still trusted.
##
## A path that ends short by a little is geometry - an off-mesh seat, a corner
## the mesh does not quite reach. A path that ends short by a lot means the
## destination genuinely cannot be reached, which is recovery's job.
const FINISHED_PATH_TOLERANCE: float = 2.5

## Seconds an actor may sit motionless inside its final approach before the
## destination is treated as reached.
##
## Stopping a pixel or two short is invisible. Never arriving is not.
const SETTLED_ARRIVAL_SECONDS: float = 0.35


@export_category("Wiring")

## The actor. Defaults to this node's parent.
@export var body: CharacterBody2D

## The agent to path with. Found among the body's children when left empty.
@export var agent: NavigationAgent2D

## The component that owns the body's velocity. Found as a sibling when empty.
@export var movement: ActorMovement

## Avoidance, path following and recovery tuning. A default is built if empty.
@export var profile: ActorNavigationProfile


@export_category("Debug")

## Prints navigation events for this actor.
@export var show_navigation_messages: bool = false


var _state: NavigationState = NavigationState.IDLE
var _destination: NavigationDestination = null

var _target_pending: bool = false
var _time_since_repath: float = 0.0
var _last_pathed_position: Vector2 = Vector2.ZERO

var _steering_direction: Vector2 = Vector2.ZERO
var _safe_velocity: Vector2 = Vector2.ZERO

## Time scale applied when the agent was last given a velocity.
##
## The avoidance solver must see real speeds or it plans for a world moving at
## a fraction of the true rate. The answer comes back in that same scaled
## space, so it is divided out again here and everything downstream keeps
## working in unscaled logical units.
var _agent_velocity_scale: float = 1.0
var _has_safe_velocity: bool = false

var _stuck_elapsed: float = 0.0
var _stuck_check_position: Vector2 = Vector2.ZERO
var _stuck_checks: int = 0
var _recovery_attempts: int = 0

var _sidestep_direction: Vector2 = Vector2.ZERO
var _sidestep_remaining: float = 0.0
var _sidestep_sign: float = 1.0

var _travel_avoidance_priority: float = 0.5

## How close the actor must be before it stops following the path and steers
## straight at the destination. Recomputed whenever a path is requested.
var _final_approach_radius: float = 0.0

var _is_in_final_approach: bool = false
var _desired_velocity: Vector2 = Vector2.ZERO
var _solver_stall_elapsed: float = 0.0
var _settled_elapsed: float = 0.0


func _ready() -> void:
	if body == null:
		body = get_parent() as CharacterBody2D

	if profile == null:
		profile = ActorNavigationProfile.new()

	if agent == null:
		agent = _find_agent()

	if movement == null:
		movement = _find_movement()

	if body == null or agent == null or movement == null:
		push_error(
			"ActorNavigation '%s' is missing a body, agent or movement component."
			% get_path()
		)
		return

	_apply_agent_profile()

	if not agent.velocity_computed.is_connected(_on_velocity_computed):
		agent.velocity_computed.connect(_on_velocity_computed)

	_stuck_check_position = body.global_position


func _find_agent() -> NavigationAgent2D:
	if body == null:
		return null

	for child: Node in body.get_children():
		var found: NavigationAgent2D = child as NavigationAgent2D

		if found != null:
			return found

	return null


func _find_movement() -> ActorMovement:
	var parent: Node = get_parent()

	if parent == null:
		return null

	for sibling: Node in parent.get_children():
		var found: ActorMovement = sibling as ActorMovement

		if found != null:
			return found

	return null


## Pushes the profile onto the agent.
##
## Called on ready and again whenever the profile is swapped, so an actor can
## change role at runtime - a customer hired as staff keeps its body and gains
## a different navigation personality.
func _apply_agent_profile() -> void:
	_travel_avoidance_priority = profile.avoidance_priority

	agent.avoidance_enabled = true
	agent.radius = profile.avoidance_radius
	agent.avoidance_priority = profile.avoidance_priority
	agent.neighbor_distance = profile.neighbour_distance
	agent.max_neighbors = profile.maximum_neighbours
	agent.time_horizon_agents = profile.time_horizon_agents
	agent.time_horizon_obstacles = profile.time_horizon_obstacles

	agent.path_desired_distance = profile.path_desired_distance
	agent.target_desired_distance = profile.target_desired_distance
	agent.path_max_distance = profile.path_maximum_distance

	if movement != null:
		agent.max_speed = movement.get_maximum_speed()


## Replaces the navigation profile at runtime.
func set_profile(
	new_profile: ActorNavigationProfile
) -> void:
	if new_profile == null:
		return

	profile = new_profile

	_apply_agent_profile()


# -----------------------------------------------------------------------------
# Commands
# -----------------------------------------------------------------------------

## Sends the actor to [param destination].
##
## Returns immediately and never stops the actor mid-stride. If the navigation
## map is not synchronised yet the request is held and applied on the first
## frame it can be, while the actor carries on with whatever it was doing.
##
## That is the single biggest behavioural change in this framework: the old code
## awaited two physics frames with movement halted every time a destination
## changed, which is where most of the "unexpected pause" came from.
func move_to(
	destination: NavigationDestination
) -> bool:
	if destination == null:
		push_warning(
			"ActorNavigation '%s' was given a null destination."
			% get_path()
		)
		return false

	if agent == null or body == null:
		return false

	_destination = destination
	_state = NavigationState.TRAVELLING

	_record_journey_start(destination.position)

	_recovery_attempts = 0
	_stuck_checks = 0
	_stuck_elapsed = 0.0
	_stuck_check_position = body.global_position

	_sidestep_remaining = 0.0
	_solver_stall_elapsed = 0.0
	_settled_elapsed = 0.0
	_is_in_final_approach = false

	_restore_travel_priority()
	_request_path(true)

	if show_navigation_messages:
		print(
			body.name,
			" navigating to ",
			_destination.get_label()
		)

	return true


## Sends the actor to a plain world position.
func move_to_position(
	world_position: Vector2,
	arrival_distance: float = 8.0,
	destination_label: String = ""
) -> bool:
	return move_to(
		NavigationDestination.to_position(
			world_position,
			arrival_distance,
			destination_label
		)
	)


## Sends the actor to a reserved [ApproachPoint].
##
## The call future staff will make for stations, storage, kegs and benches.
func move_to_approach_point(
	approach_point: ApproachPoint
) -> bool:
	return move_to(
		NavigationDestination.to_approach_point(approach_point)
	)


## Abandons the current destination and coasts to a stop.
func stop() -> void:
	_destination = null
	_target_pending = false
	_state = NavigationState.IDLE
	_sidestep_remaining = 0.0

	if movement != null:
		movement.stop()


## Stops here and becomes something other actors path around.
##
## Used when an actor settles somewhere for a while: a seated customer, a
## bartender working a station, an NPC leaning on a wall. Raising avoidance
## priority to the maximum means the solver treats this actor as an obstacle to
## flow around rather than a body to push through, which is what stops seated
## customers being shunted out of their chairs in a busy room.
func park() -> void:
	_destination = null
	_target_pending = false
	_state = NavigationState.PARKED
	_sidestep_remaining = 0.0

	if movement != null:
		movement.stop()

	if agent != null:
		agent.velocity = Vector2.ZERO

		# Parked actors YIELD rather than shove.
		#
		# parked_avoidance_priority defaulted to 1.0, which in Godot's solver
		# means "everyone else moves around me". A seated customer therefore
		# pushed approaching actors away - that is how staff carrying kegs
		# got shunted off their delivery approach on 4 August. A parked actor
		# holds its position through the physics body; it does not need
		# avoidance priority to do that, and having it actively hurts.
		agent.avoidance_priority = profile.parked_yield_priority


## Returns a parked actor to normal traffic.
func unpark() -> void:
	_restore_travel_priority()

	if _state == NavigationState.PARKED:
		_state = NavigationState.IDLE


func _restore_travel_priority() -> void:
	if agent != null:
		agent.avoidance_priority = _travel_avoidance_priority


# -----------------------------------------------------------------------------
# Frame
# -----------------------------------------------------------------------------

func _physics_process(
	delta: float
) -> void:
	if body == null or agent == null or movement == null:
		return

	# The simulation decides whether actors think, not the actor. Returning
	# without calling movement.apply() leaves the body's velocity intact, so a
	# paused actor resumes mid-stride instead of restarting from a standstill.
	if not Simulation.updates_actors():
		return

	_time_since_repath += delta

	match _state:
		NavigationState.IDLE, NavigationState.PARKED:
			# No request this frame, so ActorMovement decelerates the body.
			movement.apply(delta)

		NavigationState.TRAVELLING, NavigationState.SIDESTEPPING:
			_process_travel(delta)


func _process_travel(
	delta: float
) -> void:
	if _destination == null:
		_state = NavigationState.IDLE
		movement.apply(delta)
		return

	# A reservation lost, or a tracked object removed, invalidates the journey
	# before the actor wastes any more time walking towards it.
	if not _destination.is_valid(body):
		_fail(REASON_INVALID)
		movement.apply(delta)
		return

	if _target_pending:
		_request_path(false)

	var distance_to_destination: float = body.global_position.distance_to(
		_destination.position
	)

	_is_in_final_approach = _evaluate_final_approach(
		distance_to_destination
	)

	if distance_to_destination <= _get_effective_arrival_distance(delta):
		_arrive()
		movement.apply(delta)
		return

	# Close, and not going anywhere. Something is holding the actor just short
	# of the spot - another body, a wall corner, or a solver that has decided
	# the journey is over. Treat it as arrived rather than standing there.
	if _is_settled_short_of_destination(delta):
		_arrive()
		movement.apply(delta)
		return

	_repath_if_destination_moved()

	var desired_direction: Vector2 = _get_desired_direction(
		distance_to_destination
	)

	if desired_direction == Vector2.ZERO:
		movement.apply(delta)
		_update_stuck_detection(delta)
		return

	# Personal drift off the centreline, applied before smoothing so the
	# result is a gentle curve rather than a step sideways.
	desired_direction = _apply_lateral_offset(
		desired_direction, distance_to_destination
	)

	_steering_direction = _smooth_direction(
		desired_direction,
		delta
	)

	var speed_ratio: float = _get_speed_ratio(
		distance_to_destination
	)

	var desired_velocity: Vector2 = (
		_steering_direction
		* movement.get_maximum_speed()
		* speed_ratio
		* _speed_multiplier
	)

	_desired_velocity = desired_velocity

	# Everything above runs in unscaled logical units. The avoidance solver,
	# however, has to see the speeds the bodies genuinely move at: at six times
	# speed an actor covers six times the ground per second, and a solver told
	# otherwise plans manoeuvres far too gentle to prevent a collision. Feeding
	# it real velocities is what stops actors wedging in doorways at speed.
	_agent_velocity_scale = maxf(
		WorldTime.get_world_time_scale(),
		0.001
	)

	_apply_scaled_agent_limits(_agent_velocity_scale)

	agent.velocity = desired_velocity * _agent_velocity_scale

	var applied_velocity: Vector2 = _resolve_applied_velocity(
		desired_velocity, delta
	)

	movement.request_velocity(applied_velocity)

	movement.apply(delta)

	_record_telemetry(delta, desired_velocity, applied_velocity)

	_update_stuck_detection(delta)


## True when the path has nothing useful left to contribute.
##
## Either the actor is close enough that steering straight in is correct, or
## the agent has declared the path finished while the actor is still short of
## the spot - which means the remaining gap is projection error or a corner,
## not a route. Both are walked directly.
##
## A finished path with a large gap really is unreachable, so that still falls
## through to recovery.
func _evaluate_final_approach(
	distance_to_destination: float
) -> bool:
	if distance_to_destination <= _final_approach_radius:
		return true

	if not agent.is_navigation_finished():
		return false

	return (
		distance_to_destination
		<= _final_approach_radius * FINISHED_PATH_TOLERANCE
	)


func _get_desired_direction(
	_distance_to_destination: float
) -> Vector2:
	if _state == NavigationState.SIDESTEPPING:
		return _sidestep_direction

	# Final approach. Here the path has nothing useful left to say, so the
	# actor steers straight at the spot.
	#
	# This is what replaces the old "turn navigation and avoidance off and walk
	# at the chair" special case. A seat sits inside furniture and therefore off
	# the navigation mesh, so a path can only ever reach the edge of it. The
	# difference is that avoidance stays on for these last pixels, and the
	# slowing curve still applies, so the actor eases into the chair instead of
	# barging through whoever is stood next to it.
	if _is_in_final_approach:
		return body.global_position.direction_to(_destination.position)

	# A finished path that has not reached the destination means the route ran
	# out short: something is in the way.
	if agent.is_navigation_finished():
		_begin_recovery()
		return Vector2.ZERO

	var next_position: Vector2 = agent.get_next_path_position()

	return body.global_position.direction_to(next_position)


## Blends the new direction into the current one.
##
## Framerate independent: the same smoothing produces the same curve at 30 and
## at 144 frames per second.
func _smooth_direction(
	desired_direction: Vector2,
	delta: float
) -> Vector2:
	if _steering_direction == Vector2.ZERO:
		return desired_direction

	if profile.steering_smoothing <= 0.0:
		return desired_direction

	var weight: float = 1.0 - pow(
		profile.steering_smoothing,
		delta * 60.0
	)

	return _steering_direction.lerp(
		desired_direction,
		clampf(weight, 0.0, 1.0)
	).normalized()


func _get_speed_ratio(
	distance_to_destination: float
) -> float:
	var ratio: float = _destination.speed_scale

	if movement.profile != null:
		ratio *= movement.profile.get_arrival_speed_ratio(
			distance_to_destination
		)

	return clampf(ratio, 0.0, 1.0)


## Decides whether to move on the solver's answer or our own.
##
## The avoidance solver is worth obeying for the whole journey except the very
## end. Once NavigationAgent2D considers itself arrived it stops returning a
## useful safe velocity, and obeying a zero from it is what left actors frozen
## a few pixels short of every destination.
##
## Two escapes, in order of preference:
##
## [codeblock]
## final approach   ignore the solver outright; it has nothing left to add
##                  and the slowing curve is already doing the work
## stall guard      the solver returned nothing while we clearly wanted to
##                  move, for longer than a blink - stop believing it
## [/codeblock]
func _resolve_applied_velocity(
	desired_velocity: Vector2,
	delta: float
) -> Vector2:
	if not _has_safe_velocity:
		_solver_stall_elapsed = 0.0
		return desired_velocity

	var settle_speed: float = 1.0

	if movement.profile != null:
		settle_speed = movement.profile.settle_speed

	var solver_is_stalling: bool = (
		_safe_velocity.length() < settle_speed
		and desired_velocity.length() >= settle_speed
	)

	if not solver_is_stalling:
		_solver_stall_elapsed = 0.0

		# Lean into this actor's preferred side while the solver is
		# deflecting it. Applied to the safe velocity rather than the
		# desired one so avoidance still owns the manoeuvre - this only
		# decides which way round the obstruction it goes.
		return _apply_passing_bias(
			_safe_velocity, desired_velocity.normalized()
		)

	_solver_stall_elapsed += delta

	# On a final approach the solver is given no grace at all. It routinely
	# returns nothing to an agent it considers arrived, and waiting on that is
	# what used to strand actors short of a destination - but abandoning it
	# outright is what let two customers bulldoze each other in a doorway,
	# because both were on a final approach and neither was avoiding.
	var grace: float = 0.0 if _is_in_final_approach else SOLVER_STALL_GRACE

	if _solver_stall_elapsed >= grace:
		return desired_velocity

	return _safe_velocity


## The arrival window, widened to at least one frame of travel.
##
## An actor cannot possibly land inside a six pixel window when it covers twelve
## pixels per frame; it overshoots, turns, overshoots back, and orbits forever.
## The settled-arrival rule does not catch it either, because orbiting is not
## standing still. Tying the window to actual distance covered means arrival
## stays exact at normal speed and stays possible at any speed.
func _get_effective_arrival_distance(
	delta: float
) -> float:
	var per_frame_travel: float = (
		movement.get_maximum_speed()
		* maxf(WorldTime.get_world_time_scale(), 1.0)
		* delta
	)

	return maxf(
		_destination.arrival_distance,
		per_frame_travel * 1.5
	)


## True when the actor has stopped within reach of its destination.
##
## Distinct from being stuck: this only applies inside the final approach, and
## the answer is to finish the journey rather than to start recovering. An actor
## that recovers here sidesteps itself further away, which is exactly what the
## debug traces showed happening.
func _is_settled_short_of_destination(
	delta: float
) -> bool:
	if not _is_in_final_approach:
		_settled_elapsed = 0.0
		return false

	var settle_speed: float = 1.0

	if movement.profile != null:
		settle_speed = movement.profile.settle_speed

	if movement.get_speed() >= settle_speed:
		_settled_elapsed = 0.0
		return false

	_settled_elapsed += delta

	return _settled_elapsed >= SETTLED_ARRIVAL_SECONDS


func _on_velocity_computed(
	safe_velocity: Vector2
) -> void:
	_safe_velocity = safe_velocity / _agent_velocity_scale
	_has_safe_velocity = true


## Rescales the agent limits that are expressed in distance or speed.
##
## Radius is physical and never scales. Neighbour and corner distances do,
## because a faster actor must look further ahead to react in the same amount
## of world time. Both are clamped so a large fast-forward cannot make the
## solver consider the whole room.
func _apply_scaled_agent_limits(
	time_scale: float
) -> void:
	var clamped_scale: float = clampf(time_scale, 1.0, 4.0)

	agent.max_speed = movement.get_maximum_speed() * time_scale

	agent.neighbor_distance = (
		profile.neighbour_distance * clamped_scale
	)

	agent.path_desired_distance = (
		profile.path_desired_distance * clamped_scale
	)


# -----------------------------------------------------------------------------
# Pathing
# -----------------------------------------------------------------------------

## Sets the agent's target, projecting it onto the mesh first.
##
## When the map is not ready the request is parked in [member _target_pending]
## and retried each frame. The actor is never stopped while waiting.
func _request_path(
	is_new_destination: bool
) -> void:
	if _destination == null:
		return

	var map: RID = agent.get_navigation_map()

	if not NavigationService.is_map_ready(map):
		_target_pending = true
		return

	if not is_new_destination:
		if _time_since_repath < profile.minimum_repath_interval:
			return

	var projected: Vector2 = NavigationService.project_to_mesh(
		map,
		_destination.position
	)

	var projection_error: float = _destination.position.distance_to(
		projected
	)

	# An EXACT destination is expected to sit off the mesh - a chair seat is
	# inside furniture - so only a normal travel target is worth warning about.
	if (
		projection_error > NavigationService.PROJECTION_WARNING_DISTANCE
		and _destination.arrival_mode == NavigationDestination.ArrivalMode.NEAR
	):
		push_warning(
			"%s destination '%s' was projected %.1f pixels onto the mesh."
			% [
				body.name,
				_destination.get_label(),
				projection_error
			]
		)

	# The worst case distance from the true destination when the path finishes
	# is the sum of three separate tolerances, not the largest of them:
	#
	#   target_desired_distance   how far from its own target the agent may
	#                             stop and still call the path finished
	#   projection_error          how far that target sits from the real spot,
	#                             because the real spot is off the mesh
	#   arrival_distance          how close the caller asked us to get
	#
	# Taking maxf() here was wrong and left a dead band: a seat three pixels
	# off the mesh let the agent finish thirteen pixels out while the final
	# approach only began at ten, so the actor recovered instead of walking in.
	_final_approach_radius = (
		profile.target_desired_distance
		+ projection_error
		+ _destination.arrival_distance
	)

	agent.target_position = projected

	_target_pending = false
	_time_since_repath = 0.0
	_last_pathed_position = _destination.position

	path_recalculated.emit(_destination)


## Re-plans when a tracked destination has moved far enough to matter.
##
## A moving target that is re-pathed every frame is the classic way to make
## navigation expensive. Only a real move, and only after the throttle, earns a
## recalculation.
func _repath_if_destination_moved() -> void:
	if _time_since_repath < profile.minimum_repath_interval:
		return

	var moved: float = _last_pathed_position.distance_to(
		_destination.position
	)

	if moved < profile.destination_move_repath_distance:
		return

	_request_path(false)


## Forces a recalculation, ignoring the throttle.
func force_repath() -> void:
	if _destination == null:
		return

	_time_since_repath = profile.minimum_repath_interval

	_request_path(true)


# -----------------------------------------------------------------------------
# Arrival
# -----------------------------------------------------------------------------

func _arrive() -> void:
	telemetry_completed_journeys += 1
	_record_journey_end(true)

	var reached: NavigationDestination = _destination

	_destination = null
	_state = NavigationState.IDLE
	_sidestep_remaining = 0.0
	_settled_elapsed = 0.0
	_solver_stall_elapsed = 0.0
	_is_in_final_approach = false

	# The slowing radius has already brought the actor down to a crawl, so this
	# removes the last pixel of drift rather than causing a visible jolt.
	movement.stop()
	agent.velocity = Vector2.ZERO

	if show_navigation_messages:
		print(body.name, " arrived at ", reached.get_label())

	destination_reached.emit(reached)


func _fail(
	reason: StringName
) -> void:
	telemetry_failed_journeys += 1
	_record_journey_end(false)

	var failed: NavigationDestination = _destination

	_destination = null
	_state = NavigationState.IDLE
	_sidestep_remaining = 0.0
	_settled_elapsed = 0.0
	_solver_stall_elapsed = 0.0
	_is_in_final_approach = false

	movement.stop()

	if show_navigation_messages:
		print(
			body.name,
			" failed to reach ",
			"nothing" if failed == null else failed.get_label(),
			": ",
			reason
		)

	destination_failed.emit(failed, reason)


# -----------------------------------------------------------------------------
# Recovery
# -----------------------------------------------------------------------------

func _update_stuck_detection(
	delta: float
) -> void:
	if _state == NavigationState.SIDESTEPPING:
		_sidestep_remaining -= delta

		if _sidestep_remaining <= 0.0:
			_state = NavigationState.TRAVELLING

		return

	# Recovery is for a journey that is going nowhere, not for the last few
	# pixels. Sidestepping on a final approach pushes the actor away from the
	# spot it is trying to reach; the settled-arrival rule handles this case.
	if _is_in_final_approach:
		_stuck_elapsed = 0.0
		_stuck_checks = 0
		return

	_stuck_elapsed += delta

	if _stuck_elapsed < profile.stuck_check_interval:
		return

	_stuck_elapsed = 0.0

	var moved: float = body.global_position.distance_to(
		_stuck_check_position
	)

	_stuck_check_position = body.global_position

	if moved >= profile.stuck_minimum_movement:
		_stuck_checks = 0
		_recovery_attempts = 0
		return

	_stuck_checks += 1

	if _stuck_checks < profile.stuck_checks_before_recovery:
		return

	_stuck_checks = 0

	_begin_recovery()


## Escalates through cheap fixes before giving up.
##
## Most jams in a busy tavern are two actors politely refusing to pass each
## other, which a sidestep clears in half a second and a full repath does not
## clear at all. Pathfinding is the expensive last resort, not the first
## response.
func _begin_recovery() -> void:
	_recovery_attempts += 1

	if _recovery_attempts > profile.maximum_recovery_attempts:
		_fail(REASON_BLOCKED)
		return

	recovery_started.emit(_recovery_attempts)

	if show_navigation_messages:
		print(
			body.name,
			" recovering, attempt ",
			_recovery_attempts,
			"/",
			profile.maximum_recovery_attempts
		)

	# Odd attempts sidestep, even attempts re-plan. Alternating means a jam
	# that a sidestep cannot fix still reaches a repath, and a bad path that a
	# repath cannot fix still gets shaken loose by a sidestep.
	telemetry_recoveries += 1

	if _recovery_attempts % 2 == 1:
		telemetry_sidesteps += 1
		_begin_sidestep()
	else:
		telemetry_recovery_repaths += 1
		force_repath()


func _begin_sidestep() -> void:
	var forward: Vector2 = _steering_direction

	if forward == Vector2.ZERO:
		forward = body.global_position.direction_to(
			_destination.position
		)

	if forward == Vector2.ZERO:
		forward = Vector2.RIGHT

	# Alternate sides so a second sidestep does not repeat the first.
	_sidestep_sign *= -1.0

	var sideways: Vector2 = forward.orthogonal() * _sidestep_sign

	var candidate: Vector2 = (
		body.global_position
		+ sideways * profile.sidestep_distance
	)

	var map: RID = agent.get_navigation_map()

	var projected: Vector2 = NavigationService.project_to_mesh(
		map,
		candidate
	)

	# If that side is off the mesh, the other side almost certainly is not.
	if projected.distance_to(candidate) > profile.sidestep_distance * 0.5:
		sideways = -sideways
		_sidestep_sign *= -1.0

	_sidestep_direction = sideways.normalized()
	_sidestep_remaining = profile.sidestep_duration
	_state = NavigationState.SIDESTEPPING


# -----------------------------------------------------------------------------
# Reading
# -----------------------------------------------------------------------------

## The velocity the actor wants this frame, before avoidance.
func get_desired_velocity() -> Vector2:
	return _desired_velocity


## The velocity the avoidance solver last returned.
func get_safe_velocity() -> Vector2:
	if not _has_safe_velocity:
		return Vector2.ZERO

	return _safe_velocity


## How close the actor must be before it steers straight at its destination.
func get_final_approach_radius() -> float:
	return _final_approach_radius


func is_in_final_approach() -> bool:
	return _is_in_final_approach


## The time scale last handed to the avoidance solver.
func get_agent_velocity_scale() -> float:
	return _agent_velocity_scale


## Recovery attempts spent on the current destination.
func get_recovery_attempts() -> int:
	return _recovery_attempts


func get_state() -> NavigationState:
	return _state


func is_travelling() -> bool:
	return (
		_state == NavigationState.TRAVELLING
		or _state == NavigationState.SIDESTEPPING
	)


func is_parked() -> bool:
	return _state == NavigationState.PARKED


func has_destination() -> bool:
	return _destination != null


func get_destination() -> NavigationDestination:
	return _destination


func get_distance_to_destination() -> float:
	if _destination == null or body == null:
		return 0.0

	return body.global_position.distance_to(_destination.position)


## True when a path exists from here to [param world_position].
##
## For scoring destinations before committing to one.
func can_reach(
	world_position: Vector2
) -> bool:
	if agent == null or body == null:
		return false

	return NavigationService.is_reachable(
		agent.get_navigation_map(),
		body.global_position,
		world_position
	)


# -----------------------------------------------------------------------------
# Organic movement
# -----------------------------------------------------------------------------
#
# Three small, stable per-actor values turn uniform traffic into a crowd:
#
#   _passing_side     which way this actor steps when someone blocks it
#   _lateral_offset   how far off the path centreline it walks
#   _speed_multiplier how fast it walks relative to everyone else
#
# All three are set once in seed_personal_movement() and never change during
# the actor's life. Varying them per frame would produce noise, not character -
# an actor that picks a new side every frame is exactly the mirror dance this
# is meant to fix.

## +1 or -1. Which side this actor prefers to pass on.
var _passing_side: float = 1.0

## Stable signed offset from the path centreline, in pixels.
var _lateral_offset: float = 0.0

## Stable speed multiplier, around 1.0.
var _speed_multiplier: float = 1.0

## True once seed_personal_movement() has run.
var _personal_movement_seeded: bool = false


## Gives this actor its individual walking character.
##
## [param seed_value] makes the result reproducible - pass a customer's
## identity seed and the same customer walks the same way every run, which
## deterministic diagnostics depend on. Pass 0 for a random draw.
##
## [param restlessness] (0-1) nudges the speed multiplier: restless actors
## walk a little faster. Customers pass their personality trait; staff and
## anything else can leave it at the neutral default.
func seed_personal_movement(
	seed_value: int = 0,
	restlessness: float = 0.5
) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()

	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	_passing_side = 1.0 if rng.randf() < 0.5 else -1.0

	if profile != null:
		_lateral_offset = rng.randf_range(
			-profile.lateral_path_offset, profile.lateral_path_offset
		)

		var spread: float = profile.speed_variation

		# Centred on restlessness rather than on 1.0, so a restless customer
		# sits in the upper half of the range and a placid one in the lower.
		var centre: float = 1.0 + ((restlessness - 0.5) * spread)

		_speed_multiplier = maxf(
			0.4, rng.randf_range(centre - spread, centre + spread)
		)

	_personal_movement_seeded = true


## This actor's stable speed multiplier, for the movement layer to apply.
func get_speed_multiplier() -> float:
	return _speed_multiplier


func get_passing_side() -> float:
	return _passing_side


## Shifts an aim point sideways so this actor does not walk the exact
## centreline everyone else walks.
##
## Suppressed during final approach: the whole point of the last few pixels
## is to land precisely on a seat or a service slot, and a lateral offset
## there would fight the arrival tolerance rather than look natural.
func _apply_lateral_offset(
	direction: Vector2,
	distance_to_destination: float
) -> Vector2:
	if _lateral_offset == 0.0 or direction == Vector2.ZERO:
		return direction

	if _is_in_final_approach:
		return direction

	# Fade the offset out as the destination nears, so the actor converges on
	# the real target instead of arriving permanently beside it.
	var fade: float = clampf(distance_to_destination / 96.0, 0.0, 1.0)

	if is_zero_approx(fade):
		return direction

	var perpendicular: Vector2 = Vector2(-direction.y, direction.x)

	# Offset is a distance, direction is a unit vector: divide by a nominal
	# look-ahead so the resulting angle stays sane at any speed.
	return (
		direction + (perpendicular * (_lateral_offset / 48.0) * fade)
	).normalized()


## Breaks RVO's symmetry when the solver is actively deflecting this actor.
##
## Two actors meeting head-on both compute the same evasion and shuffle. Each
## actor having a stable preferred side, and leaning into it only while
## genuinely obstructed, resolves the standoff the way two people in a
## corridor do - one goes left, one goes right, and neither stops.
##
## Returns [param safe_velocity] unchanged when nothing is in the way, so
## this is free in open space.
func _apply_passing_bias(
	safe_velocity: Vector2,
	desired_direction: Vector2
) -> Vector2:
	if profile == null or profile.passing_side_bias <= 0.0:
		return safe_velocity

	if safe_velocity == Vector2.ZERO or desired_direction == Vector2.ZERO:
		return safe_velocity

	var deflection: float = safe_velocity.normalized().dot(desired_direction)

	# Walking freely - the solver is not fighting anything.
	if deflection >= profile.side_bias_engage_dot:
		return safe_velocity

	# Scale with how badly deflected the actor is, so a glancing avoidance
	# gets a nudge and a head-on standoff gets a real push.
	var engagement: float = clampf(
		(profile.side_bias_engage_dot - deflection)
		/ maxf(0.01, profile.side_bias_engage_dot + 1.0),
		0.0,
		1.0
	)

	var perpendicular: Vector2 = Vector2(
		-desired_direction.y, desired_direction.x
	) * _passing_side

	var speed: float = safe_velocity.length()

	return (
		safe_velocity.normalized()
		+ (perpendicular * profile.passing_side_bias * engagement)
	).normalized() * speed


## Sets avoidance priority for an actor that is busy with a job.
##
## Staff on a task have somewhere specific to be; a customer milling about
## does not. Without this every actor competes equally and a bartender
## carrying a keg loses to whoever happens to be closer.
func set_working(working: bool) -> void:
	if agent == null or profile == null:
		return

	if is_parked():
		return

	agent.avoidance_priority = (
		profile.working_priority if working else _travel_avoidance_priority
	)


# -----------------------------------------------------------------------------
# Navigation telemetry
# -----------------------------------------------------------------------------
#
# Lifetime counters for one actor, collected by [NavigationReport].
#
# The reports so far have carried `navigation_failures: 0` and treated that as
# "navigation is fine". It is not the same thing: a failure means the actor
# gave up, and an actor can grind against a doorway for six seconds, recover
# three times and walk twice as far as it needed to without ever failing. The
# numbers below are the ones that distinguish "got there" from "got there
# well".
#
# All of this is plain arithmetic on values the navigation loop already
# computes, so it costs nothing worth measuring. It is always on, because a
# jam that only happens when diagnostics are off is the one you never catch.

## Recoveries (sidestep or repath) triggered on this actor.
var telemetry_recoveries: int = 0

## Sidesteps specifically - the cheap half of recovery.
var telemetry_sidesteps: int = 0

## Full repaths forced by recovery, the expensive half.
var telemetry_recovery_repaths: int = 0

## Journeys that ended in [method _fail] rather than arrival.
var telemetry_failed_journeys: int = 0

var telemetry_completed_journeys: int = 0

## Seconds spent wanting to move but not moving, across the actor's life.
## This is the number that reads as "stuck" to a player.
var telemetry_stalled_seconds: float = 0.0

## Seconds the avoidance solver spent deflecting this actor away from where
## it wanted to go. High values mean crowding, not a bug.
var telemetry_deflected_seconds: float = 0.0

## Actual pixels walked.
var telemetry_distance_travelled: float = 0.0

## Sum of straight-line distances of every journey undertaken.
##
## Distance walked during completed journeys only - the numerator of path
## efficiency. Distinct from telemetry_distance_travelled, which includes
## wandering during abandoned journeys and is the right number for "how far
## does this actor walk in a shift".
var telemetry_distance_travelled_on_journeys: float = 0.0

## travelled / direct is path efficiency: 1.0 is a perfect straight line,
## 1.2 is a sensible route round furniture, and 2.0 means the actor walked
## twice as far as it needed to. This is the single most useful navigation
## number there is, and nothing was recording it.
var telemetry_direct_distance: float = 0.0

## Longest single stall, in seconds. An average hides the one actor that
## froze for ten seconds in a doorway.
var telemetry_longest_stall: float = 0.0

var _telemetry_current_stall: float = 0.0
var _telemetry_last_position: Vector2 = Vector2.ZERO
var _telemetry_has_last_position: bool = false

## Distance walked and straight-line distance for the journey in progress.
##
## Kept separate and only folded into the totals on arrival. Adding direct
## distance at journey start and travelled distance continuously made the
## two describe different sets of journeys - an in-flight journey
## contributed its full direct distance but only part of its travelled
## distance, which produced efficiency below 1.0. That is arithmetically
## impossible for a real path and was the first thing this report caught.
var _journey_travelled: float = 0.0
var _journey_direct: float = 0.0
var _journey_active: bool = false


## Accumulates this frame's telemetry. Called from the travel loop.
func _record_telemetry(
	delta: float,
	desired_velocity: Vector2,
	applied_velocity: Vector2
) -> void:
	if body == null:
		return

	if _telemetry_has_last_position:
		var step: float = _telemetry_last_position.distance_to(
			body.global_position
		)

		telemetry_distance_travelled += step

		if _journey_active:
			_journey_travelled += step

	_telemetry_last_position = body.global_position
	_telemetry_has_last_position = true

	var settle: float = 1.0

	if movement != null and movement.profile != null:
		settle = movement.profile.settle_speed

	var wants_to_move: bool = desired_velocity.length() >= settle
	var is_moving: bool = body.velocity.length() >= settle

	if wants_to_move and not is_moving:
		_telemetry_current_stall += delta
		telemetry_stalled_seconds += delta
		telemetry_longest_stall = maxf(
			telemetry_longest_stall, _telemetry_current_stall
		)
	else:
		_telemetry_current_stall = 0.0

	# Deflection: the solver is sending the actor somewhere other than where
	# it asked to go. Measured against the same threshold the passing bias
	# uses, so the two numbers describe the same event.
	if (
		wants_to_move
		and applied_velocity.length() > 0.0
		and profile != null
	):
		var alignment: float = applied_velocity.normalized().dot(
			desired_velocity.normalized()
		)

		if alignment < profile.side_bias_engage_dot:
			telemetry_deflected_seconds += delta


## Records the straight-line length of a journey as it begins.
func _record_journey_start(destination_position: Vector2) -> void:
	if body == null:
		return

	_journey_travelled = 0.0
	_journey_direct = body.global_position.distance_to(destination_position)
	_journey_active = true


## Folds a finished journey into the efficiency totals.
##
## Only completed journeys count. An abandoned or re-targeted journey has a
## travelled distance that belongs to a destination it never reached, and
## including it would blame the pathing for a decision the gameplay made.
func _record_journey_end(completed: bool) -> void:
	if not _journey_active:
		return

	_journey_active = false

	if not completed:
		return

	# Sub-pixel journeys make the ratio meaningless.
	if _journey_direct < 8.0:
		return

	telemetry_distance_travelled_on_journeys += _journey_travelled
	telemetry_direct_distance += _journey_direct


## Everything known about this actor's navigation, for [NavigationReport].
func get_telemetry() -> Dictionary:
	var efficiency: float = 0.0

	if telemetry_direct_distance > 0.0:
		efficiency = (
			telemetry_distance_travelled_on_journeys
			/ telemetry_direct_distance
		)

	return {
		"actor": String(body.name) if body != null else "",
		"profile": (
			profile.resource_path.get_file() if profile != null else ""
		),
		"recoveries": telemetry_recoveries,
		"sidesteps": telemetry_sidesteps,
		"recovery_repaths": telemetry_recovery_repaths,
		"completed_journeys": telemetry_completed_journeys,
		"failed_journeys": telemetry_failed_journeys,
		"stalled_seconds": telemetry_stalled_seconds,
		"longest_stall_seconds": telemetry_longest_stall,
		"deflected_seconds": telemetry_deflected_seconds,
		"distance_travelled": telemetry_distance_travelled,
		"distance_on_completed_journeys": (
			telemetry_distance_travelled_on_journeys
		),
		"direct_distance": telemetry_direct_distance,
		"path_efficiency": efficiency,
		"passing_side": _passing_side,
		"lateral_offset": _lateral_offset,
		"speed_multiplier": _speed_multiplier,
		"personal_movement_seeded": _personal_movement_seeded,
		"state": _state_name(),
		"is_parked": is_parked(),
	}


func _state_name() -> String:
	match _state:
		NavigationState.IDLE:
			return "IDLE"
		NavigationState.TRAVELLING:
			return "TRAVELLING"
		NavigationState.SIDESTEPPING:
			return "SIDESTEPPING"
		NavigationState.PARKED:
			return "PARKED"

	return "UNKNOWN"
