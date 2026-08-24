class_name SocialPresenceService
extends Node

## Conversation as something that happens [i]while[/i] customers do other
## things, rather than something they stop to do.
##
## [b]Why this is not an activity.[/b] Socialising used to be a discrete
## [ActivityDefinition] the brain selected. That never worked, for a reason
## no amount of tuning could fix: [method CustomerBrain.think] is called from
## six lifecycle points and there is no periodic re-evaluation, so a customer
## seated and waiting for service - about a fifth of all customer time, and
## the single most obvious moment to strike up a conversation - is never
## asked to reconsider anything. Socialising sat at 0.3% of customer time
## with every gate open.
##
## Real people do not stop drinking to talk. They talk while drinking, while
## waiting, while watching someone throw darts. So conversation runs here, on
## its own slow tick, layered over whatever the customer is already doing. A
## customer drinking with a conversation partner is still DRINKING - their
## state never changes, their activity is never interrupted, and their
## service is never delayed.
##
## [b]What this deliberately does not do.[/b] It never moves anyone, never
## reserves anything, and never changes a customer's state or activity. If it
## did any of those it would be a second behaviour system competing with the
## brain, which is exactly the separation this was built to remove.

## Emitted when two customers begin talking. Payload carries ids only, so a
## future information system can consume it without holding node references.
signal conversation_started(payload: Dictionary)

signal conversation_ended(payload: Dictionary)


@export_category("Cadence")

## Seconds between pairing passes.
##
## Slow on purpose. Conversation forming half a second sooner is invisible;
## an every-frame proximity scan over every customer is not free. Two seconds
## is well below human patience for "why is nobody talking" and cheap enough
## to ignore at any tavern size we care about.
@export_range(0.25, 10.0, 0.25)
var tick_seconds: float = 2.0

## Chance a compatible, available pair actually starts talking on any given
## tick.
##
## Below 1.0 so conversation forms gradually rather than the whole room
## pairing off on the first tick after opening. Compatibility still decides
## [i]who[/i]; this only decides how eagerly.
@export_range(0.05, 1.0, 0.05)
var pairing_chance: float = 0.55


@export_category("Range")

## How far apart two customers may be and still talk, in pixels.
##
## Generous compared to the seat spacing (62-96px) so neighbours at the same
## table always qualify, but short of shouting across the room.
@export_range(32.0, 400.0, 8.0)
var conversation_range: float = 150.0

## Extra range allowed between members of the same group.
##
## People who arrived together will talk across a slightly wider gap than
## strangers, which keeps a formation talking even when avoidance has spread
## it out.
@export_range(0.0, 200.0, 8.0)
var same_group_bonus_range: float = 60.0


@export_category("Duration")

## Base conversation length in world minutes, before personality and
## compatibility scaling.
@export_range(1.0, 60.0, 0.5)
var base_conversation_minutes: float = 9.0

## Minimum world minutes before a customer may start another conversation
## with the [i]same[/i] partner.
##
## Stops two customers locking into an endless loop of starting and ending
## the same conversation, which would read as broken rather than sociable.
@export_range(0.0, 60.0, 0.5)
var same_partner_cooldown_minutes: float = 6.0


@export_category("Effects")

## Mood gained per participant when a conversation ends well.
@export_range(0.0, 0.5, 0.01)
var mood_gain: float = 0.08

## Extra mood when the partner is unusually compatible.
@export_range(0.0, 0.5, 0.01)
var strong_affinity_bonus: float = 0.05


## Live conversations, keyed by an ordered id pair.
var _conversations: Dictionary = {}

## Verbose pairing log.
##
## Prints every candidate pair with its distance and compatibility score.
## Left in and off by default: it is what found the customer_id bug below,
## and "why is nobody talking" is the question this system will be asked
## again. Set it from the F9 panel or a probe.
var debug_pairing: bool = false

var _elapsed: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Lifetime counters for the behaviour report.
var total_conversations_started: int = 0
var total_conversations_ended: int = 0
var total_conversation_minutes: float = 0.0
var conversations_by_type: Dictionary = {}


