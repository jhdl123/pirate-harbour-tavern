class_name StationCapabilities
extends RefCounted

## What a beverage station is able to do.
##
## Capabilities are the join between a station and a drink or recipe, exactly
## as [StaffCapabilities] is the join between a worker and a task. A
## [DrinkDefinition] or [DrinkRecipeDefinition] lists the capabilities it
## requires; a station lists the capabilities it has; the service layer
## intersects the two.
##
## This is what stops drink names appearing inside station scripts. A new
## drink that needs heating simply requires [constant HEAT_LIQUID], and every
## station that already has that capability can make it - with no script edit
## anywhere.


# --- Drawing and pouring -----------------------------------------------------

## Draw a measure out of a cask, keg or barrel mounted at the station.
const DRAW_FROM_CASK: StringName = &"draw_from_cask"

## Pour a measure out of a bottle.
const POUR_FROM_BOTTLE: StringName = &"pour_from_bottle"

## Reach bottles kept behind a lock. Premium and rare spirits need this.
const ACCESS_SECURED_BOTTLES: StringName = &"access_secured_bottles"


# --- Preparation -------------------------------------------------------------

## Mix one serving to order.
const MIX_SINGLE: StringName = &"mix_single"

## Mix a whole batch at once, for a shared serving.
const PREPARE_BATCH: StringName = &"prepare_batch"

## Apply heat to a liquid.
const HEAT_LIQUID: StringName = &"heat_liquid"

## Brew or infuse, as distinct from simply heating.
const BREW: StringName = &"brew"


# --- Filling shared vessels --------------------------------------------------

const FILL_PITCHER: StringName = &"fill_pitcher"
const FILL_SHARED_BOWL: StringName = &"fill_shared_bowl"
const FILL_SHARED_CASK: StringName = &"fill_shared_cask"


# --- Ingredient access -------------------------------------------------------

## Reach clean water at or beside the station.
const ACCESS_WATER: StringName = &"access_water"

## Reach dry goods: sugar, nutmeg, spices, coffee beans.
const ACCESS_DRY_INGREDIENTS: StringName = &"access_dry_ingredients"

## Reach fresh perishables: citrus and similar.
const ACCESS_FRESH_INGREDIENTS: StringName = &"access_fresh_ingredients"


## True when [param held] covers every entry in [param required].
##
## An empty [param required] means "any station will do". That is deliberate
## and matches [method StaffCapabilities.satisfies]: a drink that needs no
## special equipment should not need a capability invented for it.
static func satisfies(
	held: Array[StringName],
	required: Array[StringName]
) -> bool:
	if required.is_empty():
		return true

	if held.is_empty():
		return false

	for capability: StringName in required:
		if not held.has(capability):
			return false

	return true


## The entries of [param required] that [param held] does not cover.
##
## Used by the UI and the diagnostics panel to say *why* a drink cannot be
## made here, rather than only that it cannot.
static func get_missing(
	held: Array[StringName],
	required: Array[StringName]
) -> Array[StringName]:
	var missing: Array[StringName] = []

	for capability: StringName in required:
		if not held.has(capability):
			missing.append(capability)

	return missing


## Every capability this class names, for validation and debug listing.
static func get_all_capabilities() -> Array[StringName]:
	return [
		DRAW_FROM_CASK, POUR_FROM_BOTTLE, ACCESS_SECURED_BOTTLES,
		MIX_SINGLE, PREPARE_BATCH, HEAT_LIQUID, BREW,
		FILL_PITCHER, FILL_SHARED_BOWL, FILL_SHARED_CASK,
		ACCESS_WATER, ACCESS_DRY_INGREDIENTS, ACCESS_FRESH_INGREDIENTS,
	]


static func is_known(capability: StringName) -> bool:
	return get_all_capabilities().has(capability)


## Human-readable name, for prompts and the diagnostics panel.
static func get_display_name(capability: StringName) -> String:
	return String(capability).capitalize()
