class_name CarriedItemRecovery
extends RefCounted

## Decides, and carries out, what happens to an item left in a worker's hands.
##
## Split from [StaffMember] deliberately. The worker knows how to walk and how
## to hold things; it should not also contain a branching policy about where a
## drink belongs, because the next staff role will need a different answer and
## would otherwise copy this logic with one line changed.
##
## The service works in two halves:
##
## [codeblock]
## plan()     look at the world and choose an outcome. Cheap, no side effects,
##            safe to call every tick while the worker walks somewhere.
## execute()  perform the chosen transfer, now that the worker is in reach.
## [/codeblock]
##
## Planning separately from executing is what lets the worker change its mind
## on the way: if a customer orders the exact drink it is carrying while it is
## halfway to the bar to put it down, the next plan is a reassignment instead.
##
## Every route moves the item through an existing transaction -
## [ItemCarrier.place_into], the station's own "put back" interaction, or
## [StockStorage.deposit_carried]. Nothing here clears a slot directly except
## the explicitly-enabled disposal route, which always reports itself.


## A plan is a Dictionary so that a new route can add a field without every
## caller needing to know about it. Keys:
##
## [codeblock]
## outcome        CarriedItemPolicy.Outcome
## is_possible    bool    false means no route was found at all
## is_immediate   bool    true when execute() can run from where the worker is
## position       Vector2 where to stand, when not immediate
## node           Node    the counter, station or storage involved
## slot_index     int     for a service slot
## task           TavernTask, for REASSIGN
## detail         String  human-readable, for diagnostics
## [/codeblock]
const OUTCOME_KEY: StringName = &"outcome"


## Chooses the best available outcome for whatever [param worker] is holding.
##
## Returns a plan whose [code]is_possible[/code] is false when the policy's
## whole outcome list came up empty, which is the caller's cue to record a
## recovery failure and try again after the policy's retry delay.
static func plan(
	worker: Node,
	policy: CarriedItemPolicy
) -> Dictionary:
	var carrier: ItemCarrier = _get_carrier(worker)

	if carrier == null or not carrier.is_carrying():
		return _impossible("nothing carried")

	if policy == null:
		policy = CarriedItemPolicy.new()

	var definition: ItemDefinition = carrier.get_carried_definition()

	for outcome: CarriedItemPolicy.Outcome in policy.get_outcome_order():
		var candidate: Dictionary = _plan_outcome(
			worker,
			carrier,
			definition,
			policy,
			outcome
		)

		if bool(candidate.get("is_possible", false)):
			return candidate

	if policy.allow_disposal:
		return {
			OUTCOME_KEY: CarriedItemPolicy.Outcome.DISPOSE,
			"is_possible": true,
			"is_immediate": true,
			"detail": "no route available; disposal is permitted",
		}

	return _impossible("no route available and disposal is not permitted")


static func _plan_outcome(
	worker: Node,
	carrier: ItemCarrier,
	definition: ItemDefinition,
	policy: CarriedItemPolicy,
	outcome: CarriedItemPolicy.Outcome
) -> Dictionary:
	match outcome:
		CarriedItemPolicy.Outcome.REASSIGN:
			return _plan_reassign(worker, definition, policy)

		CarriedItemPolicy.Outcome.RETURN_TO_SERVICE_SLOT:
			return _plan_service_slot(worker, definition)

		CarriedItemPolicy.Outcome.RETURN_TO_SOURCE_STATION:
			return _plan_station(worker, definition)

		CarriedItemPolicy.Outcome.RETURN_TO_STORAGE:
			return _plan_storage(worker, carrier)

		CarriedItemPolicy.Outcome.RETAIN:
			if not policy.allow_retaining_as_last_resort:
				return _impossible("retaining is not permitted")

			return {
				OUTCOME_KEY: CarriedItemPolicy.Outcome.RETAIN,
				"is_possible": true,
				"is_immediate": true,
				"detail": "kept in hand; no better route available",
			}

		CarriedItemPolicy.Outcome.DISPOSE:
			if not policy.allow_disposal:
				return _impossible("disposal is not permitted")

			return {
				OUTCOME_KEY: CarriedItemPolicy.Outcome.DISPOSE,
				"is_possible": true,
				"is_immediate": true,
				"detail": "disposal explicitly permitted by policy",
			}

	return _impossible("unknown outcome")


# -----------------------------------------------------------------------------
# Routes
# -----------------------------------------------------------------------------

