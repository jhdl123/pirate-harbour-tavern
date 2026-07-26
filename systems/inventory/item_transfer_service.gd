class_name ItemTransferService
extends RefCounted

## The single place where items move between slots and containers.
##
## Player interactions, staff AI, storage furniture, trays, shops and a future
## drag-and-drop UI all call these static methods, so they all obey exactly the
## same rules.
##
## Safety contract
## ---------------
## 1. A transfer is fully validated before anything is mutated.
## 2. The source is never emptied before the destination is confirmed valid.
## 3. Quantities never go negative and never exceed item or slot capacity.
## 4. A failed transfer leaves both sides completely unchanged.
## 5. Items are never silently destroyed and never duplicated.
##
## Every call returns an [ItemTransferResult] describing what happened.


## Pass as [param requested_amount] to move the whole source stack.
const AMOUNT_ALL: int = -1


# --- Public API --------------------------------------------------------------

## Moves items from [param source] into [param destination].
##
## Handles full move, partial move, merge, partial merge and swap, and returns
## a descriptive failure when none of those are possible.
##
## [param requested_amount] defaults to the whole source stack. A swap is only
## ever attempted when the whole source stack is being moved.
static func transfer(
	source: ItemSlot,
	destination: ItemSlot,
	requested_amount: int = AMOUNT_ALL,
	allow_swap: bool = true
) -> ItemTransferResult:
	var plan: Dictionary = _build_plan(
		source,
		destination,
		requested_amount,
		allow_swap
	)

	var result: ItemTransferResult = _plan_to_result(plan)

	if not result.is_success():
		return result

	return _apply_plan(source, destination, plan, result)


## Validates a transfer without changing anything.
##
## Useful for interaction prompts, AI decisions and UI hover states.
static func can_transfer(
	source: ItemSlot,
	destination: ItemSlot,
	requested_amount: int = AMOUNT_ALL,
	allow_swap: bool = true
) -> ItemTransferResult:
	return _plan_to_result(
		_build_plan(
			source,
			destination,
			requested_amount,
			allow_swap
		)
	)


## Moves items from [param source] into the best slot of [param container].
##
## Existing matching stacks are filled before empty slots are used, which keeps
## containers tidy without any container-specific code. Swapping is never used
## here, because a container always has the option of another slot.
static func transfer_to_container(
	source: ItemSlot,
	container: ItemContainer,
	requested_amount: int = AMOUNT_ALL
) -> ItemTransferResult:
	if source == null or container == null:
		return ItemTransferResult.failure(
			ItemTransferResult.Status.INVALID_REQUEST
		)

	if source.is_empty():
		return ItemTransferResult.failure(
			ItemTransferResult.Status.SOURCE_EMPTY
		)

	if not source.can_remove():
		return ItemTransferResult.failure(
			ItemTransferResult.Status.SOURCE_LOCKED,
			0,
			source.get_definition()
		)

	var definition: ItemDefinition = source.get_definition()

	var effective_amount: int = _resolve_amount(
		requested_amount,
		source.get_quantity()
	)

	if effective_amount <= 0:
		return ItemTransferResult.failure(
			ItemTransferResult.Status.INVALID_REQUEST,
			0,
			definition
		)

	var stack_to_move: ItemStack = source.peek()
	var target_slots: Array[ItemSlot] = []

	for merge_slot: ItemSlot in container.find_merge_targets(stack_to_move):
		target_slots.append(merge_slot)

	for empty_slot: ItemSlot in container.find_empty_slots(definition):
		target_slots.append(empty_slot)

	if target_slots.is_empty():
		return _container_rejection_result(
			container,
			definition,
			effective_amount
		)

	var total_moved: int = 0
	var last_status: ItemTransferResult.Status = (
		ItemTransferResult.Status.NO_CAPACITY
	)

	for target_slot: ItemSlot in target_slots:
		if total_moved >= effective_amount:
			break

		var step: ItemTransferResult = transfer(
			source,
			target_slot,
			effective_amount - total_moved,
			false
		)

		if not step.is_success():
			continue

		total_moved += step.amount_moved

		if step.status == ItemTransferResult.Status.MERGED:
			last_status = ItemTransferResult.Status.MERGED
		elif step.status == ItemTransferResult.Status.PARTIALLY_MERGED:
			last_status = ItemTransferResult.Status.MERGED
		else:
			last_status = ItemTransferResult.Status.MOVED

	if total_moved <= 0:
		return _container_rejection_result(
			container,
			definition,
			effective_amount
		)

	var final_status: ItemTransferResult.Status = last_status

	if total_moved < effective_amount:
		if last_status == ItemTransferResult.Status.MERGED:
			final_status = ItemTransferResult.Status.PARTIALLY_MERGED
		else:
			final_status = ItemTransferResult.Status.PARTIALLY_MOVED

	return ItemTransferResult.new(
		final_status,
		total_moved,
		effective_amount,
		definition
	)


