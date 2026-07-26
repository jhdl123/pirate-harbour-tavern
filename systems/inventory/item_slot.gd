class_name ItemSlot
extends RefCounted

## One runtime position that holds zero or one [ItemStack].
##
## A slot owns its stack. It copies anything put into it and copies anything it
## hands out, so two slots can never end up sharing one stack object. That
## single rule is what prevents accidental item duplication.
##
## A slot contains no UI code and no scene references. UI observes
## [signal contents_changed] and reads [method peek] instead.
##
## Mutating helpers here are deliberately low-level. Gameplay should move items
## with [ItemTransferService] so that every transfer follows the same rules.


## Emitted whenever the held stack changes in any way.
##
## [param previous_stack] and [param current_stack] are independent copies and
## are safe to keep. An empty stack means "nothing here".
signal contents_changed(
	previous_stack: ItemStack,
	current_stack: ItemStack
)


## Stable identifier, unique within its owning [ItemContainer].
##
## Used by save data to restore items to the same visible position.
var slot_id: StringName = &""

## Filters, capacity and permissions for this slot.
var rules: ItemSlotRules = null

var _stack: ItemStack = ItemStack.new()


func _init(
	new_slot_id: StringName = &"",
	slot_rules: ItemSlotRules = null
) -> void:
	slot_id = new_slot_id
	rules = slot_rules

	if rules == null:
		rules = ItemSlotRules.new()


# --- Reading -----------------------------------------------------------------

func is_empty() -> bool:
	return _stack.is_empty()


func has_item() -> bool:
	return not _stack.is_empty()


## Returns an independent copy of the held stack.
##
## Mutating the returned stack never affects the slot.
func peek() -> ItemStack:
	return _stack.duplicate_stack()


## Returns the held definition, or null when the slot is empty.
##
## Safe to compare by identity or by [member ItemDefinition.item_id].
func get_definition() -> ItemDefinition:
	if _stack.is_empty():
		return null

	return _stack.definition


func get_item_id() -> StringName:
	return _stack.get_item_id()


func get_quantity() -> int:
	if _stack.is_empty():
		return 0

	return _stack.quantity


## Returns the capacity this slot allows for [param definition].
func get_capacity_for(definition: ItemDefinition) -> int:
	return rules.get_effective_capacity(definition)


## Returns how many more of the held item would fit.
func get_remaining_space() -> int:
	if _stack.is_empty():
		return 0

	return maxi(
		get_capacity_for(_stack.definition) - _stack.quantity,
		0
	)


## Returns how many of [param definition] this slot could take right now.
##
## Accounts for filters, permissions, merge permission and both capacities.
func get_acceptable_amount(definition: ItemDefinition) -> int:
	if definition == null:
		return 0

	if not rules.allow_insert:
		return 0

	if not rules.accepts_definition(definition):
		return 0

	if _stack.is_empty():
		return get_capacity_for(definition)

	if not rules.allow_merge:
		return 0

	if _stack.definition.item_id != definition.item_id:
		return 0

	return get_remaining_space()


# --- Validation --------------------------------------------------------------

func can_insert() -> bool:
	return rules.allow_insert


func can_remove() -> bool:
	return rules.allow_remove


func can_swap() -> bool:
	return rules.allow_swap


func allows_partial() -> bool:
	return rules.allow_partial


## Returns true when this slot's filters accept [param definition].
func accepts_definition(definition: ItemDefinition) -> bool:
	return rules.accepts_definition(definition)


## Returns true when [param stack] could merge into what is already held.
func can_merge_stack(stack: ItemStack) -> bool:
	if stack == null or stack.is_empty():
		return false

	if _stack.is_empty():
		return false

	if not rules.allow_merge:
		return false

	if not _stack.matches_definition(stack.definition):
		return false

	if not _stack.is_metadata_compatible_with(stack):
		return false

	return get_remaining_space() > 0


# --- Mutation ----------------------------------------------------------------
#
# These are the only places the held stack changes. ItemTransferService
# validates a whole transaction before calling any of them.

## Replaces the contents with a private copy of [param stack].
##
## Returns false and changes nothing when the resulting stack would be invalid.
## Pass null or an empty stack to empty the slot.
func set_stack(stack: ItemStack) -> bool:
	if stack == null or stack.is_empty():
		clear()
		return true

	if stack.quantity < 0:
		push_error(
			"ItemSlot '"
			+ String(slot_id)
			+ "' rejected a stack with a negative quantity."
		)
		return false

	var capacity: int = get_capacity_for(stack.definition)

	if stack.quantity > capacity:
		push_error(
			"ItemSlot '"
			+ String(slot_id)
			+ "' rejected "
			+ str(stack.quantity)
			+ " x '"
			+ String(stack.get_item_id())
			+ "' because its capacity is "
			+ str(capacity)
			+ "."
		)
		return false

	var previous: ItemStack = _stack
	_stack = stack.duplicate_stack()

	contents_changed.emit(previous, peek())

	return true


## Empties the slot and returns what was held.
##
## Returns an empty stack when the slot was already empty.
func clear() -> ItemStack:
	if _stack.is_empty():
		return ItemStack.new()

	var previous: ItemStack = _stack
	_stack = ItemStack.new()

	contents_changed.emit(previous, peek())

	return previous


## Adds up to [param amount] of the held or matching item.
##
## Returns the amount actually added. Does not validate filters or permissions:
## callers are expected to have validated first.
func add_quantity(
	definition: ItemDefinition,
	amount: int,
	stack_metadata: Dictionary = {}
) -> int:
	if definition == null or amount <= 0:
		return 0

	var previous: ItemStack = _stack.duplicate_stack()
	var added: int = 0

	if _stack.is_empty():
		var capacity: int = get_capacity_for(definition)
		added = mini(amount, capacity)

		if added <= 0:
			return 0

		_stack = ItemStack.new(
			definition,
			added,
			stack_metadata
		)
	else:
		added = mini(amount, get_remaining_space())

		if added <= 0:
			return 0

		_stack.quantity += added

	contents_changed.emit(previous, peek())

	return added


## Removes up to [param amount] items and returns them as an independent stack.
func remove_quantity(amount: int) -> ItemStack:
	if amount <= 0 or _stack.is_empty():
		return ItemStack.new()

	var previous: ItemStack = _stack.duplicate_stack()
	var removed: ItemStack = _stack.split(amount)

	contents_changed.emit(previous, peek())

	return removed


# --- Serialisation -----------------------------------------------------------

func to_dictionary() -> Dictionary:
	return {
		"slot_id": String(slot_id),
		"stack": _stack.to_dictionary(),
	}


## Restores contents from [method to_dictionary] data.
##
## Bypasses filters on purpose: a save must be able to restore whatever was
## legitimately stored, even if rules were later tightened. Capacity is still
## respected so a stack can never load above its limit.
func from_dictionary(
	data: Dictionary,
	registry: ItemRegistry
) -> void:
	var loaded: ItemStack = ItemStack.new()

	if data.has("stack") and data["stack"] is Dictionary:
		loaded = ItemStack.from_dictionary(
			data["stack"],
			registry
		)

	if not loaded.is_empty():
		var capacity: int = get_capacity_for(loaded.definition)

		if loaded.quantity > capacity:
			push_warning(
				"Slot '"
				+ String(slot_id)
				+ "' loaded "
				+ str(loaded.quantity)
				+ " x '"
				+ String(loaded.get_item_id())
				+ "' but only holds "
				+ str(capacity)
				+ ". The excess was dropped."
			)
			loaded.quantity = capacity

	var previous: ItemStack = _stack
	_stack = loaded

	contents_changed.emit(previous, peek())
