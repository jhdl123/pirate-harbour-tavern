class_name OrderCatalogueEntry
extends Resource

## One product offered by a supplier.
##
## Extended for the Beverage Framework rather than replaced, because the
## existing ordering system already did the job for plain items and every
## supplier resource in the project points at this class.
##
## An entry is one of two shapes:
##
## [codeblock]
## ITEM     an ItemDefinition, delivered into an ItemContainer
##          "Sugar Loaf", "Nutmeg", "Coffee Beans", "Punch Bowls"
##
## FILLED   a container plus its contents, delivered into a BeverageStorage
##          "Hogshead of Kill-Devil", "Pipe of Madeira", "Crate of Brandy"
## [/codeblock]
##
## The second shape is why bulk stock never needed a HogsheadOfRum item: the
## order names a container id and a content id, and delivery builds a real
## [FilledContainer] out of them.


enum Shape {
	## A normal inventory item.
	ITEM,

	## A container arriving with something in it.
	FILLED_CONTAINER,
}


@export_category("Product")

@export var shape: Shape = Shape.ITEM

## Item offered when [member shape] is [constant Shape.ITEM].
@export var item: ItemDefinition


@export_category("Filled Container")

## Container ordered when [member shape] is
## [constant Shape.FILLED_CONTAINER].
@export var container_id: StringName = &""

## What it arrives full of.
@export var content_id: StringName = &""

## Measures in each container. Zero means "arrives full".
@export_range(0, 100000, 1)
var fill_quantity: int = 0

## Whether it arrives sealed.
##
## Sealed stock does not begin ageing until tapped, which is what lets a
## hogshead of rum sit in the cellar indefinitely.
@export var arrives_sealed: bool = true


@export_category("Pricing")

## Use -1 to read ItemDefinition.base_buy_price.
@export_range(-1, 999999, 1)
var unit_price_override: int = -1

## Fraction the price may swing either way, for future market variation.
##
## Read by nothing yet. Present so a price that moves does not need this
## resource re-authored.
@export_range(0.0, 1.0, 0.01)
var price_variance: float = 0.0


@export_category("Availability")

## Maximum allowed on one order. Zero means no supplier-specific limit.
@export_range(0, 9999, 1)
var maximum_order_quantity: int = 20

## How often this is in stock at all, 0..1. One means always.
@export_range(0.0, 1.0, 0.01)
var availability: float = 1.0

## How scarce this is, for future market and event systems.
@export var rarity: DrinkDefinition.Availability = (
	DrinkDefinition.Availability.COMMON
)

## Trade route or region tags, e.g. &"caribbean", &"iberian".
@export var region_tags: Array[StringName] = []

## Tavern reputation needed before this appears. Zero means always offered.
@export_range(0, 1000, 1)
var reputation_requirement: int = 0


@export_category("Delivery")

## Delivery time in world minutes. Zero uses the supplier default.
@export_range(0, 10080, 1)
var delivery_minutes: int = 0

## Storage tags the delivery must be routed to.
##
## Empty means "wherever it fits". Bulk casks name cellar storage; premium
## bottles name locked storage.
@export var destination_storage_tags: Array[StringName] = []


# --- Pricing -----------------------------------------------------------------

func get_unit_price() -> int:
	if unit_price_override >= 0:
		return unit_price_override

	if item != null:
		return item.base_buy_price

	return 0


func get_maximum_quantity() -> int:
	if maximum_order_quantity <= 0:
		return 9999

	return maximum_order_quantity


# --- Shape -------------------------------------------------------------------

func is_filled_container() -> bool:
	return shape == Shape.FILLED_CONTAINER


func is_item() -> bool:
	return shape == Shape.ITEM


## Measures each delivered container holds.
##
## Zero on the resource means "full", resolved against the container so an
## author never has to repeat a capacity that is already defined elsewhere.
func get_fill_quantity(registry: BeverageRegistry) -> int:
	if not is_filled_container():
		return 0

	if fill_quantity > 0:
		return fill_quantity

	if registry == null:
		return 0

	var container: ContainerDefinition = registry.get_container(container_id)

	return container.maximum_capacity if container != null else 0


## Builds one delivered container. Returns null when it cannot be resolved.
func create_filled_container(
	registry: BeverageRegistry,
	world_minutes: int = -1
) -> FilledContainer:
	if not is_filled_container() or registry == null:
		return null

	var container: ContainerDefinition = registry.get_container(container_id)
	var content: BeverageContentDefinition = registry.get_content(content_id)

	if container == null or content == null:
		push_warning(
			"OrderCatalogueEntry at "
			+ resource_path
			+ " refers to unknown container '"
			+ String(container_id)
			+ "' or content '"
			+ String(content_id)
			+ "'. Nothing was delivered."
		)
		return null

	var batch: FilledContainer = FilledContainer.create(
		container, content, get_fill_quantity(registry), world_minutes
	)
	batch.sealed = arrives_sealed

	return batch


# --- Display -----------------------------------------------------------------

## What the order UI shows, e.g. "Hogshead (very large cask) of Kill-Devil".
func get_display_name(registry: BeverageRegistry = null) -> String:
	if is_item():
		return item.display_name if item != null else "Unknown Item"

	if registry == null:
		return "%s of %s" % [String(container_id), String(content_id)]

	var container: ContainerDefinition = registry.get_container(container_id)
	var content: BeverageContentDefinition = registry.get_content(content_id)

	var container_text: String = (
		container.get_display_name_with_explanation()
		if container != null
		else String(container_id)
	)
	var content_text: String = (
		content.display_name if content != null else String(content_id)
	)

	return "%s of %s" % [container_text, content_text]


## Short line describing what one unit contains, for a tooltip.
func get_detail_text(registry: BeverageRegistry = null) -> String:
	if is_item():
		if item == null:
			return ""

		var ingredient: IngredientDefinition = item as IngredientDefinition

		if ingredient != null:
			return "1 %s per unit" % ingredient.unit_name

		return "stacks to %d" % item.maximum_stack_size

	if registry == null:
		return ""

	var container: ContainerDefinition = registry.get_container(container_id)

	if container == null:
		return ""

	return "%d %s per container" % [
		get_fill_quantity(registry), container.unit_name,
	]


# --- Validation --------------------------------------------------------------

func is_valid() -> bool:
	if get_unit_price() < 0:
		return false

	if is_filled_container():
		return not container_id.is_empty() and not content_id.is_empty()

	return item != null


func validate_or_warn() -> bool:
	if is_filled_container():
		if container_id.is_empty() or content_id.is_empty():
			push_error(
				"OrderCatalogueEntry at "
				+ resource_path
				+ " is a filled container but names no container or content."
			)
			return false

		if unit_price_override < 0:
			push_warning(
				"OrderCatalogueEntry at "
				+ resource_path
				+ " is a filled container with no unit_price_override. There "
				+ "is no item to read a price from, so it will cost nothing."
			)

		return true

	if item == null:
		push_error(
			"OrderCatalogueEntry at "
			+ resource_path
			+ " has no item."
		)
		return false

	return true


## Stable key for this offer, used by the order UI and order lines.
##
## Item entries key on the item id, which is what the ordering system already
## did. Filled containers have no item, so they key on container plus content -
## which also means the same cask in two sizes stays two distinct offers.
func get_offer_id() -> StringName:
	if is_item():
		return item.item_id if item != null else &""

	return StringName("%s__%s" % [String(container_id), String(content_id)])
