class_name ItemRegistry
extends Resource

## Maps stable item ids back to [ItemDefinition] resources.
##
## Save files store item ids, never resource paths, so loading needs one place
## that can answer "which definition is 'grog'?". This resource is that place.
##
## It is a plain [Resource] rather than an autoload, so a test, a shop or a
## future modded content pack can use its own registry without touching global
## state.


## Every item definition the game knows about.
##
## [DrinkDefinition] resources belong here too - a drink IS an item.
@export var definitions: Array[ItemDefinition] = []

var _lookup: Dictionary = {}
var _lookup_built: bool = false


## Returns the definition for [param item_id], or null when it is unknown.
func get_definition(item_id: StringName) -> ItemDefinition:
	_ensure_lookup()

	if not _lookup.has(item_id):
		return null

	return _lookup[item_id]


func has_definition(item_id: StringName) -> bool:
	_ensure_lookup()

	return _lookup.has(item_id)


func get_item_ids() -> Array[StringName]:
	_ensure_lookup()

	var ids: Array[StringName] = []

	for key: Variant in _lookup:
		ids.append(key)

	return ids


## Returns every definition carrying [param tag].
##
## Useful for future shops, recipe filters and stock lists.
func get_definitions_with_tag(tag: StringName) -> Array[ItemDefinition]:
	_ensure_lookup()

	var matches: Array[ItemDefinition] = []

	for definition: ItemDefinition in definitions:
		if definition != null and definition.has_tag(tag):
			matches.append(definition)

	return matches


## Adds a definition at runtime. Intended for tests and generated content.
func register(definition: ItemDefinition) -> bool:
	if definition == null or not definition.validate_or_warn():
		return false

	_ensure_lookup()

	if _lookup.has(definition.item_id):
		if _lookup[definition.item_id] == definition:
			return true

		push_error(
			"ItemRegistry already contains a different item with the id '"
			+ String(definition.item_id)
			+ "'. Item ids must be unique."
		)
		return false

	if not definitions.has(definition):
		definitions.append(definition)

	_lookup[definition.item_id] = definition

	return true


## Forces the lookup to rebuild after [member definitions] is edited in code.
func rebuild() -> void:
	_lookup_built = false
	_ensure_lookup()


## Checks every entry once and reports problems. Returns true when all are fine.
func validate_or_warn() -> bool:
	rebuild()

	var is_valid: bool = true
	var seen_ids: Dictionary = {}

	for definition: ItemDefinition in definitions:
		if definition == null:
			push_error(
				"ItemRegistry "
				+ resource_path
				+ " contains an empty entry."
			)
			is_valid = false
			continue

		if not definition.validate_or_warn():
			is_valid = false
			continue

		if seen_ids.has(definition.item_id):
			push_error(
				"ItemRegistry "
				+ resource_path
				+ " contains duplicate item id '"
				+ String(definition.item_id)
				+ "'."
			)
			is_valid = false
			continue

		seen_ids[definition.item_id] = true

	return is_valid


func _ensure_lookup() -> void:
	if _lookup_built:
		return

	_lookup.clear()

	for definition: ItemDefinition in definitions:
		if definition == null:
			continue

		if definition.item_id.is_empty():
			push_error(
				"ItemRegistry "
				+ resource_path
				+ " contains an item with no item_id: "
				+ definition.display_name
			)
			continue

		if _lookup.has(definition.item_id):
			push_error(
				"ItemRegistry "
				+ resource_path
				+ " contains duplicate item id '"
				+ String(definition.item_id)
				+ "'. Only the first entry will be used."
			)
			continue

		_lookup[definition.item_id] = definition

	_lookup_built = true
