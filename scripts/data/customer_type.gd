class_name CustomerType
extends Resource


@export_category("Identity")
@export var display_name: String = "Customer"
@export var customer_texture: Texture2D


@export_category("Spawning")

@export_range(0.0, 100.0, 0.1)
var spawn_weight: float = 1.0


@export_category("Movement")

@export var movement_speed: float = 120.0
@export var seat_movement_speed: float = 45.0


@export_category("Service")

## World minutes between sitting down and placing an order.
##
## World time, not real seconds: at the default rate one game minute is one
## real second, so these numbers feel identical to the old ones at normal speed
## while now pausing, scaling and skipping correctly.
@export_range(0, 600, 1)
var order_delay_minutes: int = 2

## World minutes a customer will wait to be served before leaving.
@export_range(0, 600, 1)
var patience_duration_minutes: int = 15


@export_category("Drink Preferences")

@export var available_drinks: Array[DrinkDefinition] = []

@export var preferred_drink: DrinkDefinition

@export_range(0.0, 1.0, 0.05)
var preferred_drink_chance: float = 0.75


@export_category("Economy")

@export_range(0.0, 5.0, 0.05)
var payment_multiplier: float = 1.0


@export_category("AI")

## Shared, authored traits for every customer of this type - seeds that
## customer's own CustomerNeeds at spawn. Optional: a type with no
## personality assigned still spawns fine, just with CustomerNeeds' plain
## defaults (see CustomerNeeds.seed_from's null check).
@export var personality: Personality

## Free-form grouping for future VIP handling (see docs/CUSTOMER_AI_SYSTEM.md's
## "Future VIPs" section) - e.g. &"regular", &"merchant", &"naval_officer".
## Not read anywhere yet.
@export var customer_category: StringName = &"regular"

## How much attention this customer type deserves when it eventually matters
## (queueing ahead of regulars, a future notification when one arrives).
## Not read anywhere yet.
@export_range(0, 10, 1)
var priority_level: int = 0

## Free-form "how special is this" score for a future VIP-detection or
## special-dialogue system to sort by. Not read anywhere yet.
@export var importance_score: float = 0.0


@export_category("Identity Foundation")

## Stable string ID, e.g. [code]&"merchant"[/code]. Preferred over enum
## ordering or resource paths everywhere the type needs naming in save data,
## diagnostics or events - renaming the .tres or reordering the array then
## costs nothing. Empty falls back to the resource filename.
@export var type_id: StringName = &""

@export_multiline var description: String = ""

## A disabled type is skipped by spawning entirely. Lets a type be authored
## and balanced before it is turned on, and lets one be switched off without
## deleting it from every spawner array.
@export var enabled: bool = true

## Free-form grouping tags, e.g. [code]&"seafarer"[/code],
## [code]&"local"[/code]. Read by [SocialCompatibility] for who gets on with
## whom, and by the existing Modifiers system's CUSTOMER_TYPE_WEIGHT /
## CUSTOMER_GROUP_SIZE / CUSTOMER_STAY_DURATION targets, which have been
## waiting on this field since Phase 4A.
@export var tags: Array[StringName] = []

## Broad social bucket used as an implicit tag, e.g. [code]&"crew"[/code].
@export var social_category: StringName = &""


@export_category("Identity Foundation - Economy")

## Multiplies the rolled starting money from CustomerAIBalanceConfig, on top
## of the personality's own wealth multiplier.
@export_range(0.1, 10.0, 0.05)
var starting_money_multiplier: float = 1.0

## How freely this type spends. Higher types tolerate expensive drinks.
@export_range(0.0, 1.0, 0.05)
var spending_willingness: float = 0.5

## How readily this type orders another drink once the first is done.
@export_range(0.0, 3.0, 0.05)
var reorder_tendency: float = 1.0

## How readily this type tips. No tipping mechanic consumes this yet - the
## existing payment_multiplier is a price multiplier, not a tip.
@export_range(0.0, 2.0, 0.05)
var tipping_tendency: float = 0.5


@export_category("Identity Foundation - Visit Behaviour")

## Weighted chances of each visit intention, keyed by
## [member VisitIntentConfig.intent_id]. An id with no entry is never
## rolled for this type; a type with an empty dictionary falls back to any
## enabled intent. See [method VisitIntentRegistry.select_weighted].
@export var visit_intent_weights: Dictionary = {}

## Chance this type arrives alone rather than as part of a group.
@export_range(0.0, 1.0, 0.05)
var solo_arrival_chance: float = 0.5

## Weighted group sizes, keyed by size as a string, e.g.
## [code]{"2": 3.0, "4": 1.0}[/code]. Empty means the existing group
## definition weighting decides, unchanged.
@export var group_size_weights: Dictionary = {}

