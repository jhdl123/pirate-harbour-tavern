class_name StaffTaskExecutor
extends RefCounted

## How one kind of work is actually carried out.
##
## This is the extension point of the whole staff system. [StaffMember] has no
## idea what serving or cleaning involves: it asks the executor for the next
## [StaffTaskStep], walks where it is told, calls
## [method perform_action] when told, and reports the outcome to the board.
##
## Adding a task type therefore never touches the worker:
##
## [codeblock]
## 1. add the id to TavernTaskTypes
## 2. add a TavernTaskDefinition .tres and register it on the board config
## 3. create a producer that creates and validates the task
## 4. subclass this, and register it in EXECUTOR_SCRIPTS below
## [/codeblock]
##
## [b]Executors must plan from the world, not from memory.[/b]
## [method get_next_step] is called again after every arrival and every action,
## and it should re-read the real state each time. That is what makes a player
## override free: if the drink is gone, the next step is a different one, with
## no invalidation plumbing anywhere.
##
## An executor instance belongs to one worker and one task, so holding state
## for an in-flight action (as [CleanSeatExecutor] does) is fine.


## Outcome of [method perform_action] and [method poll_action].
enum ActionResult {
	## Finished successfully. The worker asks for the next step.
	DONE,

	## Under way. The worker polls until this changes.
	RUNNING,

	## Could not be done. The worker fails the task.
	FAILED,
}


## task type -> executor script.
##
## One dictionary, deliberately: "which types can staff actually perform?" has
## exactly one answer, and it is visible here rather than spread across a
## registry resource, a scene and three scripts.
const EXECUTOR_SCRIPTS: Dictionary = {
	TavernTaskTypes.SERVE_DRINK:
		"res://systems/staff/executors/serve_drink_executor.gd",
	TavernTaskTypes.DELIVER_GROUP_KEG:
		"res://systems/staff/executors/deliver_group_keg_executor.gd",
	TavernTaskTypes.CLEAN_SEAT:
		"res://systems/staff/executors/clean_seat_executor.gd",
	TavernTaskTypes.PREPARE_DRINK:
		"res://systems/staff/executors/prepare_drink_executor.gd",
	TavernTaskTypes.REFILL_STATION:
		"res://systems/staff/executors/refill_station_executor.gd",
}


## Set by [method create_for] so failure messages can name the type.
var task_type: StringName = &""


## A fresh executor for [param task_type], or null when none is registered.
##
## Null is a normal answer, not an error: it is how the board knows a task type
## exists as data but cannot yet be performed by anybody.
static func create_for(
	task_type_id: StringName
) -> StaffTaskExecutor:
	if not EXECUTOR_SCRIPTS.has(task_type_id):
		return null

	var script_path: String = EXECUTOR_SCRIPTS[task_type_id]

	if not ResourceLoader.exists(script_path):
		push_warning(
			"StaffTaskExecutor: '%s' is registered for task type '%s' but "
			% [script_path, String(task_type_id)]
			+ "does not exist."
		)

		return null

	var executor_script: GDScript = load(script_path) as GDScript

	if executor_script == null:
		return null

	var executor: StaffTaskExecutor = executor_script.new()

	if executor == null:
		return null

	executor.task_type = task_type_id

	return executor


static func has_executor_for(
	task_type_id: StringName
) -> bool:
	return EXECUTOR_SCRIPTS.has(task_type_id)


# -----------------------------------------------------------------------------
# Interface
# -----------------------------------------------------------------------------

## True when [param worker] could sensibly start [param task] right now.
##
## Called before every claim, on a throw-away executor instance, so it must be
## cheap and must not change anything. This is where "there is no prepared
## drink to deliver" is answered.
func can_claim(
	_worker: Node,
	_task: TavernTask
) -> bool:
	return true


## Called once, immediately after the claim succeeded.
##
## The place to take reservations and to record on the task exactly which
## source was chosen. Returning false releases the claim.
func on_claimed(
	_worker: Node,
	_task: TavernTask
) -> bool:
	return true


## What the worker should do next, decided from the current world state.
func get_next_step(
	_worker: Node,
	_task: TavernTask
) -> StaffTaskStep:
	return StaffTaskStep.fail(&"executor_not_implemented")


## Runs the world action for a [constant StaffTaskStep.Kind.ACT] step.
func perform_action(
	_worker: Node,
	_task: TavernTask
) -> ActionResult:
	return ActionResult.FAILED


## Checks on an action that reported
## [constant ActionResult.RUNNING].
func poll_action(
	_worker: Node,
	_task: TavernTask
) -> ActionResult:
	return ActionResult.DONE


## Cleans up anything this executor started. Always called when the task ends,
## however it ended, so cancelling from outside is safe.
func abort(
	_worker: Node,
	_task: TavernTask,
	_reason: StringName
) -> void:
	pass


## World minutes until this task stops being achievable, or -1 when it cannot
## expire.
##
## Cleaning returns -1: a dirty seat waits indefinitely. Serving returns the
## customer's remaining patience, which is the whole reason viability checking
## exists.
func get_deadline_minutes(
	_worker: Node,
	_task: TavernTask
) -> float:
	return -1.0


