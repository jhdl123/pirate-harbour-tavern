class_name StationStockPlan
extends RefCounted

## What a [DrinksStation] serves and what legitimately restocks it.
##
## One resolver, derived from the beverage framework, so nothing else has to
## guess. Before this the association lived only in each station instance's
## [code]refill_item[/code] override - and an instance that forgot to override
## it silently inherited the base scene's grog barrel, producing a Port Wine
## station that asked staff for a Grog Barrel. That looked valid to every
## consumer: the task was well-formed, the stock existed, the transfer
## succeeded. Nothing could catch it because nothing knew what the station
## SHOULD have wanted.
##
## The rule now: content is authoritative, and the restock item is whatever
## registered stock declares [member ItemDefinition.provides_content_id] equal
## to it. Adding a drink means adding a stock resource, not another branch.


## Why a plan could not be built. Mirrors the diagnostic reason codes.
enum Problem {
	NONE,
	NO_STATION,
	NO_DRINK,
	NO_CONTENT,
	NO_STOCK_ITEM,
	STOCK_TYPE_MISMATCH,
}


var station: DrinksStation = null

## Content the station actually pours - the authoritative identity.
var content_id: StringName = &""

## Container the station serves from.
var container_id: StringName = &""

## Stock item that legitimately restocks this station.
var restock_item: ItemDefinition = null

## Servings one collected unit of [member restock_item] delivers.
var servings_per_unit: int = 0

## True when the station pours whole bottles rather than measures.
var is_bottled: bool = false

var problem: Problem = Problem.NONE
var detail: String = ""


static func for_station(
	target: DrinksStation,
	registry: BeverageRegistry,
	item_registry: ItemRegistry
) -> StationStockPlan:
	var plan := StationStockPlan.new()
	plan.station = target

	if target == null:
		plan.problem = Problem.NO_STATION
		return plan

	if target.served_drink == null:
		plan.problem = Problem.NO_DRINK
		plan.detail = "%s has no served_drink." % target.name
		return plan

	plan.content_id = target.get_service_content_id()

	if plan.content_id.is_empty():
		plan.content_id = target.served_drink.content_id

	if plan.content_id.is_empty():
		plan.problem = Problem.NO_CONTENT
		plan.detail = "%s serves %s, which declares no content_id." % [
			target.name, target.served_drink.item_id
		]
		return plan

	if target.service_container != null:
		plan.container_id = target.service_container.container_id

	plan.is_bottled = (
		target.served_drink.get_default_serving_format_id() == &"bottle_serving"
	)

	plan.restock_item = _find_stock_for_content(plan.content_id, item_registry)

	if plan.restock_item == null:
		plan.problem = Problem.NO_STOCK_ITEM
		plan.detail = (
			"No registered stock item declares provides_content_id '%s'."
			% String(plan.content_id)
		)
		return plan

	plan.servings_per_unit = _resolve_servings_per_unit(
		plan.restock_item, target, registry
	)

	return plan


## Whether [param item] is legitimate restock for this station.
##
## The check the refill task was missing. A grog barrel carried to a port wine
## shelf fails here rather than succeeding and corrupting the shelf.
func accepts_stock(item: ItemDefinition) -> bool:
	if item == null:
		return false

	return item.provides_content_id == content_id


func is_valid() -> bool:
	return problem == Problem.NONE


## Reason code for diagnostics and alerts.
func get_reason_code() -> StringName:
	match problem:
		Problem.NO_STATION: return &"NO_SERVICE_STATION"
		Problem.NO_DRINK: return &"STATION_CONFIG_INVALID"
		Problem.NO_CONTENT: return &"STATION_CONFIG_INVALID"
		Problem.NO_STOCK_ITEM: return &"NO_STOCK_SOURCE"
		Problem.STOCK_TYPE_MISMATCH: return &"STOCK_TYPE_MISMATCH"
		_: return &""


func describe() -> String:
	if is_valid():
		return "%s: %s <- %s (%d servings/unit)" % [
			station.name, String(content_id),
			restock_item.display_name, servings_per_unit
		]

	return "%s: %s - %s" % [
		"?" if station == null else station.name,
		String(get_reason_code()), detail
	]


static func _find_stock_for_content(
	content_id: StringName,
	item_registry: ItemRegistry
) -> ItemDefinition:
	if item_registry == null or content_id.is_empty():
		return null

	for item: ItemDefinition in item_registry.definitions:
		if item != null and item.provides_content_id == content_id:
			return item

	return null


static func _resolve_servings_per_unit(
	item: ItemDefinition,
	target: DrinksStation,
	registry: BeverageRegistry
) -> int:
	if item.provides_servings > 0:
		return item.provides_servings

	if registry == null or item.provides_container_id.is_empty():
		return 0

	var container: ContainerDefinition = registry.get_container(
		item.provides_container_id
	)

	if container == null:
		return 0

	var per_serving: int = maxi(target.get_measures_per_serving(), 1)

	return maxi(container.maximum_capacity / per_serving, 1)
