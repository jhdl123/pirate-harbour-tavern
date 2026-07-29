class_name TaskViabilityConfig
extends Resource

## How the board decides whether a task can still be finished in time.
##
## The stress-test report showed 127 cancellations against 67 completions, and
## almost all of the cancellations were serving tasks abandoned because the
## customer had left. The worker was not choosing badly by its own scoring - it
## was choosing by urgency, and the most urgent customer is very often the one
## about to walk out. Urgency alone actively selects doomed work.
##
## Viability is the missing half of that judgement: not "who needs this most?"
## but "can I actually get there in time?".
##
## Every value here is a tuning knob rather than a rule. Estimates are meant to
## be roughly right, not exact - a worker that predicted its own arrival to the
## frame would feel inhuman, and the safety margin exists precisely so that
## being a bit wrong is survivable.


enum Verdict {
	## Comfortably achievable.
	VIABLE,

	## Achievable, but with little room. Still worth trying.
	MARGINAL,

	## Almost certainly cannot be finished in time.
	NON_VIABLE,

	## No estimate could be made, for example a task with no deadline.
	UNKNOWN,
}


@export_category("Enable")

## Master switch. Off restores the Phase 3A behaviour exactly.
@export var enabled: bool = true


@export_category("Margins")

## World minutes of slack required before a task counts as comfortably viable.
##
## Above this the worker is confident; between this and zero it is taking a
## chance. Raising it makes the worker more cautious and will increase the
## number of customers who leave unserved during an overload - which is the
## honest outcome, not a failure.
@export_range(0.0, 60.0, 0.5)
var comfortable_margin_minutes: float = 3.0

## Fixed slack subtracted from every estimate.
##
## Covers everything the estimate cannot see: waiting for a path, stepping
## around a customer, the last few pixels of an approach.
@export_range(0.0, 60.0, 0.5)
var safety_buffer_minutes: float = 1.5

## Margin below which a task is refused outright, when refusal is permitted.
##
## Strongly negative on purpose, and the value most likely to need retuning.
## An A/B benchmark of this system found that a mild threshold made things
## measurably worse: the worker refused jobs it would probably have finished,
## stood idle instead, and completed fewer customers than the version with no
## viability checking at all. Rejection should mean "clearly impossible", not
## "looks tight" - looking tight is what the score penalty is for.
@export_range(-60.0, 0.0, 0.5)
var rejection_margin_minutes: float = -3.0


@export_category("Acceptance")

## Whether a non-viable task may be claimed even when better work exists.
##
## Off by default: given a choice, a worker should always take the job it can
## finish.
@export var may_accept_non_viable_tasks: bool = false

## Whether a worker with nothing else to do may attempt a non-viable task.
##
## On by default, and the benchmark is the reason. Rejecting a doomed task
## only helps if there is something better to do instead; a worker that
## refuses the only job available serves nobody and the customer leaves
## regardless. Attempting a long shot costs a walk and sometimes wins, because
## the estimate is deliberately approximate and patience is not the only way a
## task can end.
@export var accept_best_non_viable_when_idle: bool = true

## Whether an unknown estimate is treated as acceptable.
##
## On: a task with no deadline - cleaning, for instance - is never blocked by
## a system designed for customers with patience timers.
@export var accept_unknown_viability: bool = true


@export_category("Scoring")

## Score added to a comfortably viable task.
@export_range(0.0, 500.0, 1.0)
var viable_bonus: float = 40.0

## Score removed from a task the worker expects to miss.
##
## Large, because a doomed task should lose to almost anything achievable even
## when the doomed customer is the most urgent person in the room.
@export_range(0.0, 1000.0, 1.0)
var non_viable_penalty: float = 400.0

## Score added per world minute of margin, between zero and the comfortable
## margin. Rewards the achievable-with-room task over the achievable-just-about
## one without any hard cut-off between them.
@export_range(0.0, 100.0, 0.5)
var margin_weight: float = 8.0


@export_category("Estimation")

## Pixels per second used when the worker's own speed cannot be read.
@export_range(10.0, 1000.0, 5.0)
var fallback_speed: float = 90.0

## Multiplier applied to straight-line distance when no navigation path is
## available.
##
## Real routes are longer than the crow flies. 1.35 is about right for a room
## with tables in it; raise it for a more cluttered tavern.
@export_range(1.0, 3.0, 0.05)
var straight_line_detour_factor: float = 1.35

## Whether to ask the navigation server for a real path length.
##
## Much more accurate around furniture, and affordable because it is only done
## when a task is being seriously considered, never per frame for every task.
@export var use_navigation_path_length: bool = true

## Seconds a computed path length stays usable before it is recomputed.
##
## The worker and the customer both move, but not far in a fraction of a
## second, and pathfinding for every candidate on every evaluation is the one
## thing that would make this expensive.
@export_range(0.0, 30.0, 0.1)
var maximum_path_estimate_age_seconds: float = 1.0

## World minutes added for each hand-off the task involves.
##
## Covers picking a drink off the counter and putting it in front of a
## customer: both are instantaneous in code and clearly are not in life.
@export_range(0.0, 30.0, 0.1)
var interaction_overhead_minutes: float = 0.35


@export_category("Re-evaluation")

## Improvement in margin, in world minutes, that makes a previously rejected
## task worth reconsidering.
##
## Without this a task rejected once would be re-estimated on every single
## evaluation for as long as it existed.
@export_range(0.0, 30.0, 0.1)
var reevaluation_margin_delta: float = 1.0

## Seconds before a non-viable task is re-estimated regardless.
@export_range(0.0, 300.0, 0.5)
var reevaluation_interval_seconds: float = 4.0


## The verdict for a given margin.
func classify(
	margin_minutes: float,
	has_estimate: bool
) -> Verdict:
	if not has_estimate:
		return Verdict.UNKNOWN

	if margin_minutes < rejection_margin_minutes:
		return Verdict.NON_VIABLE

	if margin_minutes < comfortable_margin_minutes:
		return Verdict.MARGINAL

	return Verdict.VIABLE


## Score contribution for a verdict and margin.
func get_score_contribution(
	verdict: Verdict,
	margin_minutes: float
) -> float:
	match verdict:
		Verdict.VIABLE:
			return viable_bonus

		Verdict.MARGINAL:
			return clampf(
				margin_minutes * margin_weight,
				-non_viable_penalty,
				viable_bonus
			)

		Verdict.NON_VIABLE:
			return -non_viable_penalty

	return 0.0


## True when a verdict permits a claim under this configuration.
func permits_claim(
	verdict: Verdict
) -> bool:
	match verdict:
		Verdict.NON_VIABLE:
			return may_accept_non_viable_tasks

		Verdict.UNKNOWN:
			return accept_unknown_viability

	return true


static func get_verdict_name(
	verdict: Verdict
) -> String:
	return Verdict.keys()[verdict]
