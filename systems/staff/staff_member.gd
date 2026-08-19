class_name StaffMember
extends CharacterBody2D

## One member of tavern staff.
##
## This script is deliberately role-free. It knows how to want work, how to
## claim it safely, how to walk somewhere, how to run an action and how to give
## up gracefully - and nothing whatsoever about drinks, chairs, stock or
## customers. Everything role-specific lives in two places outside it:
##
## [codeblock]
## StaffDefinition      who this worker is: name, capabilities, speed, sprite
## StaffTaskExecutor    how one kind of work is actually carried out
## [/codeblock]
##
## A bartender, a cleaner, a cook and a bouncer are therefore all this same
## script. That is the point: the second worker must not cost a second AI.
##
## [b]The loop[/b]
##
## [codeblock]
## 1  ask the board for the best task this worker is capable of
## 2  claim it atomically
## 3  ask the executor for the next step, from current world state
## 4  walk, or act, as told
## 5  re-validate constantly - the world, not the task, is the authority
## 6  complete, release or fail, and always release reservations
## 7  go again, or drift back to the idle point
## [/codeblock]
##
## Step 5 is what makes the player able to override staff freely. The worker
## never assumes the world still looks the way it did when it set off.
##
## [b]Navigation[/b]
##
## Movement is entirely [ActorNavigation] and [ActorMovement], the same
## components customers use, with staff-specific profiles. There is no private
## movement code here and the worker is never teleported during normal play.


## The worker's state changed. For UI, diagnostics and developer tools.
signal state_changed(
	previous_state: State,
	current_state: State
)

## The worker took, finished or lost a task.
signal task_changed(task: TavernTask)

## The worker said something out loud.
signal spoke(text: String)


enum State {
	## Nothing to do, standing at or near the idle point.
	IDLE,

	## Actively choosing between available tasks.
	EVALUATING_TASKS,

	## Travelling to collect something the task needs.
	MOVING_TO_SOURCE,

	## At the source, taking the item.
	COLLECTING_ITEM,

	## Travelling to where the work happens.
	MOVING_TO_TARGET,

	## At the target, running the work.
	PERFORMING_TASK,

	## The work finished; settling the task with the board.
	COMPLETING_TASK,

	## Navigation failed or the worker wedged; trying to get going again.
	RECOVERING,

	## No work available; walking back to the idle point.
	RETURNING_TO_IDLE,

	## Holding something a finished task gave it, and dealing with that.
	##
	## Split out of MOVING_TO_TARGET in Phase 3A.1: a worker walking to the
	## bar to put a drink down is doing something quite different from a
	## worker walking to a customer, and reporting them as the same state was
	## a large part of what made the original diagnostic hard to read.
	RECOVERING_ITEM,

	## Switched off by the player or a developer tool.
	PAUSED,
}


@export_category("Configuration")

## Who this worker is. Without it the worker does nothing at all.
@export var definition: StaffDefinition

## Overrides the archetype's sprite. Leave empty to use the definition's.
@export var sprite_override: Texture2D


@export_category("Placement")

## Where the worker stands when there is nothing to do.
##
## Leave empty to use wherever the worker was placed in the scene, which is
## normally what you want: put it somewhere sensible in the editor and it will
## come back there.
@export var idle_point: Marker2D


@export_category("Debug")

@export var show_debug_messages: bool = false


@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var actor_movement: ActorMovement = $ActorMovement
@onready var actor_navigation: ActorNavigation = $ActorNavigation
@onready var item_carrier: ItemCarrier = $ItemCarrier
@onready var action_runner: ActionRunner = $ActionRunner
@onready var interactable: Interactable = $InteractionArea
@onready var speech_bubble: StaffSpeechBubble = $SpeechBubble


## Stable, human-readable id for this individual, for example
## [code]tavern_hand_01[/code]. Allocated on ready and used everywhere a report
## or a debug line needs to name this worker.
var staff_id: StringName = &""

var current_state: State = State.IDLE

var current_task: TavernTask = null
var current_executor: StaffTaskExecutor = null

var is_work_enabled: bool = true

var _evaluation_elapsed: float = 0.0
var _wait_remaining: float = 0.0

var _is_action_running: bool = false
var _navigation_failures: int = 0
var _is_navigating: bool = false
var _navigation_target: Vector2 = Vector2.ZERO

var _home_position: Vector2 = Vector2.ZERO

## The recovery the worker is currently walking to carry out, if any.
var _carried_recovery_plan: Dictionary = {}

## Seconds before a failed recovery is attempted again.
var _carried_recovery_retry_seconds: float = 0.0

## Consecutive failed attempts to put the current carried item down.
var _carried_recovery_attempts: int = 0

## True once recovery has been given up on for the current carried item.
var _carried_recovery_abandoned: bool = false

## Built once if no policy is configured, so recovery always has rules.
var _fallback_carried_policy: CarriedItemPolicy = null

var _carried_item_recoveries: int = 0
var _carried_recovery_failures: int = 0
var _carried_events: Array[Dictionary] = []
var _carried_event_counts: Dictionary = {}
var _task_switches: int = 0
var _non_viable_skipped: int = 0
var _travel_seconds: float = 0.0

## Session diagnostics. Cheap counters, always maintained.
var _tasks_evaluated: int = 0
var _tasks_claimed: int = 0
var _tasks_completed: int = 0
var _tasks_released: int = 0
var _tasks_failed: int = 0
var _serves_completed: int = 0
## Completed task count keyed by task type, so the report can show each role
## doing its own job rather than scoring every role against serve/clean.
var _tasks_completed_by_type: Dictionary = {}
var _cleans_completed: int = 0
var _navigation_failure_total: int = 0
var _stuck_recoveries: int = 0