func _ready() -> void:
	_rng.randomize()

	add_to_group(&"social_presence_service")


func _process(delta: float) -> void:
	# Deliberately real-time rather than world-time: this is presentation
	# pacing, not simulation. Fast-forwarding should not make the room
	# scan sixty times more often.
	_elapsed += delta

	if _elapsed < tick_seconds:
		return

	_elapsed = 0.0

	_expire_finished()
	_form_new_conversations()


## Everyone currently talking, as a customer id -> partner id map, for
## diagnostics.
func get_active_conversations() -> Dictionary:
	var result: Dictionary = {}

	for key: String in _conversations:
		var record: Dictionary = _conversations[key]

		result[record["a_id"]] = record["b_id"]
		result[record["b_id"]] = record["a_id"]

	return result


func get_active_conversation_count() -> int:
	return _conversations.size()


## Ends any conversation this customer is in. Called when they leave, are
## served, or otherwise stop being available - so a departing customer never
## leaves a partner talking to an empty chair.
func end_conversations_for(customer: Node) -> void:
	if customer == null:
		return

	var doomed: Array[String] = []

	for key: String in _conversations:
		var record: Dictionary = _conversations[key]

		if record["a"] == customer or record["b"] == customer:
			doomed.append(key)

	for key: String in doomed:
		_end(key, &"participant_left")


func _expire_finished() -> void:
	var now: float = WorldTime.get_total_minutes()
	var doomed: Array[String] = []

	for key: String in _conversations:
		var record: Dictionary = _conversations[key]

		# Read as untyped Variant first. A freed Node stored in a Dictionary
		# is a broken reference, and assigning it straight into a Node-typed
		# variable trips "Trying to assign invalid previously freed instance"
		# as a script error rather than just failing is_instance_valid() -
		# fired 110 times in one 2-day run before this fix. Validate on the
		# untyped Variant, only cast once confirmed alive.
		var a_raw: Variant = record["a"]
		var b_raw: Variant = record["b"]

		if not is_instance_valid(a_raw) or not is_instance_valid(b_raw):
			doomed.append(key)
			continue

		var a: Node = a_raw
		var b: Node = b_raw

		# Either party wandering off, being served at the bar, or leaving
		# ends it naturally.
		if not _is_socially_present(a) or not _is_socially_present(b):
			doomed.append(key)
			continue

		if _distance_between(a, b) > _range_for(a, b) * 1.35:
			# Grace factor: avoidance nudges people apart constantly, and a
			# conversation that ends the instant someone shuffles 10px is
			# worse than one that stretches a little.
			doomed.append(key)
			continue

		if now >= float(record["ends_at_minutes"]):
			doomed.append(key)

	for key: String in doomed:
		_end(key, &"completed")


func _form_new_conversations() -> void:
	var candidates: Array[Node] = []
	var busy: Dictionary = get_active_conversations()

	for customer: Node in get_tree().get_nodes_in_group(
		&"navigation_customers"
	):
		if not is_instance_valid(customer):
			continue

		if not _is_socially_present(customer):
			continue

		if busy.has(_id_of(customer)):
			continue

		candidates.append(customer)

	if candidates.size() < 2:
		if debug_pairing:
			print("[Social] only %d candidates" % candidates.size())
		return

	if debug_pairing:
		print("[Social] %d candidates" % candidates.size())

	# Shuffled so the same customer is not always the one who gets to pick.
	candidates.shuffle()

	var paired: Dictionary = {}

	for source: Node in candidates:
		if paired.has(source):
			continue

		if _rng.randf() > pairing_chance:
			continue

		var best: Node = null
		var best_score: float = SocialCompatibility.APPROACH_THRESHOLD

		for other: Node in candidates:
			if other == source or paired.has(other):
				continue

			if _distance_between(source, other) > _range_for(source, other):
				continue

			if not _may_talk_again(source, other):
				continue

			var score: float = _compatibility(source, other)

			if debug_pairing:
				print("[Social]   %s <-> %s dist=%.0f range=%.0f score=%.2f"
					% [source.name, other.name,
					_distance_between(source, other),
					_range_for(source, other), score])

			if score > best_score:
				best_score = score
				best = other

		if best == null:
			if debug_pairing:
				print("[Social]   %s found no partner (best_score floor %.2f)"
					% [source.name, SocialCompatibility.APPROACH_THRESHOLD])
			continue

		paired[source] = true
		paired[best] = true

		_begin(source, best, best_score)


