class_name TavernTaskDefinition
extends Resource

## Static, shared data describing one kind of work.
##
## A [TavernTask] is one real outstanding job - "customer Sailor7 is waiting for
## a grog". This resource is the class of job it belongs to: what it is called,
## how important that class is relative to others, who is allowed to do it, and
## how forgiving the board should be when it goes wrong.
##
## Keeping this out of [StaffMember] is the whole point. Balancing how eagerly
## staff clean versus serve is editing two [code].tres[/code] files, not
## rewriting an AI script and hoping nothing else depended on the old numbers.
##
## Definitions are registered on [member TavernTaskBoardConfig.task_definitions]
## and looked up by [member task_type].


@export_category("Identity")

## Stable identifier. Must match one of the constants in [TavernTaskTypes].
@export var task_type: StringName = &""

## Name shown in developer tools, staff inspection and diagnostics.
@export var display_name: String = "Task"

## Optional explanation for tooling.
@export_multiline var description: String = ""

## Groups tasks together in exported diagnostic reports.
##
## Free-form: "service", "cleaning", "stock", "maintenance".
@export var diagnostic_category: StringName = &"general"


@export_category("Selection")

## How important this class of work is before any situational factors.
##
## The starting point of the score. Recommended relative values:
##
## [codeblock]
## 120  serving a customer whose patience is nearly out (via urgency)
## 100  normal drink service
##  60  cleaning a seat that is blocking future customers
##  40  routine cleaning
## [/codeblock]
##
## Urgency, age and distance move a task around this number; they do not
## replace it, so a class of work can never quietly out-rank a much more
## important one just by sitting in the queue.
@export_range(0.0, 1000.0, 1.0)
var base_priority: float = 50.0

## How strongly a task's own urgency (0..1) adds to its score.
##
## Urgency is supplied by whatever produced the task - for a waiting customer
## it is how much patience has run down. Setting this to zero makes the task
## type ignore urgency entirely.
@export_range(0.0, 500.0, 1.0)
var urgency_weight: float = 80.0

## Score added per world minute the task has been waiting, capped by
## [member maximum_age_bonus].
##
## Stops a distant or awkward job being starved forever by a stream of easier
## ones. This is the anti-starvation term, not the main ordering term.
@export_range(0.0, 50.0, 0.1)
var age_weight: float = 1.5

## Ceiling on the age contribution, so an ancient task cannot out-rank a
## genuinely urgent one.
@export_range(0.0, 500.0, 1.0)
var maximum_age_bonus: float = 30.0

## Score removed per 100 pixels of straight-line distance from the worker.
##
## Deliberately gentle. Distance should break ties between similar jobs, not
## decide which kind of work matters.
@export_range(0.0, 200.0, 1.0)
var distance_weight: float = 12.0

## Score added when the worker already holds the item this task needs.
##
## Prevents the "put it down, walk away, come back for it" behaviour that a
## purely distance-based score produces.
@export_range(0.0, 500.0, 1.0)
var carried_item_bonus: float = 60.0

## Score removed per previous failure on this specific task.
##
## A task that has already defeated the worker twice should be tried after the
## ones that have not.
@export_range(0.0, 200.0, 1.0)
var failure_penalty: float = 25.0


## How a task type reacts to a worker that is already holding something.
##
## Data rather than code, so a future task that genuinely does not care - a
## worker shouting an order across the room, say - declares that in its
## resource instead of overriding an executor method.
enum CarriedItemRule {
	## The worker's hands must be empty, or hold exactly the required item.
	##
	## The correct default for anything involving an item.
	REQUIRES_MATCHING_OR_EMPTY,

	## The worker's hands must be completely empty.
	##
	## Cleaning uses this: you cannot scrub a table one-handed holding a pint.
	REQUIRES_EMPTY_HANDS,

	## The task does not care what the worker is holding.
	IGNORES_CARRIED_ITEMS,
}


@export_category("Requirements")

## See [enum CarriedItemRule].
@export var carried_item_rule: CarriedItemRule = (
	CarriedItemRule.REQUIRES_MATCHING_OR_EMPTY
)

## Multiplier on this task type's viability score contribution.
##
## One leaves the shared [TaskViabilityConfig] weights untouched. Zero opts a
## task type out of viability scoring without disabling it globally.
@export_range(0.0, 5.0, 0.05)
var viability_weight: float = 1.0


## Capabilities a worker must hold to claim this. See [StaffCapabilities].
@export var required_capabilities: Array[StringName] = []


@export_category("Retry and Failure")

## How many times a worker may re-attempt after a recoverable failure
## (navigation gave up, a transfer was refused) before the task is failed.
@export_range(0, 20, 1)
var maximum_retries: int = 2

## Total failures across all workers before the task is abandoned entirely.
##
## Separate from [member maximum_retries] so a task that defeats three
## different workers is retired even though none of them individually gave up.
@export_range(1, 50, 1)
var maximum_failures: int = 4

## World minutes a claimed task may run before the board takes it back.
##
## The safety net for a worker that is removed, frozen or wedged without ever
## reporting a failure. Zero disables the timeout.
@export_range(0, 600, 1)
var timeout_world_minutes: int = 20

## Seconds a released or failed task waits before it can be claimed again.
##
## Stops a worker instantly re-claiming a task it just failed and spinning.
@export_range(0.0, 120.0, 0.5)
var retry_cooldown_seconds: float = 3.0


@export_category("Interruption")

## Whether a worker may drop this part-way through for something better.
##
## False for anything mid-transaction. A worker holding a customer's drink
## should finish delivering it, not wander off to a marginally higher score.
@export var can_be_interrupted: bool = false

## Whether the player doing this job themselves should quietly cancel it.
##
## Almost always true: the authoritative world state wins, and staff should
## notice and move on rather than repeating what the player just did.
@export var player_may_override: bool = true


@export_category("Presentation")

## Whether completing this task raises a toast notification.
##
## Off by default for routine work - a toast for every drink delivered is
## noise, and hiding real messages behind noise is the failure mode this whole
## communication framework exists to avoid.
@export var notify_on_completion: bool = false


func is_valid() -> bool:
	return (
		not task_type.is_empty()
		and not display_name.strip_edges().is_empty()
		and maximum_failures >= 1
	)


func validate_or_warn() -> bool:
	if is_valid():
		return true

	push_warning(
		"TavernTaskDefinition '%s' is incomplete: it needs a task_type, a "
		% String(task_type)
		+ "display_name and at least one permitted failure."
	)

	return false


## The age contribution for a task that has waited [param age_minutes].
func get_age_bonus(
	age_minutes: float
) -> float:
	if age_weight <= 0.0:
		return 0.0

	return minf(
		age_minutes * age_weight,
		maximum_age_bonus
	)
