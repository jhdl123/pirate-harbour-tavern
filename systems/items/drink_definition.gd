class_name DrinkDefinition
extends ItemDefinition


@export_category("Drink Timing")

## Real-world seconds a customer spends drinking this drink.
##
## This is customer activity time, not simulated GameTime.
@export_range(0.0, 600.0, 0.1)
var drink_duration_seconds: float = 8.0


@export_category("Drink Visuals")

## Icon displayed when a customer orders this drink.
@export var order_icon_texture: Texture2D

## Texture displayed while the player carries the prepared drink.
@export var carried_texture: Texture2D

## Texture displayed when the drink is full and placed in the world.
@export var full_container_texture: Texture2D

## Texture displayed after the drink has been consumed.
@export var empty_container_texture: Texture2D

## Texture displayed if the container breaks.
@export var broken_container_texture: Texture2D


@export_category("Breakage")

## Multiplier applied to the base break chance.
##
## 1.0 uses the normal chance.
## 0.5 halves it.
## 2.0 doubles it.
@export_range(0.0, 100.0, 0.05)
var break_chance_multiplier: float = 1.0


func is_valid_drink() -> bool:
	return (
		is_valid()
		and category == ItemCategory.DRINK
		and drink_duration_seconds >= 0.0
	)
