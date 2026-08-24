class_name CustomerAIBalanceConfig
extends Resource

## Every Phase 2B spawn-range and need-change value in one place.
##
## Requirement 9 asks that gameplay constants not be scattered across
## scripts. Per-activity scoring thresholds and weights still live on their
## own [ActivityCondition] resources (that data already had a home from
## Phase 1/2A, and moving it here would separate a condition's gate from its
## score) - this resource is specifically for values that describe a
## customer's *starting* state and how simple events nudge it afterward.
## Intoxication's leave/order threshold intentionally lives on the relevant
## [NeedThresholdCondition] resources instead of here, so there is exactly
## one authoritative place for that number rather than two that could drift
## apart - see docs/CUSTOMER_AI_SYSTEM.md.


@export_category("Starting Money")
@export var minimum_starting_money: int = 15
@export var maximum_starting_money: int = 45


@export_category("Visit Duration")

## World minutes, before Personality.visit_duration_multiplier is applied.
## How many orders a customer may give up waiting for before it leaves.
##
## 1 reproduces the old behaviour, where a single slow serve ejected the
## customer. Above 1, being ignored repeatedly still empties the room but one
## slow pint does not.
## World minutes before a visit ends at which the customer is given one
## chance to decide it is done, rather than being ejected by the timer.
## Should match leave_end_of_visit_pressure.tres's pressure_window_minutes.
@export var leave_decision_window_minutes: int = 30

## How often, in world minutes, the customer re-weighs leaving once inside the
## end-of-visit window. The pressure bonus ramps as the visit runs out, so one
## check at the start of the window is too early to change any decision.
@export var leave_decision_recheck_minutes: int = 10

@export var abandoned_orders_before_leaving: int = 3

@export var minimum_visit_duration_minutes: int = 20
@export var maximum_visit_duration_minutes: int = 90


@export_category("Starting Thirst")
@export_range(0.0, 1.0, 0.05)
var minimum_starting_thirst: float = 0.4
@export_range(0.0, 1.0, 0.05)
var maximum_starting_thirst: float = 0.9


@export_category("Starting Satisfaction")
## Satisfaction is implemented as CustomerNeeds.mood, carried over unchanged
## from Phase 1 naming - see CustomerNeeds' class doc comment.
@export_range(0.0, 1.0, 0.05)
var minimum_starting_satisfaction: float = 0.6
@export_range(0.0, 1.0, 0.05)
var maximum_starting_satisfaction: float = 0.9


@export_category("Satisfaction Changes")
@export_range(0.0, 1.0, 0.01)
var satisfaction_gain_on_service: float = 0.10
@export_range(0.0, 1.0, 0.01)
var satisfaction_loss_on_patience_expiry: float = 0.30


@export_category("Thirst and Intoxication")
@export_range(0.0, 1.0, 0.01)
var thirst_reduction_per_drink: float = 0.35

## Scales alcohol_strength -> actual CustomerNeeds.intoxication gained per
## drink, before Personality.temperance is applied. Kept small so the
## default maximum_drinks_per_visit (2) rarely reaches a gating threshold on
## its own - raise this or maximum_drinks_per_visit to test intoxication
## gating specifically.
@export_range(0.0, 1.0, 0.01)
var intoxication_gain_scale: float = 0.15


@export_category("Visit Safeguard")
## The *typical* drink limit before Personality.preferred_drink_count_multiplier
## is applied - see "Drink-limit preparation" in docs/CUSTOMER_AI_SYSTEM.md's
## Phase 2C section. Renamed in spirit only; the field itself is unchanged
## from Phase 2B so existing saved values keep working.
@export_range(1, 10, 1)
var maximum_drinks_per_visit: int = 2

## Phase 2C: hard safety ceiling no personality multiplier can ever push a
## customer past, regardless of how "heavy drinker" their
## preferred_drink_count_multiplier is configured. "Do not allow unlimited
## ordering" - see Customer.get_activity_flags()'s under_drink_limit.
@export_range(1, 20, 1)
var absolute_maximum_drinks_per_visit: int = 5


@export_category("Phase 2C - Engagement")
## How much CustomerNeeds.engagement decays each time a decision is made -
## see CustomerNeeds.decay_engagement()'s doc comment for why this happens
## per-decision rather than on a timer.
@export_range(0.0, 0.5, 0.01)
var engagement_decay_per_decision: float = 0.08


@export_category("Phase 2C - Social Discovery")
## World pixels used by Customer.get_activity_flags()'s has_social_partner
## eligibility check. Kept independent from SocialiseAtSeatBehaviour's own
## social_range_pixels (which actually picks the partner once the activity
## starts) rather than cross-referencing it, the same way
## leave_visit_time_scoring.tres's threshold is a separate number from
## maximum_visit_duration_minutes above - keep the two roughly matched when
## tuning either.
@export_range(16.0, 1000.0, 8.0)
var social_discovery_range_pixels: float = 220.0
