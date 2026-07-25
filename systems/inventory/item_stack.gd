class_name ItemStack
extends Resource

## The static definition shared by every item in this stack.
@export var definition: ItemDefinition

## Current number of items in this stack.
@export_range(0, 999999, 1)
var quantity: int = 0


func _init(
	item_definition: ItemDefinition = null,
	starting_quantity: int = 0
) -> void:
	definition = item_definition
	quantity = maxi(starting_quantity, 0)
	clamp_quantity()


func is_empty() -> bool:
	return definition == null or quantity <= 0


func is_valid() -> bool:
	return (
		definition != null
		and definition.is_valid()
		and quantity >= 0
		and quantity <= definition.maximum_stack_size
	)


func get_available_space() -> int:
	if definition == null:
		return 0

	return maxi(
		definition.maximum_stack_size - quantity,
		0
	)


func can_accept(
	item_definition: ItemDefinition,
	amount: int = 1
) -> bool:
	if item_definition == null or amount <= 0:
		return false

	if definition == null or quantity <= 0:
		return amount <= item_definition.maximum_stack_size

	if definition != item_definition:
		return false

	return quantity + amount <= definition.maximum_stack_size


## Adds as many items as the stack can hold.
##
## Returns the amount successfully added.
func add(amount: int) -> int:
	if definition == null or amount <= 0:
		return 0

	var amount_added: int = mini(
		amount,
		get_available_space()
	)

	quantity += amount_added
	return amount_added


## Removes as many items as are available.
##
## Returns the amount successfully removed.
func remove(amount: int) -> int:
	if amount <= 0 or is_empty():
		return 0

	var amount_removed: int = mini(amount, quantity)
	quantity -= amount_removed

	return amount_removed


func can_merge_with(other_stack: ItemStack) -> bool:
	return (
		other_stack != null
		and not other_stack.is_empty()
		and definition != null
		and definition == other_stack.definition
		and get_available_space() > 0
	)


## Transfers as many items as possible from another stack.
##
## Returns the number transferred.
func merge_from(other_stack: ItemStack) -> int:
	if not can_merge_with(other_stack):
		return 0

	var transfer_amount: int = mini(
		get_available_space(),
		other_stack.quantity
	)

	var transferred: int = add(transfer_amount)
	other_stack.remove(transferred)

	return transferred


## Removes items from this stack and returns them as a new stack.
func split(amount: int) -> ItemStack:
	if amount <= 0 or is_empty():
		return null

	var split_quantity: int = mini(amount, quantity)
	remove(split_quantity)

	return ItemStack.new(definition, split_quantity)


func clear() -> void:
	definition = null
	quantity = 0


func duplicate_stack() -> ItemStack:
	return ItemStack.new(definition, quantity)


func get_total_base_buy_value() -> int:
	if definition == null:
		return 0

	return definition.get_base_buy_value(quantity)


func get_total_base_sell_value() -> int:
	if definition == null:
		return 0

	return definition.get_base_sell_value(quantity)


func clamp_quantity() -> void:
	if definition == null:
		quantity = 0
		return

	quantity = clampi(
		quantity,
		0,
		definition.maximum_stack_size
	)