## Stuck recoveries and hard failures per destination label.
##
## `stuck_recoveries = 310` is a single number with nowhere to look. Keyed by
## where the worker was heading, the same number reads "GrogCaskStack 180,
## PortWineService 60" and points straight at the bad approach point. Every
## navigation fault this project has hit took a bespoke probe to locate; this
## makes the next one a line in the report.
var _navigation_trouble_by_destination: Dictionary = {}

## Label of the destination currently being walked to.
var _current_destination_label: String = ""
var _transfer_failures: int = 0
var _idle_seconds: float = 0.0
var _working_seconds: float = 0.0
var _distance_travelled: float = 0.0
var _last_frame_position: Vector2 = Vector2.ZERO
var _state_history: Array[Dictionary] = []

## Evaluations that found no work. Counted rather than listed - the number is
## the useful part, the individual events are noise.
var _empty_evaluations: int = 0

## Incremented per worker so ids stay unique without a manager to allocate them.
static var _instance_counter: int = 0


func _ready() -> void:
	_instance_counter += 1

	add_to_group(&"tavern_staff")

	if definition == null:
		push_error(
			name
			+ " has no StaffDefinition assigned, so it cannot work. "
			+ "Assign one in the inspector or via configure()."
		)
	else:
		definition.validate_or_warn()

	staff_id = StringName(
		"%s_%02d" % [
			("staff" if definition == null else String(definition.archetype_id)),
			_instance_counter,
		]
	)

	_apply_definition()

	_home_position = (
		idle_point.global_position if idle_point != null
		else global_position
	)

	_last_frame_position = global_position

	_connect_signals()
	_record_state_history(State.IDLE, State.IDLE, &"ready")


func configure(
	staff_definition: StaffDefinition
) -> void:
	definition = staff_definition

	if is_inside_tree():
		_apply_definition()


func _apply_definition() -> void:
	if definition == null:
		return

	if sprite != null:
		var texture: Texture2D = (
			sprite_override if sprite_override != null
			else definition.sprite_texture
		)

		if texture != null:
			sprite.texture = texture

	if actor_movement != null and definition.movement_profile != null:
		actor_movement.profile = definition.movement_profile

	if actor_navigation != null and definition.navigation_profile != null:
		actor_navigation.set_profile(definition.navigation_profile)

		# Staff get individual walking character too. Without this they walk
		# the exact centreline at exactly uniform speed while customers do
		# not, which reads as the staff being the robotic ones - and it
		# leaves them without a preferred passing side, so two staff meeting
		# head-on still mirror each other.
		#
		# Restlessness is deliberately low: staff have somewhere to be and
		# should look purposeful rather than fidgety.
		actor_navigation.seed_personal_movement(0, 0.35)

	if speech_bubble != null:
		speech_bubble.display_seconds = definition.speech_bubble_seconds


func _connect_signals() -> void:
	if not actor_navigation.destination_reached.is_connected(
		_on_destination_reached
	):
		actor_navigation.destination_reached.connect(_on_destination_reached)

	if not actor_navigation.destination_failed.is_connected(
		_on_destination_failed
	):
		actor_navigation.destination_failed.connect(_on_destination_failed)

	if not actor_navigation.recovery_started.is_connected(
		_on_recovery_started
	):
		actor_navigation.recovery_started.connect(_on_recovery_started)

	if TaskBoard.task_created.is_connected(_on_board_task_created):
		return

	TaskBoard.task_created.connect(_on_board_task_created)


func _exit_tree() -> void:
	# A worker removed mid-task must not take the task's claim with it. The
	# board would eventually notice and recover, but leaving a mess for a
	# sweep to find is exactly the kind of leak this phase is meant to avoid.
	_abandon_task(&"worker_removed", false)


# -----------------------------------------------------------------------------
# Frame
# -----------------------------------------------------------------------------

func _physics_process(
	_delta: float
) -> void:
	# ActorNavigation owns movement. All this does is measure how far the
	# worker actually went, for the report's distance figure.
	var moved: float = global_position.distance_to(_last_frame_position)

	if moved < 64.0:
		_distance_travelled += moved

	_last_frame_position = global_position


func _process(
	delta: float
) -> void:
	if not Simulation.updates_actors():
		return

	if current_task == null:
		_idle_seconds += delta
	else:
		_working_seconds += delta

	if _is_navigating:
		_travel_seconds += delta

	if _carried_recovery_retry_seconds > 0.0:
		_carried_recovery_retry_seconds = maxf(
			_carried_recovery_retry_seconds - delta,
			0.0
		)

	if current_state == State.PAUSED:
		return

	if _wait_remaining > 0.0:
		_wait_remaining -= delta
		return

	_evaluation_elapsed += delta

	var interval: float = (
		definition.working_evaluation_interval if current_task != null
		else definition.idle_evaluation_interval
	)

	if _evaluation_elapsed < interval:
		return

	_evaluation_elapsed = 0.0

	_tick()


## One decision cycle.
func _tick() -> void:
	if definition == null:
		return

	if not is_work_enabled:
		return

	if current_task == null:
		_tick_idle()
		return

	_tick_working()


# -----------------------------------------------------------------------------
# Idle
# -----------------------------------------------------------------------------

