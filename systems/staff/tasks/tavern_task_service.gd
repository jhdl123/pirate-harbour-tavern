class_name TavernTaskService
extends Node

## The single source of truth for work the tavern needs doing.
##
## Autoloaded as [code]TaskBoard[/code]. There is deliberately one board: two
## overlapping task managers is how a worker ends up serving a drink that was
## already served, and how a reservation leaks with nobody owning the cleanup.
##
## [b]The shape of the system[/b]
##
## [codeblock]
## world requirement                a chair is dirty, a customer is waiting
##   -> task producer               TavernTaskCoordinator, listening to signals
##   -> central task board          this class: dedup, claim, score, sweep
##   -> staff evaluates             StaffMember asks select_best_task()
##   -> claimed and reserved        claim() is atomic; reservations attach here
##   -> staff executes              StaffTaskExecutor drives the real world API
##   -> world confirms              the customer really was served
##   -> task completes              complete(), and the board tells everybody
## [/codeblock]
##
## [b]What this class does not do[/b]
##
## It never touches gameplay. It does not know what a drink is, cannot serve a
## customer, and has no opinion on whether a chair is dirty. Producers tell it
## what exists; validators tell it whether that is still true; executors do the
## work. That separation is what lets the player override staff freely - the
## board simply finds out the requirement went away and cancels the task.
##
## [b]Performance[/b]
##
## Nothing here scans the scene tree. Tasks are indexed by id, by type and by
## target key, so "is there already a cleaning task for this chair?" is a
## dictionary lookup rather than a search. The only periodic work is
## [method _sweep], which runs a few times a second over open tasks only.


## A task was added to the board.
signal task_created(task: TavernTask)

## Any state transition. The catch-all for UI and diagnostics.
signal task_state_changed(
	task: TavernTask,
	previous_state: TavernTask.State
)

## The world confirmed the requirement is met.
signal task_completed(task: TavernTask)

## The requirement stopped existing.
signal task_cancelled(task: TavernTask)

## The requirement existed and could not be met.
signal task_failed(task: TavernTask)

## Something worth writing down went wrong. See [method report_issue].
signal issue_reported(issue: Dictionary)


const DEFAULT_CONFIG_PATH: String = (
	"res://Data/staff/task_board_config.tres"
)

## Issue types, so producers, workers and reports agree on spelling.
const ISSUE_DUPLICATE_TASK: StringName = &"duplicate_task"
const ISSUE_STALE_CLAIM: StringName = &"stale_task_claim"
const ISSUE_LEAKED_RESERVATION: StringName = &"leaked_reservation"
const ISSUE_INVALID_TARGET: StringName = &"invalid_task_target"
const ISSUE_MISSING_DEFINITION: StringName = &"missing_task_definition"
const ISSUE_NAVIGATION_FAILED: StringName = &"staff_navigation_failed"
const ISSUE_MISSING_PREPARED_ITEM: StringName = &"missing_prepared_item"
const ISSUE_TRANSFER_FAILED: StringName = &"item_transfer_failure"
const ISSUE_DUPLICATE_SERVICE: StringName = &"attempted_duplicate_service"
const ISSUE_DUPLICATE_CLEANING: StringName = &"attempted_duplicate_cleaning"
const ISSUE_STUCK_RECOVERY: StringName = &"staff_stuck_recovery"


@export var config: TavernTaskBoardConfig = null


var _tasks_by_id: Dictionary = {}
var _tasks_by_target_key: Dictionary = {}

## task_type -> Array[TavernTask], open tasks only (AVAILABLE or BLOCKED).
var _open_by_type: Dictionary = {}

## Every task not yet in a terminal state, in creation order.
var _open_tasks: Array[TavernTask] = []

## Terminal tasks retained for the diagnostic report.
var _finished_tasks: Array[TavernTask] = []

## task_type -> Callable(task) -> bool. See [method register_validator].
var _validators: Dictionary = {}

var _issues: Array[Dictionary] = []

## Per-decision records for the exported report. Bounded.
var _decisions: Array[Dictionary] = []

## dedup key -> the decision record it refers to, so repeats update in place.
var _rejection_index: Dictionary = {}

var _decisions_dropped: int = 0
var _non_viable_rejections: int = 0

## resolution reason -> count, for the report's cancellation breakdown.
var _cancellation_reason_counts: Dictionary = {}
var _issues_dropped: int = 0
var _finished_tasks_dropped: int = 0

var _next_task_number: int = 1
var _sweep_elapsed: float = 0.0

## Session counters, cheap enough to keep unconditionally.
var _total_created: int = 0
var _total_completed: int = 0
var _total_cancelled: int = 0
var _total_failed: int = 0


func _ready() -> void:
	_resolve_config()

	process_mode = Node.PROCESS_MODE_ALWAYS


func _resolve_config() -> void:
	if config != null:
		config.validate_or_warn()
		return

	if ResourceLoader.exists(DEFAULT_CONFIG_PATH):
		config = load(DEFAULT_CONFIG_PATH) as TavernTaskBoardConfig

	if config == null:
		push_warning(
			"TaskBoard could not load "
			+ DEFAULT_CONFIG_PATH
			+ " - running with built-in defaults and no task definitions, "
			+ "so no task can be created."
		)

		config = TavernTaskBoardConfig.new()
		return

	config.validate_or_warn()


func _process(
	delta: float
) -> void:
	# The board is world simulation, so a paused game freezes it. Cooldowns
	# are real-time and continue to be read correctly on resume.
	if not Simulation.updates_actors():
		return

	_sweep_elapsed += delta

	if _sweep_elapsed < config.sweep_interval_seconds:
		return

	_sweep_elapsed = 0.0

	_sweep()


# -----------------------------------------------------------------------------
# Keys
# -----------------------------------------------------------------------------

## A stable deduplication key for work about [param node].
##
## Uses the instance id, which is unique for the lifetime of the node and
## therefore correct for both permanent furniture and transient customers.
static func build_node_key(
	task_type: StringName,
	node: Node
) -> String:
	if node == null:
		return ""

	return "%s:%d" % [String(task_type), node.get_instance_id()]


