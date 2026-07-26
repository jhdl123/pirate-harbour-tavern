class_name ItemTags
extends RefCounted

## Named tag constants used by items, slots and containers.
##
## Tags are plain [StringName] values stored as data on [ItemDefinition] and
## on slot/container rules. This class only provides convenient, spell-checked
## names for the tags the project uses today.
##
## The item system is NOT limited to the tags listed here. Any tag typed into
## an [ItemDefinition] resource works immediately, so new item groups never
## require a script change.


# --- Broad handling groups ---------------------------------------------------

## Something small enough to eventually go into a personal inventory.
const SMALL_ITEM: StringName = &"small_item"

## Something that must stay in the hands and never enter a backpack.
const BULKY_ITEM: StringName = &"bulky_item"

## Something that belongs to customer service rather than storage.
const SERVICE_ITEM: StringName = &"service_item"


# --- Drinks ------------------------------------------------------------------

## A finished drink ready to be handed to a customer.
const PREPARED_DRINK: StringName = &"prepared_drink"

## Unprepared drink supply such as a keg, barrel or bottle crate.
const DRINK_STOCK: StringName = &"drink_stock"


# --- Tableware and waste -----------------------------------------------------

const TABLEWARE: StringName = &"tableware"
const CLEAN_TABLEWARE: StringName = &"clean_tableware"
const DIRTY_TABLEWARE: StringName = &"dirty_tableware"
const WASTE: StringName = &"waste"


# --- Production and trade ----------------------------------------------------

const TOOL: StringName = &"tool"
const RESOURCE: StringName = &"resource"
const INGREDIENT: StringName = &"ingredient"
const TRADE_GOOD: StringName = &"trade_good"
const CONTRABAND: StringName = &"contraband"


## Returns true when [param tags] contains every tag in [param required_tags].
##
## An empty [param required_tags] list always passes.
static func has_all(
	tags: Array[StringName],
	required_tags: Array[StringName]
) -> bool:
	for required_tag: StringName in required_tags:
		if not tags.has(required_tag):
			return false

	return true


## Returns true when [param tags] contains at least one of [param any_tags].
##
## An empty [param any_tags] list always passes, so "no filter" means
## "accept anything".
static func has_any(
	tags: Array[StringName],
	any_tags: Array[StringName]
) -> bool:
	if any_tags.is_empty():
		return true

	for candidate_tag: StringName in any_tags:
		if tags.has(candidate_tag):
			return true

	return false


## Returns true when [param tags] and [param blocked_tags] share no entries.
static func has_none(
	tags: Array[StringName],
	blocked_tags: Array[StringName]
) -> bool:
	for blocked_tag: StringName in blocked_tags:
		if tags.has(blocked_tag):
			return false

	return true