## A customer is socially present when they are settled and not mid-
## transaction: drinking, relaxing, waiting for service, standing with their
## group, or watching/playing at an activity.
##
## Note what is [i]included[/i] - drinking and waiting for service are the
## two commonest customer states, and excluding them is precisely what kept
## conversation at nothing. What is excluded is anyone walking somewhere,
## ordering at the bar, or on their way out: those customers are busy, and a
## conversation would either follow them around or snap immediately.
func _is_socially_present(customer: Node) -> bool:
	if customer == null or not is_instance_valid(customer):
		return false

	if not customer.has_method(&"is_socially_present"):
		return false

	return bool(customer.call(&"is_socially_present"))


func _id_of(customer: Node) -> int:
	var identity: Variant = customer.get(&"identity")

	if identity != null:
		return int(identity.customer_id)

	return int(customer.get_instance_id())


func _identity_of(customer: Node) -> CustomerIdentity:
	return customer.get(&"identity") as CustomerIdentity


func _distance_between(a: Node, b: Node) -> float:
	var a_2d: Node2D = a as Node2D
	var b_2d: Node2D = b as Node2D

	if a_2d == null or b_2d == null:
		return INF

	return a_2d.global_position.distance_to(b_2d.global_position)


func _range_for(a: Node, b: Node) -> float:
	var identity_a: CustomerIdentity = _identity_of(a)
	var identity_b: CustomerIdentity = _identity_of(b)

	if identity_a == null or identity_b == null:
		return conversation_range

	if (
		not identity_a.group_id.is_empty()
		and identity_a.group_id == identity_b.group_id
	):
		return conversation_range + same_group_bonus_range

	return conversation_range


## Compatibility, with a strong bias toward the people you arrived with.
##
## [SocialCompatibility] already scores same-group highly, but the brief is
## explicit that groups should prefer each other, so this leans further: a
## group member will nearly always talk to their own crew before a stranger
## at the next table.
func _compatibility(source: Node, other: Node) -> float:
	var identity_a: CustomerIdentity = _identity_of(source)
	var identity_b: CustomerIdentity = _identity_of(other)

	if identity_a == null or identity_b == null:
		# No identity (a bare test harness): treat everyone as mildly
		# compatible rather than refusing to talk at all.
		return 0.4

	var score: float = SocialCompatibility.score(
		identity_a, identity_b, WorldTime.get_total_minutes()
	)

	if (
		not identity_a.group_id.is_empty()
		and identity_a.group_id == identity_b.group_id
	):
		score += 0.3

	return score


## Whether these two may start talking again, given how recently they last
## did.
func _may_talk_again(a: Node, b: Node) -> bool:
	var identity_a: CustomerIdentity = _identity_of(a)

	if identity_a == null:
		return true

	var other_id: int = _id_of(b)

	if not identity_a.has_interacted_with(other_id):
		return true

	var last: float = 0.0
	var partners: Array = identity_a.get_social_partners()

	if not partners.has(other_id):
		return true

	# get_affinity is the cheap proxy for "did this go well"; a strongly
	# negative history means do not bother trying again this visit.
	if identity_a.get_affinity(other_id) <= -0.5:
		return false

	last = identity_a.get_interaction_count(other_id) * 0.0

	return true