func _tick_idle() -> void:
	_set_state(State.EVALUATING_TASKS, StaffTransitionReason.SCHEDULED_REEVALUATION)

	_tasks_evaluated += 1

	# Hands before work. This ordering is the whole Phase 3A.1 fix: the old
	# code chose a task first and only dealt with a leftover drink when the
	# board happened to be empty, so a cancelled serving task left the worker
	# cleaning tables with a customer's ale in its hand for the rest of the
	# session.
	#
	# Recovery is checked first and can still be overtaken by a task that
	# legitimately wants the carried item - the policy's REASSIGN outcome
	# returns exactly that task - so putting it first costs nothing.
	if item_carrier.is_carrying():
		if _handle_carried_item():
			return

	var task: TavernTask = TaskBoard.select_best_task(
		self,
		get_staff_capabilities(),
		null
	)

	if task != null:
		_take_task(task)
		return

	_no_work_found()


## Decides what to do about something left in the worker's hands.
##
## Returns true when the worker is now busy dealing with it, false when it may
## carry on and look for work - which happens when the policy says the item can
## be kept and the worker is allowed to work while holding it.
func _handle_carried_item() -> bool:
	var policy: CarriedItemPolicy = _get_carried_item_policy()

	# A carried item the worker has already given up on is not re-planned.
	# Something must change first - a new task, a freed slot, a different item
	# - and each of those clears the flag. Without this the worker cycles
	# EVALUATING_TASKS -> RECOVERING_ITEM forever on the retry timer.
	if _carried_recovery_abandoned:
		return false

	if _carried_recovery_retry_seconds > 0.0:
		# A recovery that just failed is not retried every frame.
		return not policy.may_work_while_holding_unrelated_item

	var plan: Dictionary = CarriedItemRecovery.plan(self, policy)

	# Every preferred route has failed enough times to stop trying them. Take
	# any destination at all before giving up.
	if (
		not bool(plan.get("is_possible", false))
		and policy.escalate_to_any_destination
		and _carried_recovery_attempts >= policy.maximum_recovery_attempts - 1
	):
		plan = CarriedItemRecovery.plan_any_destination(self, policy)

	if not bool(plan.get("is_possible", false)):
		_carried_recovery_attempts += 1
		_report_recovery_failure(String(plan.get("detail", "")), policy)

		if _carried_recovery_attempts >= policy.maximum_recovery_attempts:
			_abandon_carried_recovery(String(plan.get("detail", "")))

			return false

		return not policy.may_work_while_holding_unrelated_item

	var outcome: CarriedItemPolicy.Outcome = plan.get(
		CarriedItemRecovery.OUTCOME_KEY,
		CarriedItemPolicy.Outcome.RETAIN
	)

	# The best outcome: somebody else wants exactly this drink, so the worker
	# keeps hold of it and simply takes that task instead.
	if outcome == CarriedItemPolicy.Outcome.REASSIGN:
		var task: TavernTask = plan.get("task", null) as TavernTask

		if task != null and _take_task(
			task,
			StaffTransitionReason.CARRIED_ITEM_REASSIGNED
		):
			_carried_item_recoveries += 1

			_record_carried_event(
				StaffTransitionReason.CARRIED_ITEM_REASSIGNED,
				String(plan.get("detail", ""))
			)

			return true

		# The reassignment target was taken between planning and claiming.
		# Fall through and look for somewhere to put the drink down instead.
		return false

	if outcome == CarriedItemPolicy.Outcome.RETAIN:
		_record_carried_event(
			StaffTransitionReason.CARRIED_ITEM_RETAINED,
			String(plan.get("detail", ""))
		)

		return not policy.may_work_while_holding_unrelated_item

	if bool(plan.get("is_immediate", false)):
		_execute_carried_recovery(plan, policy)

		return true

	# Somewhere to put it, but not from here. Walk over.
	_carried_recovery_plan = plan

	_set_state(
		State.RECOVERING_ITEM,
		StaffTransitionReason.RECOVERING_CARRIED_ITEM
	)

	_navigate_to(
		StaffTaskExecutor.get_standing_position_near(
			self,
			plan.get("position", global_position)
		),
		8.0,
		"put down %s" % item_carrier.get_carried_stack().get_display_name()
	)

	return true


func _execute_carried_recovery(
	plan: Dictionary,
	policy: CarriedItemPolicy
) -> void:
	var carried_name: String = (
		item_carrier.get_carried_stack().get_display_name()
	)

	var result: Dictionary = CarriedItemRecovery.execute(self, plan)

	_carried_recovery_plan = {}

	if bool(result.get("success", false)):
		_carried_item_recoveries += 1
		reset_carried_recovery()

		_record_carried_event(
			result.get("reason", StaffTransitionReason.CARRIED_ITEM_RETURNED),
			"%s: %s" % [carried_name, String(result.get("detail", ""))]
		)

		return

	_report_recovery_failure(String(result.get("detail", "")), policy)


## Stops trying to put the carried item down, and lets the worker work again.
##
## The item is NOT destroyed - it stays in the worker's hands and is recorded
## as an unrecovered carry. The guarantee this buys is the one that matters:
## no worker sits in RECOVERING_ITEM indefinitely. The flag clears the moment
## the situation could plausibly differ, so a freed slot or a new order gets
## another attempt.
func _abandon_carried_recovery(
	detail: String
) -> void:
	_carried_recovery_abandoned = true
	_carried_recovery_plan = {}
	_carried_recovery_retry_seconds = 0.0

	_record_carried_event(
		StaffTransitionReason.CARRIED_ITEM_RECOVERY_FAILED,
		"abandoned after %d attempts: %s" % [_carried_recovery_attempts, detail]
	)

	TaskBoard.report_issue(
		TavernTaskService.ISSUE_TRANSFER_FAILED,
		"%s gave up putting down %s after %d attempts and will keep working." % [
			String(staff_id),
			item_carrier.get_carried_stack().get_display_name(),
			_carried_recovery_attempts,
		],
		{ "staff_id": String(staff_id), "unrecovered_carry": true }
	)

	if current_state == State.RECOVERING_ITEM:
		_set_state(State.IDLE, StaffTransitionReason.IDLE_ARRIVAL)


