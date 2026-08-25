class_name SocialiseAtSeatBehaviour
extends ActivityBehaviour

## Talks with a nearby seated customer without leaving the chair.
##
## Finds its partner itself, at [method on_enter] time, rather than through
## a condition-time domain flag alone - a flag only needs to answer "is
## anyone available" cheaply for scoring; actually picking one (and telling
## it it is being socialised with) only needs to happen for the customer
## that wins the decision. See [ActivityContext.domain_flags]'
## [code]has_social_partner[/code] for the scoring-time check and
## [method Customer.find_nearby_social_partner] for the shared search both
## use.
##
## One customer can start this without its partner having chosen anything -
## the partner is only notified (optionally) that it is being talked to; it
## keeps making its own decisions independently, per the brief's "do not
## require both customers to select the activity at exactly the same time".


@export_category("Duration")
@export_range(1.0, 30.0, 1.0)
var minimum_duration_minutes: float = 3.0
@export_range(1.0, 30.0, 1.0)
var maximum_duration_minutes: float = 8.0


@export_category("Range")
## World pixels - see Customer.find_nearby_social_partner().
@export_range(16.0, 1000.0, 8.0)
var social_range_pixels: float = 220.0


@export_category("Notification")
## Whether to tell the partner it is being socialised with (currently just
## a debug-visible flag on the partner, not new partner behaviour - see the
## class doc comment on this phase's deliberately simple visual goal).
@export var notify_partner: bool = true


@export_category("Effects")
## Added to CustomerNeeds.mood on completion, for the initiating customer.
@export_range(0.0, 1.0, 0.01)
var satisfaction_gain: float = 0.1

## Added to CustomerNeeds.mood on completion, for the partner - only
## applied if a partner was actually found; see Customer._on_socialise_finished().
@export_range(0.0, 1.0, 0.01)
var partner_satisfaction_gain: float = 0.05

## Added to CustomerNeeds.social on completion - see that need's doc
## comment on why this decays per-decision rather than on its own timer.
## Renamed from `engagement_gain` when CustomerNeeds.engagement was split
## into social/entertainment/relaxation - see
## docs/history/2026-08-25_CUSTOMER_ARCHITECTURE_AUDIT.md.
@export_range(0.0, 1.0, 0.01)
var social_gain: float = 0.25


func on_enter(context: ActivityContext) -> void:
	var customer: Customer = context.actor as Customer

	if customer == null:
		return

	var partner: Customer = customer.find_nearby_social_partner(
		social_range_pixels
	)

	customer.begin_socialising(
		partner,
		minimum_duration_minutes,
		maximum_duration_minutes,
		notify_partner,
		satisfaction_gain,
		partner_satisfaction_gain,
		social_gain
	)
