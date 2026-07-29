class_name TavernTask
extends RefCounted

## One real outstanding requirement in the world.
##
## A task is not an instruction to a worker. It is a statement of fact:
## "chair table2/chairLeft is dirty", "Sailor7 is waiting for a grog". Nothing
## about it changes when a worker picks it up, and nothing about it is true
## because a worker believes it - the world is always the authority, and
## [method TavernTaskService.revalidate] is what re-asks the world.
##
## That distinction is what makes the player able to override staff freely. If
## the player cleans the chair, the fact stops being true, the task is
## invalidated, and the worker releases it. Nothing has to notify anybody.
##
## [b]Lifecycle[/b]
##
## [codeblock]
## AVAILABLE     nobody is doing this
## CLAIMED       a worker has taken it and is travelling
## IN_PROGRESS   the worker is at the target and acting on it
## BLOCKED       still needed, but not doable right now (no drink is ready)
## COMPLETED     the world confirmed the requirement is met
## CANCELLED     the requirement went away (player did it, customer left)
## FAILED        it was needed, tried, and could not be done
## [/codeblock]
##
## Everything that happens to a task is appended to
## [member state_history], which is what the exported diagnostic report reads.
## Never mutate the fields directly from gameplay code - go through
## [TavernTaskService] so history, indexes and signals stay in step.


enum State {
	## Nobody has claimed this. The only state a worker may claim from.
	AVAILABLE,

	## A worker owns this and is on its way.
	CLAIMED,

	## The worker is at the target, acting on it.
	IN_PROGRESS,

	## Still a real requirement, but not currently actionable.
	##
	## A waiting customer with no matching drink prepared sits here: the need
	## is real, the work is not yet possible, and the player is the missing
	## ingredient. Blocked tasks are re-tested cheaply every board tick.
	BLOCKED,

	## The world confirmed the requirement is met.
	COMPLETED,

	## The requirement stopped existing.
	CANCELLED,

	## The requirement existed and could not be met.
	FAILED,
}


# --- Identity ----------------------------------------------------------------

## Stable, human-readable id, for example [code]serve_drink_00017[/code].
##
## Allocated by [TavernTaskService] and never reused within a session, so
## diagnostics can follow one task across every state it passed through.
var task_id: StringName = &""

## See [TavernTaskTypes].
var task_type: StringName = &""

## The shared data for this class of work.
var definition: TavernTaskDefinition = null

## Identifies the world thing this task is about, for deduplication.
##
## Two tasks with the same key are the same requirement, so the board refuses
## to create the second one. Built by the producer - see
## [method TavernTaskService.build_node_key].
var target_key: String = ""


# --- State -------------------------------------------------------------------

var state: State = State.AVAILABLE

## Why the task left AVAILABLE for a terminal state. Free-form, for reports.
var resolution_reason: StringName = &""

## Set when the last attempt failed, for diagnostics and scoring.
var last_failure_reason: StringName = &""

## True once a worker has done the thing but not yet reported it.
##
## The gap is at most one frame, but a validator that runs inside it sees a
## clean chair or a served customer and quite correctly concludes the
## requirement has gone away - cancelling a task that was in fact just
## completed. This flag tells [method TavernTaskService.revalidate] to leave the
## last word to the worker.
var is_resolution_pending: bool = false


# --- What the work concerns --------------------------------------------------

## Where the worker collects something, when the task needs a collection leg.
##
## Held weakly: the bar counter being removed invalidates the task rather than
## crashing the worker mid-journey.
var source_ref: WeakRef = null

## Object-specific detail about the source, for example
## [code]{ "slot_index": 2 }[/code] for a bar service slot.
var source_data: Dictionary = {}

## What the work is done to: the customer, the chair, the station.
var target_ref: WeakRef = null

## Optional final destination when it differs from the target.
var destination_ref: WeakRef = null

## The item this task needs, when it needs one.
var required_definition: ItemDefinition = null

var required_quantity: int = 1

## Any [Reservable]s claimed on this task's behalf, released together.
var reservations: Array[Reservable] = []


# --- Assignment --------------------------------------------------------------

## Stable id of the worker holding this, or empty.
var assigned_worker_id: StringName = &""

## The worker node, held weakly so a removed worker frees the task.
var assigned_worker_ref: WeakRef = null


# --- Urgency -----------------------------------------------------------------

## 0..1, supplied and refreshed by whatever produced the task.
##
## For a waiting customer this is how far patience has run down. The board
## never invents this: only the producer knows what urgency means for its own
## kind of work.
var urgency: float = 0.0

## Score this task was given the moment a worker selected it.
##
## Recorded rather than recalculated so a report shows why the worker chose
## what it chose, not what it would choose now.
var selected_score: float = 0.0


# --- Times, in world minutes -------------------------------------------------

var created_minutes: float = 0.0
var claimed_minutes: float = -1.0
var started_minutes: float = -1.0
var finished_minutes: float = -1.0

## Real seconds (not world minutes) before this may be claimed again.
##
## Real time on purpose: a cooldown is a stop-spinning guard, not a piece of
## world simulation, and it must still work while the clock is paused.
var cooldown_until_ticks_ms: int = 0


# --- Counters ----------------------------------------------------------------

var retry_count: int = 0
var failure_count: int = 0


# --- Viability and churn tracking --------------------------------------------

## Cached navigation path lengths, keyed by leg name.
##
## Pathfinding for every candidate on every evaluation would be the expensive
## part of viability checking, so a measurement is reused for a configurable
## fraction of a second. Not serialised: a performance detail, not state.
var path_estimate_cache: Dictionary = {}