## A key for work about one slot of a multi-slot object.
static func build_slot_key(
	task_type: StringName,
	node: Node,
	slot_index: int
) -> String:
	if node == null:
		return ""

	return "%s:%d:%d" % [
		String(task_type),
		node.get_instance_id(),
		slot_index,
	]


# -----------------------------------------------------------------------------
# Creating
# -----------------------------------------------------------------------------

## Adds a requirement to the board, or returns the existing one.
##
## Deduplication is by [param target_key]: calling this twice for the same
## dirty chair returns the same task and records a
## [constant ISSUE_DUPLICATE_TASK] the second time. Producers are therefore
## free to be enthusiastic - "tell the board again" is always safe.
##
## [param options] may contain any of:
##
## [codeblock]
## source            Node    where something is collected from
## source_data       Dictionary
## target            Node    what the work is done to
## destination       Node    where the work ends, if not the target
## required_item     ItemDefinition
## required_quantity int
## urgency           float   0..1
## metadata          Dictionary
## [/codeblock]
func create_task(
	task_type: StringName,
	target_key: String,
	options: Dictionary = {}
) -> TavernTask:
	var existing: TavernTask = find_by_target_key(target_key)

	if existing != null and not existing.is_terminal():
		if options.has("urgency"):
			existing.urgency = clampf(float(options["urgency"]), 0.0, 1.0)

		return existing

	var definition: TavernTaskDefinition = config.find_definition(task_type)

	if definition == null:
		report_issue(
			ISSUE_MISSING_DEFINITION,
			"No TavernTaskDefinition is registered for task type '%s', so "
			% String(task_type)
			+ "the task was not created.",
			{ "target_key": target_key }
		)

		return null

	var task: TavernTask = TavernTask.new()

	task.task_id = StringName(
		"%s_%05d" % [String(task_type), _next_task_number]
	)

	_next_task_number += 1

	task.task_type = task_type
	task.definition = definition
	task.target_key = target_key
	task.created_minutes = _now_minutes()

	var source: Node = options.get("source", null) as Node
	var target: Node = options.get("target", null) as Node
	var destination: Node = options.get("destination", null) as Node

	if source != null:
		task.source_ref = weakref(source)

	if target != null:
		task.target_ref = weakref(target)

	if destination != null:
		task.destination_ref = weakref(destination)

	task.source_data = (
		options.get("source_data", {}) as Dictionary
	).duplicate(true)

	task.required_definition = (
		options.get("required_item", null) as ItemDefinition
	)

	task.required_quantity = int(options.get("required_quantity", 1))
	task.urgency = clampf(float(options.get("urgency", 0.0)), 0.0, 1.0)

	task.metadata = (
		options.get("metadata", {}) as Dictionary
	).duplicate(true)

	task.record_state(
		TavernTask.State.AVAILABLE,
		&"created",
		task.created_minutes
	)

	_index(task)

	_total_created += 1

	if config.console_debug_enabled:
		print("[TaskBoard] created ", task.describe())

	task_created.emit(task)

	return task


func _index(
	task: TavernTask
) -> void:
	_tasks_by_id[task.task_id] = task

	if not task.target_key.is_empty():
		_tasks_by_target_key[task.target_key] = task

	_open_tasks.append(task)

	_open_list_for(task.task_type).append(task)


func _open_list_for(
	task_type: StringName
) -> Array:
	if not _open_by_type.has(task_type):
		_open_by_type[task_type] = []

	return _open_by_type[task_type]


func _unindex(
	task: TavernTask
) -> void:
	_open_tasks.erase(task)
	_open_list_for(task.task_type).erase(task)

	if (
		not task.target_key.is_empty()
		and _tasks_by_target_key.get(task.target_key) == task
	):
		_tasks_by_target_key.erase(task.target_key)


# -----------------------------------------------------------------------------
# Reading
# -----------------------------------------------------------------------------

func get_task(
	task_id: StringName
) -> TavernTask:
	return _tasks_by_id.get(task_id) as TavernTask


func find_by_target_key(
	target_key: String
) -> TavernTask:
	if target_key.is_empty():
		return null

	return _tasks_by_target_key.get(target_key) as TavernTask


## Every task that has not reached a terminal state.
func get_open_tasks() -> Array[TavernTask]:
	var open: Array[TavernTask] = []

	open.assign(_open_tasks)

	return open


## Open tasks of one type. Indexed, so this is cheap enough to call often.
func get_open_tasks_of_type(
	task_type: StringName
) -> Array[TavernTask]:
	var open: Array[TavernTask] = []

	open.assign(_open_list_for(task_type))

	return open


## Tasks a worker could take right now.
func get_claimable_tasks() -> Array[TavernTask]:
	var claimable: Array[TavernTask] = []

	for task: TavernTask in _open_tasks:
		if task.is_claimable():
			claimable.append(task)

	return claimable


## Tasks currently owned by a worker.
func get_active_tasks() -> Array[TavernTask]:
	var active: Array[TavernTask] = []

	for task: TavernTask in _open_tasks:
		if task.is_active():
			active.append(task)

	return active


func get_tasks_for_worker(
	worker: Node
) -> Array[TavernTask]:
	var owned: Array[TavernTask] = []

	for task: TavernTask in _open_tasks:
		if task.is_held_by(worker):
			owned.append(task)

	return owned


func get_finished_tasks() -> Array[TavernTask]:
	var finished: Array[TavernTask] = []

	finished.assign(_finished_tasks)

	return finished


func get_open_task_count() -> int:
	return _open_tasks.size()


# -----------------------------------------------------------------------------
# Validators
# -----------------------------------------------------------------------------

