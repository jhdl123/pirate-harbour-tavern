class_name DeliverGroupKegExecutor
extends StaffTaskExecutor

## Carries one filled small keg from storage to a waiting customer group.
##
## Structurally the same job as [ServeDrinkExecutor], and deliberately built
## the same way: the keg is a real [ItemStack] that really leaves the storage
## container through [method ItemCarrier.take_from], and the shared serving is
## created by the group system's own code rather than by a second copy of it
## living in here. Nothing is spawned and nothing teleports.
##
## The group is addressed by id rather than by node reference. A group can be
## freed mid-delivery - it is a Node, not a resource - and looking it up each
## time is what lets the worker discover that and put the keg back rather than
## walk to a formation point that no longer exists.


## Set by [method get_next_step] so [method perform_action] knows which half
## of the job it is running.
var _pending_action: StringName = &""

## True once the keg has actually been set down for the group.
var _has_delivered: bool = false


func can_claim(
	worker: Node,
	task: TavernTask
) -> bool:
	if task.required_definition == null:
		return false

	var carrier: ItemCarrier = get_carrier(worker)

	if carrier == null:
		return false

	if _find_group(task) == null:
		return false

	# Already holding the right keg - the best possible starting position.
	if carrier.is_carrying_item(task.required_definition.item_id):
		return true

	if carrier.is_carrying():
		return false

	return _find_storage(task) != null


func on_claimed(
	_worker: Node,
	task: TavernTask
) -> bool:
	var storage: Node = _find_storage(task)

	if storage == null:
		var carrier: ItemCarrier = get_carrier(_worker)

		return (
			carrier != null
			and task.required_definition != null
			and carrier.is_carrying_item(task.required_definition.item_id)
		)

	task.source_ref = weakref(storage)

	return true


func get_next_step(
	worker: Node,
	task: TavernTask
) -> StaffTaskStep:
	_pending_action = &""

	if _has_delivered:
		return StaffTaskStep.complete()

	if task.required_definition == null:
		return StaffTaskStep.fail(&"no_required_item")

	var group: Node = _find_group(task)

	if group == null:
		# The party left, or the visit failed, while the keg was in transit.
		return StaffTaskStep.fail(&"group_no_longer_waiting")

	var carrier: ItemCarrier = get_carrier(worker)

	if carrier == null:
		return StaffTaskStep.fail(&"worker_cannot_carry")

	if carrier.is_carrying_item(task.required_definition.item_id):
		return _step_towards_group(worker, task, group)

	if carrier.is_carrying():
		return StaffTaskStep.release(&"hands_not_free")

	return _step_towards_storage(worker, task)


func perform_action(
	worker: Node,
	task: TavernTask
) -> ActionResult:
	match _pending_action:
		&"collect":
			return _collect_keg(worker, task)

		&"place":
			return _place_keg(worker, task)

	return ActionResult.FAILED


# -----------------------------------------------------------------------------
# Collecting
# -----------------------------------------------------------------------------

func _step_towards_storage(
	worker: Node,
	task: TavernTask
) -> StaffTaskStep:
	var storage: Node = _find_storage(task)

	if storage == null:
		return StaffTaskStep.release(&"group_keg_unavailable")

	task.source_ref = weakref(storage)

	var storage_2d: Node2D = storage as Node2D

	if storage_2d == null:
		return StaffTaskStep.fail(&"storage_has_no_position")

	var marker_position: Vector2 = storage_2d.global_position
	var stand_at: Vector2 = get_standing_position_near(worker, marker_position)

	if not is_in_working_position(
		worker,
		marker_position,
		stand_at,
		get_reach(worker)
	):
		return StaffTaskStep.move_to(
			stand_at,
			8.0,
			"%s (group keg)" % String(storage.name)
		)

	_pending_action = &"collect"

	return StaffTaskStep.act("collect group keg")


func _collect_keg(
	worker: Node,
	task: TavernTask
) -> ActionResult:
	var storage: Node = task.get_source()

	if storage == null or not storage.has_method(&"take_one"):
		return ActionResult.FAILED

	var carrier: ItemCarrier = get_carrier(worker)

	if carrier == null:
		return ActionResult.FAILED

	# The real transaction. One stack leaves the container and enters the
	# worker's hands; the reservation only ever promised that it would.
	var result: ItemTransferResult = storage.call(
		&"take_one", task.required_definition.item_id, carrier
	) as ItemTransferResult

	if result == null or not result.is_success():
		TaskBoard.report_issue(
			TavernTaskService.ISSUE_TRANSFER_FAILED,
			"Worker could not take %s from %s."
			% [task.required_definition.display_name, String(storage.name)],
			{ "task_id": String(task.task_id) }
		)

		return ActionResult.FAILED

	var manager: Node = _find_group_manager()

	if manager != null and manager.has_method(&"notify_group_keg_collected"):
		manager.call(&"notify_group_keg_collected", task)

	return ActionResult.DONE


# -----------------------------------------------------------------------------
# Delivering
# -----------------------------------------------------------------------------