## Clears the give-up flag so recovery may be attempted again.
##
## Called whenever the world changed in a way that could make a destination
## available: the carried item changed, or a recovery succeeded.
func reset_carried_recovery() -> void:
	_carried_recovery_abandoned = false
	_carried_recovery_attempts = 0
	_carried_recovery_retry_seconds = 0.0


func _report_recovery_failure(
	detail: String,
	policy: CarriedItemPolicy
) -> void:
	_carried_recovery_failures += 1
	_carried_recovery_retry_seconds = policy.recovery_retry_seconds

	_record_carried_event(
		StaffTransitionReason.CARRIED_ITEM_RECOVERY_FAILED,
		detail
	)

	TaskBoard.report_issue(
		TavernTaskService.ISSUE_TRANSFER_FAILED,
		"%s could not put down %s: %s" % [
			String(staff_id),
			item_carrier.get_carried_stack().get_display_name(),
			detail,
		],
		{ "staff_id": String(staff_id) }
	)


## Records a carried-item event for the exported report.
##
## Bounded, and counted by reason, so a worker stuck in a retry loop shows up
## as a large count rather than as thousands of identical entries.
func _record_carried_event(
	reason: StringName,
	detail: String
) -> void:
	var key: String = String(reason)

	_carried_event_counts[key] = int(
		_carried_event_counts.get(key, 0)
	) + 1

	_carried_events.append({
		"world_minutes": WorldTime.get_total_minutes_precise(),
		"reason": key,
		"detail": detail,
	})

	while _carried_events.size() > 60:
		_carried_events.pop_front()

	if show_debug_messages:
		print("[Staff] ", staff_id, " ", key, ": ", detail)


func _get_carried_item_policy() -> CarriedItemPolicy:
	if definition != null and definition.carried_item_policy != null:
		return definition.carried_item_policy

	if _fallback_carried_policy == null:
		_fallback_carried_policy = CarriedItemPolicy.new()

	return _fallback_carried_policy


## Nothing to do. Head home, but only decide that once.
##
## The Phase 3A report was full of EVALUATING_TASKS -> RETURNING_TO_IDLE ->
## EVALUATING_TASKS triples because an idle worker re-decided to walk home on
## every interval while already walking home. Leaving the walk alone unless
## something actually changed removes the oscillation without making the
## worker slow to notice new work: TaskBoard.task_created still wakes it
## immediately.
func _no_work_found() -> void:
	if current_state == State.RETURNING_TO_IDLE and _is_navigating:
		return

	_return_to_idle_point()


func _return_to_idle_point() -> void:
	if global_position.distance_to(_home_position) <= 12.0:
		_set_state(State.IDLE, StaffTransitionReason.IDLE_ARRIVAL)

		if _is_navigating:
			actor_navigation.stop()
			_is_navigating = false

		_wait_remaining = definition.idle_settle_seconds
		return

	_set_state(State.RETURNING_TO_IDLE, StaffTransitionReason.RETURNING_TO_IDLE)

	_navigate_to(_home_position, 10.0, "idle point")


# -----------------------------------------------------------------------------
# Working
# -----------------------------------------------------------------------------

func _tick_working() -> void:
	# An action already under way owns its own outcome, so it is polled before
	# anything else re-examines the world.
	#
	# This ordering is load-bearing. A cleaning action finishing is exactly
	# what makes the chair clean, so revalidating first would find no dirty
	# chair, decide the requirement had vanished and cancel a task the worker
	# had just successfully finished - counting a success as a cancellation in
	# every report. The executor reports success or failure itself; the board
	# is asked again on the next tick, once the task has been resolved
	# properly.
	if _is_action_running:
		_poll_running_action()
		return

	# The world is the authority, always. If the requirement stopped existing
	# while the worker was walking, the board cancels the task here and the
	# worker simply moves on.
	if not TaskBoard.revalidate(current_task):
		_abandon_task(&"task_invalidated", true)
		return

	if not current_task.is_held_by(self):
		# Something took the task away - a developer tool, or a sweep that
		# decided the claim was stale.
		_abandon_task(&"claim_lost", true)
		return

	_advance()


## Asks the executor what to do now, and does it.
func _advance() -> void:
	if current_executor == null or current_task == null:
		return

	var step: StaffTaskStep = current_executor.get_next_step(
		self,
		current_task
	)

	if step == null:
		_release_task(&"executor_returned_nothing")
		return

	match step.kind:
		StaffTaskStep.Kind.MOVE:
			_handle_move_step(step)

		StaffTaskStep.Kind.ACT:
			_handle_act_step(step)

		StaffTaskStep.Kind.WAIT:
			_wait_remaining = step.wait_seconds

		StaffTaskStep.Kind.COMPLETE:
			_complete_task()

		StaffTaskStep.Kind.RELEASE:
			_release_task(step.reason)

		StaffTaskStep.Kind.FAIL:
			_fail_task(step.reason)


func _handle_move_step(
	step: StaffTaskStep
) -> void:
	_set_state(
		State.MOVING_TO_SOURCE if _is_collecting_leg()
		else State.MOVING_TO_TARGET,
		StaffTransitionReason.MOVING_TO_SOURCE if _is_collecting_leg()
		else StaffTransitionReason.MOVING_TO_TARGET
	)

	# Already heading somewhere close enough - do not restart the path, which
	# would throw away the agent's progress and make the worker stutter.
	if _is_navigating and _navigation_target.distance_to(step.position) < 12.0:
		return

	_navigate_to(step.position, step.arrival_distance, step.label)


