class_name ItemDefinition
extends Resource

## Static, shared data describing one kind of item.
##
## An [ItemDefinition] never stores "how many" or "where" - that is the job of
## [ItemStack], [ItemSlot] and [ItemContainer]. One definition resource is
## shared by every stack of that item in the game.
##
## Specialised definitions extend this resource when an item needs extra
## domain data. [DrinkDefinition] is the current example.


## Where an item prefers to go when it is picked up.
##
## This is a hint used by future pickup and quick-move code. Slot and container
## rules always remain authoritative - a preference never overrides a rule.
enum HandlingDestination {
	## Let the receiving system decide. Normally: inventory first, then hands.
	AUTOMATIC,

	## Should be held in the hands, for example a prepared customer drink.
	CARRIER,

	## Should go into a personal inventory, for example a small tool.
	INVENTORY,

	## Should only ever live in world storage, for example a full barrel.
	STORAGE,
}


@export_category("Identity")

## Stable internal identifier used by save data and systems.
##
## Examples:
## grog
## ale
## cleaning_rag
## dirty_tankard
##
## Once an item is used in save data, this must not be renamed.
@export var item_id: StringName = &""

## Name displayed to the player.
@export var display_name: String = "Unnamed Item"

## Optional description used in menus and tooltips.
@export_multiline var description: String = ""


@export_category("Classification")

## Data-driven categories used by slot and container rules.
##
## See [ItemTags] for the names currently used by the project. Any additional
## tag can be typed in here without changing a script.
@export var tags: Array[StringName] = []


@export_category("Visuals")

## Texture used by inventories, menus and tooltips.
@export var inventory_icon: Texture2D

## Texture used when the item is visible in the world.
##
## Used today by the chair's drink sprite, and later by bar service slots,
## trays and world pickups.
@export var world_texture: Texture2D

## Texture used while an actor carries the item in its hands.
@export var carried_texture: Texture2D


@export_category("Inventory")

## Maximum number of this item allowed in one stack.
##
## Examples:
## Prepared drinks, tools and barrels: 1
## Tableware, ingredients and trade goods: 8+
@export_range(1, 9999, 1)
var maximum_stack_size: int = 1

## Where this item prefers to go when it is picked up.
@export var preferred_destination: HandlingDestination = (
	HandlingDestination.AUTOMATIC
)


@export_category("Economy")

## Baseline amount normally paid to acquire one item.
##
## The economy system may later apply supply, reputation and event modifiers.
@export_range(0, 999999, 1)
var base_buy_price: int = 0

## Baseline amount normally received for selling one item.
##
## This is data, not necessarily the final transaction price.
@export_range(0, 999999, 1)
var base_sell_price: int = 0


@export_category("Restock")

## Beverage content a full unit of this stock item delivers.
##
## The link that makes restocking data-driven. A station knows what content it
## serves; this says which stock item provides that content, so nothing has to
## map "port wine station" to "port wine crate" in code. Empty means this item
## is not drink stock.
##
## Without it the only association was the station's own [code]refill_item[/code]
## override - and an instance that forgot to override inherited the base
## scene's grog barrel while looking perfectly valid.
@export var provides_content_id: StringName = &""

## Container a full unit of this stock item represents - see
## [ContainerDefinition] ids.
##
## A cask stack unit is a [code]firkin[/code]; a crate of bottles is a
## [code]crate[/code]. Used to work out how much one collected unit refills.
@export var provides_container_id: StringName = &""

## How many servings this restocks a station by, when it cannot be derived.
##
## Zero means "work it out from the container capacity and the station's
## serving size", which is the preferred path. A non-zero value is an
## explicit override for stock that does not map cleanly onto a container.
@export_range(0, 999, 1)
var provides_servings: int = 0


@export_category("Metadata")

## Starting per-stack metadata copied into every new [ItemStack].
##
## Extension point for future quality, spoilage, ownership or contraband data.
## Leave empty unless an item genuinely needs per-stack state, because stacks
## with different metadata will not merge.
@export var default_metadata: Dictionary = {}


func is_valid() -> bool:
	return (
		not item_id.is_empty()
		and not display_name.strip_edges().is_empty()
		and maximum_stack_size > 0
		and base_buy_price >= 0
		and base_sell_price >= 0
	)


## Reports configuration problems once, with enough detail to fix them.
##
## Returns true when the definition is usable.
func validate_or_warn() -> bool:
	if item_id.is_empty():
		push_error(
			"ItemDefinition '"
			+ display_name
			+ "' ("
			+ resource_path
			+ ") has no item_id. "
			+ "A stable item_id is required for save data."
		)
		return false

	if display_name.strip_edges().is_empty():
		push_error(
			"ItemDefinition '"
			+ String(item_id)
			+ "' has no display name."
		)
		return false

	if maximum_stack_size <= 0:
		push_error(
			"ItemDefinition '"
			+ String(item_id)
			+ "' has an invalid maximum_stack_size of "
			+ str(maximum_stack_size)
			+ "."
		)
		return false

	if base_buy_price < 0 or base_sell_price < 0:
		push_error(
			"ItemDefinition '"
			+ String(item_id)
			+ "' has a negative price."
		)
		return false

	return true


func can_stack() -> bool:
	return maximum_stack_size > 1


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func has_any_tag(any_tags: Array[StringName]) -> bool:
	return ItemTags.has_any(tags, any_tags)


func has_all_tags(required_tags: Array[StringName]) -> bool:
	return ItemTags.has_all(tags, required_tags)


func has_no_tags(blocked_tags: Array[StringName]) -> bool:
	return ItemTags.has_none(tags, blocked_tags)


## Returns an independent copy of the default metadata.
##
## Copying prevents every stack of an item from sharing one dictionary.
func get_default_metadata() -> Dictionary:
	return default_metadata.duplicate(true)


func get_base_buy_value(quantity: int = 1) -> int:
	return base_buy_price * maxi(quantity, 0)


func get_base_sell_value(quantity: int = 1) -> int:
	return base_sell_price * maxi(quantity, 0)