## Registers "is this task still a real requirement?" for one task type.
##
## The board holds no gameplay knowledge, so it cannot answer this itself. The
## producer that creates a kind of task also registers how to re-check it, and
## the board calls that whenever it matters: on the sweep, before a claim, and
## before a worker acts.
##
## [param validator] takes a [TavernTask] and returns false when the
## requirement has gone away.
func register_validator(
	task_type: StringName,
	validator: Callable
) -> void:
	_validators[task_type] = validator


func unregister_validator(
	task_type: StringName
) -> void:
	_validators.erase(task_type)


## Re-asks the world whether [param task] is still needed.
##
## Cancels the task and returns false when it is not. This is the single method
## that makes player overrides work: nothing has to tell the board that the
## player cleaned a chair, because the next revalidate finds the chair clean.
func revalidate(
	task: TavernTask
) -> bool:
	if task == null:
		return false

	if task.is_terminal():
		return false

	# A worker has already done the work and is one tick away from saying so.
	# Re-asking the world now would cancel a task that succeeded.
	if task.is_resolution_pending:
		return true

	if config.cancel_tasks_with_missing_targets:
		if task.target_ref != null and task.get_target() == null:
			cancel(task, &"target_removed")
			return false

	if not _validators.has(task.task_type):
		return true

	var validator: Callable = _validators[task.task_type]

	if not validator.is_valid():
		return true

	if bool(validator.call(task)):
		return true

	cancel(task, &"no_longer_required")

	return false


# -----------------------------------------------------------------------------
# Scoring and selection
# -----------------------------------------------------------------------------

## How attractive [param task] is to [param worker]. Higher wins.
##
## Kept deliberately readable: every term is one line, every weight lives on
## the task's own [TavernTaskDefinition], and [method explain_score] prints the
## same terms so a surprising choice can always be accounted for.
func score_task(
	task: TavernTask,
	worker: Node
) -> float:
	return float(_score_terms(task, worker)["total"])


## The score broken into its parts, for developer tools and reports.
func explain_score(
	task: TavernTask,
	worker: Node
) -> Dictionary:
	return _score_terms(task, worker)


func _score_terms(
	task: TavernTask,
	worker: Node
) -> Dictionary:
	var definition: TavernTaskDefinition = task.definition

	if definition == null:
		return { "total": 0.0 }

	var base: float = definition.base_priority
	var urgency_term: float = task.urgency * definition.urgency_weight

	var age_term: float = definition.get_age_bonus(
		task.get_age_minutes(_now_minutes())
	)

	var distance_term: float = 0.0
	var worker_2d: Node2D = worker as Node2D

	if worker_2d != null and definition.distance_weight > 0.0:
		var distance: float = worker_2d.global_position.distance_to(
			task.get_reference_position()
		)

		distance_term = -(distance / 100.0) * definition.distance_weight

	var carried_term: float = 0.0

	if task.required_definition != null and _worker_carries(worker, task):
		carried_term = definition.carried_item_bonus

	var failure_term: float = (
		-float(task.failure_count) * definition.failure_penalty
	)

	# The term added in Phase 3A.1. Urgency alone actively selects doomed work,
	# because the most urgent customer is very often the one about to leave;
	# this is what pulls the score back down for a job that cannot be finished
	# in time.
	var viability_term: float = float(
		task.last_viability.get("score", 0.0)
	)

	var total: float = (
		base
		+ urgency_term
		+ age_term
		+ distance_term
		+ carried_term
		+ failure_term
		+ viability_term
	)

	return {
		"task_id": String(task.task_id),
		"base_priority": base,
		"urgency": urgency_term,
		"age": age_term,
		"distance": distance_term,
		"already_carrying": carried_term,
		"previous_failures": failure_term,
		"viability": viability_term,
		"viability_verdict": String(
			task.last_viability.get("verdict_name", "UNKNOWN")
		),
		"estimated_minutes": float(
			task.last_viability.get("estimated_minutes", -1.0)
		),
		"margin_minutes": float(
			task.last_viability.get("margin_minutes", 0.0)
		),
		"total": total,
	}


func _worker_carries(
	worker: Node,
	task: TavernTask
) -> bool:
	if worker == null or not worker.has_method(&"get_item_carrier"):
		return false

	var carrier: ItemCarrier = worker.get_item_carrier() as ItemCarrier

	if carrier == null:
		return false

	return carrier.is_carrying_item(task.required_definition.item_id)


