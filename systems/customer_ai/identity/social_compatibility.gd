class_name SocialCompatibility
extends RefCounted

## Whether two customers would get on, for this visit only.
##
## [b]Deliberately not a relationship system.[/b] Nothing here persists
## between days - that is explicitly deferred. What this scores is "would
## these two, as they are right now, plausibly talk to each other", from
## authored type tags plus whatever has already happened tonight in
## [CustomerIdentity]'s visit-level social memory.
##
## [b]All static.[/b] Compatibility is a pure function of two identities and
## the world clock; giving it instance state would invite a per-customer
## cache that then has to be invalidated when tags or affinity change.
##
## The score runs -1.0 (would actively avoid) to 1.0 (would seek out), with
## 0.0 meaning indifferent. Callers decide their own thresholds - see
## [constant APPROACH_THRESHOLD] for the suggested one.


## Below this, a customer will not approach a stranger. Not enforced here -
## exposed so every caller uses the same number rather than inventing one.
const APPROACH_THRESHOLD: float = 0.15

## Below this, a customer actively avoids the other.
const AVOIDANCE_THRESHOLD: float = -0.35

## Contribution of a single shared tag, before the cap.
const SHARED_TAG_BONUS: float = 0.18

## Contribution of a single disliked tag. Deliberately larger in magnitude
## than a shared tag: one strong dislike should outweigh two mild affinities,
## which is what makes a merchant leave rather than settle in next to a
## table of pirates.
const DISLIKED_TAG_PENALTY: float = -0.4

## Ceiling on tag-derived score, so a type with many tags cannot run away
## with an arbitrarily high compatibility just by being verbose.
const MAXIMUM_TAG_SCORE: float = 0.55


## How well [param source] would get on with [param other] right now.
##
## Returns 0.0 for a null identity or for a customer compared with
## themselves, so a caller iterating a room does not need to filter first.
static func score(
	source: CustomerIdentity,
	other: CustomerIdentity,
	world_minutes: float = 0.0
) -> float:
	if source == null or other == null:
		return 0.0

	if source.customer_id == other.customer_id:
		return 0.0

	var total: float = 0.0

	total += _score_tags(source, other)
	total += _score_group(source, other)
	total += _score_history(source, other, world_minutes)
	total += _score_disposition(source, other)

	return clampf(total, -1.0, 1.0)


## Tag agreement: shared tags and explicit compatible_tags raise the score,
## disliked_tags lower it. Capped so a long tag list cannot dominate.
static func _score_tags(
	source: CustomerIdentity,
	other: CustomerIdentity
) -> float:
	var other_tags: Array[StringName] = other.get_tags()

	if other_tags.is_empty():
		return 0.0

	var positive: float = 0.0
	var negative: float = 0.0

	var source_type: CustomerType = source.customer_type

	for tag: StringName in other_tags:
		if source_type != null and source_type.disliked_tags.has(tag):
			negative += DISLIKED_TAG_PENALTY

		if source_type != null and source_type.compatible_tags.has(tag):
			positive += SHARED_TAG_BONUS
		elif source.get_tags().has(tag):
			# An unlisted shared tag still counts, at half weight: being the
			# same sort of person is weaker evidence than the type author
			# explicitly saying these two get on.
			positive += SHARED_TAG_BONUS * 0.5

	positive = minf(positive, MAXIMUM_TAG_SCORE)

	# Same type is a mild bonus on top, not a substitute for tags.
	if (
		not source.get_type_id().is_empty()
		and source.get_type_id() == other.get_type_id()
	):
		positive = minf(positive + 0.1, MAXIMUM_TAG_SCORE)

	return positive + negative


## Arriving together is the single strongest signal there is.
static func _score_group(
	source: CustomerIdentity,
	other: CustomerIdentity
) -> float:
	if source.group_id.is_empty() or other.group_id.is_empty():
		return 0.0

	if source.group_id != other.group_id:
		# Members of a different group are slightly less approachable -
		# they already have company.
		return -0.1

	var loyalty: float = 0.7

	if source.personality != null:
		loyalty = source.personality.group_loyalty

	return 0.35 + (loyalty * 0.25)


## What has already happened tonight. A good previous conversation makes a
## second one likelier; a bad one makes it much less likely.
##
## Recency matters: a chat an hour ago should not pull as hard as one five
## minutes ago, or a customer would orbit the first person they ever met.
static func _score_history(
	source: CustomerIdentity,
	other: CustomerIdentity,
	world_minutes: float
) -> float:
	if not source.has_interacted_with(other.customer_id):
		return 0.0

	var affinity: float = source.get_affinity(other.customer_id)
	var count: int = source.get_interaction_count(other.customer_id)

	var score: float = affinity * 0.4

	# Diminishing returns on repetition, so two customers do not lock into
	# talking only to each other for a whole visit.
	score -= minf(float(count) * 0.08, 0.3)

	return score


