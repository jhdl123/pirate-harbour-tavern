class_name CanAffordDrinkCondition
extends ActivityCondition

## Hard gate: does this customer have enough money for at least one of
## their CustomerType's available drinks?
##
## Reads real drink prices (DrinkDefinition.base_sell_price, scaled by
## Customer.payment_multiplier the same way payment itself is computed) so
## this never drifts from what a drink actually costs - no separate
## "afford threshold" number to keep in sync. See
## Customer.choose_drink_from_customer_type() for the matching filter that
## keeps a specific drink choice affordable once this condition has already
## let Order Drink through.


func is_satisfied(context: ActivityContext) -> bool:
	var customer: Customer = context.actor as Customer

	if customer == null or customer.customer_type == null:
		return true

	if context.needs == null:
		return true

	return _cheapest_available_price(customer) <= context.needs.wealth


func get_rejection_reason(context: ActivityContext) -> String:
	var customer: Customer = context.actor as Customer
	var cheapest: int = _cheapest_available_price(customer)
	var wealth: int = context.needs.wealth if context.needs != null else 0

	return (
		"cannot afford any available drink (cheapest £%d, has £%d)"
		% [cheapest, wealth]
	)


func _cheapest_available_price(customer: Customer) -> int:
	if customer == null or customer.customer_type == null:
		return 0

	var cheapest: int = -1

	for drink: DrinkDefinition in customer.customer_type.available_drinks:
		if drink == null:
			continue

		var price: int = roundi(
			float(drink.base_sell_price) * customer.payment_multiplier
		)

		if cheapest < 0 or price < cheapest:
			cheapest = price

	return maxi(cheapest, 0)
