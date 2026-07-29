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
