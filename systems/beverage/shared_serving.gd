class_name SharedServing
extends Node2D

## A drink several customers share, sitting in the world.
##
## A punch bowl on a table is not a carried item and not a station - it is a
## persistent object with portions left in it. Customers seated at its table
## take a portion at a time until it is empty.
##
## Deliberately anchored to a TABLE rather than to a customer group. The
## project has no group system yet, and the brief forbids building one here, so
## "the group" is defined as whoever is seated at this table. When a real group
## system arrives it sets [member group_id] and nothing else changes - the
## object is already designed to be owned by a group rather than by a table.


signal portion_taken(remaining: int, consumer: Node)
signal became_empty
signal spoiled


@export_category("Contents")

## Drink id this serving is of.
@export var drink_id: StringName = &""

## Serving format that created it: punch bowl, pitcher, table cask.
@export var serving_format_id: StringName = &""

## Content id, when the serving holds a real liquid that can spoil.
@export var content_id: StringName = &""


@export_category("Portions")

@export_range(0, 100, 1)
var remaining_portions: int = 0

@export_range(1, 100, 1)
var maximum_portions: int = 1


@export_category("Ownership")

## Set by a future group system. Empty means "whoever is at this table".
@export var group_id: StringName = &""

## Table this serving belongs to. The anchor everything else derives from.
@export var anchor_table: Node2D

## How close a customer must be to the anchor table to count as sharing.
##
## Generous on purpose: a seated customer is at their chair, not at the middle
## of the table.
@export_range(8.0, 512.0, 1.0)
var shared_radius: float = 96.0


@export_category("Spoilage")

## World minute this was prepared. Minus one means never.
@export var prepared_at_minutes: int = -1

@export var can_spoil: bool = false

@export var spoilage_profile: SpoilageProfileDefinition


var _registry: BeverageRegistry = null
var _vessel_pool: VesselPool = null
var _is_spoiled: bool = false
var _vessel_released: bool = false


func _ready() -> void:
	add_to_group(&"shared_servings")


## Configures a newly created serving. Called by [SharedServingService].
func configure(
	registry: BeverageRegistry,
	vessel_pool: VesselPool,
	drink: DrinkDefinition,
	format: ServingFormatDefinition,
	world_minutes: int
) -> void:
	_registry = registry
	_vessel_pool = vessel_pool

	if drink != null:
		drink_id = drink.item_id
		content_id = drink.content_id

	if format != null:
		serving_format_id = format.format_id
		maximum_portions = format.portion_count
		remaining_portions = format.portion_count

	prepared_at_minutes = world_minutes

	var recipe: DrinkRecipeDefinition = (
		registry.get_recipe_for_drink(drink_id) if registry != null else null
	)

	if recipe != null:
		can_spoil = recipe.result_can_spoil
		spoilage_profile = recipe.result_spoilage_profile
	elif drink != null:
		can_spoil = drink.can_spoil_after_serving
		spoilage_profile = drink.spoilage_profile


func is_empty() -> bool:
	return remaining_portions <= 0


func is_spoiled() -> bool:
	return _is_spoiled


## Whether [param consumer] may take a portion right now.
func can_take_portion(consumer: Node) -> bool:
	if is_empty() or _is_spoiled:
		return false

	return is_consumer_eligible(consumer)


## Whether [param consumer] belongs to this serving's group.
##
## With no group system, eligibility is proximity to the anchor table: anyone
## seated there shares the bowl. A real group system overrides this by setting
## [member group_id] and comparing directly.
func is_consumer_eligible(consumer: Node) -> bool:
	if consumer == null:
		return false

	if not group_id.is_empty():
		var consumer_group: Variant = consumer.get(&"group_id")

		return consumer_group != null and StringName(String(consumer_group)) == group_id

	if anchor_table == null:
		return true

	var consumer_2d: Node2D = consumer as Node2D

	if consumer_2d == null:
		return false

	return consumer_2d.global_position.distance_to(
		anchor_table.global_position
	) <= shared_radius


