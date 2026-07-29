class_name VisitTavernActivityBehaviour
extends ActivityBehaviour

## Sends the customer to whatever [TavernActivityPoint] [CustomerBrain]
## already reserved for this activity (via [member ActivityDefinition.
## destination_tag] - see [ActivityContext.reserved_destination]'s doc
## comment), and hands off to [code]&"return_to_seat"[/code] once the visit
## is done.
##
## Does not reserve anything itself - [CustomerBrain._enter] already did
## that generically, the same way it would for any destination-tagged
## activity. This behaviour's only job is the actual visit: travel there,
## wait out the configured duration, apply the point's configured effects,
## then leave. Reusable for any future [TavernActivityPoint] (cards,
## musicians, a notice board) with zero changes here - only the
## [ActivityDefinition.destination_tag] and the target point's own config
## differ.


func on_enter(context: ActivityContext) -> void:
	var customer: Customer = context.actor as Customer

	if customer == null:
		return

	var reservable: Reservable = context.reserved_destination

	if reservable == null:
		customer.abandon_activity_visit(&"no_reserved_destination")
		return

	var point: TavernActivityPoint = reservable.get_parent() as TavernActivityPoint

	if point == null:
		customer.abandon_activity_visit(&"reserved_destination_not_a_activity_point")
		return

	customer.begin_visiting_activity(point)
