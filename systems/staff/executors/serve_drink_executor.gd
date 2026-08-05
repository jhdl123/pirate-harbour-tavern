class_name ServeDrinkExecutor
extends StaffTaskExecutor

## Carries one prepared drink from a bar service slot to one waiting customer.
##
## Every step here goes through a system the player already uses:
##
## [codeblock]
## finding the drink   BarCounter.get_service_container(), the same slots the
##                     player puts drinks into
## collecting it       ItemCarrier.take_from(), so the slot really empties and
##                     the worker really holds the one ItemStack
## serving it          Customer.try_serve(), the exact method the player's own
##                     interaction now calls
## [/codeblock]
##
## Nothing is spawned, nothing is teleported, no station stock is consumed a
## second time, and there is no staff-only representation of a drink anywhere.
## If this executor were deleted, the player could still do all of it by hand.
##
## [b]Why the drink is not reserved with a Reservable[/b]
##
## A service slot is an [ItemSlot] inside an [ItemContainer], not a node, so it
## cannot hold a [Reservable] child. Exclusivity comes from the task board
## instead: a slot already named by another live serve task is skipped in
## [method _find_source_slot], and the claim on the task is itself atomic. The
## player is deliberately still able to take a "reserved" drink - the worker
## finds the slot empty on arrival and re-plans, which is the behaviour we
## want, not a bug to prevent.


## Set when [method get_next_step] returns an ACT step, so
## [method perform_action] knows which half of the job it is running.
var _pending_action: StringName = &""

## True once the drink has actually been handed over.
##
## Without this the executor re-plans after a successful serve, finds the hands
## empty and the customer no longer waiting, and releases a task it had in fact
## just finished - which the board then cancels as "no longer required". The
## work happened either way, but the diagnostics would say otherwise and
## notify_on_completion would never fire.
var _has_served: bool = false


func can_claim(
	worker: Node,
	task: TavernTask
) -> bool:
	var customer: Node = task.get_target()

	if customer == null:
		return false

	if not customer.has_method(&"is_awaiting_service"):
		return false

	if not bool(customer.call(&"is_awaiting_service")):
		return false

	if task.required_definition == null:
		return false

	var carrier: ItemCarrier = get_carrier(worker)

	if carrier == null:
		return false

	# Already holding the right drink - the best possible starting position.
	if carrier.is_carrying_item(task.required_definition.item_id):
		return true

	# Holding something else. Refusing here rather than inventing a
	# "put it down somewhere" step keeps this phase honest: the worker only
	# ever carries what a task gave it.
	if carrier.is_carrying():
		return false

	# An empty Dictionary is not null, so this must be tested with is_empty().
	# Comparing the result to null instead made every claim succeed and then
	# immediately fail its setup, which showed up as a claim/release spin.
	return not _find_source_slot(worker, task).is_empty()


func on_claimed(
	worker: Node,
	task: TavernTask
) -> bool:
	var carrier: ItemCarrier = get_carrier(worker)

	if carrier != null and task.required_definition != null:
		if carrier.is_carrying_item(task.required_definition.item_id):
			return true

	var found: Dictionary = _find_source_slot(worker, task)

	if found.is_empty():
		return false

	task.source_ref = weakref(found["counter"] as Node)
	task.source_data = { &"slot_index": int(found["slot_index"]) }

	return true


func get_next_step(
	worker: Node,
	task: TavernTask
) -> StaffTaskStep:
	_pending_action = &""

	# Asked first, and before any world checks: the requirement is met, and
	# nothing about the hands or the customer can change that after the fact.
	if _has_served:
		return StaffTaskStep.complete()

	var customer: Node = task.get_target()

	if customer == null:
		return StaffTaskStep.fail(&"customer_missing")

	if task.required_definition == null:
		return StaffTaskStep.fail(&"no_required_item")

	var carrier: ItemCarrier = get_carrier(worker)

	if carrier == null:
		return StaffTaskStep.fail(&"worker_cannot_carry")

	if carrier.is_carrying_item(task.required_definition.item_id):
		return _step_towards_customer(worker, task, customer)

	if carrier.is_carrying():
		# The worker's hands changed under it - a developer tool, or a future
		# system handing it something. Give the task up cleanly rather than
		# quietly dropping whatever it is now holding.
		return StaffTaskStep.release(&"hands_not_free")

	return _step_towards_drink(worker, task)


