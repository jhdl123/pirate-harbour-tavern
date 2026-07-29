class_name TavernTaskBoardConfig
extends Resource

## Everything tuneable about the task board, in one file.
##
## Loaded once by the [code]TaskBoard[/code] autoload from
## [constant TavernTaskService.DEFAULT_CONFIG_PATH], the same pattern
## [WorldTime] uses for [GameTimeConfig]. Nothing here is read per frame.
##
## The scoring weights that vary per kind of work live on each
## [TavernTaskDefinition] instead. What is here is board-wide policy: how often
## it sweeps, how much history it keeps, and how loudly it talks.


@export_category("Task Definitions")

## Every kind of work this board understands, looked up by
## [member TavernTaskDefinition.task_type].
##
## A task type with no definition here is refused at creation with a warning
## rather than silently created with invented defaults.
@export var task_definitions: Array[TavernTaskDefinition] = []


@export_category("Maintenance")

## Seconds between the board's own sweep.
##
## The sweep expires stale claims, clears cooldowns and re-tests BLOCKED tasks.
## It is not how workers find work - they ask the board directly - so this can
## be slow without making staff sluggish.
@export_range(0.05, 10.0, 0.05)
var sweep_interval_seconds: float = 0.5

## Whether the board drops tasks whose target node has been freed.
##
## Effectively always on. Exposed so a test can turn it off and inspect what
## would otherwise have been swept away.
@export var cancel_tasks_with_missing_targets: bool = true


@export_category("History")

## Completed, cancelled and failed tasks kept in memory for the report.
##
## Bounded on purpose: a long session must not grow without limit. The oldest
## entries are discarded first and the report records that it happened.
@export_range(0, 5000, 10)
var maximum_retained_finished_tasks: int = 400

## Structured issues kept in memory for the report.
@export_range(0, 5000, 10)
var maximum_retained_issues: int = 300


@export_category("Viability")

## How the board estimates whether a task can still be finished in time.
##
## Null disables viability checking entirely and restores Phase 3A selection.
@export var viability_config: TaskViabilityConfig


@export_category("Commitment")

## Seconds a worker will not re-claim a task it personally just released.
##
## The narrowest oscillation the board can produce is release-then-reclaim by
## the same worker on consecutive ticks. This closes it without stopping a
## different worker picking the task up immediately.
@export_range(0.0, 120.0, 0.5)
var same_worker_reclaim_cooldown_seconds: float = 6.0

## Score a candidate must beat the worker's current task by before the worker
## will switch.
##
## Zero would make the worker abandon a job for a rival worth one point more,
## which is the classic oscillation. This is the hysteresis band.
@export_range(0.0, 500.0, 5.0)
var task_switch_score_margin: float = 120.0

## World minutes a worker stays on a newly claimed task before any switch is
## considered at all.
##
## A worker that has just set off should be allowed to get somewhere.
@export_range(0.0, 60.0, 0.1)
var minimum_commitment_minutes: float = 0.75


@export_category("Decision Logging")

## Whether per-decision records are kept for the exported report.
##
## These are what let a report explain why a task was skipped rather than only
## that it was. Recorded per decision, never per frame.
@export var record_decisions: bool = true

## Decision records retained. Oldest are dropped first.
@export_range(0, 20000, 50)
var maximum_retained_decisions: int = 600

## Whether rejections are recorded as well as acceptances.
##
## Rejections are the more useful half - "why did nobody take this?" - but
## they are also far more numerous, so they can be turned off independently.
@export var record_rejections: bool = true

## Identical consecutive rejections of the same task for the same reason that
## are collapsed into one record with a count.
##
## Without this, one unreachable customer produces a rejection record on every
## evaluation for as long as they sit there.
@export var deduplicate_rejections: bool = true


@export_category("Debug")

## Prints every creation, claim, completion and failure.
##
## Off by default: at a busy tavern this is several lines per second.
@export var console_debug_enabled: bool = false


## The definition registered for [param task_type], or null.
func find_definition(
	task_type: StringName
) -> TavernTaskDefinition:
	for definition: TavernTaskDefinition in task_definitions:
		if definition == null:
			continue

		if definition.task_type == task_type:
			return definition

	return null


## Warns about missing or duplicated task types. Called once at startup.
func validate_or_warn() -> bool:
	var seen: Dictionary = {}
	var is_valid: bool = true

	for definition: TavernTaskDefinition in task_definitions:
		if definition == null:
			push_warning(
				"TavernTaskBoardConfig contains an empty definition entry."
			)

			is_valid = false
			continue

		if not definition.validate_or_warn():
			is_valid = false
			continue

		if seen.has(definition.task_type):
			push_warning(
				"TavernTaskBoardConfig has two definitions for task type '%s'."
				% String(definition.task_type)
			)

			is_valid = false
			continue

		seen[definition.task_type] = true

	for required: StringName in TavernTaskTypes.get_implemented_types():
		if not seen.has(required):
			push_warning(
				"TavernTaskBoardConfig has no definition for implemented "
				+ "task type '%s'." % String(required)
			)

			is_valid = false

	return is_valid
