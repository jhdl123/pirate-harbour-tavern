class_name ReturnToSeatBehaviour
extends ActivityBehaviour

## Sends the customer back to their own already-reserved chair.
##
## Entered directly (never scored) from [VisitTavernActivityBehaviour] once
## a tavern activity visit finishes, the same deterministic hand-off
## [OrderDrinkBehaviour] -> [DrinkBehaviour] already uses. No destination
## tag - the target is [Customer.reserved_chair], not something
## [DestinationBroker] needs to find, since the customer already knows
## exactly which chair is theirs for the whole visit.


func on_enter(context: ActivityContext) -> void:
	var customer: Customer = context.actor as Customer

	if customer == null:
		return

	customer.begin_returning_to_seat()
