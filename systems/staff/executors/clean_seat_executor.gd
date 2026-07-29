class_name CleanSeatExecutor
extends StaffTaskExecutor

## Runs the tavern's existing cleaning action on a dirty seat.
##
## The worker never sets a cleanliness flag. It calls
## [method Chair.try_clean], which is the same method the player's own
## interaction calls, which starts the same [ActionDefinition] on the worker's
## own [ActionRunner], via the same [CleanableComponent]. Duration, cancellation
## and the broken-glass complication therefore behave identically whoever is
## holding the rag.
##
## The only thing the worker brings of its own is an [ActionRunner], which is a
## component on its scene exactly as it is on the player's.
##
## [b]Player overrides[/b]
##
## If the player cleans the seat first, [method CleanableComponent.can_start_cleaning]
## simply returns false and the task's validator finds the chair clean, so the
## task is cancelled before the worker acts. If the player starts cleaning while
## the worker is walking over, the same check refuses the worker a second run:
## one cleaning action, one seat, always.


## True between starting the action and seeing it finish.
var _is_cleaning: bool = false

## Watches the chair rather than the runner, because the chair is what knows
## whether cleaning actually resolved or turned into broken glass.
var _watched_chair: Chair = null

var _cleaning_finished: bool = false
var _cleaning_succeeded: bool = false

## The task being cleaned for, so the signal handlers can reach it.
var _pending_task: TavernTask = null


func can_claim(
	worker: Node,
	task: TavernTask
) -> bool:
	var chair: Chair = task.get_target() as Chair

	if chair == null or chair.cleanable == null:
		return false

	if not chair.cleanable.can_start_cleaning():
		return false

	var runner: ActionRunner = get_action_runner(worker)

	if runner == null or runner.is_running:
		return false

	return true


func get_next_step(
	worker: Node,
	task: TavernTask
) -> StaffTaskStep:
	var chair: Chair = task.get_target() as Chair

	if chair == null or not is_instance_valid(chair):
		return StaffTaskStep.fail(&"chair_missing")

	if _is_cleaning:
		return StaffTaskStep.wait(0.2, "cleaning")

	if _cleaning_finished:
		if _cleaning_succeeded:
			return StaffTaskStep.complete()

		return StaffTaskStep.release(&"cleaning_interrupted")

	if chair.cleanable == null or not chair.cleanable.has_cleaning_task():
		# Already clean. Completing rather than failing is correct: the world
		# requirement is met, and it does not matter who met it.
		return StaffTaskStep.complete()

	if chair.cleanable.is_cleaning:
		# Somebody else - the player - is mid-action on this seat.
		return StaffTaskStep.release(&"already_being_cleaned")

	var stand_at: Vector2 = _get_cleaning_position(worker, chair)

	if not is_in_working_position(
		worker,
		chair.global_position,
		stand_at,
		get_reach(worker)
	):
		return StaffTaskStep.move_to(
			stand_at,
			10.0,
			String(chair.name)
		)

	return StaffTaskStep.act("clean seat")


func perform_action(
	worker: Node,
	task: TavernTask
) -> ActionResult:
	var chair: Chair = task.get_target() as Chair

	if chair == null or chair.cleanable == null:
		return ActionResult.FAILED

	if not chair.cleanable.has_cleaning_task():
		return ActionResult.DONE

	if chair.cleanable.is_cleaning:
		TaskBoard.report_issue(
			TavernTaskService.ISSUE_DUPLICATE_CLEANING,
			"Worker reached %s but it was already being cleaned - the second "
			% String(chair.name)
			+ "cleaning action was not started.",
			{ "task_id": String(task.task_id) }
		)

		return ActionResult.FAILED

	_watch(chair, task)

	_pending_task = task

	# The shared, authoritative cleaning entry point.
	if not bool(chair.try_clean(worker)):
		_unwatch()

		return ActionResult.FAILED

	_is_cleaning = true

	# Flagged here rather than on completion, and the ordering is the whole
	# point. TavernTaskCoordinator connects to cleaning_completed at startup,
	# so its handler runs before this executor's - it would see a clean chair,
	# assume the player did it, and cancel a task the worker had just earned.
	# Claiming the resolution up front removes the race entirely.
	_mark_resolution_pending()

	return ActionResult.RUNNING


func poll_action(
	_worker: Node,
	_task: TavernTask
) -> ActionResult:
	if not _cleaning_finished:
		if _watched_chair == null or not is_instance_valid(_watched_chair):
			_is_cleaning = false

			return ActionResult.FAILED

		return ActionResult.RUNNING

	_is_cleaning = false

	if _cleaning_succeeded:
		return ActionResult.DONE

	return ActionResult.FAILED


func abort(
	worker: Node,
	_task: TavernTask,
	_reason: StringName
) -> void:
	if _is_cleaning:
		var runner: ActionRunner = get_action_runner(worker)

		if runner != null and runner.is_running:
			runner.force_cancel_current_action()

	_is_cleaning = false

	_clear_resolution_pending()
	_unwatch()


# -----------------------------------------------------------------------------
# Watching the chair
# -----------------------------------------------------------------------------

