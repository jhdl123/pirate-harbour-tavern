class_name BeverageRegistry
extends Resource

## Maps every stable beverage id back to its definition.
##
## The same idea as [ItemRegistry], and deliberately the same shape: save data
## and gameplay code refer to ids, so exactly one place has to answer "what is
## 'kill_devil'?". Keeping it a plain [Resource] rather than an autoload means a
## test, a future content pack or a modded supplier can use its own registry
## without touching global state.
##
## Drinks and ingredients are NOT stored here. They are [ItemDefinition]s and
## live in [ItemRegistry], because a drink is an item. This registry holds the
## beverage-only concepts that have no item identity: contents, containers,
## serving formats, recipes, storage profiles and spoilage profiles.


@export_category("Definitions")

@export var contents: Array[BeverageContentDefinition] = []
@export var containers: Array[ContainerDefinition] = []
@export var serving_formats: Array[ServingFormatDefinition] = []
@export var recipes: Array[DrinkRecipeDefinition] = []
@export var storage_profiles: Array[StorageProfileDefinition] = []
@export var spoilage_profiles: Array[SpoilageProfileDefinition] = []


@export_category("Items")

## The item registry drinks and ingredients live in.
##
## Optional. When set, the registry can resolve a drink id straight from a
## content id, which the service and UI layers both want.
@export var item_registry: ItemRegistry


var _content_lookup: Dictionary = {}
var _container_lookup: Dictionary = {}
var _format_lookup: Dictionary = {}
var _recipe_lookup: Dictionary = {}
var _storage_lookup: Dictionary = {}
var _spoilage_lookup: Dictionary = {}
var _recipe_by_output: Dictionary = {}
var _lookups_built: bool = false


# --- Lookups -----------------------------------------------------------------

func get_content(content_id: StringName) -> BeverageContentDefinition:
	_ensure_lookups()

	return _content_lookup.get(content_id, null)


func get_container(container_id: StringName) -> ContainerDefinition:
	_ensure_lookups()

	return _container_lookup.get(container_id, null)


func get_serving_format(format_id: StringName) -> ServingFormatDefinition:
	_ensure_lookups()

	return _format_lookup.get(format_id, null)


func get_recipe(recipe_id: StringName) -> DrinkRecipeDefinition:
	_ensure_lookups()

	return _recipe_lookup.get(recipe_id, null)


func get_storage_profile(profile_id: StringName) -> StorageProfileDefinition:
	_ensure_lookups()

	return _storage_lookup.get(profile_id, null)


func get_spoilage_profile(profile_id: StringName) -> SpoilageProfileDefinition:
	_ensure_lookups()

	return _spoilage_lookup.get(profile_id, null)


## The recipe producing [param drink_id], or null when it is not prepared.
func get_recipe_for_drink(drink_id: StringName) -> DrinkRecipeDefinition:
	_ensure_lookups()

	return _recipe_by_output.get(drink_id, null)


func get_drink(drink_id: StringName) -> DrinkDefinition:
	if item_registry == null:
		return null

	return item_registry.get_definition(drink_id) as DrinkDefinition


func get_ingredient(item_id: StringName) -> IngredientDefinition:
	if item_registry == null:
		return null

	return item_registry.get_definition(item_id) as IngredientDefinition


# --- Collections -------------------------------------------------------------

## Every drink in the item registry, in registry order.
func get_all_drinks() -> Array[DrinkDefinition]:
	var drinks: Array[DrinkDefinition] = []

	if item_registry == null:
		return drinks

	for definition: ItemDefinition in item_registry.definitions:
		var drink: DrinkDefinition = definition as DrinkDefinition

		if drink != null:
			drinks.append(drink)

	return drinks


func get_all_ingredients() -> Array[IngredientDefinition]:
	var found: Array[IngredientDefinition] = []

	if item_registry == null:
		return found

	for definition: ItemDefinition in item_registry.definitions:
		var ingredient: IngredientDefinition = definition as IngredientDefinition

		if ingredient != null:
			found.append(ingredient)

	return found


## Serving formats [param drink] may actually be ordered in.
##
## Intersects both directions: the drink must list the format, and the format
## must accept the drink.
func get_serving_formats_for_drink(
	drink: DrinkDefinition
) -> Array[ServingFormatDefinition]:
	_ensure_lookups()

	var formats: Array[ServingFormatDefinition] = []

	if drink == null:
		return formats

	if drink.serving_format_ids.is_empty():
		return formats

	for format_id: StringName in drink.serving_format_ids:
		var format: ServingFormatDefinition = get_serving_format(format_id)

		if format == null:
			continue

		if format.accepts_drink(drink):
			formats.append(format)

	return formats


## Containers whose definition accepts [param content].
func get_containers_for_content(
	content: BeverageContentDefinition
) -> Array[ContainerDefinition]:
	_ensure_lookups()

	var found: Array[ContainerDefinition] = []

	if content == null:
		return found

	for container: ContainerDefinition in containers:
		if container != null and container.accepts_content(content):
			found.append(container)

	return found


## Drinks that are poured from [param content_id].
func get_drinks_for_content(
	content_id: StringName
) -> Array[DrinkDefinition]:
	var found: Array[DrinkDefinition] = []

	for drink: DrinkDefinition in get_all_drinks():
		if drink.content_id == content_id:
			found.append(drink)

	return found