## Creates [param stack] directly inside [param destination].
##
## Only for slots being filled from a generator with no real source slot, such
## as the current drinks station. Everything that has a real source slot must
## use [method transfer] instead.
static func give_to_slot(
	destination: ItemSlot,
	stack: ItemStack
) -> ItemTransferResult:
	if destination == null or stack == null:
		return ItemTransferResult.failure(
			ItemTransferResult.Status.INVALID_REQUEST
		)

	if stack.is_empty():
		return ItemTransferResult.failure(
			ItemTransferResult.Status.SOURCE_EMPTY
		)

	var source: ItemSlot = ItemSlot.new(
		&"transfer_source",
		_build_permissive_rules(stack)
	)

	if not source.set_stack(stack):
		return ItemTransferResult.failure(
			ItemTransferResult.Status.INVALID_REQUEST,
			stack.quantity,
			stack.definition
		)

	return transfer(source, destination)


# --- Planning ----------------------------------------------------------------
#
# _build_plan never mutates anything. It returns a description of what would
# happen, which _apply_plan then carries out.

static func _build_plan(
	source: ItemSlot,
	destination: ItemSlot,
	requested_amount: int,
	allow_swap: bool
) -> Dictionary:
	var plan: Dictionary = {
		"status": ItemTransferResult.Status.INVALID_REQUEST,
		"amount": 0,
		"requested": 0,
		"definition": null,
		"is_swap": false,
	}

	if source == null or destination == null:
		return plan

	if source == destination:
		return plan

	if requested_amount == 0 or requested_amount < AMOUNT_ALL:
		return plan

	if source.is_empty():
		plan["status"] = ItemTransferResult.Status.SOURCE_EMPTY
		return plan

	var definition: ItemDefinition = source.get_definition()
	plan["definition"] = definition

	var effective_amount: int = _resolve_amount(
		requested_amount,
		source.get_quantity()
	)

	plan["requested"] = effective_amount

	if effective_amount <= 0:
		plan["status"] = ItemTransferResult.Status.INVALID_REQUEST
		return plan

	if not source.can_remove():
		plan["status"] = ItemTransferResult.Status.SOURCE_LOCKED
		return plan

	if not destination.can_insert():
		plan["status"] = ItemTransferResult.Status.DESTINATION_LOCKED
		return plan

	if not destination.accepts_definition(definition):
		plan["status"] = ItemTransferResult.Status.REJECTED_ITEM
		return plan

	# --- Destination is empty: move or partial move ---
	if destination.is_empty():
		var capacity: int = destination.get_capacity_for(definition)
		var movable: int = mini(effective_amount, capacity)

		if movable <= 0:
			plan["status"] = ItemTransferResult.Status.NO_CAPACITY
			return plan

		if movable < effective_amount and not destination.allows_partial():
			plan["status"] = ItemTransferResult.Status.NO_CAPACITY
			return plan

		plan["amount"] = movable

		if movable < effective_amount:
			plan["status"] = ItemTransferResult.Status.PARTIALLY_MOVED
		else:
			plan["status"] = ItemTransferResult.Status.MOVED

		return plan

	# --- Destination holds the same item: merge or partial merge ---
	var source_stack: ItemStack = source.peek()

	if destination.get_item_id() == definition.item_id:
		if not destination.can_merge_stack(source_stack):
			# Same item but blocked by metadata or merge permission.
			# A swap of identical items achieves nothing, so report why.
			plan["status"] = ItemTransferResult.Status.INCOMPATIBLE_STACKS
			return plan

		var space: int = destination.get_remaining_space()
		var mergeable: int = mini(effective_amount, space)

		if mergeable <= 0:
			plan["status"] = ItemTransferResult.Status.NO_CAPACITY
			return plan

		if mergeable < effective_amount and not destination.allows_partial():
			plan["status"] = ItemTransferResult.Status.NO_CAPACITY
			return plan

		plan["amount"] = mergeable

		if mergeable < effective_amount:
			plan["status"] = ItemTransferResult.Status.PARTIALLY_MERGED
		else:
			plan["status"] = ItemTransferResult.Status.MERGED

		return plan

	# --- Destination holds a different item: swap or refuse ---
	if not allow_swap:
		plan["status"] = ItemTransferResult.Status.NO_CAPACITY
		return plan

	if _can_swap(source, destination, effective_amount):
		plan["amount"] = effective_amount
		plan["is_swap"] = true
		plan["status"] = ItemTransferResult.Status.SWAPPED
		return plan

	plan["status"] = ItemTransferResult.Status.NO_CAPACITY

	return plan


