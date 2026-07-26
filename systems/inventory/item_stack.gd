class_name ItemStack
extends Resource

## A runtime quantity of one item, plus optional per-stack metadata.
##
## [ItemDefinition] answers "what is this item?".
## [ItemStack] answers "how many, and in what condition?".
##
## Ownership rule
## --------------
## A stack instance is owned by exactly one holder. [ItemSlot] always stores a
## private copy and always hands out copies, so no two slots can ever share one
## stack object. Anything creating a stack for a slot should let the slot copy
## it rather than keeping its own reference and mutating it later.


## The static definition shared by every item in this stack.
@export var definition: ItemDefinition

## Current number of items in this stack.
@export_range(0, 999999, 1)
var quantity: int = 0

## Optional per-stack state.
##
## Extension point for future quality, spoilage, ownership or contraband data.
## Two stacks with different metadata never merge automatically.
@export var metadata: Dictionary = {}


func _init(
	item_definition: ItemDefinition = null,
	starting_quantity: int = 0,
	starting_metadata: Dictionary = {}
) -> void:
	definition = item_definition
	quantity = maxi(starting_quantity, 0)
	metadata = starting_metadata.duplicate(true)
	clamp_quantity()


## Preferred way to build a stack.
##
## Seeds metadata from the definition's defaults, then applies any overrides.
static func create(
	item_definition: ItemDefinition,
	starting_quantity: int = 1,
	metadata_overrides: Dictionary = {}
) -> ItemStack:
	if item_definition == null:
		push_error("ItemStack.create() received a null ItemDefinition.")
		return ItemStack.new()

	if starting_quantity < 0:
		push_error(
			"ItemStack.create() received a negative quantity for '"
			+ String(item_definition.item_id)
			+ "'."
		)
		starting_quantity = 0

	var combined_metadata: Dictionary = (
		item_definition.get_default_metadata()
	)

	for key: Variant in metadata_overrides:
		combined_metadata[key] = metadata_overrides[key]

	return ItemStack.new(
		item_definition,
		starting_quantity,
		combined_metadata
	)


## Returns a shared, always-empty-safe stack.
static func create_empty() -> ItemStack:
	return ItemStack.new()


func is_empty() -> bool:
	return definition == null or quantity <= 0


func is_valid() -> bool:
	return (
		definition != null
		and definition.is_valid()
		and quantity >= 0
		and quantity <= definition.maximum_stack_size
	)


func get_item_id() -> StringName:
	if definition == null:
		return &""

	return definition.item_id


func get_display_name() -> String:
	if definition == null:
		return "Nothing"

	return definition.display_name


func get_maximum_stack_size() -> int:
	if definition == null:
		return 0

	return definition.maximum_stack_size


func get_available_space() -> int:
	if definition == null:
		return 0

	return maxi(definition.maximum_stack_size - quantity, 0)


## Returns true when this stack holds the given definition.
##
## Compares stable ids rather than object identity so that duplicated or
## reloaded resources still match.
func matches_definition(other_definition: ItemDefinition) -> bool:
	if definition == null or other_definition == null:
		return false

	return definition.item_id == other_definition.item_id


## Returns true when both stacks carry equivalent per-stack state.
##
## Stacks with incompatible metadata must never merge.
func is_metadata_compatible_with(other_stack: ItemStack) -> bool:
	if other_stack == null:
		return false

	if metadata.size() != other_stack.metadata.size():
		return false

	for key: Variant in metadata:
		if not other_stack.metadata.has(key):
			return false

		if metadata[key] != other_stack.metadata[key]:
			return false

	return true


## Returns true when [param other_stack] could be merged into this one.
func can_merge_with(other_stack: ItemStack) -> bool:
	if other_stack == null or other_stack.is_empty():
		return false

	if is_empty():
		return false

	if not matches_definition(other_stack.definition):
		return false

	if not is_metadata_compatible_with(other_stack):
		return false

	return get_available_space() > 0