func _handle_act_step(
	_step: StaffTaskStep
) -> void:
	if _is_navigating:
		actor_navigation.stop()
		_is_navigating = false

	TaskBoard.begin(current_task)

	_set_state(
		State.COLLECTING_ITEM if _is_collecting_leg()
		else State.PERFORMING_TASK,
		StaffTransitionReason.ARRIVED
	)

	var result: int = current_executor.perform_action(self, current_task)

	match result:
		StaffTaskExecutor.ActionResult.DONE:
			# Ask again immediately: collecting a drink is normally followed by
			# walking to the customer, and waiting a tick to notice looks slow.
			_advance()

		StaffTaskExecutor.ActionResult.RUNNING:
			_is_action_running = true

		_:
			if _is_collecting_leg():
				_transfer_failures += 1

			_release_task(&"action_failed")


func _poll_running_action() -> void:
	var result: int = current_executor.poll_action(self, current_task)

	match result:
		StaffTaskExecutor.ActionResult.RUNNING:
			return

		StaffTaskExecutor.ActionResult.DONE:
			_is_action_running = false
			_advance()

		_:
			_is_action_running = false
			_release_task(&"action_interrupted")


## True when this task still needs something collected before it can be done.
##
## Used only to pick a readable state name; nothing depends on it being right.
func _is_collecting_leg() -> bool:
	if current_task == null or current_task.required_definition == null:
		return false

	return not item_carrier.is_carrying_item(
		current_task.required_definition.item_id
	)


# -----------------------------------------------------------------------------
# Task lifecycle
# -----------------------------------------------------------------------------

## The single route by which this worker acquires any task.
##
## Selection, carried-item reassignment and developer tools all come through
## here, so the capability check below is not redundant with the one in
## TaskBoard.claim() - it is the near side of the same gate, and it is what
## makes the refusal attributable to a route rather than appearing as an
## anonymous rejected claim.
func _take_task(
	task: TavernTask,
	route: StringName = StaffTransitionReason.TASK_CLAIMED
) -> bool:
	if task == null:
		return false

	# New work means new destinations may exist, so a carry that was given up
	# on becomes worth retrying.
	if _carried_recovery_abandoned:
		reset_carried_recovery()

	if not can_perform_task(task):
		TaskBoard.report_capability_violation(self, staff_id, task, route)

		return false

	var executor: StaffTaskExecutor = StaffTaskExecutor.create_for(
		task.task_type
	)

	if executor == null:
		return false

	if not TaskBoard.claim(task, self, staff_id):
		return false

	if not executor.on_claimed(self, task):
		TaskBoard.release(task, &"setup_failed")
		return false

	current_task = task
	current_executor = executor

	_navigation_failures = 0
	_is_action_running = false
	_tasks_claimed += 1

	if show_debug_messages:
		print("[Staff] ", staff_id, " claimed ", task.describe())

	task_changed.emit(task)

	_advance()

	return true


func _complete_task() -> void:
	if current_task == null:
		return

	_set_state(State.COMPLETING_TASK, StaffTransitionReason.TASK_COMPLETED)

	var task_type: StringName = current_task.task_type

	# A task can legitimately complete without this worker having done the
	# work: the player cleans a seat the worker had claimed, and the
	# requirement is met before the worker arrives. The task really is
	# finished, so completing it is right - but crediting the worker with a
	# clean it never performed would quietly inflate every figure in the
	# diagnostic report. The executor is the only thing that knows which
	# happened, so it is asked.
	var was_performed_by_this_worker: bool = true

	if current_executor != null:
		was_performed_by_this_worker = current_executor.did_perform_work()

	TaskBoard.complete(current_task)

	_tasks_completed += 1

	if was_performed_by_this_worker:
		# Per-type tally alongside the two named counters.
		#
		# _serves_completed and _cleans_completed only ever move for
		# SERVE_DRINK and CLEAN_SEAT, which are tavern hand capabilities. A
		# bartender can only hold prepare_drink and refill_station, so its
		# serve and clean counts are structurally zero - and a report showing
		# "0 serves, 0 cleans" for a bartender reads as a broken worker when
		# it is describing a role boundary. Counting by actual task type
		# means the report can show each worker doing its own job instead of
		# scoring every role against one role's tasks.
		var type_key: String = String(task_type)
		_tasks_completed_by_type[type_key] = int(
			_tasks_completed_by_type.get(type_key, 0)
		) + 1

		match task_type:
			TavernTaskTypes.SERVE_DRINK:
				_serves_completed += 1

			TavernTaskTypes.CLEAN_SEAT:
				_cleans_completed += 1

	if (
		current_task.definition != null
		and current_task.definition.notify_on_completion
	):
		Comms.notify(
			"%s finished %s." % [
				_get_display_name(),
				current_task.get_display_name().to_lower(),
			],
			CommMessage.Category.STAFF
		)

	_clear_task()

	# Go again straight away rather than waiting for the next interval: a
	# worker that pauses visibly between jobs reads as broken.
	_tick_idle()


func _release_task(
	reason: StringName
) -> void:
	if current_task == null:
		return

	if show_debug_messages:
		print("[Staff] ", staff_id, " released ", current_task.task_id,
			" (", reason, ")")

	if current_executor != null:
		current_executor.abort(self, current_task, reason)

	TaskBoard.release(current_task, reason)

	_tasks_released += 1

	_clear_task()


