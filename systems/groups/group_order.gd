class_name GroupOrder
extends RefCounted

## One order placed by a group.
##
## Carries drink id AND serving-format id together, which is what the Beverage
## Framework has wanted since serving formats were added: "a Punch Bowl of Rum
## Punch" is two ids, not one. Nothing here duplicates [DrinkDefinition] or
## [ServingFormatDefinition] - it only points at them.
##
## Shared and individual orders are the same object with [member is_shared]
## flipped, so payment, service and failure handling have one path rather than
## two that can drift.


enum Status {
	## Chosen but not yet accepted by the tavern.
	PENDING,

	## Ingredients and vessel reserved, preparation not started.
	RESERVED,

	## A staff task is working on it.
	IN_PREPARATION,

	## Made, waiting to be carried over.
	READY,

	## Handed to the group.
	DELIVERED,

	## Consumed to the last portion.
	COMPLETED,

	## Could not be fulfilled. See [member failure_reason].
	FAILED,
}


enum Failure {
	NONE,
	NO_STOCK,
	NO_VESSEL,
	NO_STATION,
	NO_STAFF,
	CANNOT_AFFORD,
	ABANDONED,
}


var order_id: StringName = &""
var group_id: StringName = &""

## The member who placed it. Normally the leader for a shared order.
var ordering_member_id: StringName = &""

var drink_id: StringName = &""
var serving_format_id: StringName = &""

## Whether the whole group drinks from one vessel.
var is_shared: bool = false

## How many of this order. Always 1 for a shared serving.
var quantity: int = 1

var status: Status = Status.PENDING
var failure_reason: Failure = Failure.NONE

## Price agreed when the order was placed, so a later price change cannot
## alter what the group is charged.
var price: int = 0

## Whether the money has actually changed hands. Guards double payment.
var paid: bool = false

## Where the drink goes: table id or standing-area id.
var destination_place_id: StringName = &""

## The reservation held by [PreparationService], when preparing.
var preparation_request: PreparationRequest = null

## The world object once delivered.
var shared_serving: SharedServing = null


static func create(
	for_group_id: StringName,
	member_id: StringName,
	drink: StringName,
	format: StringName,
	shared: bool
) -> GroupOrder:
	var order: GroupOrder = GroupOrder.new()
	order.order_id = StringName(
		"order_%s_%d" % [String(for_group_id), Time.get_ticks_usec()]
	)
	order.group_id = for_group_id
	order.ordering_member_id = member_id
	order.drink_id = drink
	order.serving_format_id = format
	order.is_shared = shared

	return order


func is_active() -> bool:
	return status != Status.COMPLETED and status != Status.FAILED


func is_delivered() -> bool:
	return status == Status.DELIVERED


func has_failed() -> bool:
	return status == Status.FAILED


func fail(reason: Failure) -> void:
	status = Status.FAILED
	failure_reason = reason


## Marks the order paid exactly once. Returns false if it already was.
##
## The guard is what stops group revenue being counted per member: every
## payment path calls this, and only the first call can succeed.
func mark_paid() -> bool:
	if paid:
		return false

	paid = true

	return true


## Price for this order, from the drink and its serving format.
func calculate_price(registry: BeverageRegistry) -> int:
	if registry == null:
		return 0

	var drink: DrinkDefinition = registry.get_drink(drink_id)

	if drink == null:
		return 0

	var format: ServingFormatDefinition = registry.get_serving_format(
		serving_format_id
	)

	return drink.get_sale_price(format) * maxi(quantity, 1)


## "Punch Bowl of Rum Punch", using the historical name and its explanation.
func get_display_name(registry: BeverageRegistry) -> String:
	if registry == null:
		return String(drink_id)

	var drink: DrinkDefinition = registry.get_drink(drink_id)
	var drink_name: String = (
		drink.display_name if drink != null else String(drink_id)
	)

	var format: ServingFormatDefinition = registry.get_serving_format(
		serving_format_id
	)

	if format == null:
		return drink_name

	return format.get_order_display_name(drink_name)


func get_status_name() -> String:
	return Status.keys()[status].capitalize()


func get_failure_text() -> String:
	match failure_reason:
		Failure.NO_STOCK:
			return "not enough stock"
		Failure.NO_VESSEL:
			return "no clean vessel"
		Failure.NO_STATION:
			return "no station can make it"
		Failure.NO_STAFF:
			return "no staff available"
		Failure.CANNOT_AFFORD:
			return "the group could not pay"
		Failure.ABANDONED:
			return "abandoned"
		_:
			return ""


func to_save_dict() -> Dictionary:
	return {
		"order_id": String(order_id),
		"group_id": String(group_id),
		"ordering_member_id": String(ordering_member_id),
		"drink_id": String(drink_id),
		"serving_format_id": String(serving_format_id),
		"is_shared": is_shared,
		"quantity": quantity,
		"status": int(status),
		"failure_reason": int(failure_reason),
		"price": price,
		"paid": paid,
		"destination_place_id": String(destination_place_id),
	}


static func from_save_dict(data: Dictionary) -> GroupOrder:
	var order: GroupOrder = GroupOrder.new()
	order.order_id = StringName(String(data.get("order_id", "")))
	order.group_id = StringName(String(data.get("group_id", "")))
	order.ordering_member_id = StringName(
		String(data.get("ordering_member_id", ""))
	)
	order.drink_id = StringName(String(data.get("drink_id", "")))
	order.serving_format_id = StringName(
		String(data.get("serving_format_id", ""))
	)
	order.is_shared = bool(data.get("is_shared", false))
	order.quantity = int(data.get("quantity", 1))
	order.status = int(data.get("status", 0)) as Status
	order.failure_reason = int(data.get("failure_reason", 0)) as Failure
	order.price = int(data.get("price", 0))
	order.paid = bool(data.get("paid", false))
	order.destination_place_id = StringName(
		String(data.get("destination_place_id", ""))
	)

	return order
