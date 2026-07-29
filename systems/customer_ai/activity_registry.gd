class_name ActivityRegistry
extends Resource

## Every [ActivityDefinition] a [CustomerBrain] may choose between.
##
## The activity system's equivalent of [ItemRegistry] - same shape,
## deliberately, so anyone already familiar with how items are registered
## recognises this immediately. A plain [Resource] rather than an autoload,
## so a test, a special event, or a future VIP-only registry can build its
## own without touching global state.


@export var definitions: Array[ActivityDefinition] = []

var _lookup: Dictionary = {}
var _lookup_built: bool = false


func get_definition(activity_id: StringName) -> ActivityDefinition:
	_ensure_lookup()

	if not _lookup.has(activity_id):
		return null

	return _lookup[activity_id]


func has_definition(activity_id: StringName) -> bool:
	_ensure_lookup()

	return _lookup.has(activity_id)


## Every registered activity whose conditions are currently satisfied.
## Kept as a general-purpose query (tests, tooling, a future direct check)
## - [method CustomerBrain.think] no longer calls this itself, since it
## needs to know *why* a rejected candidate was rejected for diagnostics,
## which means walking [member definitions] directly rather than through a
## pre-filtered list. See [code]docs/CUSTOMER_AI_SYSTEM.md[/code].
func get_available(context: ActivityContext) -> Array[ActivityDefinition]:
	var available: Array[ActivityDefinition] = []

	for definition: ActivityDefinition in definitions:
		if definition == null:
			continue

		if definition.is_available(context):
			available.append(definition)

	return available


## Forces the lookup to rebuild after [member definitions] is edited in code.
func rebuild() -> void:
	_lookup_built = false
	_ensure_lookup()


## Checks every entry once and reports problems. Returns true when all are
## fine. Mirrors [method ItemRegistry.validate_or_warn] exactly.
func validate_or_warn() -> bool:
	rebuild()

	var is_valid: bool = true
	var seen_ids: Dictionary = {}

	for definition: ActivityDefinition in definitions:
		if definition == null:
			push_error(
				"ActivityRegistry "
				+ resource_path
				+ " contains an empty entry."
			)

			is_valid = false
			continue

		if not definition.validate_or_warn():
			is_valid = false
			continue

		if seen_ids.has(definition.activity_id):
			push_error(
				"ActivityRegistry "
				+ resource_path
				+ " contains duplicate activity id '"
				+ String(definition.activity_id)
				+ "'."
			)

			is_valid = false
			continue

		seen_ids[definition.activity_id] = true

	return is_valid


func _ensure_lookup() -> void:
	if _lookup_built:
		return

	_lookup.clear()

	for definition: ActivityDefinition in definitions:
		if definition == null:
			continue

		if definition.activity_id.is_empty():
			continue

		if _lookup.has(definition.activity_id):
			push_error(
				"ActivityRegistry "
				+ resource_path
				+ " contains duplicate activity id '"
				+ String(definition.activity_id)
				+ "'. Only the first entry will be used."
			)

			continue

		_lookup[definition.activity_id] = definition

	_lookup_built = true