func can_accept(
	item_definition: ItemDefinition,
	amount: int = 1
) -> bool:
	if item_definition == null or amount <= 0:
		return false

	if is_empty():
		return amount <= item_definition.maximum_stack_size

	if definition.item_id != item_definition.item_id:
		return false

	return quantity + amount <= definition.maximum_stack_size


## Adds as many items as the stack can hold.
##
## Returns the amount successfully added.
func add(amount: int) -> int:
	if definition == null or amount <= 0:
		return 0

	var amount_added: int = mini(amount, get_available_space())
	quantity += amount_added

	return amount_added


## Removes as many items as are available.
##
## Returns the amount successfully removed. Clears the definition once the
## stack becomes empty so the slot reads as truly empty.
func remove(amount: int) -> int:
	if amount <= 0 or is_empty():
		return 0

	var amount_removed: int = mini(amount, quantity)
	quantity -= amount_removed

	if quantity <= 0:
		clear()

	return amount_removed


## Transfers as many items as possible from another stack.
##
## Returns the number transferred. Prefer [ItemTransferService] for anything
## involving slots; this helper exists for stack-level maths.
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


## Removes items from this stack and returns them as an independent stack.
func split(amount: int) -> ItemStack:
	if amount <= 0 or is_empty():
		return ItemStack.new()

	var split_quantity: int = mini(amount, quantity)
	var split_definition: ItemDefinition = definition
	var split_metadata: Dictionary = metadata.duplicate(true)

	remove(split_quantity)

	return ItemStack.new(
		split_definition,
		split_quantity,
		split_metadata
	)


func clear() -> void:
	definition = null
	quantity = 0
	metadata = {}


## Returns an independent copy, including a deep copy of the metadata.
func duplicate_stack() -> ItemStack:
	return ItemStack.new(
		definition,
		quantity,
		metadata
	)


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


# --- Serialisation -----------------------------------------------------------

## Converts the stack to plain, save-friendly data.
##
## Only stable ids and primitives are stored - never resource or node
## references. An empty stack serialises to an empty dictionary.
func to_dictionary() -> Dictionary:
	if is_empty():
		return {}

	var data: Dictionary = {
		"item_id": String(definition.item_id),
		"quantity": quantity,
	}

	if not metadata.is_empty():
		data["metadata"] = metadata.duplicate(true)

	return data


## Rebuilds a stack from [method to_dictionary] data.
##
## [param registry] resolves the stable item id back to an [ItemDefinition].
## Returns an empty stack when the item id is unknown, so a save containing a
## removed item degrades gracefully instead of crashing.
static func from_dictionary(
	data: Dictionary,
	registry: ItemRegistry
) -> ItemStack:
	if data.is_empty():
		return ItemStack.new()

	if not data.has("item_id"):
		push_warning(
			"ItemStack.from_dictionary() received data without an item_id."
		)
		return ItemStack.new()

	if registry == null:
		push_error(
			"ItemStack.from_dictionary() requires an ItemRegistry to resolve '"
			+ str(data["item_id"])
			+ "'."
		)
		return ItemStack.new()

	var item_id: StringName = StringName(str(data["item_id"]))
	var resolved: ItemDefinition = registry.get_definition(item_id)

	if resolved == null:
		push_warning(
			"Unknown item id '"
			+ String(item_id)
			+ "' while loading. The stack was dropped."
		)
		return ItemStack.new()

	var loaded_quantity: int = int(data.get("quantity", 0))

	if loaded_quantity < 0:
		push_warning(
			"Item '"
			+ String(item_id)
			+ "' loaded with a negative quantity. Clamped to zero."
		)
		loaded_quantity = 0

	var loaded_metadata: Dictionary = {}

	if data.has("metadata") and data["metadata"] is Dictionary:
		loaded_metadata = (data["metadata"] as Dictionary).duplicate(true)

	return ItemStack.new(
		resolved,
		loaded_quantity,
		loaded_metadata
	)