## The best task [param worker] could take right now, or null.
##
## Filters first, scores second: capability and executor checks are cheap and
## rule most candidates out before any distance maths happens.
## The best task [param worker] could take right now, or null.
##
## Every candidate is put through the same gauntlet, cheapest test first, and
## every rejection is recorded with a reason. That ordering matters twice over:
## it keeps evaluation affordable, and it means the exported report can say
## "forty tasks were rejected because the customer would have left before I
## arrived" instead of leaving a reader to infer it from a completion rate.
##
## [param current_task] is the worker's existing job, if any. Passing it in
## enables the commitment rules: a worker will not drop real work for a
## marginally better alternative, and will not consider switching at all
## during the first
## [member TavernTaskBoardConfig.minimum_commitment_minutes] of a claim.
func select_best_task(
	worker: Node,
	capabilities: Array[StringName],
	current_task: TavernTask = null
) -> TavernTask:
	var best: TavernTask = null
	var best_score: float = -INF
	var worker_id: StringName = _get_worker_id(worker)

	# The best candidate that failed only the viability gate. Kept so a worker
	# with no achievable work can still attempt the least hopeless job rather
	# than standing still - see
	# TaskViabilityConfig.accept_best_non_viable_when_idle.
	var best_long_shot: TavernTask = null
	var best_long_shot_score: float = -INF

	var considered: int = 0

	for task: TavernTask in _open_tasks:
		if task == current_task:
			continue

		if not task.is_claimable():
			continue

		if task.definition == null:
			continue

		considered += 1

		if not StaffCapabilities.satisfies(
			capabilities,
			task.definition.required_capabilities
		):
			_record_rejection(
				worker_id,
				task,
				StaffTransitionReason.CAPABILITY_MISMATCH,
				{}
			)
			continue

		# A worker must not walk off to clean a table with a customer's drink
		# still in its hand. This is the check whose absence produced the
		# Phase 3A defect.
		var executor: StaffTaskExecutor = StaffTaskExecutor.create_for(
			task.task_type
		)

		if executor == null:
			_record_rejection(
				worker_id,
				task,
				StaffTransitionReason.NO_EXECUTOR,
				{}
			)
			continue

		if not executor.is_compatible_with_carried_item(worker, task):
			_record_rejection(
				worker_id,
				task,
				StaffTransitionReason.CARRIED_ITEM_INCOMPATIBLE,
				{ "carried": String(_get_carried_id(worker)) }
			)
			continue

		if _is_in_reclaim_cooldown(task, worker_id):
			_record_rejection(
				worker_id,
				task,
				StaffTransitionReason.CLAIM_COOLDOWN,
				{}
			)
			continue

		if not executor.can_claim(worker, task):
			_record_rejection(
				worker_id,
				task,
				StaffTransitionReason.EXECUTOR_REFUSED,
				{}
			)
			continue

		if not revalidate(task):
			_record_rejection(
				worker_id,
				task,
				StaffTransitionReason.NO_LONGER_REQUIRED,
				{}
			)
			continue

		var viability: Dictionary = _evaluate_viability(worker, task, executor)

		if not bool(viability.get("permits_claim", true)):
			_record_rejection(
				worker_id,
				task,
				StaffTransitionReason.NOT_VIABLE,
				viability
			)

			var long_shot_score: float = score_task(task, worker)

			if long_shot_score > best_long_shot_score:
				best_long_shot_score = long_shot_score
				best_long_shot = task

			continue

		var score: float = score_task(task, worker)

		if score > best_score:
			best_score = score
			best = task

	# Nothing achievable. Rather than idle, take the least hopeless job if the
	# configuration allows it: an idle worker definitely serves nobody.
	if best == null and best_long_shot != null:
		var viability_config: TaskViabilityConfig = get_viability_config()

		if (
			viability_config != null
			and viability_config.accept_best_non_viable_when_idle
			and current_task == null
		):
			_record_decision(
				worker_id,
				best_long_shot,
				true,
				StaffTransitionReason.NOT_VIABLE,
				best_long_shot_score,
				best_long_shot.last_viability,
				considered
			)

			return best_long_shot

	if best == null:
		return null

	# Switching away from real work needs to be worth it. Without a margin a
	# worker abandons a job the instant an alternative scores one point
	# higher, and then abandons that one on the way back.
	if current_task != null and not current_task.is_terminal():
		if not _may_switch_from(current_task, best_score, worker):
			return null

	_record_decision(
		worker_id,
		best,
		true,
		StaffTransitionReason.TASK_CLAIMED,
		best_score,
		best.last_viability,
		considered
	)

	return best


## Whether a worker holding [param current_task] should drop it.
func _may_switch_from(
	current_task: TavernTask,
	candidate_score: float,
	worker: Node
) -> bool:
	if current_task.claimed_minutes >= 0.0:
		var held_for: float = _now_minutes() - current_task.claimed_minutes

		if held_for < config.minimum_commitment_minutes:
			return false

	var current_score: float = score_task(current_task, worker)

	return candidate_score > current_score + config.task_switch_score_margin


## True when [param worker_id] released this task too recently to retake it.
func _is_in_reclaim_cooldown(
	task: TavernTask,
	worker_id: StringName
) -> bool:
	if task.last_released_by.is_empty():
		return false

	if task.last_released_by != worker_id:
		return false

	var elapsed_ms: int = Time.get_ticks_msec() - task.last_released_ticks_ms

	return elapsed_ms < int(
		config.same_worker_reclaim_cooldown_seconds * 1000.0
	)


## Runs, caches and records a viability estimate for [param task].
##
## Cached against the task rather than recomputed per candidate per tick: the
## expensive part is the navigation query, and a fraction of a second of
## staleness costs nothing when the safety buffer is measured in minutes.
func _evaluate_viability(
	worker: Node,
	task: TavernTask,
	executor: StaffTaskExecutor
) -> Dictionary:
	var viability_config: TaskViabilityConfig = get_viability_config()

	if viability_config == null or not viability_config.enabled:
		return { "permits_claim": true }

	var age_ms: int = Time.get_ticks_msec() - task.last_viability_ticks_ms

	var interval_ms: int = int(
		viability_config.reevaluation_interval_seconds * 1000.0
	)

	var is_fresh: bool = (
		not task.last_viability.is_empty()
		and age_ms < interval_ms
	)

	# A previously non-viable task is re-checked promptly, because the thing
	# most likely to have changed is the worker's own position - it may have
	# walked much closer while doing something else.
	if is_fresh:
		var previous_verdict: int = int(
			task.last_viability.get(
				"verdict",
				TaskViabilityConfig.Verdict.UNKNOWN
			)
		)

		if previous_verdict != TaskViabilityConfig.Verdict.NON_VIABLE:
			return task.last_viability

	var viability: Dictionary = TaskViability.evaluate(
		worker,
		task,
		executor,
		viability_config
	)

	# A task type may scale its own sensitivity without touching the shared
	# weights - or opt out entirely with a weight of zero.
	if task.definition != null and task.definition.viability_weight != 1.0:
		viability["score"] = (
			float(viability.get("score", 0.0))
			* task.definition.viability_weight
		)

	task.last_viability = viability
	task.last_viability_ticks_ms = Time.get_ticks_msec()

	return viability


func get_viability_config() -> TaskViabilityConfig:
	if config == null:
		return null

	return config.viability_config


# -----------------------------------------------------------------------------
# Transitions
# -----------------------------------------------------------------------------