## Another waiting customer who ordered exactly this.
##
## Looks for an open board task rather than scanning customers directly, so
## the ordinary claiming, deduplication and reservation rules all still apply
## and two workers can never reassign the same drink to the same person.
static func _plan_reassign(
	worker: Node,
	definition: ItemDefinition,
	policy: CarriedItemPolicy
) -> Dictionary:
	if definition == null:
		return _impossible("nothing to reassign")

	var worker_position: Vector2 = _get_position(worker)

	var best: TavernTask = null
	var best_distance: float = INF

	# Only task types this worker is actually allowed to perform.
	#
	# The previous version looked exclusively at serve_drink, which handed a
	# bartender holding a prepared drink a customer-delivery task and was the
	# route by which the bartender completed two serves in the long test. A
	# drink in the hand is not permission to leave your role.
	for task: TavernTask in _get_reassignable_tasks(worker):
		if task.required_definition == null:
			continue

		if task.required_definition.item_id != definition.item_id:
			continue

		if not policy.may_steal_claimed_tasks and not task.is_claimable():
			continue

		var target: Node = task.get_target()

		if target == null or not target.has_method(&"is_awaiting_service"):
			continue

		if not bool(target.call(&"is_awaiting_service")):
			continue

		var distance: float = worker_position.distance_to(
			task.get_reference_position()
		)

		if (
			policy.maximum_reassignment_distance > 0.0
			and distance > policy.maximum_reassignment_distance
		):
			continue

		if distance < best_distance:
			best_distance = distance
			best = task

	if best == null:
		return _impossible("no other customer wants this drink")

	return {
		OUTCOME_KEY: CarriedItemPolicy.Outcome.REASSIGN,
		"is_possible": true,
		"is_immediate": true,
		"task": best,
		"detail": "reassigned to %s" % String(best.task_id),
	}


## Open tasks this worker could legitimately take, across every task type that
## consumes an item.
##
## Asking the board per type rather than scanning all open tasks keeps this on
## the indexed path, and asking the worker for its capabilities keeps the rule
## in one place instead of hard-coding which role may do what.
static func _get_reassignable_tasks(
	worker: Node
) -> Array[TavernTask]:
	var candidates: Array[TavernTask] = []

	if worker == null or not worker.has_method(&"get_staff_capabilities"):
		return candidates

	var capabilities: Array[StringName] = worker.call(
		&"get_staff_capabilities"
	)

	for task_type: StringName in TavernTaskTypes.get_implemented_types():
		for task: TavernTask in TaskBoard.get_open_tasks_of_type(task_type):
			if task.definition == null:
				continue

			if not StaffCapabilities.satisfies(
				capabilities,
				task.definition.required_capabilities
			):
				continue

			candidates.append(task)

	return candidates


static func _plan_service_slot(
	worker: Node,
	definition: ItemDefinition
) -> Dictionary:
	var tree: SceneTree = _get_tree(worker)

	if tree == null or definition == null:
		return _impossible("no scene tree")

	var worker_position: Vector2 = _get_position(worker)

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

			if slot == null or not slot.is_empty():
				continue

			# Ask the slot itself rather than assuming a counter takes drinks.
			if slot.get_acceptable_amount(definition) <= 0:
				continue

			var slot_position: Vector2 = _get_slot_position(
				node,
				slot_index,
				worker
			)
			var distance: float = worker_position.distance_to(slot_position)

			if distance < best_distance:
				best_distance = distance

				best = {
					OUTCOME_KEY: CarriedItemPolicy.Outcome.RETURN_TO_SERVICE_SLOT,
					"is_possible": true,
					"is_immediate": distance <= _get_reach(worker),
					"position": slot_position,
					"node": node,
					"slot_index": slot_index,
					"detail": "%s slot %d" % [String(node.name), slot_index],
				}

	if best.is_empty():
		return _impossible("no free service slot accepts it")

	return best


static func _plan_station(
	worker: Node,
	definition: ItemDefinition
) -> Dictionary:
	var tree: SceneTree = _get_tree(worker)

	if tree == null or definition == null:
		return _impossible("no scene tree")

	var worker_position: Vector2 = _get_position(worker)

	var best: Node = null
	var best_distance: float = INF

	for node: Node in tree.get_nodes_in_group(&"drink_stations"):
		var station: Node2D = node as Node2D

		if station == null or not is_instance_valid(station):
			continue

		var served: Variant = station.get("served_drink")

		if served == null:
			continue

		var served_drink: ItemDefinition = served as ItemDefinition

		if served_drink == null or served_drink.item_id != definition.item_id:
			continue

		var distance: float = worker_position.distance_to(
			station.global_position
		)

		if distance < best_distance:
			best_distance = distance
			best = station

	if best == null:
		return _impossible("no station serves this drink")

	var best_2d: Node2D = best as Node2D

	return {
		OUTCOME_KEY: CarriedItemPolicy.Outcome.RETURN_TO_SOURCE_STATION,
		"is_possible": true,
		"is_immediate": best_distance <= _get_reach(worker),
		"position": best_2d.global_position,
		"node": best,
		"detail": String(best.name),
	}


