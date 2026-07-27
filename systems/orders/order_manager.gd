class_name OrderManager
extends Node

## Records and validates stock orders.
##
## This first version deliberately stops at a pending order. It spends the
## money, records the requested lines and calculates an expected arrival time.
## A later delivery system can consume pending_orders without changing the
## ledger UI or supplier resources.

signal order_submitted(order: Dictionary)
signal order_rejected(reason: String)

@export var economy_manager: EconomyManager

var pending_orders: Array[Dictionary] = []
var _next_order_number: int = 1


func submit_order(
	supplier: SupplierDefinition,
	quantities: Dictionary
) -> Dictionary:
	if supplier == null or not supplier.is_valid():
		return _reject("The supplier catalogue is not configured.")

	if economy_manager == null:
		return _reject("The order system has no EconomyManager.")

	var lines: Array[Dictionary] = []
	var total_cost: int = 0

	for entry: OrderCatalogueEntry in supplier.entries:
		if entry == null or not entry.is_valid():
			continue

		var item_id: StringName = entry.item.item_id
		var quantity: int = maxi(
			int(quantities.get(item_id, 0)),
			0
		)

		quantity = mini(quantity, entry.get_maximum_quantity())

		if quantity <= 0:
			continue

		var unit_price: int = entry.get_unit_price()
		var line_total: int = unit_price * quantity

		lines.append({
			"item_id": item_id,
			"display_name": entry.item.display_name,
			"quantity": quantity,
			"unit_price": unit_price,
			"line_total": line_total,
			"item_definition": entry.item,
		})

		total_cost += line_total

	if lines.is_empty():
		return _reject("Choose at least one item before submitting.")

	if not economy_manager.can_afford(total_cost):
		return _reject(
			"You need £%d but only have £%d."
			% [total_cost, economy_manager.get_money()]
		)

	if not economy_manager.spend_money(total_cost, &"stock_order"):
		return _reject("The payment could not be completed.")

	var placed_at: GameTimeStamp = WorldTime.get_timestamp()
	var expected_at: GameTimeStamp = placed_at.added_days(
		supplier.delivery_delay_days
	)

	var order: Dictionary = {
		"order_number": _next_order_number,
		"supplier_id": supplier.supplier_id,
		"supplier_name": supplier.display_name,
		"lines": lines,
		"total_cost": total_cost,
		"placed_at_minutes": placed_at.total_minutes,
		"placed_at_text": placed_at.get_full_text(),
		"expected_at_minutes": expected_at.total_minutes,
		"expected_at_text": expected_at.get_full_text(),
		"status": &"pending",
	}

	_next_order_number += 1
	pending_orders.append(order)
	order_submitted.emit(order)

	return {
		"success": true,
		"message": (
			"Order #%d placed. Expected %s."
			% [order.order_number, order.expected_at_text]
		),
		"order": order,
	}


func get_pending_orders() -> Array[Dictionary]:
	return pending_orders.duplicate(true)


func _reject(reason: String) -> Dictionary:
	order_rejected.emit(reason)

	return {
		"success": false,
		"message": reason,
	}
