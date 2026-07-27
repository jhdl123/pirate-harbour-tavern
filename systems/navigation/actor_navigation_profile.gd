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