static func _plan_storage(
	worker: Node,
	carrier: ItemCarrier
) -> Dictionary:
	var tree: SceneTree = _get_tree(worker)

	if tree == null:
		return _impossible("no scene tree")

	var definition: ItemDefinition = carrier.get_carried_definition()

	for node: Node in tree.get_nodes_in_group(&"stock_storage"):
		var storage: Node = node

		if storage == null or not is_instance_valid(storage):
			continue

		var inventory: Variant = storage.get("inventory")
		var container: ItemContainer = inventory as ItemContainer

		# Ask the container whether it would take this, rather than walking
		# across the room to find out that storage rejects prepared drinks.
		if container == null or not container.accepts_definition(definition):
			continue

		var storage_2d: Node2D = storage as Node2D
		var position: Vector2 = (
			Vector2.ZERO if storage_2d == null else storage_2d.global_position
		)

		return {
			OUTCOME_KEY: CarriedItemPolicy.Outcome.RETURN_TO_STORAGE,
			"is_possible": true,
			"is_immediate": (
				_get_position(worker).distance_to(position)
				<= _get_reach(worker)
			),
			"position": position,
			"node": storage,
			"detail": String(storage.name),
		}

	return _impossible("storage will not accept it")


# -----------------------------------------------------------------------------
# Execution
# -----------------------------------------------------------------------------

## Carries out [param plan], which must be immediate.
##
## Returns [code]{ success: bool, reason: StringName, detail: String }[/code].
## [code]reason[/code] is a [StaffTransitionReason] constant so the caller can
## record it without translating anything.
static func execute(
	worker: Node,
	plan_data: Dictionary
) -> Dictionary:
	var carrier: ItemCarrier = _get_carrier(worker)

	if carrier == null or not carrier.is_carrying():
		return _result(true, StaffTransitionReason.OTHER, "nothing carried")

	var outcome: CarriedItemPolicy.Outcome = plan_data.get(
		OUTCOME_KEY,
		CarriedItemPolicy.Outcome.RETAIN
	)

	var detail: String = String(plan_data.get("detail", ""))

	match outcome:
		CarriedItemPolicy.Outcome.RETAIN:
			return _result(
				true,
				StaffTransitionReason.CARRIED_ITEM_RETAINED,
				detail
			)

		CarriedItemPolicy.Outcome.REASSIGN:
			# Nothing moves: the worker keeps the drink and the caller claims
			# the task it was matched to. Recorded as a distinct outcome
			# because "kept it because somebody else wants it" and "kept it
			# because there was nowhere to put it" are very different events.
			return _result(
				true,
				StaffTransitionReason.CARRIED_ITEM_REASSIGNED,
				detail
			)

		CarriedItemPolicy.Outcome.RETURN_TO_SERVICE_SLOT:
			return _execute_service_slot(carrier, plan_data, detail)

		CarriedItemPolicy.Outcome.RETURN_TO_SOURCE_STATION:
			return _execute_station(worker, carrier, plan_data, detail)

		CarriedItemPolicy.Outcome.RETURN_TO_STORAGE:
			return _execute_storage(carrier, plan_data, detail)

		CarriedItemPolicy.Outcome.DISPOSE:
			var discarded: ItemStack = carrier.clear_carried_item()

			return _result(
				true,
				StaffTransitionReason.CARRIED_ITEM_DISPOSED,
				"destroyed %s (%s)" % [discarded.get_display_name(), detail]
			)

	return _result(
		false,
		StaffTransitionReason.CARRIED_ITEM_RECOVERY_FAILED,
		"unknown outcome"
	)


static func _execute_service_slot(
	carrier: ItemCarrier,
	plan_data: Dictionary,
	detail: String
) -> Dictionary:
	var counter: Node = plan_data.get("node", null) as Node

	if counter == null or not is_instance_valid(counter):
		return _result(
			false,
			StaffTransitionReason.CARRIED_ITEM_RECOVERY_FAILED,
			"the counter went away"
		)

	var slot: ItemSlot = counter.call(
		&"get_service_slot",
		int(plan_data.get("slot_index", -1))
	) as ItemSlot

	if slot == null:
		return _result(
			false,
			StaffTransitionReason.CARRIED_ITEM_RECOVERY_FAILED,
			"the slot went away"
		)

	var result: ItemTransferResult = carrier.place_into(slot)

	if not result.is_success():
		return _result(
			false,
			StaffTransitionReason.CARRIED_ITEM_RECOVERY_FAILED,
			result.get_message()
		)

	return _result(
		true,
		StaffTransitionReason.CARRIED_ITEM_RETURNED,
		detail
	)