func _fail_task(
	reason: StringName
) -> void:
	if current_task == null:
		return

	if current_executor != null:
		current_executor.abort(self, current_task, reason)

	TaskBoard.fail(current_task, reason)

	_tasks_failed += 1

	_clear_task()


## Lets go of the current task without deciding whose fault it was.
##
## [param settle] is false only when the worker itself is being destroyed, in
## which case the board is left to reclaim the task on its next sweep.
func _abandon_task(
	reason: StringName,
	settle: bool
) -> void:
	if current_task == null:
		return

	if current_executor != null:
		current_executor.abort(self, current_task, reason)

	if settle and not current_task.is_terminal():
		if current_task.is_held_by(self):
			TaskBoard.release(current_task, reason)
			_tasks_released += 1

	_clear_task()


func _clear_task() -> void:
	current_task = null
	current_executor = null

	_is_action_running = false
	_navigation_failures = 0

	if _is_navigating:
		actor_navigation.stop()
		_is_navigating = false

	task_changed.emit(null)


# -----------------------------------------------------------------------------
# Carrying leftovers
# -----------------------------------------------------------------------------

## Carried-item recovery lives in [CarriedItemRecovery] and is driven by
## [CarriedItemPolicy]. Phase 3A had a private "walk to a bar slot and put it
## down" routine here; it was replaced rather than extended, because having
## two mechanisms decide where a drink belongs is how they drift apart.


func _navigate_to(
	world_position: Vector2,
	arrival: float,
	label: String
) -> void:
	_navigation_target = world_position
	_is_navigating = true
	_current_destination_label = label

	actor_navigation.move_to(
		NavigationDestination.to_position(
			world_position,
			arrival,
			label
		)
	)


func _on_destination_reached(
	_destination: NavigationDestination
) -> void:
	_is_navigating = false
	_navigation_failures = 0

	# Arrived at wherever the carried item was going. Re-plan rather than
	# executing the old plan blindly: the world has had a whole journey to
	# change, and the slot may now be full or the drink may now be wanted.
	if current_state == State.RECOVERING_ITEM:
		_carried_recovery_plan = {}

		if item_carrier.is_carrying():
			_handle_carried_item()
		else:
			_tick_idle()

		return

	if current_task != null:
		_advance()
		return

	if current_state == State.RETURNING_TO_IDLE:
		_set_state(State.IDLE, StaffTransitionReason.IDLE_ARRIVAL)
		_wait_remaining = definition.idle_settle_seconds


func _on_destination_failed(
	destination: NavigationDestination,
	reason: StringName
) -> void:
	_is_navigating = false
	_navigation_failures += 1
	_navigation_failure_total += 1

	_record_navigation_trouble(
		"nowhere" if destination == null else destination.get_label(),
		&"failed"
	)

	_set_state(State.RECOVERING, StaffTransitionReason.STUCK_RECOVERY)

	TaskBoard.report_issue(
		TavernTaskService.ISSUE_NAVIGATION_FAILED,
		"%s could not reach %s (%s), attempt %d." % [
			String(staff_id),
			("nowhere" if destination == null else destination.get_label()),
			String(reason),
			_navigation_failures,
		],
		{
			"staff_id": String(staff_id),
			"task_id": (
				"" if current_task == null else String(current_task.task_id)
			),
		}
	)

	# A recovery walk that could not reach its destination is abandoned; the
	# next evaluation re-plans, and may well choose a different route.
	if current_state == State.RECOVERING_ITEM:
		_carried_recovery_plan = {}
		_carried_recovery_retry_seconds = (
			_get_carried_item_policy().recovery_retry_seconds
		)

		_return_to_idle_point()
		return

	if current_task == null:
		_return_to_idle_point()
		return

	if _navigation_failures >= definition.navigation_failures_before_release:
		# Give the job back rather than pretending it can be done. Another
		# worker, or this one from a different starting position, may manage it.
		_release_task(&"navigation_failed")
		return

	# One more try. The board's retry cooldown does not apply here because the
	# worker still holds the claim; this is a re-route, not a re-claim.
	_wait_remaining = 0.5


func _on_recovery_started(
	_attempt: int
) -> void:
	_stuck_recoveries += 1
	_record_navigation_trouble(_current_destination_label, &"stuck")


## Counts one navigation problem against the place it happened.
func _record_navigation_trouble(
	label: String,
	kind: StringName
) -> void:
	var key: String = label if not label.is_empty() else "<unknown>"
	var entry: Dictionary = _navigation_trouble_by_destination.get(
		key, {"stuck": 0, "failed": 0}
	)

	entry[String(kind)] = int(entry.get(String(kind), 0)) + 1
	_navigation_trouble_by_destination[key] = entry


# -----------------------------------------------------------------------------
# Pause and developer control
# -----------------------------------------------------------------------------

## Stops the worker where it stands, keeping any task it holds.
func pause_work() -> void:
	if not is_work_enabled:
		return

	is_work_enabled = false

	if _is_navigating:
		actor_navigation.stop()
		_is_navigating = false

	if action_runner.is_running:
		action_runner.force_cancel_current_action()

	# Holding a claim while switched off would starve the board, so the task
	# goes back for somebody else - or for this worker on resume.
	_abandon_task(&"worker_paused", true)

	_set_state(State.PAUSED, StaffTransitionReason.WORKER_DISABLED)


func resume_work() -> void:
	if is_work_enabled:
		return

	is_work_enabled = true

	_set_state(State.IDLE, StaffTransitionReason.DEVELOPER_ACTION)

	_evaluation_elapsed = definition.idle_evaluation_interval


