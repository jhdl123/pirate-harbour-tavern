class_name VisitTavernActivityBehaviour
extends ActivityBehaviour

## Sends the customer to whatever [TavernActivityPoint] [CustomerBrain]
## already reserved for this activity (via [member ActivityDefinition.
## destination_tag] - see [ActivityContext.reserved_destination]'s doc
## comment), and hands off to [code]&"return_to_seat"[/code] once the visit
## is done.
##
## Does not reserve the initiator's own slot - [CustomerBrain._enter]
## already did that generically, the same way it would for any
## destination-tagged activity. When [member ActivityDefinition.
## max_participants] allows more than one (Darts: 1-2), this also makes a
## single, synchronous attempt to co-opt a second participant: find a
## free second slot on the same point, find a nearby available customer via
## [method Customer.find_nearby_activity_partner], and if both succeed,
## reserve the second slot for them and start them alongside the initiator.
## No waiting or timeout - if nobody suitable is nearby right now, this
## proceeds solo immediately, the same way [SocialiseAtSeatBehaviour]'s
## partner search already does. Reusable for any future multi-slot
## [TavernActivityPoint] (cards, dice) with zero changes here - only
## [ActivityDefinition.max_participants] and the target point's own slot
## count differ.


## How far to look for a second participant, in pixels. Mirrors
## [member CustomerAIBalanceConfig.social_discovery_range_pixels]'s existing
## convention for this kind of number.
@export_range(0.0, 500.0, 5.0)
var partner_search_range_pixels: float = 220.0


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

	var my_slot: TavernActivitySlot = point.get_slot_for(reservable)

	if _try_start_with_partner(context, customer, point, my_slot):
		return

	customer.begin_visiting_activity(point, my_slot)


## Attempts to co-opt a second participant. Returns true (having already
## started both customers) only when a free second slot, a nearby available
## customer, and a successful reservation for them all line up - otherwise
## returns false and leaves everything unchanged for the caller to fall
## back to the ordinary solo path.
func _try_start_with_partner(
	context: ActivityContext,
	customer: Customer,
	point: TavernActivityPoint,
	my_slot: TavernActivitySlot
) -> bool:
	if context.activity == null or context.activity.max_participants <= 1:
		return false

	var second_slot: TavernActivitySlot = point.get_free_slot()

	if second_slot == null or second_slot.reservable == null:
		return false

	var partner: Customer = customer.find_nearby_activity_partner(
		partner_search_range_pixels
	)

	if partner == null:
		return false

	if not second_slot.reservable.reserve(partner):
		return false

	customer.begin_visiting_activity(point, my_slot)
	partner.begin_visiting_activity_as_partner(
		point, second_slot, context.activity, customer
	)

	return true