func perform_action(
	worker: Node,
	task: TavernTask
) -> ActionResult:
	match _pending_action:
		&"collect":
			return _collect_drink(worker, task)

		&"serve":
			return _serve_customer(worker, task)

	return ActionResult.FAILED


# -----------------------------------------------------------------------------
# Collecting
# -----------------------------------------------------------------------------

func _step_towards_drink(
	worker: Node,
	task: TavernTask
) -> StaffTaskStep:
	var slot_view: Dictionary = _resolve_recorded_slot(task)

	if slot_view.is_empty():
		# Whatever we were walking towards has gone. Look again before giving
		# up: another slot may hold an identical drink.
		slot_view = _find_source_slot(worker, task)

		if slot_view.is_empty():
			return StaffTaskStep.release(&"prepared_drink_unavailable")

		task.source_ref = weakref(slot_view["counter"] as Node)
		task.source_data = { &"slot_index": int(slot_view["slot_index"]) }

	var counter: Node = slot_view["counter"] as Node
	var slot_index: int = int(slot_view["slot_index"])

	var marker_position: Vector2 = _get_slot_position(counter, slot_index)
	var reach: float = _get_slot_reach(worker, counter)

	var stand_at: Vector2 = get_standing_position_near(
		worker,
		marker_position
	)

	if not is_in_working_position(
		worker,
		marker_position,
		stand_at,
		reach
	):
		return StaffTaskStep.move_to(
			stand_at,
			8.0,
			"%s slot %d" % [String(counter.name), slot_index]
		)

	_pending_action = &"collect"

	return StaffTaskStep.act("collect drink")


func _collect_drink(
	worker: Node,
	task: TavernTask
) -> ActionResult:
	var slot_view: Dictionary = _resolve_recorded_slot(task)

	if slot_view.is_empty():
		return ActionResult.FAILED

	var counter: Node = slot_view["counter"] as Node
	var slot_index: int = int(slot_view["slot_index"])

	var service_slot: ItemSlot = counter.call(
		&"get_service_slot",
		slot_index
	) as ItemSlot

	if service_slot == null or service_slot.is_empty():
		return ActionResult.FAILED

	var carrier: ItemCarrier = get_carrier(worker)

	if carrier == null:
		return ActionResult.FAILED

	# The real transfer. One ItemStack moves out of the counter and into the
	# worker's hands; no copy is made and no drink is created.
	var result: ItemTransferResult = carrier.take_from(service_slot)

	if not result.is_success():
		TaskBoard.report_issue(
			TavernTaskService.ISSUE_TRANSFER_FAILED,
			"Worker could not take %s from %s slot %d: %s"
			% [
				task.required_definition.display_name,
				String(counter.name),
				slot_index,
				result.get_message(),
			],
			{ "task_id": String(task.task_id) }
		)

		return ActionResult.FAILED

	return ActionResult.DONE


# -----------------------------------------------------------------------------
# Serving
# -----------------------------------------------------------------------------

func _step_towards_customer(
	worker: Node,
	task: TavernTask,
	customer: Node
) -> StaffTaskStep:
	if not bool(customer.call(&"is_awaiting_service")):
		# Somebody else got there first, or the customer moved on. The worker
		# is still holding a real drink, so the task is released rather than
		# completed and StaffMember will put the drink back.
		return StaffTaskStep.release(&"customer_no_longer_waiting")

	var approach: Vector2 = customer.call(
		&"get_service_approach_position"
	)

	var customer_2d: Node2D = customer as Node2D
	var reach: float = get_reach(worker)

	var stand_at: Vector2 = get_standing_position_near(worker, approach)

	if customer_2d != null:
		if is_in_working_position(
			worker,
			customer_2d.global_position,
			stand_at,
			reach
		):
			_pending_action = &"serve"

			return StaffTaskStep.act("serve customer")

	return StaffTaskStep.move_to(
		stand_at,
		10.0,
		String(customer.name)
	)


