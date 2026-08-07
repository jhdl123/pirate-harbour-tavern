class_name ContainerDefinition
extends Resource

## A physical container type, described independently of what is in it.
##
## A container never permanently defines one drink. "Hogshead" is a shape and a
## capacity; [FilledContainer] is what pairs it with contents. That separation
## is what stops the project needing a HogsheadOfRum class, a HogsheadOfMadeira
## class, and so on for every combination.
##
## Historical names are kept in the player-facing display and followed by a
## plain-English explanation in brackets - see
## [method get_display_name_with_explanation]. Capacities are configurable
## game values chosen for balance. They are historically *inspired*, not exact
## period measures: real cask sizes varied by place, date and contents.


enum Category {
	## Cask family: firkin, kilderkin, barrel, hogshead, puncheon, pipe.
	CASK,

	## Individual sealed bottle.
	BOTTLE,

	## A case holding other containers, normally bottles.
	CRATE,

	## Shared jug poured out at a table.
	PITCHER,

	## Shared open bowl, ladled from.
	BOWL,

	## Small cask placed on a table for a group.
	TABLE_CASK,

	## Single-customer drinking vessel: cup, mug, tankard, glass.
	DRINKING_VESSEL,

	## Sack, box or jar for dry goods.
	DRY_CONTAINER,
}


@export_category("Identity")

@export var container_id: StringName = &""

## Period name shown to the player, e.g. "Firkin".
@export var historical_name: String = "Unnamed Container"

## Plain-English gloss shown in brackets after the historical name,
## e.g. "small cask". Leave empty when the historical name needs no help -
## "Bottle" explains itself.
@export var simplified_explanation: String = ""

@export_multiline var description: String = ""

@export var icon: Texture2D


@export_category("Classification")

@export var category: Category = Category.CASK

## Content tags this container may hold.
##
## Empty means "anything". A cask normally lists
## [constant BeverageTags.LIQUID]; a sack lists
## [constant BeverageTags.DRY_GOOD].
@export var supported_content_tags: Array[StringName] = [BeverageTags.LIQUID]


@export_category("Capacity")

## Measures this container holds when full.
##
## One measure is one dram-sized unit of liquid. Serving formats convert
## measures into servings, so changing a cask size never touches a drink.
@export_range(1, 100000, 1)
var maximum_capacity: int = 100

## Word shown beside quantities, for display only.
@export var unit_name: String = "measures"


@export_category("Handling")

## Whether an actor can pick this up and carry it.
@export var portable: bool = true

## Whether this is supplier-sized bulk stock rather than service stock.
@export var bulk_storage: bool = false

## Whether a customer is served directly from or drinks out of this.
@export var customer_serving: bool = false

## Whether contents may be moved in or out at all.
@export var transferable: bool = true

## Whether stock may be drawn OUT of this container.
@export var can_be_transfer_source: bool = true

## Whether stock may be put INTO this container.
@export var can_be_transfer_destination: bool = true


@export_category("Storage")

## Bulk storage space one of these occupies. Used by cellar capacity later.
@export_range(0.0, 1000.0, 0.1)
var storage_space_usage: float = 1.0

## Item id of the empty version of this container, when one is tracked.
##
## Leave empty when emptying it produces nothing worth keeping.
@export var empty_container_item_id: StringName = &""

## Where a container of this size normally lives - see [BeverageTags].
##
## Descriptive, not enforced: a [StorageProfileDefinition] still decides what a
## location will ACCEPT, because that is a property of the liquid rather than
## the vessel. This is the hint used to route a delivery to the right room
## when the content itself has no opinion, and to explain to the player why a
## puncheon belongs in the cellar and a kilderkin behind the bar.
@export var typical_storage_tags: Array[StringName] = []


@export_category("Visuals")

@export var full_texture: Texture2D
@export var partial_texture: Texture2D
@export var empty_texture: Texture2D


## Player-facing name: historical name, then the gloss in brackets.
##
## "Firkin (small cask)". When no explanation is configured, just "Bottle".
func get_display_name_with_explanation() -> String:
	if simplified_explanation.strip_edges().is_empty():
		return historical_name

	return "%s (%s)" % [historical_name, simplified_explanation]


## True when [param content] may go into this container.
func accepts_content(content: BeverageContentDefinition) -> bool:
	if content == null:
		return false

	if supported_content_tags.is_empty():
		return true

	return ItemTags.has_any(content.tags, supported_content_tags)


func is_bulk() -> bool:
	return bulk_storage


func is_serving_vessel() -> bool:
	return customer_serving


## Texture matching a fill level from 0.0 (empty) to 1.0 (full).
##
## Falls back sensibly so a container with only one texture still works.
func get_texture_for_fill(fill_fraction: float) -> Texture2D:
	if fill_fraction <= 0.0:
		return empty_texture if empty_texture != null else full_texture

	if fill_fraction >= 1.0:
		return full_texture if full_texture != null else partial_texture

	if partial_texture != null:
		return partial_texture

	return full_texture if full_texture != null else empty_texture


func is_valid() -> bool:
	return (
		not container_id.is_empty()
		and not historical_name.strip_edges().is_empty()
		and maximum_capacity > 0
	)


func validate_or_warn() -> bool:
	if container_id.is_empty():
		push_error(
			"ContainerDefinition at "
			+ resource_path
			+ " has no container_id."
		)
		return false

	if maximum_capacity <= 0:
		push_error(
			"ContainerDefinition '"
			+ String(container_id)
			+ "' has an invalid maximum_capacity of "
			+ str(maximum_capacity)
			+ "."
		)
		return false

	if not transferable and (can_be_transfer_source or can_be_transfer_destination):
		push_warning(
			"ContainerDefinition '"
			+ String(container_id)
			+ "' is not transferable but is marked as a transfer source or "
			+ "destination. The transferable flag wins."
		)

	return true