func _watch(
	chair: Chair,
	task: TavernTask
) -> void:
	_unwatch()

	_watched_chair = chair
	_pending_task = task
	_cleaning_finished = false
	_cleaning_succeeded = false

	if chair.cleanable == null:
		return

	if not chair.cleanable.cleaning_completed.is_connected(
		_on_cleaning_completed
	):
		chair.cleanable.cleaning_completed.connect(_on_cleaning_completed)

	if not chair.cleanable.cleaning_cancelled.is_connected(
		_on_cleaning_cancelled
	):
		chair.cleanable.cleaning_cancelled.connect(_on_cleaning_cancelled)

	if not chair.cleanable.complication_triggered.is_connected(
		_on_complication_triggered
	):
		chair.cleanable.complication_triggered.connect(
			_on_complication_triggered
		)


func _unwatch() -> void:
	if _watched_chair == null or not is_instance_valid(_watched_chair):
		_watched_chair = null
		return

	var cleanable: CleanableComponent = _watched_chair.cleanable

	if cleanable != null:
		if cleanable.cleaning_completed.is_connected(_on_cleaning_completed):
			cleanable.cleaning_completed.disconnect(_on_cleaning_completed)

		if cleanable.cleaning_cancelled.is_connected(_on_cleaning_cancelled):
			cleanable.cleaning_cancelled.disconnect(_on_cleaning_cancelled)

		if cleanable.complication_triggered.is_connected(
			_on_complication_triggered
		):
			cleanable.complication_triggered.disconnect(
				_on_complication_triggered
			)

	_watched_chair = null


func _on_cleaning_completed() -> void:
	_cleaning_finished = true
	_cleaning_succeeded = true

	_mark_resolution_pending()


func _on_cleaning_cancelled(
	_task: CleaningTask
) -> void:
	_cleaning_finished = true
	_cleaning_succeeded = false

	# The worker no longer owns the outcome, so the coordinator must be free
	# to cancel this task if the seat is cleaned by somebody else.
	_clear_resolution_pending()


## Broken glass. The seat is not clean, but the worker did its job correctly
## and a fresh cleaning requirement now exists, so this counts as a successful
## action. The producer creates a new task for the new mess.
func _on_complication_triggered(
	_task: CleaningTask,
	_cost: int
) -> void:
	_cleaning_finished = true
	_cleaning_succeeded = true

	_mark_resolution_pending()


## Stops the board's sweep cancelling this task as "already clean" in the frame
## between the action finishing and the worker completing it.
##
## The seat really is clean by then, so the validator is not wrong - it is just
## too quick, and a task the worker finished should be recorded as completed
## rather than cancelled.
func _mark_resolution_pending() -> void:
	if _pending_task != null:
		_pending_task.is_resolution_pending = true


func _clear_resolution_pending() -> void:
	if _pending_task != null:
		_pending_task.is_resolution_pending = false


# -----------------------------------------------------------------------------
# Positioning
# -----------------------------------------------------------------------------

## Where to stand to clean [param chair].
##
## Prefers the chair's own staging position - the spot a customer walks to
## before sitting down, which is by definition walkable and directly in front
## of the seat - and falls back to projecting the chair onto the mesh.
func _get_cleaning_position(
	worker: Node,
	chair: Chair
) -> Vector2:
	var target: Vector2 = chair.global_position

	if chair.has_method(&"get_staging_position"):
		target = chair.get_staging_position()

	return get_standing_position_near(worker, target)


## Only true when this worker ran the cleaning action through to a result.
##
## Arriving at a seat the player has already dealt with completes the task but
## earns the worker nothing.
func did_perform_work() -> bool:
	return _cleaning_finished and _cleaning_succeeded


# -----------------------------------------------------------------------------
# Viability
# -----------------------------------------------------------------------------

## Dirty seats do not expire.
##
## Returning -1 keeps cleaning entirely out of the viability system, which is
## correct: there is no deadline to miss, so no estimate could ever reject one.
func get_deadline_minutes(
	_worker: Node,
	_task: TavernTask
) -> float:
	return -1.0


func estimate_travel_pixels(
	worker: Node,
	task: TavernTask
) -> float:
	var chair: Chair = task.get_target() as Chair

	if chair == null:
		return -1.0

	return TaskViability.measure_distance(
		worker,
		task,
		"to_chair",
		get_worker_position(worker),
		_get_cleaning_position(worker, chair),
		TaskBoard.get_viability_config()
	)


## The cleaning action's own configured duration.
func estimate_action_seconds(
	_worker: Node,
	task: TavernTask
) -> float:
	var chair: Chair = task.get_target() as Chair

	if chair == null or chair.cleanable == null:
		return 0.0

	var cleaning_task: CleaningTask = chair.cleanable.current_task

	if cleaning_task == null:
		return 0.0

	var action: ActionDefinition = cleaning_task.get_action()

	return 0.0 if action == null else action.duration_seconds

func describe() -> Dictionary:
	return {
		"task_type": String(task_type),
		"is_cleaning": _is_cleaning,
		"cleaning_finished": _cleaning_finished,
		"cleaning_succeeded": _cleaning_succeeded,
	}