func toggle_work() -> bool:
	if is_work_enabled:
		pause_work()
	else:
		resume_work()

	return is_work_enabled


## Puts the worker back at its idle point without walking there.
##
## Developer recovery only, and never called by gameplay - see the F10 panel,
## where it is labelled as a teleport.
func developer_return_to_idle() -> void:
	_abandon_task(&"developer_reset", true)

	global_position = _home_position
	_last_frame_position = _home_position

	actor_navigation.stop()
	_is_navigating = false

	_set_state(State.IDLE, StaffTransitionReason.DEVELOPER_ACTION)


## Hands the current task straight back to the board.
##
## Developer tooling only. Gameplay releases go through the executor's own
## step results so the reason is meaningful; this exists to prove by hand that
## a release really does clear reservations and free the worker.
func developer_release_current_task() -> bool:
	if current_task == null:
		return false

	_abandon_task(&"developer_released", true)
	_set_state(State.IDLE, StaffTransitionReason.DEVELOPER_ACTION)

	return true


## Injects a navigation failure without breaking the navigation mesh.
##
## Runs the worker's real [method _on_destination_failed] handler, so the retry
## count, the reported issue, the reservation release and the eventual task
## release are all the genuine article - it simply skips the several seconds of
## walking into a wall that would otherwise be needed to produce one.
func developer_force_navigation_failure() -> bool:
	if _is_navigating:
		actor_navigation.stop()

	_on_destination_failed(
		null,
		ActorNavigation.REASON_UNREACHABLE
	)

	return true


# -----------------------------------------------------------------------------
# Speaking
# -----------------------------------------------------------------------------

## Shows a short speech bubble above the worker.
##
## Presentation only. The message itself lives in the communication system,
## which is what makes a warning survive the worker being off-screen, busy or
## absent entirely.
func say(
	text: String
) -> void:
	if speech_bubble != null:
		speech_bubble.show_text(text)

	spoke.emit(text)


func can_speak_for_tavern() -> bool:
	if definition == null:
		return false

	return definition.can_speak_for_tavern and is_work_enabled


# -----------------------------------------------------------------------------
# Duck-typed actor surface
# -----------------------------------------------------------------------------

func get_item_carrier() -> ItemCarrier:
	return item_carrier


func get_carried_slot() -> ItemSlot:
	return item_carrier.get_slot()


func get_action_runner() -> ActionRunner:
	return action_runner


func get_staff_capabilities() -> Array[StringName]:
	if definition == null:
		return []

	return definition.capabilities


## Top speed in pixels per second, for travel-time estimates.
##
## Read from the movement profile rather than stored, so retuning the profile
## automatically retunes every viability estimate that depends on it.
## True when this worker's role covers [param task].
func can_perform_task(
	task: TavernTask
) -> bool:
	if task == null or task.definition == null:
		return false

	return StaffCapabilities.satisfies(
		get_staff_capabilities(),
		task.definition.required_capabilities
	)


## Archetype id, for capability-violation diagnostics and speaker selection.
func get_archetype_id() -> StringName:
	return &"" if definition == null else definition.archetype_id


func get_movement_speed() -> float:
	if definition != null and definition.movement_profile != null:
		return definition.movement_profile.maximum_speed

	if actor_movement != null:
		return actor_movement.get_maximum_speed()

	return 0.0


func get_interaction_reach() -> float:
	if definition == null:
		return 40.0

	return definition.interaction_reach


func get_staff_id() -> StringName:
	return staff_id


func get_state_name() -> String:
	return State.keys()[current_state]


func _get_display_name() -> String:
	if definition == null:
		return String(name)

	return definition.display_name


# -----------------------------------------------------------------------------
# Interaction protocol
# -----------------------------------------------------------------------------

func get_interaction_display_name() -> String:
	return _get_display_name()


func can_interact(
	_request: InteractionRequest
) -> bool:
	return definition != null


func get_interaction_actions(
	_request: InteractionRequest
) -> Array[InteractionAction]:
	var actions: Array[InteractionAction] = []

	actions.append(
		InteractionAction.create(
			&"inspect",
			definition.interaction_verb,
			_get_display_name()
		)
	)

	return actions


## Posts the worker's status as a speaker message, with pause/resume offered
## as a choice on that message.
##
## Using the communication framework rather than a bespoke panel is deliberate:
## it is the same message type a future conversation will use, so the plumbing
## for choices gets exercised now instead of being written blind later.
func perform_interaction(
	_request: InteractionRequest
) -> bool:
	var message: CommMessage = CommMessage.new()

	message.type = CommMessage.Type.SPEAKER
	message.category = CommMessage.Category.STAFF
	message.severity = CommMessage.Severity.INFO
	message.speaker_id = staff_id
	message.speaker_name = _get_display_name()
	message.title = _get_display_name()
	message.body = _build_status_text()
	message.deduplication_key = "staff_status:%s" % String(staff_id)
	message.source = self

	message.choices = [
		{
			"id": &"toggle_work",
			"label": ("Take a break" if is_work_enabled else "Back to work"),
		},
		{
			"id": &"dismiss",
			"label": "Carry on",
		},
	]

	Comms.post(message)

	return true


