class_name CustomerIdentity
extends RefCounted

## One customer's identity for one visit: their type, their own personality
## values, their visit intention, and who they have talked to tonight.
##
## [b]A RefCounted, not a Resource.[/b] This is created per spawned customer
## and dies with them; making it a Resource would invite saving hundreds of
## them to disk, which the brief explicitly rules out. The authored data it
## reads ([CustomerType], [Personality], [VisitIntentConfig]) stays in .tres
## where it belongs.
##
## [b]Personality is jittered, not copied.[/b] [member personality] is a
## private duplicate of the type's authored [Personality] with each trait
## nudged within [member Personality.trait_variance]. Before this existed
## every sailor shared one [Personality] resource, scored identically and
## therefore walked an identical activity sequence - the single largest
## cause of customers looking like clones. Generated once, in
## [method initialise], and never changed again during the visit: temporary
## state belongs in [CustomerNeeds], which is seeded from this and then runs
## independently.
##
## [b]Determinism.[/b] Everything random here goes through [member rng].
## Seed it (see [method initialise]) and the same customer index produces the
## same traits and the same intent every run, which is what the deterministic
## diagnostic mode and the personality tests rely on.

## Emitted once, after traits and intent are settled. Payload is plain data
## rather than node references so a future information system can consume it
## without touching the scene tree.
signal identity_initialised(payload: Dictionary)

## Emitted when the visit intention is chosen.
signal visit_intention_selected(payload: Dictionary)


## Authored type this customer spawned as. Never null in normal play; a null
## type degrades to plain defaults rather than crashing, so a test harness
## can build a customer without authoring resources.
var customer_type: CustomerType = null

## This customer's own jittered traits. See the class doc comment.
var personality: Personality = null

## Why they came tonight. May be null when no registry was supplied - every
## reader treats null as "no bias", so the customer behaves exactly as they
## did before intents existed.
var visit_intent: VisitIntentConfig = null

## Stable identifier used in events and diagnostics.
var customer_id: int = 0

## Group this customer belongs to, or an empty StringName when solo.
var group_id: StringName = &""

## True when this customer's intent was inherited from their group rather
## than rolled individually - see [method adopt_group_intent].
var intent_inherited_from_group: bool = false

var rng: RandomNumberGenerator = null

## Visit-level social familiarity. Keyed by the other customer's id;
## each value is a Dictionary of interaction_count, last_interaction_minutes
## and affinity. Cleared when the customer leaves - nothing here persists
## between days, which the brief explicitly defers.
var _social_memory: Dictionary = {}


## Builds the identity. Call once, immediately after the customer is spawned
## and before [method CustomerNeeds.seed_from].
##
## [param deterministic_seed] of 0 means "use a random seed"; any non-zero
## value makes traits and intent reproducible. The developer menu's
## deterministic mode passes the customer index so a stress run repeats
## exactly.
func initialise(
	type: CustomerType,
	intent_registry: VisitIntentRegistry,
	id: int,
	deterministic_seed: int = 0
) -> void:
	customer_type = type
	customer_id = id

	rng = RandomNumberGenerator.new()

	if deterministic_seed != 0:
		rng.seed = deterministic_seed
	else:
		rng.randomize()

	personality = _build_personality()

	if intent_registry != null and customer_type != null:
		visit_intent = intent_registry.select_weighted(
			customer_type.visit_intent_weights, rng
		)
	elif intent_registry != null:
		visit_intent = intent_registry.select_weighted({}, rng)

	identity_initialised.emit(build_event_payload())

	if visit_intent != null:
		visit_intention_selected.emit(build_event_payload())


## Replaces an individually rolled intent with the group's shared one.
##
## Groups own their intention (brief section 8): letting each member roll
## their own would let one member of a celebrating crew decide they came for
## a quiet meeting and drag the group's scoring apart. Individual variation
## still survives through [member personality], which is never overwritten.
func adopt_group_intent(intent: VisitIntentConfig) -> void:
	if intent == null:
		return

	visit_intent = intent
	intent_inherited_from_group = true

	visit_intention_selected.emit(build_event_payload())


## Duplicate of the type's authored personality with per-trait jitter.
##
## [method Resource.duplicate] rather than a hand-written field-by-field copy
## on purpose: a trait added to [Personality] later is jittered automatically
## if it is listed in [method Personality.get_variable_trait_names], and is
## simply copied unchanged if it is not. No change needed here either way.
func _build_personality() -> Personality:
	var source: Personality = null

	if customer_type != null:
		source = customer_type.personality

	if source == null:
		# No authored personality: plain defaults, still a private instance
		# so nothing can leak between customers.
		return Personality.new()

	return source.create_visit_profile(rng)


## Effective sociability for this visit: personality plus intent offset.
## Clamped, so a strongly antisocial intent on an already shy customer
## cannot produce a negative that would invert a downstream multiplier.
func get_sociability() -> float:
	var base: float = 0.5

	if personality != null:
		base = personality.social_tendency

	if visit_intent != null:
		base += visit_intent.sociability_offset

	return clampf(base, 0.0, 1.0)


