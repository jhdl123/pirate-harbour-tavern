class_name BeverageTags
extends RefCounted

## Named tag constants for drinks, liquids, ingredients and containers.
##
## These extend [ItemTags] rather than replacing it. Tags stay plain
## [StringName] data on resources, so a new drink family or a new customer
## preference group never needs a script change - it only needs a tag typed
## into a resource.
##
## Customer preference systems are expected to score drinks by these tags.
## Deliberately there is no "which archetypes like this" list on a drink:
## that would put preference data in the wrong place and make every new
## customer type an edit to every drink.


# --- Drink families ----------------------------------------------------------

const RUM: StringName = &"rum"
const BEER: StringName = &"beer"
const ALE: StringName = &"ale"
const WINE: StringName = &"wine"
const SPIRIT: StringName = &"spirit"
const CIDER: StringName = &"cider"
const MIXED_DRINK: StringName = &"mixed_drink"
const HOT_DRINK: StringName = &"hot_drink"


# --- Strength ----------------------------------------------------------------

const NON_ALCOHOLIC: StringName = &"non_alcoholic"
const WEAK_ALCOHOL: StringName = &"weak_alcohol"
const STRONG_ALCOHOL: StringName = &"strong_alcohol"


# --- Market position ---------------------------------------------------------

const CHEAP: StringName = &"cheap"
const PREMIUM: StringName = &"premium"
const IMPORTED: StringName = &"imported"
const LUXURY: StringName = &"luxury"


# --- Service shape -----------------------------------------------------------

## A drink or format intended to be consumed by more than one customer.
const SHARED: StringName = &"shared"

## A drink or format intended for exactly one customer.
const INDIVIDUAL: StringName = &"individual"


# --- Customer affinity -------------------------------------------------------
#
# These are hints a preference system reads. They are NOT a whitelist: a drink
# without any affinity tag is still orderable by anyone.

const SAILOR_FAVOURITE: StringName = &"sailor_favourite"
const PIRATE_FAVOURITE: StringName = &"pirate_favourite"
const MERCHANT_FAVOURITE: StringName = &"merchant_favourite"
const CAPTAIN_FAVOURITE: StringName = &"captain_favourite"
const OFFICER_FAVOURITE: StringName = &"officer_favourite"


# --- Physical stock ----------------------------------------------------------

## A bulk supplier-sized container: cask, hogshead, pipe, crate.
const BULK_CONTAINER: StringName = &"bulk_container"

## A container a customer is served from or drinks out of.
const SERVING_VESSEL: StringName = &"serving_vessel"

## A filled stock item that has a content id and a quantity.
const FILLED_STOCK: StringName = &"filled_stock"

## An empty container item, tracked so it can be refilled or returned.
const EMPTY_CONTAINER: StringName = &"empty_container"


# --- Content families (what is inside a container) ---------------------------

## Anything pourable. Used by container content-tag compatibility.
const LIQUID: StringName = &"liquid"

## A dry good measured by weight or count: sugar, nutmeg, coffee beans.
const DRY_GOOD: StringName = &"dry_good"

## Something that goes off. Pairs with a spoilage profile.
const PERISHABLE: StringName = &"perishable"


# --- Storage groups ----------------------------------------------------------

const CELLAR_STORAGE: StringName = &"cellar_storage"
const BAR_STORAGE: StringName = &"bar_storage"
const DRY_STORAGE: StringName = &"dry_storage"
const LOCKED_STORAGE: StringName = &"locked_storage"


## Every tag this class names, for validation and debug listing.
##
## GDScript cannot reflect over its own constants, so this list is explicit.
## It is kept here so validation and the debug panel always agree on what a
## "known" tag is. A tag missing from this list still works everywhere - it is
## only reported as unrecognised by the validator.
static func get_all_tags() -> Array[StringName]:
	return [
		RUM, BEER, ALE, WINE, SPIRIT, CIDER, MIXED_DRINK, HOT_DRINK,
		NON_ALCOHOLIC, WEAK_ALCOHOL, STRONG_ALCOHOL,
		CHEAP, PREMIUM, IMPORTED, LUXURY,
		SHARED, INDIVIDUAL,
		SAILOR_FAVOURITE, PIRATE_FAVOURITE, MERCHANT_FAVOURITE,
		CAPTAIN_FAVOURITE, OFFICER_FAVOURITE,
		BULK_CONTAINER, SERVING_VESSEL, FILLED_STOCK, EMPTY_CONTAINER,
		LIQUID, DRY_GOOD, PERISHABLE,
		CELLAR_STORAGE, BAR_STORAGE, DRY_STORAGE, LOCKED_STORAGE,
	]


static func is_known(tag: StringName) -> bool:
	return get_all_tags().has(tag)