func _serve_customer(
	worker: Node,
	task: TavernTask
) -> ActionResult:
	var customer: Node = task.get_target()

	if customer == null or not customer.has_method(&"try_serve"):
		return ActionResult.FAILED

	if not bool(customer.call(&"is_awaiting_service")):
		TaskBoard.report_issue(
			TavernTaskService.ISSUE_DUPLICATE_SERVICE,
			"Worker reached %s to serve, but the customer was no longer "
			% String(customer.name)
			+ "waiting - the drink was not handed over.",
			{ "task_id": String(task.task_id) }
		)

		return ActionResult.FAILED

	# Raised *before* the serve, not after. Customer.try_serve() changes the
	# customer's state synchronously and emits service_state_changed from
	# inside itself, so TavernTaskCoordinator sees "this customer is no longer
	# waiting" while we are still inside this call. Setting the flag first is
	# what tells the coordinator and the board that the requirement is being
	# met right now rather than disappearing, so a successful delivery is
	# recorded as a completion instead of a cancellation.
	task.is_resolution_pending = true

	# The shared, authoritative serve. Identical to the player's own path:
	# it re-checks the state and the carried item, empties the hands and runs
	# the real drinking/paying flow.
	if not bool(customer.call(&"try_serve", worker)):
		task.is_resolution_pending = false

		return ActionResult.FAILED

	_has_served = true

	return ActionResult.DONE


# -----------------------------------------------------------------------------
# Finding drinks
# -----------------------------------------------------------------------------

## The slot this task already named, if it still holds the right drink.
func _resolve_recorded_slot(
	task: TavernTask
) -> Dictionary:
	var counter: Node = task.get_source()

	if counter == null or not counter.has_method(&"get_service_slot"):
		return {}

	var slot_index: int = int(task.source_data.get(&"slot_index", -1))

	if slot_index < 0:
		return {}

	var slot: ItemSlot = counter.call(
		&"get_service_slot",
		slot_index
	) as ItemSlot

	if slot == null or slot.is_empty():
		return {}

	if task.required_definition == null:
		return {}

	if slot.get_item_id() != task.required_definition.item_id:
		return {}

	return { "counter": counter, "slot_index": slot_index }


## The nearest service slot holding the drink this task needs.
##
## Only objects in the [code]bar_counters[/code] group are considered, which is
## how the drink station's own output slot stays out of reach: pouring is the
## player's job this phase, and taking from a station would consume stock.
func _find_source_slot(
	worker: Node,
	task: TavernTask
) -> Dictionary:
	if worker == null or task.required_definition == null:
		return {}

	var tree: SceneTree = worker.get_tree()

	if tree == null:
		return {}

	var wanted_id: StringName = task.required_definition.item_id
	var from_position: Vector2 = get_worker_position(worker)

	var best: Dictionary = {}
	var best_distance: float = INF

	for node: Node in tree.get_nodes_in_group(&"bar_counters"):
		if node == null or not is_instance_valid(node):
			continue

		if not node.has_method(&"get_service_container"):
			continue

		var container: ItemContainer = node.call(
			&"get_service_container"
		) as ItemContainer

		if container == null:
			continue

		for slot_index: int in range(container.get_slot_count()):
			var slot: ItemSlot = container.get_slot(slot_index)

			if slot == null or slot.is_empty():
				continue

			if slot.get_item_id() != wanted_id:
				continue

			if _is_slot_taken_by_another_task(node, slot_index, task):
				continue

			var slot_position: Vector2 = _get_slot_position(node, slot_index)
			var distance: float = from_position.distance_to(slot_position)

			if distance < best_distance:
				best_distance = distance
				best = { "counter": node, "slot_index": slot_index }

	return best


