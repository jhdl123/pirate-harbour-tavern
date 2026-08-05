class_name ServingFormatDefinition
extends Resource

## How a customer buys and drinks something.
##
## The format is the second half of an order. A customer does not order "ale",
## they order "a Tankard of Ale" - a [DrinkDefinition] id plus a
## [ServingFormatDefinition] id. Keeping them separate means a new drink
## inherits every existing size, and a new size applies to every existing drink,
## without either being edited.
##
## Formats also decide whether a serving is one person's or a group's. That one
## flag - [member is_shared] - is what turns an order into a persistent
## [SharedServing] anchored at a table rather than a single carried drink.


@export_category("Identity")

@export var format_id: StringName = &""

## Period name shown to the player, e.g. "Tankard".
@export var historical_name: String = "Unnamed Format"

## Plain-English gloss shown in brackets, e.g. "large mug". Optional.
@export var simplified_explanation: String = ""

@export_multiline var description: String = ""


@export_category("Vessel")

## Container the serving is presented in.
##
## Required for anything the customer physically receives. The vessel must be
## available before the serving can be made - see [VesselPool].
@export var required_container_id: StringName = &""


@export_category("Portions")

## Measures of content one whole serving uses.
##
## A dram is 1, a mug might be 4, a punch bowl 24. This is the number the
## transfer and stock systems actually move.
@export_range(1, 10000, 1)
var measures_per_serving: int = 1

## How many separate drinks a customer gets out of this serving.
##
## 1 for anything individual. A pitcher or punch bowl is greater than 1, and
## that count is what a group consumes down through.
@export_range(1, 100, 1)
var portion_count: int = 1


@export_category("Sharing")

## True when several customers drink from one serving.
@export var is_shared: bool = false

## Smallest group this format makes sense for. Advisory.
@export_range(1, 50, 1)
var minimum_group_size: int = 1

## Largest group this format is intended to cover. Advisory.
@export_range(1, 50, 1)
var maximum_group_size: int = 1

## Whether this serving must be placed on a table.
@export var requires_table: bool = false

## Whether this serving may be set down in a standing area instead.
@export var allows_standing_area: bool = false

## Whether the served object persists in the world as a group anchor.
##
## A punch bowl does; a glass does not. This is what
## [SharedServingService] keys off.
@export var creates_group_anchor: bool = false


@export_category("Modifiers")

## Multiplier on the time staff take to prepare and deliver this serving.
@export_range(0.1, 20.0, 0.05)
var service_time_modifier: float = 1.0

## Multiplier on how long a customer takes over one portion.
@export_range(0.1, 20.0, 0.05)
var consumption_time_modifier: float = 1.0

## Multiplier on the price of the whole serving.
##
## Applied on top of measures. A pitcher is usually below 1.0 per measure -
## buying in bulk is meant to be slightly cheaper.
@export_range(0.0, 20.0, 0.05)
var price_modifier: float = 1.0


@export_category("Restrictions")

## Drink tags this format will accept. Empty means any drink.
##
## A punch bowl lists [constant BeverageTags.MIXED_DRINK]; a tankard lists
## beer and ale tags.
@export var valid_drink_tags: Array[StringName] = []

## Drink tags this format refuses even if it otherwise matches.
@export var blocked_drink_tags: Array[StringName] = []


@export_category("Aftermath")

## Item id left behind once the serving is finished.
##
## Normally the dirty version of the vessel. Leave empty when nothing remains.
@export var empty_result_item_id: StringName = &""


## Player-facing name: historical name, then the gloss in brackets.
func get_display_name_with_explanation() -> String:
	if simplified_explanation.strip_edges().is_empty():
		return historical_name

	return "%s (%s)" % [historical_name, simplified_explanation]


## Full order text, e.g. "Tankard of Ale".
func get_order_display_name(drink_display_name: String) -> String:
	return "%s of %s" % [historical_name, drink_display_name]


## Order text with the gloss, e.g. "Firkin (small cask) of Kill-Devil".
func get_order_display_name_with_explanation(
	drink_display_name: String
) -> String:
	return "%s of %s" % [
		get_display_name_with_explanation(),
		drink_display_name,
	]


## True when [param drink] may be served in this format.
##
## Checks this format's own tag rules. The drink's own list of valid formats is
## checked separately by [method DrinkDefinition.allows_serving_format], so a
## mismatch on either side blocks the pairing.
func accepts_drink(drink: DrinkDefinition) -> bool:
	if drink == null:
		return false

	if not blocked_drink_tags.is_empty():
		if not ItemTags.has_none(drink.tags, blocked_drink_tags):
			return false

	if valid_drink_tags.is_empty():
		return true

	return ItemTags.has_any(drink.tags, valid_drink_tags)


## Total measures needed to make one of these servings.
func get_total_measures() -> int:
	return measures_per_serving


## Measures consumed by one portion out of a shared serving.
##
## Rounded up so a bowl can never be drunk beyond empty by rounding.
func get_measures_per_portion() -> int:
	if portion_count <= 1:
		return measures_per_serving

	return maxi(
		1,
		int(ceil(float(measures_per_serving) / float(portion_count)))
	)


func is_individual() -> bool:
	return not is_shared


func is_valid() -> bool:
	return (
		not format_id.is_empty()
		and not historical_name.strip_edges().is_empty()
		and measures_per_serving > 0
		and portion_count > 0
		and minimum_group_size <= maximum_group_size
	)


func validate_or_warn() -> bool:
	if format_id.is_empty():
		push_error(
			"ServingFormatDefinition at "
			+ resource_path
			+ " has no format_id."
		)
		return false

	if minimum_group_size > maximum_group_size:
		push_error(
			"ServingFormatDefinition '"
			+ String(format_id)
			+ "' has minimum_group_size ("
			+ str(minimum_group_size)
			+ ") above maximum_group_size ("
			+ str(maximum_group_size)
			+ ")."
		)
		return false

	if is_shared and portion_count <= 1:
		push_warning(
			"ServingFormatDefinition '"
			+ String(format_id)
			+ "' is shared but has only one portion. A group cannot take "
			+ "turns with it."
		)

	if creates_group_anchor and not is_shared:
		push_warning(
			"ServingFormatDefinition '"
			+ String(format_id)
			+ "' creates a group anchor but is not marked shared. It will be "
			+ "treated as individual."
		)

	if required_container_id.is_empty():
		push_warning(
			"ServingFormatDefinition '"
			+ String(format_id)
			+ "' names no required_container_id, so no vessel will be "
			+ "reserved for it."
		)

	return true