## Personality and intent: how open each side is to company at all.
static func _score_disposition(
	source: CustomerIdentity,
	other: CustomerIdentity
) -> float:
	var sociability: float = source.get_sociability()
	var privacy: float = source.get_privacy_preference()

	# Centred on 0.5 so an average customer contributes nothing either way.
	var score: float = (sociability - 0.5) * 0.4
	score -= (privacy - 0.5) * 0.4

	# The other party's privacy preference counts too - approaching someone
	# who visibly wants to be left alone should be less attractive.
	score -= (other.get_privacy_preference() - 0.5) * 0.2

	return score


## Whether [param source] would start something with [param other].
##
## Separate from raw [method score] because approaching has an extra gate:
## a customer who does not approach strangers will not, however compatible
## the tags say they are. Group members are exempt from that gate - they
## already know each other.
static func would_approach(
	source: CustomerIdentity,
	other: CustomerIdentity,
	world_minutes: float = 0.0
) -> bool:
	if source == null or other == null:
		return false

	var compatibility: float = score(source, other, world_minutes)

	if compatibility < APPROACH_THRESHOLD:
		return false

	var same_group: bool = (
		not source.group_id.is_empty()
		and source.group_id == other.group_id
	)

	if same_group:
		return true

	var willingness: float = 0.4

	if source.customer_type != null:
		willingness = source.customer_type.stranger_approach_willingness

	if source.personality != null:
		willingness = (
			willingness + source.personality.approaches_strangers
		) * 0.5

	# Compatibility can carry a reluctant customer part of the way, but not
	# all of it - a genuinely private merchant stays put.
	return (willingness + compatibility) >= 0.6


## Whether [param source] would actively avoid [param other] - used to keep
## a customer from settling next to someone they dislike.
static func would_avoid(
	source: CustomerIdentity,
	other: CustomerIdentity,
	world_minutes: float = 0.0
) -> bool:
	return score(source, other, world_minutes) <= AVOIDANCE_THRESHOLD


## The most compatible candidate from [param candidates], or null when none
## clears [constant APPROACH_THRESHOLD].
##
## [param candidates] is expected to be a small, already-local set - the
## nearby customers a caller got from an existing area or registry. This
## deliberately does not search the room itself: an unbounded global scan
## per decision is exactly the cost the brief rules out.
static func find_best_partner(
	source: CustomerIdentity,
	candidates: Array,
	world_minutes: float = 0.0
) -> CustomerIdentity:
	var best: CustomerIdentity = null
	var best_score: float = APPROACH_THRESHOLD

	for candidate: Variant in candidates:
		var other: CustomerIdentity = candidate as CustomerIdentity

		if other == null:
			continue

		var candidate_score: float = score(source, other, world_minutes)

		if candidate_score > best_score:
			best_score = candidate_score
			best = other

	return best


## How long a conversation between these two should run, in world minutes.
## Scaled by both sides' type multipliers and by how well they get on.
static func roll_conversation_minutes(
	source: CustomerIdentity,
	other: CustomerIdentity,
	base_minutes: float,
	rng: RandomNumberGenerator = null
) -> float:
	var multiplier: float = 1.0

	if source != null and source.customer_type != null:
		multiplier *= source.customer_type.conversation_duration_multiplier

	if other != null and other.customer_type != null:
		multiplier *= other.customer_type.conversation_duration_multiplier

	# Getting on well stretches it; barely tolerating each other cuts it.
	multiplier *= 1.0 + (score(source, other) * 0.4)

	var duration: float = base_minutes * multiplier

	if rng != null:
		duration *= rng.randf_range(0.8, 1.2)

	return maxf(0.5, duration)


## Score breakdown for the behaviour diagnostics, so "why did they walk past
## that table" has an answer rather than a number.
static func get_breakdown(
	source: CustomerIdentity,
	other: CustomerIdentity,
	world_minutes: float = 0.0
) -> Dictionary:
	if source == null or other == null:
		return {}

	return {
		"source_customer_id": source.customer_id,
		"other_customer_id": other.customer_id,
		"tag_score": _score_tags(source, other),
		"group_score": _score_group(source, other),
		"history_score": _score_history(source, other, world_minutes),
		"disposition_score": _score_disposition(source, other),
		"total": score(source, other, world_minutes),
		"would_approach": would_approach(source, other, world_minutes),
		"would_avoid": would_avoid(source, other, world_minutes),
	}