## How well this type copes with a busy tavern. Lower types are pushed
## toward leaving sooner as crowding rises.
@export_range(0.0, 1.0, 0.05)
var crowding_tolerance: float = 0.5

## Multiplies patience_duration_minutes. Kept separate from the raw minutes
## so a type can be made impatient without re-authoring the base timing.
@export_range(0.1, 3.0, 0.05)
var waiting_tolerance_multiplier: float = 1.0

## How readily this type gives up and leaves when satisfaction is low.
@export_range(0.0, 3.0, 0.05)
var dissatisfaction_departure_tendency: float = 1.0

## Preference for a seat rather than standing. Used when both a chair and a
## standing place are available.
@export_range(0.0, 1.0, 0.05)
var seating_preference: float = 0.6

## Preference for standing at the bar. No bar-standing activity exists yet;
## authored now so adding one needs no change to this resource.
@export_range(0.0, 1.0, 0.05)
var bar_standing_preference: float = 0.3

## How readily this type moves to a different area mid-visit.
@export_range(0.0, 1.0, 0.05)
var wander_tendency: float = 0.4

## How strongly members of this type follow their group's decisions.
@export_range(0.0, 1.0, 0.05)
var group_conformity: float = 0.7


@export_category("Identity Foundation - Drink Behaviour")

## Preferred drink tags, matched against DrinkDefinition tags. Layered on
## top of the existing preferred_drink / available_drinks system rather than
## replacing it - the existing preference logic still runs first.
@export var preferred_drink_tags: Array[StringName] = []

## How willing this type is to accept a different drink when their
## preference is unavailable.
@export_range(0.0, 1.0, 0.05)
var substitution_willingness: float = 0.6

## Multiplies how fast this type drinks.
@export_range(0.1, 3.0, 0.05)
var drink_speed_multiplier: float = 1.0

## Multiplies the balance config's target drink count for this type.
@export_range(0.1, 4.0, 0.05)
var desired_drink_count_multiplier: float = 1.0

## How likely this type is to join a shared keg or group order.
@export_range(0.0, 2.0, 0.05)
var group_drink_affinity: float = 1.0


@export_category("Identity Foundation - Social Behaviour")

## Baseline sociability before personality jitter and intent offsets.
@export_range(0.0, 1.0, 0.05)
var base_sociability: float = 0.5

## Tags this type gets on with. A match raises compatibility.
@export var compatible_tags: Array[StringName] = []

## Tags this type dislikes. A match lowers compatibility, and a strong
## enough dislike suppresses approaching entirely.
@export var disliked_tags: Array[StringName] = []

## How readily this type approaches someone they did not arrive with.
@export_range(0.0, 1.0, 0.05)
var stranger_approach_willingness: float = 0.4

## How readily this type joins a conversation already in progress.
@export_range(0.0, 1.0, 0.05)
var conversation_join_willingness: float = 0.5

## Multiplies how long this type's conversations run.
@export_range(0.1, 3.0, 0.05)
var conversation_duration_multiplier: float = 1.0

## How strongly this type sticks to their own group socially.
@export_range(0.0, 1.0, 0.05)
var group_social_preference: float = 0.6


@export_category("Identity Foundation - Future Information System")

## Descriptive metadata only. None of these generate rumours, secrets or
## information records today - they exist so the future information system
## can ask "who in this room would know about shipping routes" without
## another customer refactor. See docs/CUSTOMER_IDENTITY_FOUNDATION.md.

## Subjects this type plausibly knows about, e.g. &"shipping", &"smuggling".
@export var information_domains: Array[StringName] = []

## Finer-grained knowledge tags within those domains.
@export var knowledge_tags: Array[StringName] = []

## What this type tends to talk about.
@export var conversation_topics: Array[StringName] = []

## How well this type keeps a secret.
@export_range(0.0, 1.0, 0.05)
var discretion_tendency: float = 0.5

## How much weight others give what this type says.
@export_range(0.0, 1.0, 0.05)
var credibility_tendency: float = 0.5

## How much this type notices going on around them.
@export_range(0.0, 1.0, 0.05)
var observant_tendency: float = 0.5

## How much this type conceals their own business.
@export_range(0.0, 1.0, 0.05)
var secrecy_tendency: float = 0.5


## Stable id for this type, falling back to the resource filename so a type
## authored before type_id existed still reports something usable rather
## than an empty string.
func get_type_id() -> StringName:
	if not type_id.is_empty():
		return type_id

	if resource_path.is_empty():
		return &"unknown"

	return StringName(resource_path.get_file().get_basename())


func has_tag(tag: StringName) -> bool:
	return tags.has(tag) or social_category == tag