## True when a different live task has already named this slot.
##
## Linear over active tasks, which is a handful even in a busy tavern, and far
## cheaper than maintaining a second index that could fall out of step.
func _is_slot_taken_by_another_task(
	counter: Node,
	slot_index: int,
	task: TavernTask
) -> bool:
	for other: TavernTask in TaskBoard.get_active_tasks():
		if other == task:
			continue

		if other.get_source() != counter:
			continue

		if int(other.source_data.get(&"slot_index", -1)) == slot_index:
			return true

	return false


## Where this executor's worker stands to reach a slot.
##
## Serving is collection work, so it always uses the customer side. The item
## itself does not move: only the approach point differs from the bartender's.
func _get_slot_position(
	counter: Node,
	slot_index: int
) -> Vector2:
	if counter == null:
		return Vector2.ZERO

	if counter.has_method(&"get_slot_access_position"):
		return counter.call(
			&"get_slot_access_position",
			slot_index,
			BarCounter.SlotAccess.COLLECT
		)

	var counter_2d: Node2D = counter as Node2D

	if counter_2d != null:
		return counter_2d.global_position

	return Vector2.ZERO


## How close the worker must be to use a slot on [param counter].
##
## Honours the counter's own limit so staff can never reach further than the
## player can, which would look wrong and would also let a worker serve
## through a wall.
func _get_slot_reach(
	worker: Node,
	counter: Node
) -> float:
	var reach: float = get_reach(worker)

	if counter != null and "slot_interaction_distance" in counter:
		reach = minf(
			reach,
			float(counter.get("slot_interaction_distance")) - 4.0
		)

	return maxf(reach, 8.0)


# -----------------------------------------------------------------------------
# Viability
# -----------------------------------------------------------------------------

## How long the customer will keep waiting.
##
## This is the number that makes serving tasks expire and cleaning tasks not.
func get_deadline_minutes(
	_worker: Node,
	task: TavernTask
) -> float:
	var customer: Node = task.get_target()

	if customer == null:
		return 0.0

	if not customer.has_method(&"get_patience_remaining_minutes"):
		return -1.0

	return float(customer.call(&"get_patience_remaining_minutes"))


## Worker to bar to customer, or worker straight to customer when the drink is
## already in hand.
##
## Returning -1 when no drink can be found is what stops the board estimating
## a journey to a slot that does not exist.
func estimate_travel_pixels(
	worker: Node,
	task: TavernTask
) -> float:
	var customer: Node2D = task.get_target() as Node2D

	if customer == null:
		return -1.0

	var config: TaskViabilityConfig = TaskBoard.get_viability_config()
	var worker_position: Vector2 = get_worker_position(worker)
	var carrier: ItemCarrier = get_carrier(worker)

	var already_holding: bool = (
		carrier != null
		and task.required_definition != null
		and carrier.is_carrying_item(task.required_definition.item_id)
	)

	if already_holding:
		return TaskViability.measure_distance(
			worker,
			task,
			"direct",
			worker_position,
			customer.global_position,
			config
		)

	var slot_view: Dictionary = _resolve_recorded_slot(task)

	if slot_view.is_empty():
		slot_view = _find_source_slot(worker, task)

	if slot_view.is_empty():
		return -1.0

	var slot_position: Vector2 = _get_slot_position(
		slot_view["counter"] as Node,
		int(slot_view["slot_index"])
	)

	var to_slot: float = TaskViability.measure_distance(
		worker,
		task,
		"to_source",
		worker_position,
		slot_position,
		config
	)

	var to_customer: float = TaskViability.measure_distance(
		worker,
		task,
		"source_to_target",
		slot_position,
		customer.global_position,
		config
	)

	return to_slot + to_customer


## Collecting and handing over, unless the drink is already in hand.
func get_interaction_count(
	worker: Node,
	task: TavernTask
) -> int:
	var carrier: ItemCarrier = get_carrier(worker)

	if (
		carrier != null
		and task.required_definition != null
		and carrier.is_carrying_item(task.required_definition.item_id)
	):
		return 1

	return 2

func describe() -> Dictionary:
	return {
		"task_type": String(task_type),
		"pending_action": String(_pending_action),
		"has_served": _has_served,
	}
