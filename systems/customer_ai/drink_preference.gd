class_name DrinkPreference
extends Resource

## One drink a customer type is likely to order, and how they take it.
##
## Replaces the old single [member CustomerType.preferred_drink] plus a flat
## chance. A Pirate Crew who drink Kill-Devil, Bumbo and Rum Punch are three
## entries with different weights, not one favourite and a random fallback.
##
## [member preferred_format_ids] is the part the old model could not express
## at all: WHAT the drink arrives in. A Dock Labourer takes a tankard, a
## Captain takes the bottle, and both are ordering the same liquid. The format
## carries its own price and service-time modifiers, so this is a real economic
## difference rather than flavour text.
##
## Nothing here is a whitelist. A drink with no matching format still serves
## in its own default format, and a type with no preferences at all falls back
## to [member CustomerType.available_drinks].


@export_category("Drink")

@export var drink: DrinkDefinition


## Relative likelihood against the other entries on the same customer type.
##
## Not a probability - the draw normalises across whatever is affordable and
## in stock, so removing an entry never leaves a gap that has to be re-balanced
## by hand.
@export_range(0.0, 100.0, 0.1)
var weight: float = 1.0


@export_category("Serving")

## Formats this type likes to take the drink in, best first.
##
## Matched against the drink's own [member DrinkDefinition.serving_format_ids],
## so an entry asking for a format the drink does not support is skipped
## rather than producing an impossible order. Empty means "however it normally
## comes".
@export var preferred_format_ids: Array[StringName] = []


## Rough number of servings before this customer is satisfied.
##
## Read by future round-buying and pacing work. Recorded on the order now so
## the behaviour report can show it without another data pass.
@export_range(1, 12, 1)
var typical_servings: int = 1


## Whether this preference can be drawn at all right now.
func is_valid() -> bool:
	return drink != null and weight > 0.0


## The best format for this preference that [member drink] actually allows.
##
## [param allow_shared] must be false for a customer drinking alone. A punch
## bowl needs three people and a pitcher needs two; letting a solo customer
## resolve to one would price and serve an order that cannot physically
## happen. Returns an empty StringName when nothing fits, which the caller
## reads as "use the drink's default".
func resolve_format_id(
	registry: BeverageRegistry = null,
	allow_shared: bool = false
) -> StringName:
	if drink == null:
		return &""

	for format_id: StringName in preferred_format_ids:
		if not drink.allows_serving_format(format_id):
			continue

		if registry != null and not allow_shared:
			var format: ServingFormatDefinition = registry.get_serving_format(
				format_id
			)

			if format != null and format.is_shared:
				continue

		return format_id

	return &""