func _step_towards_group(
	worker: Node,
	task: TavernTask,
	group: Node
) -> StaffTaskStep:
	var centre: Vector2 = _get_group_position(group)

	if centre == Vector2.ZERO:
		return StaffTaskStep.fail(&"group_point_invalid")

	# Walk to the gap in the ring, not to the middle of it. Standing on the
	# delivery point leaves nowhere to put the keg, and the members' avoidance
	# radii mean the middle usually is not reachable anyway.
	var approach: Vector2 = _get_approach_position(group, centre)

	# Close enough to the keg point already - place it, wherever the worker
	# happens to be standing. Checked before the approach so a worker that has
	# arrived cannot be sent back out to a point it has already passed.
	if _get_worker_distance(worker, centre) <= placement_range:
		return _try_place(group)

	if not is_in_working_position(
		worker,
		approach,
		approach,
		get_reach(worker)
	):
		return StaffTaskStep.move_to(
			approach,
			12.0,
			"group %s" % String(task.metadata.get("group_id", ""))
		)

	# Standing at the approach but still out of range of the keg point: the
	# offered approach is too far out. Move in along the same line rather than
	# giving up - one bounded step, not an oscillation.
	var closer: Vector2 = approach.lerp(centre, 0.5)

	if _get_worker_distance(worker, closer) > 12.0:
		_note_approach_retry(group)

		return StaffTaskStep.move_to(closer, 10.0, "closer to the keg point")

	return _try_place(group)


## Places the keg, or waits while the group is still opening up.
func _try_place(group: Node) -> StaffTaskStep:
	if group.has_method(&"is_ready_for_keg_placement"):
		if not bool(group.call(&"is_ready_for_keg_placement")):
			return StaffTaskStep.wait(0.5, "waiting for the group to make room")

	_pending_action = &"place"

	return StaffTaskStep.act("set down group keg")


func _note_approach_retry(group: Node) -> void:
	var retries: Variant = group.get(&"delivery_approach_retries")

	if retries != null:
		group.set(&"delivery_approach_retries", int(retries) + 1)


## How close the worker must be to the keg point to put the keg down.
var placement_range: float = 72.0


## The reachable spot the group has offered for this delivery.
func _get_approach_position(group: Node, centre: Vector2) -> Vector2:
	var offered: Variant = group.get(&"delivery_approach_position")

	if offered != null and offered is Vector2 and offered != Vector2.ZERO:
		return offered

	return centre


func _get_worker_distance(worker: Node, point: Vector2) -> float:
	var worker_2d: Node2D = worker as Node2D

	return (
		worker_2d.global_position.distance_to(point)
		if worker_2d != null else INF
	)


func _place_keg(
	worker: Node,
	task: TavernTask
) -> ActionResult:
	var manager: Node = _find_group_manager()

	if manager == null or not manager.has_method(&"complete_group_keg_delivery"):
		return ActionResult.FAILED

	# The shared serving is built by the group system's own creation path, so
	# there is exactly one place a SharedServing can come from.
	if not bool(manager.call(&"complete_group_keg_delivery", task, worker)):
		return ActionResult.FAILED

	var carrier: ItemCarrier = get_carrier(worker)

	if carrier != null:
		carrier.clear_carried_item()

	_has_delivered = true

	return ActionResult.DONE


func abort(
	worker: Node,
	task: TavernTask,
	reason: StringName
) -> void:
	if _has_delivered:
		return

	var manager: Node = _find_group_manager()

	if manager != null and manager.has_method(&"notify_group_keg_delivery_aborted"):
		manager.call(&"notify_group_keg_delivery_aborted", task, reason)

	# A keg already in the hands must not evaporate. The carried-item recovery
	# policy the project already owns is what puts it back.
	super.abort(worker, task, reason)


func did_perform_work() -> bool:
	return _has_delivered


# -----------------------------------------------------------------------------
# Lookups
# -----------------------------------------------------------------------------

func _find_group_manager() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree

	if tree == null:
		return null

	var found: Array[Node] = tree.get_nodes_in_group(&"group_manager")

	return found[0] if not found.is_empty() else null


func _find_group(task: TavernTask) -> Node:
	var manager: Node = _find_group_manager()

	if manager == null or not manager.has_method(&"get_group"):
		return null

	var group_id: StringName = StringName(
		String(task.metadata.get("group_id", ""))
	)

	if group_id.is_empty():
		return null

	var group: Node = manager.call(&"get_group", group_id) as Node

	if group == null or not is_instance_valid(group):
		return null

	if group.has_method(&"is_awaiting_keg_delivery"):
		if not bool(group.call(&"is_awaiting_keg_delivery")):
			return null

	return group


func _find_storage(task: TavernTask) -> Node:
	if task.required_definition == null:
		return null

	var recorded: Node = task.get_source()

	if recorded != null and recorded.has_method(&"count_item"):
		if int(recorded.call(&"count_item", task.required_definition.item_id)) > 0:
			return recorded

	var tree: SceneTree = Engine.get_main_loop() as SceneTree

	if tree == null:
		return null

	for node: Node in tree.get_nodes_in_group(&"stock_storage"):
		if not node.has_method(&"count_item"):
			continue

		if int(node.call(&"count_item", task.required_definition.item_id)) > 0:
			return node

	return null


func _get_group_position(group: Node) -> Vector2:
	if group.has_method(&"get_serving_position"):
		return group.call(&"get_serving_position")

	return Vector2.ZERO
