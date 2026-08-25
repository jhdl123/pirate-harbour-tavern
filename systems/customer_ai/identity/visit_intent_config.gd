class_name VisitIntentConfig
extends Resource

## Why one customer (or one group) came to the tavern tonight.
##
## A plain data [Resource], authored in the Inspector like [Personality] and
## [CustomerType]. An intent never executes anything itself - it only shifts
## the numbers the existing [CustomerBrain] scoring already reads, so adding
## an intent needs a new .tres and nothing else.
##
## [b]Intents bias, they do not gate.[/b] Mandatory lifecycle work (ordering,
## being served, paying, leaving) stays under Customer's state machine and is
## never scored against an intent - see the Architecture Principle in
## docs/CUSTOMER_IDENTITY_FOUNDATION.md. An intent that could block a
## customer from ever ordering would be a bug, not a configuration choice.
##
## Stable [member intent_id] strings rather than an enum, deliberately: a
## saved game or a .tres holding &"quick_drink" keeps meaning the same thing
## no matter how many intents are added before or after it.


@export_category("Identity")

## Stable ID, e.g. [code]&"quick_drink"[/code]. Referenced by
## [member CustomerType.visit_intent_weights] and written into diagnostics.
@export var intent_id: StringName = &""

@export var display_name: String = "Unnamed Intent"

@export_multiline var description: String = ""

## A disabled intent is never selected, even if a type still weights it.
@export var enabled: bool = true


@export_category("Visit Shape")

## Multiplies the customer's rolled visit duration. A quick drink shortens
## the visit; passing time lengthens it.
@export_range(0.1, 4.0, 0.05)
var visit_duration_multiplier: float = 1.0

## Multiplies the customer's target drink count. Never overrides
## [member CustomerAIBalanceConfig.absolute_maximum_drinks_per_visit].
@export_range(0.1, 4.0, 0.05)
var drink_count_multiplier: float = 1.0

## Multiplies thirst-driven order utility - how eagerly this visit reorders.
@export_range(0.1, 4.0, 0.05)
var reorder_multiplier: float = 1.0


@export_category("Disposition")

## Added to the customer's sociability for this visit, after personality.
## Signed: a quiet meeting should push this negative.
@export_range(-1.0, 1.0, 0.05)
var sociability_offset: float = 0.0

## Added to entertainment interest for this visit.
@export_range(-1.0, 1.0, 0.05)
var entertainment_offset: float = 0.0

## Added to privacy preference - higher means "leave me alone".
@export_range(-1.0, 1.0, 0.05)
var privacy_offset: float = 0.0

## How strongly a group member sticks with their group rather than
## wandering off alone. 1.0 is the existing group-first behaviour.
@export_range(0.0, 2.0, 0.05)
var group_cohesion_multiplier: float = 1.0


@export_category("Activity Bias")

## Per-activity score offsets applied on top of the activity's own
## conditions, keyed by [member ActivityDefinition.activity_id].
##
## Authored as a plain Dictionary so a new activity needs no change here -
## an unknown key is ignored, and an activity with no entry scores exactly
## as it does today. See [method get_activity_bias].
@export var activity_score_offsets: Dictionary = {}


@export_category("Motivation Bias")

## Per-motivation weight offsets applied inside [CustomerBrain]'s stage-2
## motivation selection (CUSTOMER_MODEL.md §4) - the same flat-offset shape
## as [member activity_score_offsets] above, just read one stage earlier
## and keyed by motivation id (&"thirst"/&"social"/&"entertainment"/
## &"relaxation") rather than activity id. Optional and additive: empty
## means this intent has no opinion on which motivation wins and stage 2
## runs on needs and personality alone. See [method get_motivation_bias].
@export var motivation_weight_offsets: Dictionary = {}


@export_category("Departure")

## Multiplies how strongly falling satisfaction pushes toward leaving.
## Higher means "gives up on a bad night sooner".
@export_range(0.1, 4.0, 0.05)
var dissatisfaction_departure_multiplier: float = 1.0


@export_category("Future Information System")

## Descriptive only. What this visit is nominally about, for a future
## information/rumour system to query. Generates nothing today.
@export var topic_tags: Array[StringName] = []


## Score offset for one activity, or 0.0 when this intent has no opinion
## about it. Tolerates a missing or malformed entry rather than throwing -
## a half-authored .tres should bias nothing, not break the customer.
func get_activity_bias(activity_id: StringName) -> float:
	if activity_score_offsets.is_empty():
		return 0.0

	var key: String = String(activity_id)

	if not activity_score_offsets.has(key):
		return 0.0

	var value: Variant = activity_score_offsets[key]

	if value is float or value is int:
		return float(value)

	return 0.0


## Weight offset for one motivation, or 0.0 when this intent has no
## opinion about it - same tolerance-for-malformed-data contract as
## [method get_activity_bias].
func get_motivation_bias(motivation_id: StringName) -> float:
	if motivation_weight_offsets.is_empty():
		return 0.0

	var key: String = String(motivation_id)

	if not motivation_weight_offsets.has(key):
		return 0.0

	var value: Variant = motivation_weight_offsets[key]

	if value is float or value is int:
		return float(value)

	return 0.0


## True when this resource is complete enough to be selected.
func validate_or_warn() -> bool:
	if intent_id.is_empty():
		push_warning(
			"VisitIntentConfig '%s' has no intent_id and will be ignored."
			% resource_path
		)
		return false

	return true