func get_content_ids() -> Array[StringName]:
	_ensure_lookups()

	var ids: Array[StringName] = []

	for key: Variant in _content_lookup:
		ids.append(key)

	return ids


# --- Runtime registration ----------------------------------------------------

## Adds a definition at runtime. Intended for tests and generated content.
##
## Returns false when the id is already taken by a different resource, which is
## the case worth catching: silently replacing a definition would make two
## saves of the same game disagree.
func register_content(definition: BeverageContentDefinition) -> bool:
	if definition == null or not definition.validate_or_warn():
		return false

	_ensure_lookups()

	if _content_lookup.has(definition.content_id):
		return _content_lookup[definition.content_id] == definition

	if not contents.has(definition):
		contents.append(definition)

	_content_lookup[definition.content_id] = definition

	return true


func register_container(definition: ContainerDefinition) -> bool:
	if definition == null or not definition.validate_or_warn():
		return false

	_ensure_lookups()

	if _container_lookup.has(definition.container_id):
		return _container_lookup[definition.container_id] == definition

	if not containers.has(definition):
		containers.append(definition)

	_container_lookup[definition.container_id] = definition

	return true


func register_serving_format(definition: ServingFormatDefinition) -> bool:
	if definition == null or not definition.validate_or_warn():
		return false

	_ensure_lookups()

	if _format_lookup.has(definition.format_id):
		return _format_lookup[definition.format_id] == definition

	if not serving_formats.has(definition):
		serving_formats.append(definition)

	_format_lookup[definition.format_id] = definition

	return true


func register_recipe(definition: DrinkRecipeDefinition) -> bool:
	if definition == null or not definition.validate_or_warn():
		return false

	_ensure_lookups()

	if _recipe_lookup.has(definition.recipe_id):
		return _recipe_lookup[definition.recipe_id] == definition

	if not recipes.has(definition):
		recipes.append(definition)

	_recipe_lookup[definition.recipe_id] = definition
	_recipe_by_output[definition.output_drink_id] = definition

	return true


func register_storage_profile(definition: StorageProfileDefinition) -> bool:
	if definition == null or not definition.validate_or_warn():
		return false

	_ensure_lookups()

	if _storage_lookup.has(definition.profile_id):
		return _storage_lookup[definition.profile_id] == definition

	if not storage_profiles.has(definition):
		storage_profiles.append(definition)

	_storage_lookup[definition.profile_id] = definition

	return true


func register_spoilage_profile(definition: SpoilageProfileDefinition) -> bool:
	if definition == null or not definition.validate_or_warn():
		return false

	_ensure_lookups()

	if _spoilage_lookup.has(definition.profile_id):
		return _spoilage_lookup[definition.profile_id] == definition

	if not spoilage_profiles.has(definition):
		spoilage_profiles.append(definition)

	_spoilage_lookup[definition.profile_id] = definition

	return true


## Forces every lookup to rebuild after the arrays are edited in code.
func rebuild() -> void:
	_lookups_built = false
	_ensure_lookups()


# --- Internals ---------------------------------------------------------------

func _ensure_lookups() -> void:
	if _lookups_built:
		return

	_content_lookup.clear()
	_container_lookup.clear()
	_format_lookup.clear()
	_recipe_lookup.clear()
	_storage_lookup.clear()
	_spoilage_lookup.clear()
	_recipe_by_output.clear()

	for content: BeverageContentDefinition in contents:
		_add_to_lookup(_content_lookup, content, content.content_id if content != null else &"", "content")

	for container: ContainerDefinition in containers:
		_add_to_lookup(_container_lookup, container, container.container_id if container != null else &"", "container")

	for format: ServingFormatDefinition in serving_formats:
		_add_to_lookup(_format_lookup, format, format.format_id if format != null else &"", "serving format")

	for recipe: DrinkRecipeDefinition in recipes:
		if _add_to_lookup(_recipe_lookup, recipe, recipe.recipe_id if recipe != null else &"", "recipe"):
			if not recipe.output_drink_id.is_empty():
				_recipe_by_output[recipe.output_drink_id] = recipe

	for profile: StorageProfileDefinition in storage_profiles:
		_add_to_lookup(_storage_lookup, profile, profile.profile_id if profile != null else &"", "storage profile")

	for profile: SpoilageProfileDefinition in spoilage_profiles:
		_add_to_lookup(_spoilage_lookup, profile, profile.profile_id if profile != null else &"", "spoilage profile")

	_lookups_built = true


func _add_to_lookup(
	lookup: Dictionary,
	definition: Resource,
	id: StringName,
	kind: String
) -> bool:
	if definition == null:
		push_error(
			"BeverageRegistry "
			+ resource_path
			+ " contains an empty "
			+ kind
			+ " entry."
		)
		return false

	if id.is_empty():
		push_error(
			"BeverageRegistry "
			+ resource_path
			+ " contains a "
			+ kind
			+ " with no id: "
			+ definition.resource_path
		)
		return false

	if lookup.has(id):
		push_error(
			"BeverageRegistry "
			+ resource_path
			+ " contains duplicate "
			+ kind
			+ " id '"
			+ String(id)
			+ "'. Only the first entry will be used."
		)
		return false

	lookup[id] = definition

	return true