## Effective entertainment interest for this visit.
func get_entertainment_interest() -> float:
	var base: float = 0.5

	if personality != null:
		base = personality.entertainment_interest

	if visit_intent != null:
		base += visit_intent.entertainment_offset

	return clampf(base, 0.0, 1.0)


## Effective privacy preference for this visit. Higher means the customer
## would rather be left alone.
func get_privacy_preference() -> float:
	var base: float = 0.5

	if personality != null:
		base = personality.privacy_preference

	if visit_intent != null:
		base += visit_intent.privacy_offset

	return clampf(base, 0.0, 1.0)


## Score offset this customer's intent applies to one activity, or 0.0 when
## they have no intent.
func get_activity_bias(activity_id: StringName) -> float:
	if visit_intent == null:
		return 0.0

	return visit_intent.get_activity_bias(activity_id)


## Weight offset this customer's intent applies to one stage-2 motivation,
## or 0.0 when they have no intent. Mirrors [method get_activity_bias] one
## stage earlier - see CUSTOMER_MODEL.md §4.
func get_motivation_bias(motivation_id: StringName) -> float:
	if visit_intent == null:
		return 0.0

	return visit_intent.get_motivation_bias(motivation_id)


## Tags used for social compatibility and future information routing:
## the type's own tags plus its social category.
func get_tags() -> Array[StringName]:
	var tags: Array[StringName] = []

	if customer_type == null:
		return tags

	for tag: StringName in customer_type.tags:
		if not tags.has(tag):
			tags.append(tag)

	if not customer_type.social_category.is_empty():
		if not tags.has(customer_type.social_category):
			tags.append(customer_type.social_category)

	return tags


func get_type_id() -> StringName:
	if customer_type == null:
		return &""

	return customer_type.type_id


func get_intent_id() -> StringName:
	if visit_intent == null:
		return &""

	return visit_intent.intent_id


## Records that this customer interacted with another during this visit.
## [param affinity_delta] is signed - a pleasant conversation raises it, a
## rebuffed approach lowers it.
func record_interaction(
	other_customer_id: int,
	world_minutes: float,
	affinity_delta: float = 0.0
) -> void:
	var entry: Dictionary = _social_memory.get(other_customer_id, {
		"interaction_count": 0,
		"last_interaction_minutes": 0.0,
		"affinity": 0.0,
	})

	entry["interaction_count"] = int(entry["interaction_count"]) + 1
	entry["last_interaction_minutes"] = world_minutes
	entry["affinity"] = clampf(
		float(entry["affinity"]) + affinity_delta, -1.0, 1.0
	)

	_social_memory[other_customer_id] = entry


func has_interacted_with(other_customer_id: int) -> bool:
	return _social_memory.has(other_customer_id)


func get_affinity(other_customer_id: int) -> float:
	if not _social_memory.has(other_customer_id):
		return 0.0

	return float(_social_memory[other_customer_id]["affinity"])


func get_interaction_count(other_customer_id: int) -> int:
	if not _social_memory.has(other_customer_id):
		return 0

	return int(_social_memory[other_customer_id]["interaction_count"])


## Every customer id this customer has interacted with tonight.
func get_social_partners() -> Array:
	return _social_memory.keys()


## Stable-data payload shared by every identity event. Deliberately ids and
## values only - no node references - so a future information system can
## queue these without keeping customers alive.
func build_event_payload() -> Dictionary:
	return {
		"customer_id": customer_id,
		"customer_type_id": String(get_type_id()),
		"group_id": String(group_id),
		"visit_intent_id": String(get_intent_id()),
		"intent_inherited_from_group": intent_inherited_from_group,
		"tags": _tags_as_strings(),
		"sociability": get_sociability(),
		"discretion": get_discretion(),
	}


## Discretion tendency, read straight from the type. Descriptive metadata
## for the future information system; nothing consumes it yet.
func get_discretion() -> float:
	if customer_type == null:
		return 0.5

	return customer_type.discretion_tendency


## Full trait/intent dump for the behaviour diagnostics report.
func get_diagnostics() -> Dictionary:
	var traits: Dictionary = {}

	if personality != null:
		for trait_name: StringName in Personality.get_variable_trait_names():
			traits[String(trait_name)] = personality.get(trait_name)

	return {
		"customer_id": customer_id,
		"customer_type_id": String(get_type_id()),
		"customer_type_name": (
			customer_type.display_name if customer_type != null else ""
		),
		"group_id": String(group_id),
		"visit_intent_id": String(get_intent_id()),
		"intent_inherited_from_group": intent_inherited_from_group,
		"tags": _tags_as_strings(),
		"personality_traits": traits,
		"effective_sociability": get_sociability(),
		"effective_entertainment_interest": get_entertainment_interest(),
		"effective_privacy_preference": get_privacy_preference(),
		"social_partner_count": _social_memory.size(),
		"social_partners": _social_memory.keys(),
	}


func _tags_as_strings() -> Array:
	var result: Array = []

	for tag: StringName in get_tags():
		result.append(String(tag))

	return result