static func _execute_station(
	worker: Node,
	carrier: ItemCarrier,
	plan_data: Dictionary,
	detail: String
) -> Dictionary:
	var station: Node = plan_data.get("node", null) as Node

	if station == null or not is_instance_valid(station):
		return _result(
			false,
			StaffTransitionReason.CARRIED_ITEM_RECOVERY_FAILED,
			"the station went away"
		)

	if not station.has_method(&"perform_interaction"):
		return _result(
			false,
			StaffTransitionReason.CARRIED_ITEM_RECOVERY_FAILED,
			"the station has no interaction"
		)

	var carried_before: StringName = carrier.get_carried_item_id()

	# The station's own "put back" action - the same one a player standing
	# there holding a drink would be offered.
	var request: InteractionRequest = InteractionRequest.create(
		worker,
		station.get("interactable"),
		&"return"
	)

	var performed: bool = bool(
		station.call(&"perform_interaction", request)
	)

	if not performed or carrier.get_carried_item_id() == carried_before:
		return _result(
			false,
			StaffTransitionReason.CARRIED_ITEM_RECOVERY_FAILED,
			"the station refused it"
		)

	return _result(
		true,
		StaffTransitionReason.CARRIED_ITEM_RESTOCKED,
		detail
	)


static func _execute_storage(
	carrier: ItemCarrier,
	plan_data: Dictionary,
	detail: String
) -> Dictionary:
	var storage: Node = plan_data.get("node", null) as Node

	if storage == null or not is_instance_valid(storage):
		return _result(
			false,
			StaffTransitionReason.CARRIED_ITEM_RECOVERY_FAILED,
			"storage went away"
		)

	if not storage.has_method(&"deposit_carried"):
		return _result(
			false,
			StaffTransitionReason.CARRIED_ITEM_RECOVERY_FAILED,
			"storage cannot accept a hand-off"
		)

	var result: ItemTransferResult = storage.call(
		&"deposit_carried",
		carrier
	) as ItemTransferResult

	if result == null or not result.is_success():
		return _result(
			false,
			StaffTransitionReason.CARRIED_ITEM_RECOVERY_FAILED,
			"storage rejected it"
		)

	return _result(
		true,
		StaffTransitionReason.CARRIED_ITEM_RESTOCKED,
		detail
	)


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

static func _impossible(
	detail: String
) -> Dictionary:
	return {
		"is_possible": false,
		"is_immediate": false,
		"detail": detail,
	}


static func _result(
	success: bool,
	reason: StringName,
	detail: String
) -> Dictionary:
	return {
		"success": success,
		"reason": reason,
		"detail": detail,
	}


static func _get_carrier(
	worker: Node
) -> ItemCarrier:
	if worker == null or not worker.has_method(&"get_item_carrier"):
		return null

	return worker.get_item_carrier() as ItemCarrier


static func _get_tree(
	worker: Node
) -> SceneTree:
	if worker == null:
		return null

	return worker.get_tree()


static func _get_position(
	worker: Node
) -> Vector2:
	var worker_2d: Node2D = worker as Node2D

	return Vector2.ZERO if worker_2d == null else worker_2d.global_position


static func _get_reach(
	worker: Node
) -> float:
	if worker != null and worker.has_method(&"get_interaction_reach"):
		return float(worker.call(&"get_interaction_reach"))

	return 40.0


## Where [param worker] stands to put something into a slot.
##
## Which side depends on the role, not on the item: a bartender returns a
## drink from behind the counter, a hand from in front of it. Both reach the
## same logical slot.
static func _get_slot_position(
	counter: Node,
	slot_index: int,
	worker: Node = null
) -> Vector2:
	if counter == null:
		return Vector2.ZERO

	if counter.has_method(&"get_slot_access_position"):
		return counter.call(
			&"get_slot_access_position",
			slot_index,
			_get_access_for_worker(worker)
		)

	var counter_2d: Node2D = counter as Node2D

	return Vector2.ZERO if counter_2d == null else counter_2d.global_position


## Deposit side for anyone who prepares drinks, collection side otherwise.
static func _get_access_for_worker(
	worker: Node
) -> BarCounter.SlotAccess:
	if worker != null and worker.has_method(&"get_staff_capabilities"):
		var capabilities: Array[StringName] = worker.call(
			&"get_staff_capabilities"
		)

		if capabilities.has(StaffCapabilities.PREPARE_DRINKS):
			return BarCounter.SlotAccess.DEPOSIT

	return BarCounter.SlotAccess.COLLECT
