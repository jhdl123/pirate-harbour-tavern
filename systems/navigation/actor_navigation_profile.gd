class_name ActorNavigationProfile
extends Resource

## How one kind of actor paths, avoids and recovers.
##
## The companion to [ActorMovementProfile]: that resource decides how a body
## moves, this one decides how it decides where to move. Split because a
## bartender and a customer may share identical acceleration while needing very
## different avoidance priority and repath patience.
##
## Every value that used to be a magic number inside the customer script lives
## here, so tuning busy-tavern behaviour never means editing an actor script.


@export_category("Agent")

## Radius used by the avoidance solver, in pixels.
##
## Roughly the actor's personal space, not its collision size. Too small and
## actors clip; too large and they refuse to pass each other in a doorway.
@export_range(1.0, 64.0, 0.5)
var avoidance_radius: float = 12.0

## How much this actor yields to others. Higher yields less.
##
## The lever that stops actors fighting over the same gap: give staff a higher
## priority than customers and customers will step aside for them.
@export_range(0.0, 1.0, 0.05)
var avoidance_priority: float = 0.5

## How far away other agents are considered, in pixels.
@export_range(16.0, 512.0, 1.0)
var neighbour_distance: float = 80.0

## How many neighbours the solver considers at once.
##
## The main cost knob for a busy room. Ten is plenty for a tavern.
@export_range(1, 64, 1)
var maximum_neighbours: int = 10

## Seconds ahead the solver looks when avoiding other agents.
##
## Larger values swerve earlier and look more deliberate; too large and actors
## dodge people they were never going to meet.
@export_range(0.1, 5.0, 0.05)
var time_horizon_agents: float = 0.7

## Seconds ahead the solver looks when avoiding static obstacles.
@export_range(0.05, 5.0, 0.05)
var time_horizon_obstacles: float = 0.25


@export_category("Path Following")

## How close the actor must get to a path corner before advancing to the next.
##
## Small values hug corners and produce twitching; large values cut them.
@export_range(1.0, 64.0, 0.5)
var path_desired_distance: float = 12.0

## How close to the final path point counts as the path being finished.
@export_range(1.0, 64.0, 0.5)
var target_desired_distance: float = 10.0

## How far the actor may drift from its path before it is re-planned.
@export_range(8.0, 256.0, 1.0)
var path_maximum_distance: float = 32.0

## How strongly the steering direction is smoothed, 0 for none.
##
## The direct cause of the old twitching: the previous code pointed straight at
## the next path corner every frame, so a corner flip reversed the actor
## instantly. Smoothing turns that into a curve.
@export_range(0.0, 0.95, 0.01)
var steering_smoothing: float = 0.55


@export_category("Repathing")

## Minimum seconds between path recalculations.
##
## Repathing is the expensive operation in this system. Throttling it is what
## keeps a busy tavern affordable, and also what stops an actor dithering as
## its path flickers between two equal routes.
@export_range(0.0, 5.0, 0.05)
var minimum_repath_interval: float = 0.5

## How far a tracked destination may move before the path is recalculated.
@export_range(1.0, 256.0, 1.0)
var destination_move_repath_distance: float = 24.0


@export_category("Recovery")

## Seconds between progress checks.
@export_range(0.1, 5.0, 0.05)
var stuck_check_interval: float = 0.5

## Distance the actor must cover between checks to count as progressing.
@export_range(0.0, 64.0, 0.5)
var stuck_minimum_movement: float = 1.0

## Failed checks before recovery begins.
@export_range(1, 20, 1)
var stuck_checks_before_recovery: int = 3

## How many recovery attempts before the destination is declared unreachable.
##
## Recovery escalates: a sidestep first, then a full repath, then failure.
@export_range(0, 10, 1)
var maximum_recovery_attempts: int = 3

## How far a sidestep nudges the actor, in pixels.
##
## The cheap first response to being wedged against another actor, and the one
## that resolves most jams without any pathfinding at all.
@export_range(0.0, 128.0, 1.0)
var sidestep_distance: float = 28.0

## Seconds a sidestep runs before normal path following resumes.
@export_range(0.1, 3.0, 0.05)
var sidestep_duration: float = 0.45


@export_category("Parking")

## Avoidance priority applied when the actor stops somewhere permanent.
##
## A seated customer should be an obstacle others flow around, not a rag doll
## shoved out of its chair. Raising priority to the maximum makes the solver
## treat it as something to go around.
@export_range(0.0, 1.0, 0.05)
var parked_avoidance_priority: float = 1.0


@export_category("Organic Movement")

## How far an actor may drift sideways from the exact path centreline.
##
## [b]This is what stops actors walking in single file.[/b] Godot's path is a
## line, and every actor following it walks that identical line, which is a
## large part of why traffic looks mechanical. Each actor is given a stable
## offset within this range, so two customers crossing the same room take
## visibly different routes through it.
##
## Kept well below the avoidance radius: this is a wobble, not a detour, and
## an offset large enough to push an actor into furniture would be worse
## than the problem it solves. 0.0 restores exact centreline following.
@export_range(0.0, 24.0, 0.5)
var lateral_path_offset: float = 7.0

## How strongly an actor commits to one side when it meets someone head-on.
##
## [b]This is the fix for the mirror dance.[/b] Godot's RVO avoidance is
## symmetric: two actors approaching each other compute mirror-image
## evasions, both step the same way, and they shuffle. Giving each actor a
## stable preferred side and nudging perpendicular when avoidance is
## actively deflecting them breaks that symmetry the way two people passing
## in a corridor do.
##
## Applied only while the solver is genuinely deflecting the actor, so it
## costs nothing in open space. 0.0 disables it.
@export_range(0.0, 1.0, 0.05)
var passing_side_bias: float = 0.45

## How much the safe velocity must deviate from the desired direction before
## the side bias engages, as a dot product.
##
## Below this the actor is walking freely and needs no help. Around 0.8 is
## roughly a 35 degree deflection - enough to mean "something is in my way",
## not so much that a normal corner triggers it.
@export_range(0.0, 1.0, 0.01)
var side_bias_engage_dot: float = 0.82

## Per-actor speed variation, as a fraction of maximum speed.
##
## A crowd where everyone walks at exactly 120px/s reads as mechanical no
## matter how good the pathing is. Each actor gets a stable multiplier
## within this range. For customers this is layered on top of the
## personality's own restlessness. 0.0 makes every actor identical.
@export_range(0.0, 0.5, 0.01)
var speed_variation: float = 0.18


@export_category("Yielding")

## Avoidance priority for an actor that is parked (seated, or standing in a
## formation slot).
##
## [b]Higher is NOT better here.[/b] In Godot's solver a higher priority
## actor expects others to move around it. Setting a parked actor to maximum
## made seated customers actively shove approaching actors out of the way -
## which is how staff carrying kegs got pushed off their delivery approach.
## A parked actor should hold its ground but yield the last few pixels, so
## this sits BELOW the travelling priority rather than above it.
@export_range(0.0, 1.0, 0.05)
var parked_yield_priority: float = 0.35

## Avoidance priority for an actor that is actively performing a job.
##
## Staff on a task have somewhere to be and a customer standing in the way
## does not. Left at the profile's normal avoidance_priority when unset.
@export_range(0.0, 1.0, 0.05)
var working_priority: float = 0.75