## A swap only happens when both sides can fully accept each other's contents.
##
## Anything less would mean splitting an item with nowhere to put the remainder,
## which is how items get lost.
static func _can_swap(
	source: ItemSlot,
	destination: ItemSlot,
	effective_amount: int
) -> bool:
	if not source.can_swap() or not destination.can_swap():
		return false

	# Only a whole-stack move can swap; a partial move has no room to return.
	if effective_amount != source.get_quantity():
		return false

	# The source must be able to receive the destination's item.
	if not source.can_insert():
		return false

	if not destination.can_remove():
		return false

	var destination_definition: ItemDefinition = destination.get_definition()

	if not source.accepts_definition(destination_definition):
		return false

	# Both sides must fit entirely, or the swap would lose items.
	var source_capacity: int = source.get_capacity_for(
		destination_definition
	)

	if destination.get_quantity() > source_capacity:
		return false

	var destination_capacity: int = destination.get_capacity_for(
		source.get_definition()
	)

	if source.get_quantity() > destination_capacity:
		return false

	return true


static func _plan_to_result(plan: Dictionary) -> ItemTransferResult:
	return ItemTransferResult.new(
		plan["status"],
		plan["amount"],
		plan["requested"],
		plan["definition"]
	)


# --- Application -------------------------------------------------------------

static func _apply_plan(
	source: ItemSlot,
	destination: ItemSlot,
	plan: Dictionary,
	result: ItemTransferResult
) -> ItemTransferResult:
	if bool(plan["is_swap"]):
		return _apply_swap(source, destination, result)

	var amount: int = int(plan["amount"])
	var removed: ItemStack = source.remove_quantity(amount)

	if removed.is_empty():
		# Should be impossible after validation. Report rather than lose items.
		push_error(
			"ItemTransferService could not take "
			+ str(amount)
			+ " x '"
			+ String(result.definition.item_id)
			+ "' from the source slot after validation succeeded."
		)

		return ItemTransferResult.failure(
			ItemTransferResult.Status.INVALID_REQUEST,
			result.amount_requested,
			result.definition
		)

	var added: int = destination.add_quantity(
		removed.definition,
		removed.quantity,
		removed.metadata
	)

	if added < removed.quantity:
		# Put back anything the destination refused, so nothing is destroyed.
		var returned: int = source.add_quantity(
			removed.definition,
			removed.quantity - added,
			removed.metadata
		)

		push_error(
			"ItemTransferService could only place "
			+ str(added)
			+ " of "
			+ str(removed.quantity)
			+ " x '"
			+ String(removed.get_item_id())
			+ "'. "
			+ str(returned)
			+ " were returned to the source."
		)

		if added <= 0:
			return ItemTransferResult.failure(
				ItemTransferResult.Status.NO_CAPACITY,
				result.amount_requested,
				result.definition
			)

	result.amount_moved = added

	return result


static func _apply_swap(
	source: ItemSlot,
	destination: ItemSlot,
	result: ItemTransferResult
) -> ItemTransferResult:
	var source_stack: ItemStack = source.peek()
	var destination_stack: ItemStack = destination.peek()

	source.clear()
	destination.clear()

	var destination_accepted: bool = destination.set_stack(source_stack)
	var source_accepted: bool = source.set_stack(destination_stack)

	if destination_accepted and source_accepted:
		result.amount_moved = source_stack.quantity
		return result

	# Validation should prevent this. Restore both sides and report clearly.
	source.clear()
	destination.clear()
	source.set_stack(source_stack)
	destination.set_stack(destination_stack)

	push_error(
		"ItemTransferService rolled back a swap between '"
		+ String(source.slot_id)
		+ "' and '"
		+ String(destination.slot_id)
		+ "' because a slot refused the exchanged stack."
	)

	return ItemTransferResult.failure(
		ItemTransferResult.Status.INVALID_REQUEST,
		result.amount_requested,
		result.definition
	)


# --- Helpers -----------------------------------------------------------------

static func _resolve_amount(
	requested_amount: int,
	available: int
) -> int:
	if requested_amount == AMOUNT_ALL:
		return available

	return mini(requested_amount, available)


## Chooses the most accurate failure reason for a container that took nothing.
static func _container_rejection_result(
	container: ItemContainer,
	definition: ItemDefinition,
	requested: int
) -> ItemTransferResult:
	if not container.accepts_definition(definition):
		return ItemTransferResult.failure(
			ItemTransferResult.Status.REJECTED_ITEM,
			requested,
			definition
		)

	return ItemTransferResult.failure(
		ItemTransferResult.Status.NO_CAPACITY,
		requested,
		definition
	)


## Builds rules that accept exactly one stack, for the temporary source slot
## used by [method give_to_slot].
static func _build_permissive_rules(stack: ItemStack) -> ItemSlotRules:
	var rules: ItemSlotRules = ItemSlotRules.new()

	rules.capacity = maxi(stack.quantity, 1)
	rules.allow_insert = true
	rules.allow_remove = true
	rules.allow_merge = true
	rules.allow_swap = false
	rules.allow_partial = true

	return rules
