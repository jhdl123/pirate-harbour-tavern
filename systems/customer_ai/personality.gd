class_name Personality
extends Resource

## Authored personality traits shared by every customer of one [CustomerType].
##
## A plain data [Resource] - the same design already used for
## [ItemDefinition] and [DrinkDefinition]: designers tweak these in the
## Inspector, and nothing here changes at runtime. A [CustomerType] holds one,
## and [method CustomerNeeds.seed_from] reads it once, at spawn, to seed that
## customer's own [CustomerNeeds] - after that the two are independent, so a
## generous customer type can still produce one miserable customer having a
## bad night.
##
## Traits are intentionally coarse (0-1 sliders) and few. This is the seam
## future activities score against - "would a sociable customer want to join
## that conversation", "would a temperate customer stop drinking sooner" -
## not a finished personality model. A trait with no reader yet is still
## useful architecture: adding the reader later needs no change here.


@export_category("Starting Needs")

## Seeds [member CustomerNeeds.mood] at spawn.
@export_range(0.0, 1.0, 0.05)
var baseline_mood: float = 0.7

## Seeds [member CustomerNeeds.energy] at spawn.
@export_range(0.0, 1.0, 0.05)
var baseline_energy: float = 1.0

## Seeds [member CustomerNeeds.social_tendency] at spawn. Also read directly
## by anything that wants the customer's baseline disposition rather than
## tonight's fluctuating need - see [member CustomerNeeds.social_tendency]'s
## doc comment for the distinction.
@export_range(0.0, 1.0, 0.05)
var social_tendency: float = 0.5


@export_category("Traits")

## How freely this customer spends and tips. Unused by any behaviour yet;
## the intended reader is a future tipping/economy activity.
@export_range(0.0, 1.0, 0.05)
var generosity: float = 0.5

## How much this customer moderates their drinking. Higher values should
## eventually make intoxication climb more slowly. Unused today.
@export_range(0.0, 1.0, 0.05)
var temperance: float = 0.5

## How readily this customer investigates something new (a notice board, a
## travelling merchant, an unfamiliar game). Unused today.
@export_range(0.0, 1.0, 0.05)
var curiosity: float = 0.5

## How willing this customer is to get involved in something risky (a fight,
## a wager, a dare). Unused today.
@export_range(0.0, 1.0, 0.05)
var courage: float = 0.5


@export_category("Phase 2B - Visit Attribute Biases")

## Multiplies the configured starting-money range - "wealthy" > 1.0,
## "frugal" or poor < 1.0. See CustomerAIBalanceConfig for the base range.
@export_range(0.1, 3.0, 0.05)
var wealth_multiplier: float = 1.0

## Multiplies Order Drink's thirst-driven utility - "heavy drinker" > 1.0,
## "light drinker" < 1.0. Does not affect the hard maximum-drinks safeguard,
## only how strongly thirst pulls this customer toward ordering.
@export_range(0.1, 3.0, 0.05)
var drink_appetite: float = 1.0

## Multiplies the configured intoxication-gate threshold Order Drink and
## Leave score against - a higher tolerance lets a customer order (and
## avoid being pushed toward Leave) a little longer before the same
## alcohol_strength catches up with them. Does not change how fast
## intoxication itself rises - see temperance for that.
@export_range(0.5, 2.0, 0.05)
var intoxication_tolerance: float = 1.0

## Multiplies the configured visit-duration range - "relaxed" > 1.0,
## "hurried" < 1.0.
@export_range(0.3, 3.0, 0.05)
var visit_duration_multiplier: float = 1.0


@export_category("Phase 2C - Drink Limit Preparation")

## Multiplies CustomerAIBalanceConfig.maximum_drinks_per_visit to get this
## customer's typical target - "heavy drinker" > 1.0, "light drinker" <
## 1.0. Always clamped to CustomerAIBalanceConfig.
## absolute_maximum_drinks_per_visit regardless of this value - see
## Customer.get_activity_flags()'s under_drink_limit and
## docs/CUSTOMER_AI_SYSTEM.md's Phase 2C "Drink-limit preparation" section.
@export_range(0.2, 3.0, 0.05)
var preferred_drink_count_multiplier: float = 1.0


@export_category("Phase 2C - Social Behaviour")

## How readily this customer travels to a Tavern Activity Point rather than
## staying near their chair - "impatient"/"hurried" customers should be
## lower. Read by Visit Tavern Activity's distance scoring alongside the
## raw distance itself; unlike social_tendency this is specifically about
## willingness to leave the chair, not sociability.
@export_range(0.1, 2.0, 0.05)
var travel_willingness: float = 1.0

