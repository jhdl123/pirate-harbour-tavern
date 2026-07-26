class_name DrinkDefinition
extends ItemDefinition

## An [ItemDefinition] for a prepared drink.
##
## A [DrinkDefinition] IS the prepared drink's item definition. There is no
## second, parallel drink-item resource to keep in step: drink balance and item
## identity live in the same file.
##
## Everything generic - stable id, tags, stack size, prices, carried texture and
## world texture - is inherited from [ItemDefinition]. This resource only adds
## data that is meaningless for non-drink items.


@export_category("Drink Timing")

## Real-world seconds a customer spends drinking this drink.
##
## This is customer activity time, not simulated GameTime.
@export_range(0.0, 600.0, 0.1)
var drink_duration_seconds: float = 8.0


@export_category("Drink Visuals")

## Icon displayed above a customer while they are ordering this drink.
@export var order_icon_texture: Texture2D

## Texture displayed after the drink has been consumed.
##
## Future work: this becomes its own dirty-tableware [ItemDefinition].
@export var empty_container_texture: Texture2D

## Texture displayed if the container breaks.
##
## Future work: this becomes its own waste [ItemDefinition].
@export var broken_container_texture: Texture2D


@export_category("Breakage")

## Multiplier applied to the base break chance.
##
## 1.0 uses the normal chance.
## 0.5 halves it.
## 2.0 doubles it.
@export_range(0.0, 100.0, 0.05)
var break_chance_multiplier: float = 1.0


## Returns true when this resource is usable as a servable prepared drink.
func is_valid_drink() -> bool:
	return (
		is_valid()
		and has_tag(ItemTags.PREPARED_DRINK)
		and drink_duration_seconds >= 0.0
	)