## Takes [param task] for [param worker]. Atomic.
##
## Two workers cannot both succeed here: the state check and the assignment
## happen with no await between them, so whichever call runs second sees a task
## that is no longer AVAILABLE and is refused.
func claim(
	task: TavernTask,
	worker: Node,
	worker_id: StringName
) -> bool:
	if task == null or worker == null:
		return false

	if not task.is_claimable():
		return false

	if not revalidate(task):
		return false

	var previous: TavernTask.State = task.state

	task.assigned_worker_ref = weakref(worker)
	task.assigned_worker_id = worker_id
	task.claimed_minutes = _now_minutes()
	task.selected_score = score_task(task, worker)

	task.record_state(
		TavernTask.State.CLAIMED,
		&"claimed",
		task.claimed_minutes
	)

	if config.console_debug_enabled:
		print("[TaskBoard] claimed ", task.describe())

	task_state_changed.emit(task, previous)

	return true


## Marks the worker as having arrived and started acting.
func begin(
	task: TavernTask
) -> bool:
	if task == null or task.state != TavernTask.State.CLAIMED:
		return false

	var previous: TavernTask.State = task.state

	task.started_minutes = _now_minutes()

	task.record_state(
		TavernTask.State.IN_PROGRESS,
		&"started",
		task.started_minutes
	)

	task_state_changed.emit(task, previous)

	return true


## The world confirmed the requirement is met.
func complete(
	task: TavernTask,
	reason: StringName = &"completed"
) -> bool:
	if task == null or task.is_terminal():
		return false

	var previous: TavernTask.State = task.state

	_bank_invested_time(task)

	release_reservations(task)

	task.finished_minutes = _now_minutes()
	task.resolution_reason = reason

	task.record_state(
		TavernTask.State.COMPLETED,
		reason,
		task.finished_minutes
	)

	_retire(task)

	_total_completed += 1

	if config.console_debug_enabled:
		print("[TaskBoard] completed ", task.describe())

	task_state_changed.emit(task, previous)
	task_completed.emit(task)

	return true


## The requirement stopped existing. Not a failure.
func cancel(
	task: TavernTask,
	reason: StringName = &"cancelled"
) -> bool:
	if task == null or task.is_terminal():
		return false

	var previous: TavernTask.State = task.state

	_bank_invested_time(task)

	release_reservations(task)

	task.finished_minutes = _now_minutes()
	task.resolution_reason = reason

	task.record_state(
		TavernTask.State.CANCELLED,
		reason,
		task.finished_minutes
	)

	_retire(task)

	_total_cancelled += 1

	var reason_key: String = String(reason)

	if not StaffTransitionReason.is_cancellation_reason(reason):
		reason_key = String(StaffTransitionReason.OTHER)

	_cancellation_reason_counts[reason_key] = int(
		_cancellation_reason_counts.get(reason_key, 0)
	) + 1

	if config.console_debug_enabled:
		print("[TaskBoard] cancelled ", task.describe(), " (", reason, ")")

	task_state_changed.emit(task, previous)
	task_cancelled.emit(task)

	return true


## Hands [param task] back to the board, still needed and still doable.
##
## The normal response to "something changed under me". Costs one retry and a
## short cooldown so the same worker does not immediately re-take it and spin.
func release(
	task: TavernTask,
	reason: StringName = &"released"
) -> bool:
	if task == null or task.is_terminal():
		return false

	var previous: TavernTask.State = task.state

	release_reservations(task)

	task.is_resolution_pending = false
	_bank_invested_time(task)

	# Remembering who released this, and when, is what stops the tightest
	# oscillation the board can produce: the same worker re-claiming the task
	# it let go of on the very next evaluation.
	task.last_released_by = task.assigned_worker_id
	task.last_released_ticks_ms = Time.get_ticks_msec()

	task.assigned_worker_ref = null
	task.assigned_worker_id = &""
	task.claimed_minutes = -1.0
	task.started_minutes = -1.0
	task.retry_count += 1

	task.cooldown_until_ticks_ms = (
		Time.get_ticks_msec()
		+ int(task.definition.retry_cooldown_seconds * 1000.0)
	)

	task.record_state(
		TavernTask.State.AVAILABLE,
		reason,
		_now_minutes()
	)

	if config.console_debug_enabled:
		print("[TaskBoard] released ", task.describe(), " (", reason, ")")

	task_state_changed.emit(task, previous)

	# A task released more times than its definition allows has effectively
	# defeated the tavern, and repeating it forever is worse than admitting it.
	if task.retry_count > task.definition.maximum_retries:
		fail(task, reason)

	return true


## The requirement existed and could not be met.
##
## Below [member TavernTaskDefinition.maximum_failures] this puts the task back
## on the board for another attempt; at the limit it is retired as FAILED.
func fail(
	task: TavernTask,
	reason: StringName = &"failed"
) -> bool:
	if task == null or task.is_terminal():
		return false

	task.failure_count += 1
	task.last_failure_reason = reason

	_bank_invested_time(task)

	var previous: TavernTask.State = task.state

	release_reservations(task)

	task.is_resolution_pending = false
	task.assigned_worker_ref = null
	task.assigned_worker_id = &""

	if task.failure_count < task.definition.maximum_failures:
		task.retry_count = 0

		task.cooldown_until_ticks_ms = (
			Time.get_ticks_msec()
			+ int(task.definition.retry_cooldown_seconds * 1000.0)
		)

		task.record_state(
			TavernTask.State.AVAILABLE,
			reason,
			_now_minutes()
		)

		task_state_changed.emit(task, previous)

		return true

	task.finished_minutes = _now_minutes()
	task.resolution_reason = reason

	task.record_state(
		TavernTask.State.FAILED,
		reason,
		task.finished_minutes
	)

	_retire(task)

	_total_failed += 1

	report_issue(
		reason,
		"Task %s failed %d times and was abandoned."
		% [String(task.task_id), task.failure_count],
		{ "task_id": String(task.task_id) }
	)

	task_state_changed.emit(task, previous)
	task_failed.emit(task)

	return true