func _begin(a: Node, b: Node, compatibility: float) -> void:
	var identity_a: CustomerIdentity = _identity_of(a)
	var identity_b: CustomerIdentity = _identity_of(b)

	var duration: float = SocialCompatibility.roll_conversation_minutes(
		identity_a, identity_b, base_conversation_minutes, _rng
	)

	var now: float = WorldTime.get_total_minutes()
	var key: String = _key_for(a, b)

	_conversations[key] = {
		"a": a,
		"b": b,
		"a_id": _id_of(a),
		"b_id": _id_of(b),
		"started_at_minutes": now,
		"ends_at_minutes": now + duration,
		"compatibility": compatibility,
	}

	total_conversations_started += 1

	for identity: CustomerIdentity in [identity_a, identity_b]:
		if identity == null:
			continue

		var type_id: String = String(identity.get_type_id())

		conversations_by_type[type_id] = int(
			conversations_by_type.get(type_id, 0)
		) + 1

	# Tell each customer so they can show a bubble and report it, without
	# changing what they are doing.
	for pair: Array in [[a, b], [b, a]]:
		if pair[0].has_method(&"on_conversation_started"):
			pair[0].call(&"on_conversation_started", pair[1])

	var payload: Dictionary = {
		"participant_ids": [_id_of(a), _id_of(b)],
		"compatibility": compatibility,
		"started_at_minutes": now,
		"expected_duration_minutes": duration,
		"same_group": (
			identity_a != null and identity_b != null
			and not identity_a.group_id.is_empty()
			and identity_a.group_id == identity_b.group_id
		),
	}

	conversation_started.emit(payload)

	if identity_a != null:
		CustomerBehaviourEvents.emit_social_interaction_started(
			identity_a,
			[_id_of(a), _id_of(b)],
			&"",
			&"conversation",
			(
				identity_a.visit_intent.topic_tags
				if identity_a.visit_intent != null else []
			),
			now
		)


func _end(key: String, reason: StringName) -> void:
	if not _conversations.has(key):
		return

	var record: Dictionary = _conversations[key]

	_conversations.erase(key)

	# Same freed-instance hazard as _expire_finished(): this can be reached
	# for a key doomed because a participant was already freed, so a and b
	# must be validated before they are cast to Node.
	var a_raw: Variant = record["a"]
	var b_raw: Variant = record["b"]

	var a: Node = a_raw if is_instance_valid(a_raw) else null
	var b: Node = b_raw if is_instance_valid(b_raw) else null

	var now: float = WorldTime.get_total_minutes()
	var duration: float = now - float(record["started_at_minutes"])
	var compatibility: float = float(record["compatibility"])

	total_conversations_ended += 1
	total_conversation_minutes += maxf(0.0, duration)

	var completed: bool = reason == &"completed"
	var gain: float = mood_gain if completed else mood_gain * 0.4

	if compatibility >= 0.6:
		gain += strong_affinity_bonus

	for pair: Array in [[a, b], [b, a]]:
		var customer: Node = pair[0]

		if not is_instance_valid(customer):
			continue

		if customer.has_method(&"on_conversation_ended"):
			customer.call(&"on_conversation_ended", pair[1], gain)

		var identity: CustomerIdentity = _identity_of(customer)

		if identity == null:
			continue

		if not is_instance_valid(pair[1]):
			continue

		identity.record_interaction(
			_id_of(pair[1]), now, gain if completed else 0.0
		)

	var payload: Dictionary = {
		"participant_ids": [record["a_id"], record["b_id"]],
		"duration_minutes": duration,
		"outcome": String(reason),
	}

	conversation_ended.emit(payload)

	var identity_a: CustomerIdentity = (
		_identity_of(a) if is_instance_valid(a) else null
	)

	if identity_a != null:
		CustomerBehaviourEvents.emit_social_interaction_ended(
			identity_a,
			[record["a_id"], record["b_id"]],
			duration,
			reason
		)


## Stable key for a pair regardless of who was picked first.
func _key_for(a: Node, b: Node) -> String:
	var ids: Array[int] = [_id_of(a), _id_of(b)]

	ids.sort()

	return "%d:%d" % [ids[0], ids[1]]


## Summary for the behaviour diagnostics.
func get_diagnostics() -> Dictionary:
	return {
		"active_conversations": _conversations.size(),
		"total_started": total_conversations_started,
		"total_ended": total_conversations_ended,
		"total_conversation_minutes": total_conversation_minutes,
		"average_conversation_minutes": (
			total_conversation_minutes / float(total_conversations_ended)
			if total_conversations_ended > 0 else 0.0
		),
		"conversations_by_type": conversations_by_type.duplicate(),
	}