## Total pixels the worker expects to travel to finish this task, or -1 when
## no sensible estimate exists.
##
## The executor owns this because only it knows the shape of the journey - a
## serve is worker to bar to customer, a clean is worker to chair.
func estimate_travel_pixels(
	_worker: Node,
	_task: TavernTask
) -> float:
	return -1.0


## How many discrete hand-offs the task involves.
##
## Each one costs
## [member TaskViabilityConfig.interaction_overhead_minutes]. Collecting a
## drink and handing it over is two; cleaning is one.
func get_interaction_count(
	_worker: Node,
	_task: TavernTask
) -> int:
	return 1


## Real seconds of timed action this task will run, beyond travel.
##
## Cleaning reads its own ActionDefinition. Serving is instantaneous.
func estimate_action_seconds(
	_worker: Node,
	_task: TavernTask
) -> float:
	return 0.0


## True when [param worker] may take this task given what it is holding.
##
## The default is the strict, safe reading, and it is what fixes the Phase 3A
## defect: a worker holding something may only take a task that needs exactly
## that item. A cleaning task therefore refuses a worker carrying a pint,
## which is both correct and what stops the drink being carried around the
## tavern for the rest of the session.
##
## The rule is data-driven via
## [member TavernTaskDefinition.carried_item_rule], so a future task type that
## genuinely does not care can say so in its resource rather than by
## overriding this.
func is_compatible_with_carried_item(
	worker: Node,
	task: TavernTask
) -> bool:
	var carrier: ItemCarrier = get_carrier(worker)

	if carrier == null or not carrier.is_carrying():
		return true

	if task == null or task.definition == null:
		return false

	match task.definition.carried_item_rule:
		TavernTaskDefinition.CarriedItemRule.IGNORES_CARRIED_ITEMS:
			return true

		TavernTaskDefinition.CarriedItemRule.REQUIRES_EMPTY_HANDS:
			return false

	if task.required_definition == null:
		return false

	return carrier.is_carrying_item(task.required_definition.item_id)


## True when this executor actually carried the work out itself.
##
## A task can complete because the requirement was met by somebody else while
## the worker was still walking over. That is a genuine completion of the task
## and a false one for the worker, so counters that describe a worker's output
## ask this first. Defaults to true because most executors only ever reach a
## COMPLETE step by having done the job.
func did_perform_work() -> bool:
	return true


## Free-form state for developer tools and the exported report.
func describe() -> Dictionary:
	return { "task_type": String(task_type) }


# -----------------------------------------------------------------------------
# Shared helpers
# -----------------------------------------------------------------------------

## A walkable point next to [param world_position].
##
## World objects sit inside holes in the navigation mesh - that is what makes
## them solid - so the marker on a bar slot or the seat of a chair is very
## rarely somewhere an actor can stand. Projecting onto the mesh turns "where
## the thing is" into "where a worker can stand to use it" without any
## per-object approach markers having to be placed by hand.
static func get_standing_position_near(
	worker: Node,
	world_position: Vector2
) -> Vector2:
	var worker_2d: Node2D = worker as Node2D

	if worker_2d == null:
		return world_position

	var map: RID = worker_2d.get_world_2d().navigation_map

	if not NavigationService.is_map_ready(map):
		return world_position

	return NavigationService.project_to_mesh(map, world_position)


static func get_carrier(
	worker: Node
) -> ItemCarrier:
	if worker == null or not worker.has_method(&"get_item_carrier"):
		return null

	return worker.get_item_carrier() as ItemCarrier


static func get_action_runner(
	worker: Node
) -> ActionRunner:
	if worker == null or not worker.has_method(&"get_action_runner"):
		return null

	return worker.get_action_runner() as ActionRunner


static func get_worker_position(
	worker: Node
) -> Vector2:
	var worker_2d: Node2D = worker as Node2D

	if worker_2d == null:
		return Vector2.ZERO

	return worker_2d.global_position


## How close this worker needs to be to touch something.
static func get_reach(
	worker: Node
) -> float:
	if worker != null and worker.has_method(&"get_interaction_reach"):
		return float(worker.call(&"get_interaction_reach"))

	return 40.0


## How near the planned spot counts as standing on it, in pixels.
const ARRIVAL_TOLERANCE: float = 16.0


## True when the worker is close enough to act on something.
##
## [b]Two tests, not one, and the second one matters.[/b]
##
## The obvious test is "am I within reach of the thing?". On its own it
## livelocks. World objects sit in holes in the navigation mesh, so the nearest
## spot a worker can actually stand is often further from the object than its
## reach - a chair's staging position is 48 pixels out, and reach is 40. The
## worker then walks to the only place it can stand, finds itself still "too
## far", and walks to the same place again, forever, reporting a healthy path
## the whole time.
##
## So arriving at the spot the executor itself chose also counts. If the
## planner picked somewhere, walking there is by definition enough.
static func is_in_working_position(
	worker: Node,
	target_position: Vector2,
	standing_position: Vector2,
	reach: float
) -> bool:
	var here: Vector2 = get_worker_position(worker)

	if here.distance_to(target_position) <= reach:
		return true

	return here.distance_to(standing_position) <= ARRIVAL_TOLERANCE