## Marks a task as still needed but not currently doable.
func block(
	task: TavernTask,
	reason: StringName = &"blocked"
) -> bool:
	if task == null or task.is_terminal():
		return false

	if task.state == TavernTask.State.BLOCKED:
		return false

	var previous: TavernTask.State = task.state

	release_reservations(task)

	task.is_resolution_pending = false
	task.assigned_worker_ref = null
	task.assigned_worker_id = &""

	task.record_state(
		TavernTask.State.BLOCKED,
		reason,
		_now_minutes()
	)

	task_state_changed.emit(task, previous)

	return true


func unblock(
	task: TavernTask,
	reason: StringName = &"unblocked"
) -> bool:
	if task == null or task.state != TavernTask.State.BLOCKED:
		return false

	var previous: TavernTask.State = task.state

	task.record_state(
		TavernTask.State.AVAILABLE,
		reason,
		_now_minutes()
	)

	task_state_changed.emit(task, previous)

	return true


func set_urgency(
	task: TavernTask,
	urgency: float
) -> void:
	if task == null:
		return

	task.urgency = clampf(urgency, 0.0, 1.0)


func _retire(
	task: TavernTask
) -> void:
	_unindex(task)

	_finished_tasks.append(task)

	while _finished_tasks.size() > config.maximum_retained_finished_tasks:
		_finished_tasks.pop_front()
		_finished_tasks_dropped += 1


# -----------------------------------------------------------------------------
# Reservations
# -----------------------------------------------------------------------------

## Claims [param reservable] on behalf of [param task].
##
## The board keeps the list so that every path out of a task - complete,
## cancel, release, fail, sweep - releases the same set. That single ownership
## is what stops reservations leaking when a worker is destroyed mid-journey.
func add_reservation(
	task: TavernTask,
	reservable: Reservable,
	actor: Node
) -> bool:
	if task == null or reservable == null or actor == null:
		return false

	if not reservable.reserve(actor):
		return false

	if not task.reservations.has(reservable):
		task.reservations.append(reservable)

	task.record_reservation(
		&"reserved",
		String(reservable.get_path()),
		_now_minutes()
	)

	return true


func release_reservations(
	task: TavernTask
) -> void:
	if task == null:
		return

	for reservable: Reservable in task.reservations:
		if reservable == null or not is_instance_valid(reservable):
			continue

		reservable.release()

		task.record_reservation(
			&"released",
			String(reservable.get_path()),
			_now_minutes()
		)

	task.reservations.clear()


# -----------------------------------------------------------------------------
# Sweep
# -----------------------------------------------------------------------------

## Periodic housekeeping over open tasks only.
##
## Four jobs, none of which any other system should have to remember:
## re-test blocked tasks, revalidate open ones, take back claims from workers
## that have vanished, and time out claims that are going nowhere.
func _sweep() -> void:
	# Iterate a copy: cancelling inside the loop mutates the real list.
	var snapshot: Array[TavernTask] = get_open_tasks()

	for task: TavernTask in snapshot:
		if task.is_terminal():
			continue

		if task.state == TavernTask.State.CLAIMED or task.state == TavernTask.State.IN_PROGRESS:
			_sweep_active(task)
			continue

		revalidate(task)


func _sweep_active(
	task: TavernTask
) -> void:
	if task.get_assigned_worker() == null:
		report_issue(
			ISSUE_STALE_CLAIM,
			"Task %s was held by a worker that no longer exists."
			% String(task.task_id),
			{ "task_id": String(task.task_id) }
		)

		release(task, &"worker_lost")
		return

	if not revalidate(task):
		return

	var timeout: int = task.definition.timeout_world_minutes

	if timeout <= 0:
		return

	if task.claimed_minutes < 0.0:
		return

	if _now_minutes() - task.claimed_minutes < float(timeout):
		return

	report_issue(
		ISSUE_STALE_CLAIM,
		"Task %s exceeded its %d world-minute timeout and was taken back."
		% [String(task.task_id), timeout],
		{ "task_id": String(task.task_id) }
	)

	fail(task, &"timed_out")


# -----------------------------------------------------------------------------
# Decision records
# -----------------------------------------------------------------------------

## Records that a worker accepted a task, and on what evidence.
##
## One record per claim, not per frame. The whole point of the Phase 3A.1
## diagnostic work is that a report should explain a decision; recording
## every evaluation of every candidate would bury that in noise and cost more
## than the decision itself.
func _record_decision(
	worker_id: StringName,
	task: TavernTask,
	accepted: bool,
	reason: StringName,
	score: float,
	viability: Dictionary,
	candidates_considered: int
) -> void:
	if config == null or not config.record_decisions:
		return

	_decisions.append({
		"world_minutes": _now_minutes(),
		"worker_id": String(worker_id),
		"task_id": String(task.task_id),
		"task_type": String(task.task_type),
		"accepted": accepted,
		"reason": String(reason),
		"final_score": score,
		"base_priority": (
			0.0 if task.definition == null else task.definition.base_priority
		),
		"urgency": task.urgency,
		"candidates_considered": candidates_considered,
		"estimated_minutes": float(
			viability.get("estimated_minutes", -1.0)
		),
		"margin_minutes": float(viability.get("margin_minutes", 0.0)),
		"viability_verdict": String(
			viability.get("verdict_name", "UNKNOWN")
		),
		"repeat_count": 1,
	})

	_trim_decisions()


## Records that a worker looked at a task and did not take it.
##
## Deduplicated by (worker, task, reason): one customer the worker cannot
## reach in time would otherwise generate a record on every evaluation for as
## long as they sat there. The count is kept, because "rejected this eighty
## times" is itself worth knowing.
func _record_rejection(
	worker_id: StringName,
	task: TavernTask,
	reason: StringName,
	viability: Dictionary
) -> void:
	if config == null or not config.record_decisions:
		return

	if not config.record_rejections:
		return

	if config.deduplicate_rejections:
		var key: String = "%s|%s|%s" % [
			String(worker_id),
			String(task.task_id),
			String(reason),
		]

		if _rejection_index.has(key):
			var existing: Dictionary = _rejection_index[key]

			existing["repeat_count"] = int(existing["repeat_count"]) + 1
			existing["world_minutes"] = _now_minutes()

			return

		var record: Dictionary = _build_rejection(
			worker_id,
			task,
			reason,
			viability
		)

		_rejection_index[key] = record
		_decisions.append(record)

		_trim_decisions()

		return

	_decisions.append(
		_build_rejection(worker_id, task, reason, viability)
	)

	_trim_decisions()


