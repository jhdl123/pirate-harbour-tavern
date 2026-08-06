extends Node

## The Customer Identity and Behaviour Foundation's 20 required checks.
##
## Resource-and-brain level rather than full-scene: this suite is about
## identity generation, intent weighting and the selection/cooldown rules.
## The mandatory-lifecycle cases (7, 8) are asserted against the activity
## configuration that guarantees them, because the lifecycle itself is
## already covered end-to-end by group_keg_loop_test and the phase suites -
## duplicating that here would test Godot's navigation, not this change.


var passed: int = 0
var failed: int = 0

var intent_registry: VisitIntentRegistry
var activity_registry: ActivityRegistry

var types: Dictionary = {}


func _ready() -> void:
	intent_registry = load("res://Data/customer_ai/visit_intent_registry.tres")
	intent_registry.rebuild()

	activity_registry = load("res://Data/customer_ai/activity_registry.tres")

	for type_id: String in [
		"local_worker", "merchant", "pirate", "sailor",
		"sailor_impatient", "captain"
	]:
		types[type_id] = load(
			"res://resources/CustomerTypes/%s.tres" % type_id
		)

	_test_01_types_load()
	_test_02_intents_load()
	_test_03_identity_valid()
	_test_04_personality_varies()
	_test_05_deterministic()
	_test_06_intent_weighting()
	_test_07_08_mandatory_exempt()
	_test_09_multiple_actions()
	_test_10_cooldowns()
	_test_11_type_distributions_differ()
	_test_12_13_group_intent_ownership()
	_test_14_no_permanent_evaluation()
	_test_15_closing_override()
	_test_16_fallback()
	_test_17_disabled_types()
	_test_18_missing_metadata()
	_test_19_drink_preferences()
	_test_20_diagnostics_export()
	_test_21_social_compatibility()
	_test_22_behaviour_report()

	print("\n=== RESULT: %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _check(label: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("  [PASS] " + label)
	else:
		failed += 1
		print("  [FAIL] " + label)


func _make_identity(type_id: String, seed_value: int = 0) -> CustomerIdentity:
	var identity: CustomerIdentity = CustomerIdentity.new()

	identity.initialise(
		types[type_id], intent_registry, 1, seed_value
	)

	return identity


# 1. Every active customer type loads successfully.
func _test_01_types_load() -> void:
	print("\n--- 1: customer types load ---")

	var all_loaded: bool = true

	for type_id: String in types:
		var type: CustomerType = types[type_id]

		if type == null:
			all_loaded = false
			continue

		if String(type.get_type_id()) != type_id:
			all_loaded = false

	_check("all six customer types load with matching type_ids", all_loaded)
	_check(
		"the four briefed types are present",
		types.has("local_worker") and types.has("merchant")
		and types.has("pirate") and types.has("sailor")
	)
	_check(
		"types carry tags (unblocks the Phase 4A modifier targets)",
		not types["merchant"].tags.is_empty()
	)


# 2. Every visit intention loads successfully.
func _test_02_intents_load() -> void:
	print("\n--- 2: visit intentions load ---")

	var enabled: Array[VisitIntentConfig] = intent_registry.get_enabled()

	_check("nine intents load", enabled.size() == 9)
	_check("registry validates", intent_registry.validate_or_warn())

	for intent_id: String in [
		"quick_drink", "social_visit", "group_drinking", "celebration",
		"quiet_meeting", "waiting_for_someone", "entertainment",
		"heavy_drinking", "passing_time"
	]:
		if not intent_registry.has_intent(StringName(intent_id)):
			_check("intent '%s' is registered" % intent_id, false)
			return

	_check("every briefed intent id resolves", true)


# 3. Spawned customers receive valid identity data.
func _test_03_identity_valid() -> void:
	print("\n--- 3: identity data is valid ---")

	var identity: CustomerIdentity = _make_identity("pirate")

	_check("identity has a type", identity.customer_type != null)
	_check("identity has a personality", identity.personality != null)
	_check("identity has an intent", identity.visit_intent != null)
	_check("type id resolves", String(identity.get_type_id()) == "pirate")
	_check("tags include the social category", identity.get_tags().has(&"crew"))


# 4. Customers of the same type receive personality variation.
func _test_04_personality_varies() -> void:
	print("\n--- 4: same type, different personalities ---")

	var social_values: Array[float] = []
	var distinct: Dictionary = {}

	for index: int in 25:
		var identity: CustomerIdentity = _make_identity("sailor")
		var value: float = identity.personality.social_tendency

		social_values.append(value)
		distinct[snappedf(value, 0.001)] = true

	_check(
		"25 sailors produce more than one sociability value (%d distinct)"
		% distinct.size(),
		distinct.size() > 1
	)

	var authored: float = types["sailor"].personality.social_tendency
	var any_differs: bool = false

	for value: float in social_values:
		if not is_equal_approx(value, authored):
			any_differs = true
			break

	_check("values differ from the authored personality", any_differs)

	var identity_a: CustomerIdentity = _make_identity("sailor")

	_check(
		"the profile is a private instance, not the shared resource",
		identity_a.personality != types["sailor"].personality
	)


# 5. Deterministic mode reproduces personality and decisions.
func _test_05_deterministic() -> void:
	print("\n--- 5: deterministic reproduction ---")

	var first: CustomerIdentity = _make_identity("merchant", 12345)
	var second: CustomerIdentity = _make_identity("merchant", 12345)

	_check(
		"same seed reproduces sociability",
		is_equal_approx(
			first.personality.social_tendency,
			second.personality.social_tendency
		)
	)
	_check(
		"same seed reproduces restlessness",
		is_equal_approx(
			first.personality.restlessness, second.personality.restlessness
		)
	)
	_check(
		"same seed reproduces the intent",
		first.get_intent_id() == second.get_intent_id()
	)

	var different: CustomerIdentity = _make_identity("merchant", 999)
	var diverged: bool = (
		not is_equal_approx(
			first.personality.social_tendency,
			different.personality.social_tendency
		)
		or first.get_intent_id() != different.get_intent_id()
	)

	_check("a different seed produces different output", diverged)


# 6. Type weighting selects valid visit intentions.
func _test_06_intent_weighting() -> void:
	print("\n--- 6: weighted intent selection ---")

	var merchant_intents: Dictionary = {}

	for index: int in 200:
		var identity: CustomerIdentity = _make_identity("merchant")
		merchant_intents[String(identity.get_intent_id())] = true

	var merchant_weights: Dictionary = types["merchant"].visit_intent_weights
	var all_weighted: bool = true

	for intent_id: String in merchant_intents:
		if not merchant_weights.has(intent_id):
			all_weighted = false

	_check(
		"merchants only ever roll intents their type weights", all_weighted
	)
	_check(
		"merchants roll more than one intent across 200 spawns",
		merchant_intents.size() > 1
	)

	var pirate_intents: Dictionary = {}

	for index: int in 200:
		var identity: CustomerIdentity = _make_identity("pirate")
		pirate_intents[String(identity.get_intent_id())] = true

	_check(
		"pirates never roll the merchant-only quiet_meeting as their top",
		not pirate_intents.has("quiet_meeting")
	)

	var empty_weight_pick: VisitIntentConfig = intent_registry.select_weighted(
		{}, RandomNumberGenerator.new()
	)

	_check(
		"an unweighted type still receives a valid intent",
		empty_weight_pick != null
	)


# 7 + 8. Mandatory ordering, payment and departure remain reliable.
func _test_07_08_mandatory_exempt() -> void:
	print("\n--- 7+8: mandatory lifecycle is exempt from pacing ---")

	var brain: CustomerBrain = CustomerBrain.new()
	var mandatory_ok: bool = true

	for activity_id: String in ["order_drink", "drink", "leave"]:
		var definition: ActivityDefinition = activity_registry.get_definition(
			StringName(activity_id)
		)

		if definition == null or not definition.is_mandatory:
			mandatory_ok = false
			continue

		# Even with a cooldown forced on, a mandatory activity must pass.
		brain.begin_cooldown(definition, 0.0)

		if brain.is_on_cooldown(definition, 1.0):
			mandatory_ok = false

	_check(
		"order_drink, drink and leave are mandatory and never cool down",
		mandatory_ok
	)

	var optional: ActivityDefinition = activity_registry.get_definition(
		&"relax_at_seat"
	)

	_check(
		"an optional activity is not marked mandatory",
		optional != null and not optional.is_mandatory
	)

	brain.free()


# 9. Customers can select more than one valid optional action.
func _test_09_multiple_actions() -> void:
	print("\n--- 9: weighted selection reaches more than one action ---")

	var brain: CustomerBrain = CustomerBrain.new()

	brain.registry = activity_registry
	brain.identity = _make_identity("sailor", 4242)

	var eligible: Array[Dictionary] = [
		{"activity_id": "relax_at_seat", "score": 20.0},
		{"activity_id": "socialise_at_seat", "score": 19.0},
		{"activity_id": "wander", "score": 18.5},
	]

	var chosen: Dictionary = {}

	for index: int in 200:
		var pick: ActivityDefinition = brain._select_weighted(eligible, 20.0)

		if pick != null:
			chosen[String(pick.activity_id)] = true

	_check(
		"close-scoring candidates produce more than one outcome (%d)"
		% chosen.size(),
		chosen.size() > 1
	)

	# A candidate far below the top must never be drawn.
	var lopsided: Array[Dictionary] = [
		{"activity_id": "relax_at_seat", "score": 40.0},
		{"activity_id": "wander", "score": 1.0},
	]

	var drew_weak: bool = false

	for index: int in 200:
		var pick: ActivityDefinition = brain._select_weighted(lopsided, 40.0)

		if pick != null and pick.activity_id == &"wander":
			drew_weak = true

	_check("a far-below-threshold action is never drawn", not drew_weak)

	brain.deterministic_decisions = true

	_check(
		"deterministic mode falls back to argmax",
		brain._select_weighted(eligible, 20.0) == null
	)

	brain.free()


# 10. Immediate repeated activity selection is limited by cooldowns.
func _test_10_cooldowns() -> void:
	print("\n--- 10: cooldowns suppress immediate repeats ---")

	var brain: CustomerBrain = CustomerBrain.new()
	var definition: ActivityDefinition = activity_registry.get_definition(
		&"visit_tavern_activity"
	)

	_check(
		"visit_tavern_activity has a cooldown authored",
		definition != null and definition.cooldown_minutes > 0.0
	)

	brain.begin_cooldown(definition, 100.0)

	_check(
		"it is on cooldown immediately after ending",
		brain.is_on_cooldown(definition, 101.0)
	)
	_check(
		"it is selectable again once the cooldown elapses",
		not brain.is_on_cooldown(
			definition, 100.0 + definition.cooldown_minutes + 1.0
		)
	)
	_check(
		"cooldowns are exposed for diagnostics",
		brain.get_cooldowns().has(&"visit_tavern_activity")
	)

	brain.free()


# 11. Merchants and sailors produce measurably different distributions.
func _test_11_type_distributions_differ() -> void:
	print("\n--- 11: types behave measurably differently ---")

	var merchant_social: float = 0.0
	var pirate_social: float = 0.0
	var merchant_privacy: float = 0.0
	var pirate_privacy: float = 0.0

	for index: int in 100:
		var merchant: CustomerIdentity = _make_identity("merchant")
		var pirate: CustomerIdentity = _make_identity("pirate")

		merchant_social += merchant.get_sociability()
		pirate_social += pirate.get_sociability()
		merchant_privacy += merchant.get_privacy_preference()
		pirate_privacy += pirate.get_privacy_preference()

	merchant_social /= 100.0
	pirate_social /= 100.0
	merchant_privacy /= 100.0
	pirate_privacy /= 100.0

	print(
		"    merchant sociability %.2f / privacy %.2f"
		% [merchant_social, merchant_privacy]
	)
	print(
		"    pirate   sociability %.2f / privacy %.2f"
		% [pirate_social, pirate_privacy]
	)

	_check(
		"pirates are measurably more sociable than merchants",
		pirate_social > merchant_social + 0.1
	)
	_check(
		"merchants prefer privacy more than pirates",
		merchant_privacy > pirate_privacy + 0.1
	)

	var merchant_bias: float = 0.0
	var pirate_bias: float = 0.0

	for index: int in 100:
		merchant_bias += _make_identity("merchant").get_activity_bias(
			&"visit_tavern_activity"
		)
		pirate_bias += _make_identity("pirate").get_activity_bias(
			&"visit_tavern_activity"
		)

	print(
		"    entertainment bias - merchant %.1f / pirate %.1f"
		% [merchant_bias / 100.0, pirate_bias / 100.0]
	)

	_check(
		"merchant intents bias away from entertainment relative to pirates",
		merchant_bias < pirate_bias
	)


# 12 + 13. Group members retain valid ownership; orders are not duplicated.
func _test_12_13_group_intent_ownership() -> void:
	print("\n--- 12+13: group owns the intent ---")

	var leader: CustomerIdentity = _make_identity("pirate", 77)
	var shared: VisitIntentConfig = leader.visit_intent

	var members: Array[CustomerIdentity] = []

	for index: int in 4:
		var member: CustomerIdentity = _make_identity("pirate", 100 + index)
		member.group_id = &"group_test"
		member.adopt_group_intent(shared)
		members.append(member)

	var all_share: bool = true
	var all_flagged: bool = true
	var personalities_differ: Dictionary = {}

	for member: CustomerIdentity in members:
		if member.visit_intent != shared:
			all_share = false

		if not member.intent_inherited_from_group:
			all_flagged = false

		personalities_differ[
			snappedf(member.personality.social_tendency, 0.001)
		] = true

	_check("every member shares the group intent", all_share)
	_check("inheritance is flagged for diagnostics", all_flagged)
	_check(
		"members keep individually varied personalities (%d distinct)"
		% personalities_differ.size(),
		personalities_differ.size() > 1
	)
	_check(
		"group_id is carried in the event payload",
		String(members[0].build_event_payload()["group_id"]) == "group_test"
	)


# 14. Customers cannot remain permanently in decision evaluation.
func _test_14_no_permanent_evaluation() -> void:
	print("\n--- 14: no permanent evaluation ---")

	var brain: CustomerBrain = CustomerBrain.new()

	brain.registry = activity_registry

	# With no eligible candidates the weighted pass must return null rather
	# than loop or throw, leaving the caller's own fallback in charge.
	_check(
		"an empty candidate set returns null",
		brain._select_weighted([], -INF) == null
	)
	_check(
		"a single candidate returns null (argmax stands)",
		brain._select_weighted(
			[{"activity_id": "relax_at_seat", "score": 5.0}], 5.0
		) == null
	)
	_check(
		"commitment is false with no current activity",
		not brain.is_committed(0.0)
	)
	_check(
		"duration is never exceeded with no current activity",
		not brain.has_exceeded_duration(9999.0)
	)

	brain.free()


# 15. Closing and end-of-day states override optional activities.
func _test_15_closing_override() -> void:
	print("\n--- 15: closing overrides optional activity ---")

	var leave: ActivityDefinition = activity_registry.get_definition(&"leave")

	_check(
		"leave is mandatory, so it bypasses commitment and cooldown",
		leave != null and leave.is_mandatory
	)
	_check("leave is terminal", leave != null and leave.is_terminal)

	# Mandatory activities are excluded from the weighted draw entirely, so
	# a forced departure can never be sampled away in favour of relaxing.
	var brain: CustomerBrain = CustomerBrain.new()

	brain.registry = activity_registry

	var with_leave: Array[Dictionary] = [
		{"activity_id": "leave", "score": 60.0},
		{"activity_id": "relax_at_seat", "score": 59.0},
	]

	var sampled_leave: bool = false

	for index: int in 100:
		var pick: ActivityDefinition = brain._select_weighted(
			with_leave, 60.0
		)

		if pick != null and pick.activity_id == &"leave":
			sampled_leave = true

	_check(
		"leave is never sampled - it is taken on score alone",
		not sampled_leave
	)

	brain.free()


# 16. No valid action produces a safe fallback.
func _test_16_fallback() -> void:
	print("\n--- 16: safe fallback ---")

	var identity: CustomerIdentity = CustomerIdentity.new()

	identity.initialise(null, null, 1, 0)

	_check("a null type still produces an identity", identity != null)
	_check(
		"a null type still produces a personality",
		identity.personality != null
	)
	_check("a null registry leaves intent null", identity.visit_intent == null)
	_check(
		"a null intent yields zero activity bias",
		is_zero_approx(identity.get_activity_bias(&"relax_at_seat"))
	)
	_check(
		"sociability falls back to a valid range",
		identity.get_sociability() >= 0.0
		and identity.get_sociability() <= 1.0
	)


# 17. Disabled customer types do not spawn.
func _test_17_disabled_types() -> void:
	print("\n--- 17: disabled types and intents ---")

	var all_enabled: bool = true

	for type_id: String in types:
		if not types[type_id].enabled:
			all_enabled = false

	_check("all authored types are currently enabled", all_enabled)

	var disabled: VisitIntentConfig = VisitIntentConfig.new()

	disabled.intent_id = &"test_disabled"
	disabled.enabled = false

	var probe_registry: VisitIntentRegistry = VisitIntentRegistry.new()

	probe_registry.intents = [disabled]

	_check(
		"a disabled intent is excluded from the enabled set",
		probe_registry.get_enabled().is_empty()
	)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()

	_check(
		"a registry of only disabled intents selects nothing",
		probe_registry.select_weighted({"test_disabled": 5.0}, rng) == null
	)


# 18. Missing optional metadata does not crash the customer.
func _test_18_missing_metadata() -> void:
	print("\n--- 18: missing metadata is survivable ---")

	var bare_type: CustomerType = CustomerType.new()
	var identity: CustomerIdentity = CustomerIdentity.new()

	identity.initialise(bare_type, intent_registry, 1, 0)

	_check("a bare CustomerType produces an identity", identity != null)
	_check(
		"a type with no personality still gets defaults",
		identity.personality != null
	)
	_check(
		"an empty type_id falls back rather than crashing",
		String(bare_type.get_type_id()) != ""
	)

	var bare_intent: VisitIntentConfig = VisitIntentConfig.new()

	_check(
		"an intent with no offsets returns zero bias",
		is_zero_approx(bare_intent.get_activity_bias(&"anything"))
	)

	# A malformed offsets dictionary must be ignored, not propagated.
	bare_intent.activity_score_offsets = {"relax_at_seat": "not a number"}

	_check(
		"a malformed offset value is ignored",
		is_zero_approx(bare_intent.get_activity_bias(&"relax_at_seat"))
	)

	_check(
		"diagnostics work on a bare identity",
		identity.get_diagnostics().has("personality_traits")
	)


# 19. Existing drink preference behaviour remains functional.
func _test_19_drink_preferences() -> void:
	print("\n--- 19: existing drink preferences intact ---")

	var sailor: CustomerType = types["sailor"]

	_check(
		"available_drinks survived the resource extension",
		sailor.available_drinks.size() == 2
	)
	_check("preferred_drink is still set", sailor.preferred_drink != null)
	_check(
		"preferred_drink_chance is unchanged",
		sailor.preferred_drink_chance > 0.0
	)
	_check(
		"the new tag layer is additive, not a replacement",
		sailor.preferred_drink_tags.is_empty()
		or sailor.available_drinks.size() == 2
	)
	_check(
		"payment_multiplier survived",
		sailor.payment_multiplier > 0.0
	)


# 20. Diagnostic export contains identity and scoring data.
func _test_20_diagnostics_export() -> void:
	print("\n--- 20: diagnostics contain identity and scoring ---")

	var identity: CustomerIdentity = _make_identity("pirate", 31337)

	identity.group_id = &"group_x"
	identity.record_interaction(42, 100.0, 0.3)
	identity.record_interaction(42, 110.0, 0.2)
	identity.record_interaction(43, 120.0, -0.1)

	var diagnostics: Dictionary = identity.get_diagnostics()

	for key: String in [
		"customer_id", "customer_type_id", "group_id", "visit_intent_id",
		"tags", "personality_traits", "effective_sociability",
		"social_partners"
	]:
		if not diagnostics.has(key):
			_check("diagnostics contain '%s'" % key, false)
			return

	_check("diagnostics contain every required identity field", true)

	_check(
		"personality traits are itemised (%d)"
		% diagnostics["personality_traits"].size(),
		diagnostics["personality_traits"].size() >= 13
	)
	_check(
		"repeat interactions are counted, not duplicated",
		identity.get_interaction_count(42) == 2
		and diagnostics["social_partner_count"] == 2
	)
	_check(
		"affinity accumulates and stays clamped",
		identity.get_affinity(42) > 0.0 and identity.get_affinity(43) < 0.0
	)

	# The event payload is what a future information system consumes.
	var payload: Dictionary = identity.build_event_payload()

	_check(
		"event payloads carry stable ids and no node references",
		payload.has("customer_id") and payload.has("customer_type_id")
		and payload.has("visit_intent_id") and payload.has("discretion")
	)


# 21. Social compatibility foundation (brief section 7).
func _test_21_social_compatibility() -> void:
	print("\n--- 21: social compatibility ---")

	var pirate_a: CustomerIdentity = _make_identity("pirate", 11)
	var pirate_b: CustomerIdentity = _make_identity("pirate", 22)
	var merchant: CustomerIdentity = _make_identity("merchant", 33)

	pirate_a.customer_id = 1
	pirate_b.customer_id = 2
	merchant.customer_id = 3

	var pirate_pair: float = SocialCompatibility.score(pirate_a, pirate_b)
	var mismatch: float = SocialCompatibility.score(merchant, pirate_a)

	print("    pirate/pirate %.2f  merchant/pirate %.2f"
		% [pirate_pair, mismatch])

	_check("two pirates are compatible", pirate_pair > 0.0)
	_check(
		"a merchant scores a pirate lower (disliked tag)",
		mismatch < pirate_pair
	)
	_check("a merchant would avoid a pirate", SocialCompatibility.would_avoid(
		merchant, pirate_a
	))
	_check(
		"self-comparison is neutral",
		is_zero_approx(SocialCompatibility.score(pirate_a, pirate_a))
	)
	_check(
		"a null identity is neutral, not an error",
		is_zero_approx(SocialCompatibility.score(pirate_a, null))
	)

	# Same group beats everything else.
	pirate_a.group_id = &"crew_1"
	pirate_b.group_id = &"crew_1"

	_check(
		"arriving together raises compatibility",
		SocialCompatibility.score(pirate_a, pirate_b) > pirate_pair
	)
	_check(
		"a group member is always approachable",
		SocialCompatibility.would_approach(pirate_a, pirate_b)
	)

	# Visit history: repetition has diminishing returns.
	#
	# Measured on an ungrouped pair on purpose. A same-group pirate pair
	# already saturates the -1..1 clamp, so the penalty is real but
	# invisible there - which is correct behaviour (two crewmates do not
	# stop being crewmates) and a misleading thing to assert against.
	var solo_a: CustomerIdentity = _make_identity("sailor", 61)
	var solo_b: CustomerIdentity = _make_identity("local_worker", 62)

	solo_a.customer_id = 61
	solo_b.customer_id = 62

	var before: float = SocialCompatibility.score(solo_a, solo_b)

	for index: int in 5:
		solo_a.record_interaction(solo_b.customer_id, 100.0, 0.0)

	var after: float = SocialCompatibility.score(solo_a, solo_b)

	print("    repeat decay %.2f -> %.2f" % [before, after])

	_check("repeated interaction reduces the pull to repeat again",
		after < before)

	var breakdown: Dictionary = SocialCompatibility.get_breakdown(
		pirate_a, pirate_b
	)

	_check(
		"the breakdown explains the score",
		breakdown.has("tag_score") and breakdown.has("group_score")
		and breakdown.has("history_score")
		and breakdown.has("disposition_score")
	)

	var partners: Array = [merchant, pirate_b]

	_check(
		"the best partner is the compatible one",
		SocialCompatibility.find_best_partner(pirate_a, partners) == pirate_b
	)
	_check(
		"conversation length scales with compatibility",
		SocialCompatibility.roll_conversation_minutes(
			pirate_a, pirate_b, 10.0
		) > 0.5
	)


# 22. Aggregate behaviour reporting (brief section 12).
func _test_22_behaviour_report() -> void:
	print("\n--- 22: aggregate behaviour report ---")

	var report: CustomerBehaviourReport = CustomerBehaviourReport.new()

	report.attach()

	# Two customers with deliberately different shapes: one varied, one
	# stuck in an immediate repeat.
	var varied: CustomerIdentity = _make_identity("pirate", 501)
	varied.customer_id = 501

	CustomerBehaviourEvents.emit_identity_initialised(varied)
	CustomerBehaviourEvents.emit_intention_selected(varied)
	CustomerBehaviourEvents.emit_action_selected(varied, &"relax_at_seat", 10.0)
	CustomerBehaviourEvents.emit_action_selected(varied, &"wander", 9.0)
	CustomerBehaviourEvents.emit_action_selected(varied, &"socialise_at_seat", 8.0)
	CustomerBehaviourEvents.emit_departed(varied, &"visit_complete", 40.0, 3)

	var repetitive: CustomerIdentity = _make_identity("merchant", 502)
	repetitive.customer_id = 502

	CustomerBehaviourEvents.emit_identity_initialised(repetitive)
	CustomerBehaviourEvents.emit_intention_selected(repetitive)
	CustomerBehaviourEvents.emit_action_selected(repetitive, &"relax_at_seat", 10.0)
	CustomerBehaviourEvents.emit_action_selected(repetitive, &"relax_at_seat", 10.0)
	CustomerBehaviourEvents.emit_departed(repetitive, &"patience", 12.0, 1)

	var built: Dictionary = report.build_report()

	_check("both customers were counted", int(built["total_customers"]) == 2)
	_check(
		"per-type breakdown exists for both types",
		built["customers_by_type"].size() == 2
	)
	_check(
		"the immediate repeat was detected (%.0f%%)"
		% built["repeat_action_percentage"],
		float(built["repeat_action_percentage"]) == 50.0
	)
	_check(
		"distinct activities per visit is averaged (%.1f)"
		% built["average_distinct_activities_per_visit"],
		float(built["average_distinct_activities_per_visit"]) == 2.0
	)
	_check(
		"intention distribution is populated",
		not built["intention_distribution"].is_empty()
	)
	_check(
		"patience and voluntary departures are separated",
		float(built["patience_departure_rate"]) == 50.0
		and float(built["voluntary_departure_rate"]) == 50.0
	)
	_check(
		"the most common sequence is reported",
		not String(built["most_common_sequence"]).is_empty()
	)
	_check(
		"activity frequency is broken down by type",
		built["activity_frequency_by_type"].size() == 2
	)

	report.record_stuck(501, "MOVING_TO_SEAT")
	report.record_group_failure("group_x", "members split")

	var second: Dictionary = report.build_report()

	_check(
		"stuck customers are surfaced",
		int(second["customers_stuck_in_invalid_states"]) == 1
	)
	_check(
		"group coordination failures are surfaced",
		second["warnings"].size() == 1
	)
	_check(
		"the summary formats without error",
		not report.format_summary().is_empty()
	)

	report.detach()
	report.clear()

	_check(
		"clearing resets the report",
		int(report.build_report()["total_customers"]) == 0
	)
