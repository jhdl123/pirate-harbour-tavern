class_name DrinkDefinition
extends ItemDefinition

## An [ItemDefinition] for a drink a customer can order.
##
## A [DrinkDefinition] IS the drink's item definition. There is no second,
## parallel drink-item resource to keep in step: drink balance and item identity
## live in the same file. Everything generic - stable id, tags, stack size,
## prices, carried texture, world texture - is inherited from [ItemDefinition].
##
## The Beverage Framework adds three references that keep this resource small
## while making it far more capable:
##
## [codeblock]
## content_id            the liquid this is poured from, if any
## serving_format_ids    the sizes it may be ordered in
## recipe_id             how it is made, if it must be prepared
## [/codeblock]
##
## A customer orders a drink id AND a serving format id together, so "Tankard of
## Ale" needs no resource of its own. The serving format is carried in the
## [ItemStack] metadata of the served item rather than in a separate definition
## per size - see [BeverageServiceService.create_serving_stack].
##
## Note deliberately absent: any list of which customer archetypes like this
## drink. Preference belongs to the customer, expressed through
## [member ItemDefinition.tags]. Putting it here would make every new customer
## type an edit to every drink.


## How a drink reaches the customer.
enum ServiceMethod {
	## Drawn straight out of a cask at a station.
	DRAWN_FROM_CASK,

	## Poured from a bottle.
	POURED_FROM_BOTTLE,

	## Made to order from a recipe, one serving at a time.
	MIXED_TO_ORDER,

	## Made as a batch from a recipe, for a shared serving.
	PREPARED_AS_BATCH,

	## Sold in the sealed container it arrived in.
	SERVED_SEALED,
}


## Roughly how often this appears in a Caribbean port tavern of the period.
##
## Used by supplier availability and future era gating. Balance values, not
## historical claims.
enum Availability {
	VERY_COMMON,
	COMMON,
	UNCOMMON,
	RARE,
	VERY_RARE,
}


enum QualityTier {
	ROUGH,
	ORDINARY,
	GOOD,
	FINE,
	EXCEPTIONAL,
}


@export_category("Drink Identity")

## Broad family for grouping in menus and reports, e.g. &"spirit", &"wine".
@export var drink_category: StringName = &""

## How available this drink is in the setting.
@export var historical_availability: Availability = Availability.COMMON

## Baseline appeal before any customer preference is applied, 0..1.
@export_range(0.0, 1.0, 0.01)
var general_popularity: float = 0.5

## How hard this is to obtain at all. Feeds supplier stocking.
@export var rarity: Availability = Availability.COMMON

@export var quality_tier: QualityTier = QualityTier.ORDINARY


@export_category("Alcohol")

## How strongly one serving contributes to CustomerNeeds.intoxication.
##
## A non-alcoholic drink simply leaves this at 0.0 - no separate flag needed.
@export_range(0.0, 5.0, 0.05)
var alcohol_strength: float = 1.0


@export_category("Drink Timing")

## World minutes a customer spends over one serving.
##
## Driven by WorldTime, so drinking pauses with the simulation and finishes
## sooner when time is fast-forwarded. A serving format's
## consumption_time_modifier scales this.
@export_range(0, 600, 1)
var drink_duration_minutes: int = 8


@export_category("Beverage Framework")

## Liquid this drink is poured from.
##
## Empty for anything with no bulk liquid behind it. Set for everything drawn,
## poured or prepared, because it is how a serving finds real stock to consume.
@export var content_id: StringName = &""

## Serving formats this drink may be ordered in.
##
## Order matters: the first entry is the default when nothing else is chosen.
## A format must also accept the drink - see
## [method ServingFormatDefinition.accepts_drink] - so both sides agree.
@export var serving_format_ids: Array[StringName] = []

@export var service_method: ServiceMethod = ServiceMethod.DRAWN_FROM_CASK

## Recipe used when this drink must be prepared. Empty when it is just poured.
@export var recipe_id: StringName = &""

## Station capabilities required to serve this, beyond any the recipe needs.
##
## A drawn ale needs DRAW_FROM_CASK; a secured brandy needs
## ACCESS_SECURED_BOTTLES. Empty means any station will do.
@export var required_station_capabilities: Array[StringName] = []