func _build_rejection(
	worker_id: StringName,
	task: TavernTask,
	reason: StringName,
	viability: Dictionary
) -> Dictionary:
	if reason == StaffTransitionReason.NOT_VIABLE:
		_non_viable_rejections += 1

	return {
		"world_minutes": _now_minutes(),
		"worker_id": String(worker_id),
		"task_id": String(task.task_id),
		"task_type": String(task.task_type),
		"accepted": false,
		"reason": String(reason),
		"final_score": 0.0,
		"base_priority": (
			0.0 if task.definition == null else task.definition.base_priority
		),
		"urgency": task.urgency,
		"candidates_considered": 0,
		"estimated_minutes": float(viability.get("estimated_minutes", -1.0)),
		"margin_minutes": float(viability.get("margin_minutes", 0.0)),
		"viability_verdict": String(
			viability.get("verdict_name", "UNKNOWN")
		),
		"repeat_count": 1,
	}


func _trim_decisions() -> void:
	while _decisions.size() > config.maximum_retained_decisions:
		var dropped: Dictionary = _decisions.pop_front()

		_decisions_dropped += 1

		# Keep the dedup index honest, or a trimmed record would be updated
		# forever without ever reappearing in the report.
		for key: String in _rejection_index.keys():
			if _rejection_index[key] == dropped:
				_rejection_index.erase(key)
				break


## World minutes a worker had already spent on this task, banked so the report
## can distinguish a cheap cancellation from an expensive one.
func _bank_invested_time(
	task: TavernTask
) -> void:
	if task.claimed_minutes < 0.0:
		return

	task.invested_minutes += maxf(
		_now_minutes() - task.claimed_minutes,
		0.0
	)


func _get_worker_id(
	worker: Node
) -> StringName:
	if worker != null and worker.has_method(&"get_staff_id"):
		return worker.call(&"get_staff_id")

	return &"unknown"


func _get_carried_id(
	worker: Node
) -> StringName:
	if worker == null or not worker.has_method(&"get_item_carrier"):
		return &""

	var carrier: ItemCarrier = worker.get_item_carrier() as ItemCarrier

	return &"" if carrier == null else carrier.get_carried_item_id()


func get_decisions() -> Array[Dictionary]:
	return _decisions.duplicate(true)


# -----------------------------------------------------------------------------
# Issues
# -----------------------------------------------------------------------------

## Records something worth investigating.
##
## Deliberately not the same thing as a failure. Expected recovery - a customer
## leaving before their drink arrives - is normal and still worth being able to
## see in a report, so the report separates "issue happened" from "issue was
## severe".
func report_issue(
	issue_type: StringName,
	message: String,
	context: Dictionary = {}
) -> void:
	var issue: Dictionary = {
		"issue_type": String(issue_type),
		"message": message,
		"world_minutes": _now_minutes(),
		"context": context.duplicate(true),
	}

	_issues.append(issue)

	while _issues.size() > config.maximum_retained_issues:
		_issues.pop_front()
		_issues_dropped += 1

	if config.console_debug_enabled:
		print("[TaskBoard][issue] ", issue_type, ": ", message)

	issue_reported.emit(issue)


func get_issues() -> Array[Dictionary]:
	return _issues.duplicate(true)


# -----------------------------------------------------------------------------
# Diagnostics
# -----------------------------------------------------------------------------

## Session totals, for the report and the F10 panel.
func get_summary() -> Dictionary:
	var by_state: Dictionary = {}

	for task: TavernTask in _open_tasks:
		var key: String = task.get_state_name()

		by_state[key] = int(by_state.get(key, 0)) + 1

	return {
		"tasks_created": _total_created,
		"tasks_completed": _total_completed,
		"tasks_cancelled": _total_cancelled,
		"tasks_failed": _total_failed,
		"tasks_open": _open_tasks.size(),
		"open_by_state": by_state,
		"issues_recorded": _issues.size(),
		"issues_dropped": _issues_dropped,
		"decisions_recorded": _decisions.size(),
		"decisions_dropped": _decisions_dropped,
		"non_viable_rejections": _non_viable_rejections,
		"finished_tasks_dropped": _finished_tasks_dropped,
	}


## Everything the report needs about tasks.
func build_report_section() -> Dictionary:
	var open: Array = []
	var finished: Array = []

	for task: TavernTask in _open_tasks:
		open.append(task.to_dictionary())

	for task: TavernTask in _finished_tasks:
		finished.append(task.to_dictionary())

	return {
		"summary": get_summary(),
		"by_task_type": build_task_type_breakdown(),
		"cancellation_reasons": get_cancellation_reason_counts(),
		"viability_distribution": build_viability_distribution(),
		"decisions": get_decisions(),
		"open_tasks": open,
		"finished_tasks": finished,
		"issues": get_issues(),
	}