## Takes one portion. Returns false when there was nothing to take.
func take_portion(consumer: Node) -> bool:
	if not can_take_portion(consumer):
		return false

	remaining_portions -= 1

	portion_taken.emit(remaining_portions, consumer)

	if remaining_portions <= 0:
		_on_emptied()

	return true


## Re-evaluates freshness. Called by [SpoilageService] on a schedule.
func check_spoilage(world_minutes: int) -> bool:
	if _is_spoiled or not can_spoil or spoilage_profile == null:
		return false

	if not spoilage_profile.is_enabled() or prepared_at_minutes < 0:
		return false

	var elapsed: int = maxi(world_minutes - prepared_at_minutes, 0)
	var freshness: float = spoilage_profile.calculate_freshness(elapsed)

	if not spoilage_profile.is_spoiled_at_freshness(freshness):
		return false

	_is_spoiled = true

	spoiled.emit()
	_release_vessel()

	return true


func get_freshness(world_minutes: int) -> float:
	if not can_spoil or spoilage_profile == null or prepared_at_minutes < 0:
		return 1.0

	return spoilage_profile.calculate_freshness(
		maxi(world_minutes - prepared_at_minutes, 0)
	)


## World minutes until this spoils, or -1 when it never will.
func get_minutes_until_spoiled(world_minutes: int) -> int:
	if not can_spoil or spoilage_profile == null or prepared_at_minutes < 0:
		return -1

	if not spoilage_profile.is_enabled():
		return -1

	return spoilage_profile.get_minutes_until_spoiled(
		maxi(world_minutes - prepared_at_minutes, 0)
	)


func get_display_name() -> String:
	if _registry == null:
		return String(drink_id)

	var drink: DrinkDefinition = _registry.get_drink(drink_id)
	var format: ServingFormatDefinition = _registry.get_serving_format(
		serving_format_id
	)

	var drink_name: String = (
		drink.display_name if drink != null else String(drink_id)
	)

	if format == null:
		return drink_name

	return format.get_order_display_name(drink_name)


func to_save_dict() -> Dictionary:
	return {
		"drink_id": String(drink_id),
		"serving_format_id": String(serving_format_id),
		"content_id": String(content_id),
		"remaining_portions": remaining_portions,
		"maximum_portions": maximum_portions,
		"group_id": String(group_id),
		"prepared_at_minutes": prepared_at_minutes,
		"can_spoil": can_spoil,
		"is_spoiled": _is_spoiled,
		"position_x": global_position.x,
		"position_y": global_position.y,
	}


func from_save_dict(data: Dictionary) -> void:
	drink_id = StringName(String(data.get("drink_id", "")))
	serving_format_id = StringName(String(data.get("serving_format_id", "")))
	content_id = StringName(String(data.get("content_id", "")))
	remaining_portions = int(data.get("remaining_portions", 0))
	maximum_portions = maxi(int(data.get("maximum_portions", 1)), 1)
	group_id = StringName(String(data.get("group_id", "")))
	prepared_at_minutes = int(data.get("prepared_at_minutes", -1))
	can_spoil = bool(data.get("can_spoil", false))
	_is_spoiled = bool(data.get("is_spoiled", false))
	global_position = Vector2(
		float(data.get("position_x", 0.0)),
		float(data.get("position_y", 0.0))
	)


func _on_emptied() -> void:
	became_empty.emit()
	_release_vessel()


## Returns the vessel exactly once, however the serving ended.
##
## Emptying and spoiling both finish a serving, and a spoiled bowl that is then
## emptied must not return two bowls. The guard is what keeps vessel counts
## conserved.
func _release_vessel() -> void:
	if _vessel_released:
		return

	_vessel_released = true

	if _vessel_pool == null or _registry == null:
		return

	var format: ServingFormatDefinition = _registry.get_serving_format(
		serving_format_id
	)

	if format != null:
		_vessel_pool.release_for_format(format)


## Empties this serving immediately, releasing its vessel.
##
## Used by the diagnostics panel. Goes through the same _on_emptied() path as
## normal consumption, so the vessel accounting cannot diverge between the
## debug route and the real one.
func empty_now() -> void:
	if is_empty():
		return

	remaining_portions = 0

	_on_emptied()
