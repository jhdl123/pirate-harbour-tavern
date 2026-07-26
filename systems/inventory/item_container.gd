class_name ItemContainer
extends RefCounted

## An ordered, fixed set of [ItemSlot]s.
##
## One container script serves every storage case in the game. A player
## backpack, a cellar crate, a bar counter, a serving tray, a staff pack, a keg
## input, a station output, a delivery crate and a shop stock list differ only
## in slot count, container tags and slot rules - never in logic.
##
## Slot order is fixed and slot ids are stable, so saved items always return to
## the same visible position.
##
## Containers hold no scene references and no UI code.


## Emitted when the stack in [param slot_index] changes.
signal slot_changed(
	slot_index: int,
	previous_stack: ItemStack,
	current_stack: ItemStack
)

## Emitted after any change, for listeners that only need "something changed".
signal contents_changed


## Stable identifier used by save data, for example &"player_backpack".
var container_id: StringName = &""

## Data-driven categories describing the container itself.
##
## Examples: &"storage", &"service", &"personal". Used by future rules such as
## "staff may restock any container tagged service".
var container_tags: Array[StringName] = []

var _slots: Array[ItemSlot] = []


## Builds a container of [param slot_count] identical slots.
##
## Each slot receives its own copy of [param default_rules], so per-slot
## overrides applied later never leak into the other slots.
func _init(
	new_container_id: StringName = &"",
	slot_count: int = 1,
	default_rules: ItemSlotRules = null
) -> void:
	container_id = new_container_id

	var rules_template: ItemSlotRules = default_rules

	if rules_template == null:
		rules_template = ItemSlotRules.new()

	if slot_count < 0:
		push_error(
			"ItemContainer '"
			+ String(container_id)
			+ "' was created with a negative slot count."
		)
		slot_count = 0

	for slot_index: int in range(slot_count):
		_add_slot(
			StringName("%s_%d" % [String(container_id), slot_index]),
			rules_template.duplicate_rules()
		)


func _add_slot(
	slot_id: StringName,
	rules: ItemSlotRules
) -> ItemSlot:
	var slot: ItemSlot = ItemSlot.new(slot_id, rules)
	var slot_index: int = _slots.size()

	_slots.append(slot)

	# A bound method callable is used rather than a lambda on purpose.
	# A lambda would capture this container by strong reference, and because the
	# container also owns the slot that stores the connection, the pair would
	# form a reference cycle and never be freed.
	slot.contents_changed.connect(
		_on_slot_contents_changed.bind(slot_index)
	)

	return slot


func _on_slot_contents_changed(
	previous_stack: ItemStack,
	current_stack: ItemStack,
	slot_index: int
) -> void:
	slot_changed.emit(slot_index, previous_stack, current_stack)
	contents_changed.emit()


# --- Slot access -------------------------------------------------------------

func get_slot_count() -> int:
	return _slots.size()


func get_slot(slot_index: int) -> ItemSlot:
	if slot_index < 0 or slot_index >= _slots.size():
		push_error(
			"ItemContainer '"
			+ String(container_id)
			+ "' has no slot at index "
			+ str(slot_index)
			+ ". Valid range is 0 to "
			+ str(_slots.size() - 1)
			+ "."
		)
		return null

	return _slots[slot_index]


func get_slots() -> Array[ItemSlot]:
	return _slots.duplicate()


func get_slot_by_id(slot_id: StringName) -> ItemSlot:
	for slot: ItemSlot in _slots:
		if slot.slot_id == slot_id:
			return slot

	return null


func get_slot_index(slot: ItemSlot) -> int:
	return _slots.find(slot)


## Replaces the rules of one slot, for example to make a single visible
## service slot stricter than the rest of a counter.
func set_slot_rules(
	slot_index: int,
	rules: ItemSlotRules
) -> void:
	var slot: ItemSlot = get_slot(slot_index)

	if slot == null or rules == null:
		return

	slot.rules = rules


# --- Queries -----------------------------------------------------------------

func is_empty() -> bool:
	for slot: ItemSlot in _slots:
		if slot.has_item():
			return false

	return true


func is_full() -> bool:
	for slot: ItemSlot in _slots:
		if slot.is_empty():
			return false

	return true


## Returns true when at least one slot's filters accept [param definition].
func accepts_definition(definition: ItemDefinition) -> bool:
	if definition == null:
		return false

	for slot: ItemSlot in _slots:
		if slot.can_insert() and slot.accepts_definition(definition):
			return true

	return false


## Total number of [param item_id] held across every slot.
func get_total_quantity(item_id: StringName) -> int:
	var total: int = 0

	for slot: ItemSlot in _slots:
		if slot.get_item_id() == item_id:
			total += slot.get_quantity()

	return total


func has_item(
	item_id: StringName,
	minimum_quantity: int = 1
) -> bool:
	return get_total_quantity(item_id) >= maxi(minimum_quantity, 1)


## Slots already holding a compatible stack with room to spare.
##
## Filling these first keeps containers tidy and is what makes "add" behave the
## way players expect.
func find_merge_targets(stack: ItemStack) -> Array[ItemSlot]:
	var targets: Array[ItemSlot] = []

	if stack == null or stack.is_empty():
		return targets

	for slot: ItemSlot in _slots:
		if slot.can_merge_stack(stack):
			targets.append(slot)

	return targets