## Per-task-type totals, rates and averages.
##
## Built from the retained task records rather than from running counters, so
## it stays correct if a task moves through an unusual sequence of states.
func build_task_type_breakdown() -> Dictionary:
	var breakdown: Dictionary = {}

	var all_tasks: Array[TavernTask] = get_open_tasks()

	all_tasks.append_array(_finished_tasks)

	for task: TavernTask in all_tasks:
		var key: String = String(task.task_type)

		if not breakdown.has(key):
			breakdown[key] = {
				"created": 0,
				"claimed": 0,
				"completed": 0,
				"cancelled": 0,
				"failed": 0,
				"open": 0,
				"_claim_delay_total": 0.0,
				"_claim_delay_count": 0,
				"_execution_total": 0.0,
				"_execution_count": 0,
				"_lifetime_total": 0.0,
				"_lifetime_count": 0,
				"_invested_before_cancel_total": 0.0,
				"_invested_before_cancel_count": 0,
			}

		var entry: Dictionary = breakdown[key]

		entry["created"] = int(entry["created"]) + 1

		if task.claimed_minutes >= 0.0 or not task.assigned_worker_id.is_empty():
			entry["claimed"] = int(entry["claimed"]) + 1

		match task.state:
			TavernTask.State.COMPLETED:
				entry["completed"] = int(entry["completed"]) + 1

			TavernTask.State.CANCELLED:
				entry["cancelled"] = int(entry["cancelled"]) + 1

				entry["_invested_before_cancel_total"] = (
					float(entry["_invested_before_cancel_total"])
					+ task.invested_minutes
				)

				entry["_invested_before_cancel_count"] = int(
					entry["_invested_before_cancel_count"]
				) + 1

			TavernTask.State.FAILED:
				entry["failed"] = int(entry["failed"]) + 1

			_:
				entry["open"] = int(entry["open"]) + 1

		if task.claimed_minutes >= 0.0:
			entry["_claim_delay_total"] = (
				float(entry["_claim_delay_total"])
				+ maxf(task.claimed_minutes - task.created_minutes, 0.0)
			)

			entry["_claim_delay_count"] = int(entry["_claim_delay_count"]) + 1

		if task.started_minutes >= 0.0 and task.finished_minutes >= 0.0:
			entry["_execution_total"] = (
				float(entry["_execution_total"])
				+ maxf(task.finished_minutes - task.started_minutes, 0.0)
			)

			entry["_execution_count"] = int(entry["_execution_count"]) + 1

		if task.finished_minutes >= 0.0:
			entry["_lifetime_total"] = (
				float(entry["_lifetime_total"])
				+ maxf(task.finished_minutes - task.created_minutes, 0.0)
			)

			entry["_lifetime_count"] = int(entry["_lifetime_count"]) + 1

	# Count non-viable rejections per type from the decision log.
	for decision: Dictionary in _decisions:
		if String(decision.get("reason", "")) != String(
			StaffTransitionReason.NOT_VIABLE
		):
			continue

		var key: String = String(decision.get("task_type", ""))

		if not breakdown.has(key):
			continue

		breakdown[key]["rejected_non_viable"] = int(
			breakdown[key].get("rejected_non_viable", 0)
		) + int(decision.get("repeat_count", 1))

	for key: String in breakdown.keys():
		_finalise_breakdown_entry(breakdown[key])

	return breakdown


func _finalise_breakdown_entry(
	entry: Dictionary
) -> void:
	entry["average_claim_delay_minutes"] = _safe_average(
		entry["_claim_delay_total"],
		entry["_claim_delay_count"]
	)

	entry["average_execution_minutes"] = _safe_average(
		entry["_execution_total"],
		entry["_execution_count"]
	)

	entry["average_lifetime_minutes"] = _safe_average(
		entry["_lifetime_total"],
		entry["_lifetime_count"]
	)

	entry["average_invested_before_cancel_minutes"] = _safe_average(
		entry["_invested_before_cancel_total"],
		entry["_invested_before_cancel_count"]
	)

	var resolved: int = (
		int(entry["completed"])
		+ int(entry["cancelled"])
		+ int(entry["failed"])
	)

	entry["completion_rate"] = _safe_average(
		float(entry["completed"]),
		resolved
	)

	entry["cancellation_rate"] = _safe_average(
		float(entry["cancelled"]),
		resolved
	)

	if not entry.has("rejected_non_viable"):
		entry["rejected_non_viable"] = 0

	# Drop the working totals: they are scaffolding, not findings.
	for working_key: String in [
		"_claim_delay_total",
		"_claim_delay_count",
		"_execution_total",
		"_execution_count",
		"_lifetime_total",
		"_lifetime_count",
		"_invested_before_cancel_total",
		"_invested_before_cancel_count",
	]:
		entry.erase(working_key)


static func _safe_average(
	total: float,
	count: int
) -> float:
	return 0.0 if count <= 0 else total / float(count)


func get_cancellation_reason_counts() -> Dictionary:
	return _cancellation_reason_counts.duplicate(true)


## How the last-known viability verdicts are spread across live tasks.
func build_viability_distribution() -> Dictionary:
	var buckets: Dictionary = {
		"VIABLE": 0,
		"MARGINAL": 0,
		"NON_VIABLE": 0,
		"UNKNOWN": 0,
		"NOT_EVALUATED": 0,
	}

	var all_tasks: Array[TavernTask] = get_open_tasks()

	all_tasks.append_array(_finished_tasks)

	for task: TavernTask in all_tasks:
		if task.last_viability.is_empty():
			buckets["NOT_EVALUATED"] = int(buckets["NOT_EVALUATED"]) + 1
			continue

		var verdict: String = String(
			task.last_viability.get("verdict_name", "UNKNOWN")
		)

		buckets[verdict] = int(buckets.get(verdict, 0)) + 1

	buckets["non_viable_rejections_recorded"] = _non_viable_rejections

	return buckets


## Clears everything. Developer tooling and scene reloads only.
func reset() -> void:
	for task: TavernTask in get_open_tasks():
		release_reservations(task)

	_tasks_by_id.clear()
	_tasks_by_target_key.clear()
	_open_by_type.clear()
	_open_tasks.clear()
	_finished_tasks.clear()
	_issues.clear()
	_decisions.clear()
	_rejection_index.clear()
	_cancellation_reason_counts.clear()

	_decisions_dropped = 0
	_non_viable_rejections = 0
	_issues_dropped = 0
	_finished_tasks_dropped = 0
	_total_created = 0
	_total_completed = 0
	_total_cancelled = 0
	_total_failed = 0


func _now_minutes() -> float:
	return WorldTime.get_total_minutes_precise()