@export_category("Spoilage")

## Whether a poured or prepared serving of this goes off.
##
## Only affects the served drink. Bulk stock spoilage is decided by the
## content's own profile, which is why a sealed cask of rum keeps while a
## poured mug of it need not.
@export var can_spoil_after_serving: bool = false

## Profile applied to a served drink when [member can_spoil_after_serving].
@export var spoilage_profile: SpoilageProfileDefinition


@export_category("Drink Visuals")

## Icon displayed above a customer while they are ordering this drink.
@export var order_icon_texture: Texture2D

## Texture displayed after the drink has been consumed.
@export var empty_container_texture: Texture2D

## Texture displayed if the container breaks.
@export var broken_container_texture: Texture2D


@export_category("Breakage")

## Multiplier applied to the base break chance.
##
## 1.0 uses the normal chance. 0.5 halves it. 2.0 doubles it.
@export_range(0.0, 100.0, 0.05)
var break_chance_multiplier: float = 1.0


# --- Serving formats ---------------------------------------------------------

## Default format when an order does not specify one.
##
## Returns an empty name when this drink declares no formats, which callers
## treat as "serve it the old way" so pre-framework content keeps working.
func get_default_serving_format_id() -> StringName:
	if serving_format_ids.is_empty():
		return &""

	return serving_format_ids[0]


func allows_serving_format(format_id: StringName) -> bool:
	if serving_format_ids.is_empty():
		return true

	return serving_format_ids.has(format_id)


## True when this drink and [param format] agree with each other.
func is_compatible_with_format(format: ServingFormatDefinition) -> bool:
	if format == null:
		return false

	return allows_serving_format(format.format_id) and format.accepts_drink(self)


# --- Preparation -------------------------------------------------------------

func requires_preparation() -> bool:
	return not recipe_id.is_empty()


func is_shared_by_default() -> bool:
	return has_tag(BeverageTags.SHARED)


# --- Pricing -----------------------------------------------------------------

## Sale price for one serving in [param format].
##
## Falls back to the plain sell price when no format is given, which keeps
## every existing pricing call site working unchanged.
func get_sale_price(format: ServingFormatDefinition = null) -> int:
	if format == null:
		return base_sell_price

	return maxi(
		0,
		int(round(float(base_sell_price) * format.price_modifier))
	)


## Consumption time for one serving in [param format].
func get_consumption_minutes(
	format: ServingFormatDefinition = null
) -> int:
	if format == null:
		return drink_duration_minutes

	return maxi(
		0,
		int(round(
			float(drink_duration_minutes) * format.consumption_time_modifier
		))
	)


func get_spoilage_profile() -> SpoilageProfileDefinition:
	if not can_spoil_after_serving:
		return null

	return spoilage_profile


# --- Validation --------------------------------------------------------------

## Returns true when this resource is usable as a servable prepared drink.
func is_valid_drink() -> bool:
	return (
		is_valid()
		and has_tag(ItemTags.PREPARED_DRINK)
		and drink_duration_minutes >= 0
	)


## Reports beverage-specific configuration problems.
##
## Deliberately separate from [method ItemDefinition.validate_or_warn] so a
## drink authored before the Beverage Framework still passes basic item
## validation while being reported as incomplete here.
func validate_beverage_or_warn() -> bool:
	var is_ok: bool = true

	if requires_preparation() and service_method == ServiceMethod.DRAWN_FROM_CASK:
		push_warning(
			"DrinkDefinition '"
			+ String(item_id)
			+ "' names a recipe but its service_method is DRAWN_FROM_CASK. "
			+ "It will be poured rather than prepared."
		)

	if not requires_preparation() and content_id.is_empty():
		push_warning(
			"DrinkDefinition '"
			+ String(item_id)
			+ "' has neither a recipe_id nor a content_id, so it has no "
			+ "stock behind it and can never actually be served."
		)
		is_ok = false

	if can_spoil_after_serving and spoilage_profile == null:
		push_warning(
			"DrinkDefinition '"
			+ String(item_id)
			+ "' can spoil after serving but names no spoilage_profile."
		)

	return is_ok