## Empty slots whose filters accept [param definition].
func find_empty_slots(definition: ItemDefinition) -> Array[ItemSlot]:
	var targets: Array[ItemSlot] = []

	if definition == null:
		return targets

	for slot: ItemSlot in _slots:
		if not slot.is_empty():
			continue

		if not slot.can_insert():
			continue

		if not slot.accepts_definition(definition):
			continue

		targets.append(slot)

	return targets


## First slot holding [param item_id], or null.
func find_slot_with_item(item_id: StringName) -> ItemSlot:
	for slot: ItemSlot in _slots:
		if slot.get_item_id() == item_id:
			return slot

	return null


# --- Mutation ----------------------------------------------------------------
#
# Everything routes through ItemTransferService so containers, carriers, world
# objects and UI all obey identical rules.

## Adds [param stack] to this container.
##
## Fills matching stacks before empty slots. The passed stack is not modified.
func add_stack(stack: ItemStack) -> ItemTransferResult:
	if stack == null or stack.is_empty():
		return ItemTransferResult.failure(
			ItemTransferResult.Status.SOURCE_EMPTY
		)

	var staging_rules: ItemSlotRules = ItemSlotRules.new()
	staging_rules.capacity = maxi(stack.quantity, 1)
	staging_rules.allow_swap = false

	var staging_slot: ItemSlot = ItemSlot.new(
		&"container_staging",
		staging_rules
	)

	if not staging_slot.set_stack(stack):
		return ItemTransferResult.failure(
			ItemTransferResult.Status.INVALID_REQUEST,
			stack.quantity,
			stack.definition
		)

	return ItemTransferService.transfer_to_container(
		staging_slot,
		self
	)


## Convenience wrapper around [method add_stack].
func add_item(
	definition: ItemDefinition,
	quantity: int = 1,
	stack_metadata: Dictionary = {}
) -> ItemTransferResult:
	if definition == null:
		return ItemTransferResult.failure(
			ItemTransferResult.Status.INVALID_REQUEST
		)

	return add_stack(
		ItemStack.create(
			definition,
			quantity,
			stack_metadata
		)
	)


## Removes up to [param quantity] of [param item_id].
##
## Returns the amount actually removed. Removal is all-or-nothing only when
## [param require_full_amount] is true.
func remove_item(
	item_id: StringName,
	quantity: int = 1,
	require_full_amount: bool = false
) -> int:
	if quantity <= 0:
		return 0

	if require_full_amount and get_total_quantity(item_id) < quantity:
		return 0

	var remaining: int = quantity

	for slot: ItemSlot in _slots:
		if remaining <= 0:
			break

		if slot.get_item_id() != item_id:
			continue

		if not slot.can_remove():
			continue

		var removed: ItemStack = slot.remove_quantity(remaining)
		remaining -= removed.quantity

	return quantity - remaining


## Empties every slot. Intended for load and for test setup.
func clear() -> void:
	for slot: ItemSlot in _slots:
		slot.clear()


# --- Serialisation -----------------------------------------------------------

## Converts the container to plain, save-friendly data.
##
## Slots are stored by fixed index and stable slot id, never by node reference.
func to_dictionary() -> Dictionary:
	var slot_data: Array = []

	for slot: ItemSlot in _slots:
		slot_data.append(slot.to_dictionary())

	return {
		"container_id": String(container_id),
		"slot_count": _slots.size(),
		"slots": slot_data,
	}


## Restores contents from [method to_dictionary] data.
##
## Slot count is NOT resized from the save: the container's configured layout
## stays authoritative, so a later design change to slot count cannot corrupt
## the scene. Extra saved slots are reported rather than silently dropped.
func from_dictionary(
	data: Dictionary,
	registry: ItemRegistry
) -> void:
	if not data.has("slots") or not data["slots"] is Array:
		push_warning(
			"ItemContainer '"
			+ String(container_id)
			+ "' received save data without a slots array."
		)
		return

	clear()

	var saved_slots: Array = data["slots"]

	for slot_index: int in range(saved_slots.size()):
		if slot_index >= _slots.size():
			push_warning(
				"ItemContainer '"
				+ String(container_id)
				+ "' has "
				+ str(_slots.size())
				+ " slots but the save contained "
				+ str(saved_slots.size())
				+ ". Slot "
				+ str(slot_index)
				+ " could not be restored."
			)
			break

		if not saved_slots[slot_index] is Dictionary:
			continue

		_slots[slot_index].from_dictionary(
			saved_slots[slot_index],
			registry
		)


# --- Debugging ---------------------------------------------------------------

func describe_contents() -> String:
	var lines: PackedStringArray = []

	lines.append(
		"Container '%s' (%d slots)" % [
			String(container_id),
			_slots.size()
		]
	)

	for slot_index: int in range(_slots.size()):
		var slot: ItemSlot = _slots[slot_index]

		if slot.is_empty():
			lines.append("  %d: empty" % slot_index)
			continue

		lines.append(
			"  %d: %d x %s" % [
				slot_index,
				slot.get_quantity(),
				slot.peek().get_display_name()
			]
		)

	return "\n".join(lines)
