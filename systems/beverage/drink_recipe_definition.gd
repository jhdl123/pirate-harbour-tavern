class_name DrinkRecipeDefinition
extends Resource

## How a mixed, heated, brewed or otherwise prepared drink is made.
##
## A recipe turns real stock into real output. It never invents anything: every
## line in [member ingredients] is reserved before preparation starts and
## consumed exactly once when it finishes, so a failed preparation returns the
## stock rather than losing it. See [BeveragePreparationService].
##
## Recipes are why "add a mixed drink" is a resource edit. Bumbo is not a
## script; it is four ingredient lines, a preparation time and a required
## capability list.


@export_category("Identity")

@export var recipe_id: StringName = &""

@export var display_name: String = "Unnamed Recipe"

@export_multiline var description: String = ""


@export_category("Ingredients")

## Everything consumed to produce one batch.
@export var ingredients: Array[RecipeIngredient] = []


@export_category("Output")

## Drink id this produces.
@export var output_drink_id: StringName = &""

## Content id this produces, when the result is stored as liquid.
##
## A punch bowl holds prepared punch as content so a group can drink it down.
## A single mixed-to-order Bumbo does not need this and may leave it empty.
@export var output_content_id: StringName = &""

## Serving format the output is produced in.
@export var output_serving_format_id: StringName = &""

## Measures produced per batch.
##
## Ignored for single-serving recipes, which produce exactly one serving.
@export_range(1, 10000, 1)
var output_measures: int = 1


@export_category("Preparation")

## World minutes one batch takes to prepare, before format modifiers.
@export_range(0, 1000, 1)
var preparation_minutes: int = 2

## Whether this makes a batch for a group rather than one drink to order.
@export var is_batch_preparation: bool = false

## Batches producible in one preparation action.
@export_range(1, 100, 1)
var batch_size: int = 1

## Station capabilities required to make this.
##
## Combined with each ingredient's own access capability - a station must
## satisfy both to be a candidate.
@export var required_station_capabilities: Array[StringName] = []

## Container id the output must be made into.
##
## A punch bowl recipe names the punch bowl here, so preparation cannot start
## without one free.
@export var required_vessel_container_id: StringName = &""


@export_category("Result")

## Whether the prepared result can be kept rather than served immediately.
@export var result_may_be_stored: bool = false

## Whether the prepared result goes off.
@export var result_can_spoil: bool = true

## Spoilage profile applied to the prepared result.
@export var result_spoilage_profile: SpoilageProfileDefinition


## Every capability a station needs: the recipe's own plus each ingredient's.
func get_all_required_capabilities() -> Array[StringName]:
	var required: Array[StringName] = required_station_capabilities.duplicate()

	for ingredient: RecipeIngredient in ingredients:
		if ingredient == null:
			continue

		var access: StringName = ingredient.required_access_capability

		if access.is_empty() or required.has(access):
			continue

		required.append(access)

	return required


## Ingredients that must be present. Optional lines are excluded.
func get_required_ingredients() -> Array[RecipeIngredient]:
	var required: Array[RecipeIngredient] = []

	for ingredient: RecipeIngredient in ingredients:
		if ingredient != null and not ingredient.optional:
			required.append(ingredient)

	return required


func get_optional_ingredients() -> Array[RecipeIngredient]:
	var optional: Array[RecipeIngredient] = []

	for ingredient: RecipeIngredient in ingredients:
		if ingredient != null and ingredient.optional:
			optional.append(ingredient)

	return optional


## Preparation time in world minutes, after a format's service modifier.
func get_preparation_minutes(
	format: ServingFormatDefinition = null
) -> int:
	if format == null:
		return preparation_minutes

	return maxi(
		0,
		int(round(float(preparation_minutes) * format.service_time_modifier))
	)


func produces_content() -> bool:
	return not output_content_id.is_empty()


func is_valid() -> bool:
	if recipe_id.is_empty() or output_drink_id.is_empty():
		return false

	if ingredients.is_empty():
		return false

	for ingredient: RecipeIngredient in ingredients:
		if ingredient == null or not ingredient.is_valid():
			return false

	return preparation_minutes >= 0 and batch_size > 0


func validate_or_warn() -> bool:
	if recipe_id.is_empty():
		push_error(
			"DrinkRecipeDefinition at "
			+ resource_path
			+ " has no recipe_id."
		)
		return false

	if output_drink_id.is_empty():
		push_error(
			"DrinkRecipeDefinition '"
			+ String(recipe_id)
			+ "' produces no output_drink_id."
		)
		return false

	if ingredients.is_empty():
		push_error(
			"DrinkRecipeDefinition '"
			+ String(recipe_id)
			+ "' has no ingredients. It would create stock from nothing."
		)
		return false

	var index: int = 0

	for ingredient: RecipeIngredient in ingredients:
		if ingredient == null:
			push_error(
				"DrinkRecipeDefinition '"
				+ String(recipe_id)
				+ "' has an empty ingredient at index "
				+ str(index)
				+ "."
			)
			return false

		if not ingredient.is_valid():
			push_error(
				"DrinkRecipeDefinition '"
				+ String(recipe_id)
				+ "' has an invalid ingredient at index "
				+ str(index)
				+ ": no source id, or a quantity of "
				+ str(ingredient.quantity)
				+ "."
			)
			return false

		index += 1

	if is_batch_preparation and output_content_id.is_empty():
		push_warning(
			"DrinkRecipeDefinition '"
			+ String(recipe_id)
			+ "' is a batch preparation but produces no output_content_id, "
			+ "so the batch cannot be drunk down by a group."
		)

	if result_can_spoil and result_spoilage_profile == null:
		push_warning(
			"DrinkRecipeDefinition '"
			+ String(recipe_id)
			+ "' marks its result as spoilable but names no profile. The "
			+ "result will never actually spoil."
		)

	return true