## Structural placeholders for future personality dimensions the brief asks
## to prepare for (gambler, competitive, musical, aggressive,
## information-seeking) - not read anywhere yet. Kept as a free-form tag
## array rather than one bool per trait so a future trait needs no change
## to this class, only a new tag and a condition that checks for it -
## the same StringName-tag pattern CustomerNeeds.favourite_activity_tags
## already uses.
@export var future_trait_tags: Array[StringName] = []


@export_category("Customer Identity Foundation - New Traits")

## How readily this customer seeks out entertainment activities. Read via
## [method CustomerIdentity.get_entertainment_interest], which layers the
## visit intent's offset on top.
@export_range(0.0, 1.0, 0.05)
var entertainment_interest: float = 0.5

## How much this customer wants to be left alone. Higher values should make
## a customer avoid crowded areas and decline approaches - see
## [SocialCompatibility].
@export_range(0.0, 1.0, 0.05)
var privacy_preference: float = 0.5

## How strongly a group member stays with their group rather than wandering
## off on their own.
@export_range(0.0, 1.0, 0.05)
var group_loyalty: float = 0.7

## How readily this customer starts something with a stranger, as opposed
## to only talking to people they arrived with.
@export_range(0.0, 1.0, 0.05)
var approaches_strangers: float = 0.4

## How quickly this customer gets bored of the activity they are currently
## doing. Higher values shorten activity durations - see
## [method ActivityDefinition.roll_duration_minutes].
@export_range(0.0, 1.0, 0.05)
var restlessness: float = 0.5

## How cautious this customer is about spending. Higher values bias them
## toward cheaper drinks and fewer reorders.
@export_range(0.0, 1.0, 0.05)
var spending_caution: float = 0.5


@export_category("Customer Identity Foundation - Variation")

## How far each customer's own traits may drift from these authored values.
##
## [b]This is what stops customers of one type being clones.[/b] Every
## spawned customer gets a private duplicate of this resource with each
## variable trait nudged by up to this fraction of its own range - so one
## authored "Sailor" personality produces a crowd of individually different
## sailors rather than fifty identical ones. 0.0 restores the old exact-copy
## behaviour.
@export_range(0.0, 0.5, 0.01)
var trait_variance: float = 0.15


## Every trait [method create_visit_profile] is allowed to jitter.
##
## Traits are listed explicitly rather than discovered from the property
## list, because the multiplier traits ([member wealth_multiplier] and
## friends) have deliberately asymmetric ranges that a generic 0-1 walk
## would corrupt - those are jittered proportionally instead, in
## [method _jitter_multiplier].
static func get_variable_trait_names() -> Array[StringName]:
	return [
		&"baseline_mood",
		&"baseline_energy",
		&"social_tendency",
		&"generosity",
		&"temperance",
		&"curiosity",
		&"courage",
		&"entertainment_interest",
		&"privacy_preference",
		&"group_loyalty",
		&"approaches_strangers",
		&"restlessness",
		&"spending_caution",
	]


## Multiplier traits, jittered proportionally rather than as 0-1 values.
static func get_variable_multiplier_names() -> Array[StringName]:
	return [
		&"wealth_multiplier",
		&"drink_appetite",
		&"intoxication_tolerance",
		&"visit_duration_multiplier",
		&"preferred_drink_count_multiplier",
		&"travel_willingness",
	]


## A private, individually varied copy of this personality for one customer.
##
## The returned resource is never shared: [method Resource.duplicate] gives
## each customer their own instance, so a customer whose mood drops during a
## bad visit cannot drag down every other customer of the same type - which
## is exactly what would have happened if the authored resource were used
## directly.
##
## [param rng] is supplied by the caller so determinism stays under
## [CustomerIdentity]'s control rather than being decided here.
func create_visit_profile(rng: RandomNumberGenerator) -> Personality:
	var profile: Personality = duplicate() as Personality

	if profile == null:
		return Personality.new()

	if trait_variance <= 0.0 or rng == null:
		return profile

	for trait_name: StringName in get_variable_trait_names():
		var value: Variant = profile.get(trait_name)

		if not (value is float or value is int):
			continue

		profile.set(
			trait_name,
			clampf(
				float(value) + rng.randf_range(
					-trait_variance, trait_variance
				),
				0.0,
				1.0
			)
		)

	for multiplier_name: StringName in get_variable_multiplier_names():
		var value: Variant = profile.get(multiplier_name)

		if not (value is float or value is int):
			continue

		profile.set(
			multiplier_name,
			_jitter_multiplier(float(value), rng)
		)

	return profile


## Jitters a multiplier by a fraction of itself, then floors it at a small
## positive number. Proportional rather than absolute so a 0.5 multiplier
## and a 2.0 multiplier both vary by a sensible amount, and floored because
## a multiplier of zero would silently disable whatever reads it.
func _jitter_multiplier(
	value: float,
	rng: RandomNumberGenerator
) -> float:
	var spread: float = absf(value) * trait_variance

	return maxf(0.05, value + rng.randf_range(-spread, spread))