## The last viability evaluation, as returned by [TaskViability.evaluate].
##
## Recorded so a report can explain why a task was skipped without re-running
## the estimate, and so re-evaluation can tell whether conditions improved.
var last_viability: Dictionary = {}

## Real milliseconds when viability was last evaluated.
var last_viability_ticks_ms: int = 0

## Which worker most recently released this, and when, in real milliseconds.
##
## Stops the same worker instantly re-claiming something it just let go, which
## is the tightest oscillation loop the board can produce.
var last_released_by: StringName = &""
var last_released_ticks_ms: int = 0

## World minutes workers spent on this before it ended, summed across claims.
##
## The most useful single number for judging churn: a cancellation after ten
## seconds of walking is a very different event from one after two minutes.
var invested_minutes: float = 0.0


# --- Free-form ---------------------------------------------------------------

## Producer-specific extras. Kept out of the typed fields so a new task type
## never needs a new field on this class.
var metadata: Dictionary = {}

## Every state change, in order, as
## [code]{ minutes, from, to, reason }[/code].
var state_history: Array[Dictionary] = []

## Every reservation taken or released, as
## [code]{ minutes, action, subject }[/code].
var reservation_history: Array[Dictionary] = []


# -----------------------------------------------------------------------------
# Reading
# -----------------------------------------------------------------------------

func get_source() -> Node:
	return _resolve(source_ref)


func get_target() -> Node:
	return _resolve(target_ref)


func get_destination() -> Node:
	var destination: Node = _resolve(destination_ref)

	if destination != null:
		return destination

	return get_target()


func get_assigned_worker() -> Node:
	return _resolve(assigned_worker_ref)


func _resolve(
	reference: WeakRef
) -> Node:
	if reference == null:
		return null

	var node: Node = reference.get_ref() as Node

	if node == null or not is_instance_valid(node):
		return null

	return node


func is_terminal() -> bool:
	return (
		state == State.COMPLETED
		or state == State.CANCELLED
		or state == State.FAILED
	)


func is_active() -> bool:
	return (
		state == State.CLAIMED
		or state == State.IN_PROGRESS
	)


## True when a worker may take this right now.
func is_claimable() -> bool:
	if state != State.AVAILABLE:
		return false

	return Time.get_ticks_msec() >= cooldown_until_ticks_ms


func is_held_by(
	worker: Node
) -> bool:
	return worker != null and get_assigned_worker() == worker


## World minutes since creation.
func get_age_minutes(
	now_minutes: float
) -> float:
	return maxf(now_minutes - created_minutes, 0.0)


## Where a worker should stand to do this, in world space.
##
## Falls back through destination, target and source so a task never reports a
## nonsense position just because one of its three references is unset.
func get_reference_position() -> Vector2:
	for candidate: Node in [get_destination(), get_target(), get_source()]:
		var node_2d: Node2D = candidate as Node2D

		if node_2d != null:
			return node_2d.global_position

	return Vector2.ZERO


func get_display_name() -> String:
	if definition != null:
		return definition.display_name

	return String(task_type).capitalize()


func get_state_name() -> String:
	return State.keys()[state]


## One line for developer tools and the staff inspection panel.
func describe() -> String:
	var target: Node = get_target()

	return "%s [%s] target=%s worker=%s" % [
		String(task_id),
		get_state_name(),
		("none" if target == null else String(target.name)),
		("none" if assigned_worker_id.is_empty() else String(assigned_worker_id)),
	]


# -----------------------------------------------------------------------------
# Recording
# -----------------------------------------------------------------------------

## Records a state change. Called only by [TavernTaskService].
func record_state(
	new_state: State,
	reason: StringName,
	now_minutes: float
) -> void:
	var previous: State = state

	state = new_state

	state_history.append({
		"minutes": now_minutes,
		"from": State.keys()[previous],
		"to": State.keys()[new_state],
		"reason": String(reason),
	})


func record_reservation(
	action: StringName,
	subject: String,
	now_minutes: float
) -> void:
	reservation_history.append({
		"minutes": now_minutes,
		"action": String(action),
		"subject": subject,
	})


# -----------------------------------------------------------------------------
# Serialisation
# -----------------------------------------------------------------------------

## The report shape. Deliberately flat and JSON-safe.
func to_dictionary() -> Dictionary:
	var source: Node = get_source()
	var target: Node = get_target()

	return {
		"task_id": String(task_id),
		"task_type": String(task_type),
		"display_name": get_display_name(),
		"diagnostic_category": (
			"" if definition == null
			else String(definition.diagnostic_category)
		),
		"state": get_state_name(),
		"target_key": target_key,
		"source": ("" if source == null else String(source.name)),
		"source_data": source_data.duplicate(true),
		"target": ("" if target == null else String(target.name)),
		"required_item": (
			"" if required_definition == null
			else String(required_definition.item_id)
		),
		"required_quantity": required_quantity,
		"base_priority": (
			0.0 if definition == null else definition.base_priority
		),
		"urgency": urgency,
		"selected_score": selected_score,
		"assigned_worker": String(assigned_worker_id),
		"created_minutes": created_minutes,
		"claimed_minutes": claimed_minutes,
		"started_minutes": started_minutes,
		"finished_minutes": finished_minutes,
		"retry_count": retry_count,
		"invested_minutes": invested_minutes,
		"viability": last_viability.duplicate(true),
		"failure_count": failure_count,
		"last_failure_reason": String(last_failure_reason),
		"resolution_reason": String(resolution_reason),
		"state_history": state_history.duplicate(true),
		"reservation_history": reservation_history.duplicate(true),
		"metadata": metadata.duplicate(true),
	}