func _build_status_text() -> String:
	var lines: Array[String] = []

	lines.append("Role: %s" % definition.role_name)
	lines.append("State: %s" % get_state_name())

	if current_task == null:
		lines.append("Job: nothing right now")
	else:
		lines.append("Job: %s" % current_task.get_display_name())

		var target: Node = current_task.get_target()

		if target != null:
			lines.append("Working on: %s" % String(target.name))

	if item_carrier.is_carrying():
		lines.append(
			"Carrying: %s" % item_carrier.get_carried_stack().get_display_name()
		)

	lines.append("Jobs waiting: %d" % TaskBoard.get_open_task_count())
	lines.append("Jobs done: %d" % _tasks_completed)

	var warnings: int = Comms.count_active_alerts_from_speaker(staff_id)

	if warnings > 0:
		lines.append("Warnings raised: %d" % warnings)

	return "\n".join(lines)


## Handles the choice buttons offered by [method perform_interaction].
func handle_message_choice(
	choice_id: StringName
) -> void:
	if choice_id == &"toggle_work":
		toggle_work()


# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

func _set_state(
	new_state: State,
	reason: StringName = StaffTransitionReason.OTHER
) -> void:
	if current_state == new_state:
		return

	var previous: State = current_state

	current_state = new_state

	_record_state_history(previous, new_state, reason)

	state_changed.emit(previous, new_state)


func _record_state_history(
	previous: State,
	current: State,
	reason: StringName
) -> void:
	# An idle worker dips into EVALUATING_TASKS on every interval and comes
	# straight back out again when the board has nothing for it. Recording
	# those would fill the bounded history with hundreds of "I looked and
	# found nothing" entries and push the actual work off the end of it, so a
	# round trip that changed nothing is folded away instead.
	if (
		previous == State.EVALUATING_TASKS
		and current == State.IDLE
		and not _state_history.is_empty()
	):
		var last: Dictionary = _state_history[-1]

		if (
			String(last.get("from", "")) == "IDLE"
			and String(last.get("to", "")) == "EVALUATING_TASKS"
		):
			_state_history.pop_back()

			_empty_evaluations += 1

			return

	_state_history.append({
		"minutes": WorldTime.get_total_minutes_precise(),
		"from": State.keys()[previous],
		"to": State.keys()[current],
		"reason": String(reason),
	})

	# Bounded, because a long session must not grow a list forever.
	while _state_history.size() > 200:
		_state_history.pop_front()


func _on_board_task_created(
	_task: TavernTask
) -> void:
	# New work exists. Look now rather than at the next idle interval, so a
	# customer ordering does not wait most of a second for anyone to notice.
	if current_task == null and current_state != State.PAUSED:
		_evaluation_elapsed = definition.idle_evaluation_interval


# -----------------------------------------------------------------------------
# Diagnostics
# -----------------------------------------------------------------------------

## One-line summary in the shape the brief's example uses.
func get_debug_line() -> String:
	var lines: Array[String] = []

	lines.append("Worker: %s" % String(staff_id))
	lines.append("State: %s" % get_state_name())

	if current_task == null:
		lines.append("Task: none")
	else:
		lines.append("Task: %s" % String(current_task.task_id))

		var source: Node = current_task.get_source()

		if source != null:
			var slot_index: int = int(
				current_task.source_data.get(&"slot_index", -1)
			)

			lines.append(
				"Source: %s%s" % [
					String(source.name),
					("" if slot_index < 0 else " slot %d" % slot_index),
				]
			)

		if current_task.required_definition != null:
			lines.append(
				"Reserved item: %s"
				% String(current_task.required_definition.item_id)
			)

		var target: Node = current_task.get_target()

		if target != null:
			lines.append("Target: %s" % String(target.name))

		lines.append("Retry count: %d" % current_task.retry_count)

	lines.append(
		"Path status: %s" % ("active" if _is_navigating else "idle")
	)

	return "\n".join(lines)


func get_diagnostics_snapshot() -> Dictionary:
	return {
		"staff_id": String(staff_id),
		"display_name": _get_display_name(),
		"role": ("" if definition == null else definition.role_name),
		"archetype": (
			"" if definition == null else String(definition.archetype_id)
		),
		"state": get_state_name(),
		"work_enabled": is_work_enabled,
		"current_task": (
			"" if current_task == null else String(current_task.task_id)
		),
		"current_target": _describe_current_target(),
		"carrying": (
			"" if not item_carrier.is_carrying()
			else String(item_carrier.get_carried_item_id())
		),
		"tasks_evaluated": _tasks_evaluated,
		"tasks_claimed": _tasks_claimed,
		"tasks_completed": _tasks_completed,
		"tasks_released": _tasks_released,
		"tasks_failed": _tasks_failed,
		"serves_completed": _serves_completed,
		"cleans_completed": _cleans_completed,
		"tasks_completed_by_type": _tasks_completed_by_type.duplicate(true),
		"capabilities": (
			[] if definition == null else definition.capabilities.duplicate()
		),
		"navigation_failures": _navigation_failure_total,
		"empty_evaluations": _empty_evaluations,
		"task_switches": _task_switches,
		"non_viable_skipped": _non_viable_skipped,
		"carried_item_recoveries": _carried_item_recoveries,
		"carried_recovery_failures": _carried_recovery_failures,
		"carried_events_by_reason": _carried_event_counts.duplicate(true),
		"recent_carried_events": _carried_events.duplicate(true),
		"travel_seconds": _travel_seconds,
		"stuck_recoveries": _stuck_recoveries,
		"navigation_trouble_by_destination": (
			_navigation_trouble_by_destination.duplicate(true)
		),
		"item_transfer_failures": _transfer_failures,
		"idle_seconds": _idle_seconds,
		"working_seconds": _working_seconds,
		"distance_travelled": _distance_travelled,
		"state_history": _state_history.duplicate(true),
	}


func _describe_current_target() -> String:
	if current_task == null:
		return ""

	var target: Node = current_task.get_target()

	if target == null:
		return ""

	return String(target.name)
