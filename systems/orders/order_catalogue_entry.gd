class_name OrderCatalogueEntry
extends Resource

## One product offered by a supplier.

@export var item: ItemDefinition

## Use -1 to read ItemDefinition.base_buy_price.
@export_range(-1, 999999, 1)
var unit_price_override: int = -1

## Maximum allowed on one order. Zero means no supplier-specific limit.
@export_range(0, 9999, 1)
var maximum_order_quantity: int = 20


func get_unit_price() -> int:
	if unit_price_override >= 0:
		return unit_price_override

	if item == null:
		return 0

	return item.base_buy_price


func get_maximum_quantity() -> int:
	if maximum_order_quantity <= 0:
		return 9999

	return maximum_order_quantity


func is_valid() -> bool:
	return item != null and get_unit_price() >= 0
