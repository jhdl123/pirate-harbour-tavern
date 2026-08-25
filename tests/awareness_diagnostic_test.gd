extends Node

## Proves awareness changes decision context, not merely that occupancy
## exists - the explicit ask in the 2026-08-25 scoring audit's item 4:
## "awareness -> changed decision context, not merely: awareness ->
## occupancy count exists."
##
## Uses the real Data/customer_ai resources throughout (the actual
## visit_tavern_activity.tres, darts_awareness_scoring.tres and a real
## darts_point.tscn instance) - nothing here is a mock of the scoring
## system, only the actor/needs are hand-built rather than spawned through
## GameManager, the same "resource-and-brain level" approach
## customer_identity_test.gd already uses.
##
## PART 1: isolated contribution. Scores visit_tavern_activity for one
## fixed context twice - once with the darts point's second slot free,
## once with it occupied - with the global RNG seeded identically before
## each call so decision_variance's random draw cannot contaminate the
## comparison. Proves the ONLY thing that changes is awareness_contribution,
## and the score delta is exactly attributable to it.
##
## PART 2: decision context. Runs the same two scenarios through the real
## candidate pool (darts vs socialise, socialise's has_social_partner gate
## satisfied via a synthetic domain flag rather than a second live
## customer) and reports whether occupancy changes which activity wins -
## whatever the true answer turns out to be, not a rigged one. See the
## class doc comment on why this may legitimately turn out to be "changes
## the margin, not the winner" for darts specifically: NearestPointDistance
## Condition's falloff (600px, max +4.0) and NearbyActivityInUseCondition's
## falloff (300px, max +2.0) are both driven by the same physical distance,
## and distance's floor wherever awareness is still nonzero (>= 2.0)
## already matches awareness's own ceiling - a structural correlation
## nobody had checked before this audit.


var passed: int = 0
var failed: int = 0

var darts_definition: ActivityDefinition
var socialise_definition: ActivityDefinition
var darts_point: TavernActivityPoint


func _ready() -> void:
	var registry: ActivityRegistry = load(
		"res://Data/customer_ai/activity_registry.tres"
	)
	darts_definition = registry.get_definition(&"visit_tavern_activity")
	socialise_definition = registry.get_definition(&"socialise_at_seat")

	darts_point = load("res://scenes/furniture/darts_point.tscn").instantiate()
	darts_point.global_position = Vector2(1000, 1000)
	add_child(darts_point)

	await get_tree().process_frame

	_part_1_isolated_contribution()
	_part_2_decision_context()

	print("\n=== RESULT: %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _check(label: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("  [PASS] " + label)
	else:
		failed += 1
		print("  [FAIL] " + label)


func _make_needs(
	thirst: float, mood: float, intoxication: float,
	remaining_visit_minutes: float = 60.0
) -> CustomerNeeds:
	var needs := CustomerNeeds.new()
	needs.set_need(&"thirst", thirst)
	needs.set_need(&"mood", mood)
	needs.set_need(&"intoxication", intoxication)
	needs.set_need(&"patience", 1.0)
	needs.set_need(&"energy", 1.0)
	needs.set_context_value(&"remaining_visit_minutes", remaining_visit_minutes)
	needs.set_context_value(&"visit_duration_minutes", 90.0)
	needs.set_context_value(&"wealth", 30.0)
	return needs


func _make_context(
	needs: CustomerNeeds, position: Vector2, extra_flags: Dictionary = {}
) -> ActivityContext:
	var actor := Node2D.new()
	actor.name = "AwarenessDiagnosticActor"
	add_child(actor)
	actor.global_position = position

	var context: ActivityContext = ActivityContext.create(actor, needs, position)
	context.domain_flags = {
		&"is_settled": true,
		&"is_free_to_leave_seat": true,
		&"is_transacting_at_bar": false,
		&"group_has_away_capacity": true,
		&"group_is_drinking": false,
	}
	for key: Variant in extra_flags:
		context.domain_flags[key] = extra_flags[key]

	return context


func _second_slot_reservable() -> Reservable:
	return darts_point.slots[1].reservable


## The slot's own global position, not the point's origin - Slot1 sits at a
## +-10px visual offset from DartsPoint for the two-player layout, so
## measuring from the point's origin instead of the slot itself would be
## off by that same 10px, breaking an "exactly maximum_bonus at distance
## zero" assertion for a reason that has nothing to do with awareness.
func _second_slot_position() -> Vector2:
	return (darts_point.slots[1].reservable.get_parent() as Node2D).global_position


## PART 1 - isolated contribution proof.
func _part_1_isolated_contribution() -> void:
	print("\n--- PART 1: isolated contribution (darts alone, actor at the point) ---")

	# The point's own centre, not either slot's position - both slots sit
	# equidistant from it (+-10px), so which one is "the nearest free slot"
	# for NearestPointDistanceCondition never changes between scenario A
	# and B, keeping distance_contribution identical in both and isolating
	# awareness_contribution as the only thing that should differ.
	var needs: CustomerNeeds = _make_needs(0.3, 0.5, 0.2)
	var context: ActivityContext = _make_context(needs, darts_point.global_position)
	var expected_awareness: float = 2.0 * clampf(
		1.0 - darts_point.global_position.distance_to(_second_slot_position()) / 300.0,
		0.0, 1.0
	)

	seed(20260825)
	var breakdown_a: Dictionary = darts_definition.get_utility_breakdown(context)
	print("  Scenario A (nobody playing):    ", breakdown_a)

	_check(
		"A: darts is available",
		darts_definition.is_available(context)
	)
	_check(
		"A: awareness_contribution is 0.0 when nobody occupies the second slot",
		is_equal_approx(float(breakdown_a.get("awareness_contribution", -1.0)), 0.0)
	)

	var occupant := Node.new()
	add_child(occupant)
	_second_slot_reservable().reserve(occupant)

	seed(20260825)
	var breakdown_b: Dictionary = darts_definition.get_utility_breakdown(context)
	print("  Scenario B (someone playing):   ", breakdown_b)

	_check(
		"B: darts is still available (the other slot is still free)",
		darts_definition.is_available(context)
	)
	_check(
		"B: awareness_contribution matches the expected falloff-scaled value",
		is_equal_approx(
			float(breakdown_b.get("awareness_contribution", -1.0)),
			expected_awareness
		)
	)

	var isolated: bool = true
	for key: String in breakdown_a:
		if key == "awareness_contribution" or key == "final_score":
			continue
		if not is_equal_approx(
			float(breakdown_a[key]), float(breakdown_b.get(key, NAN))
		):
			isolated = false
			print(
				"      non-isolated difference in '", key, "': A=",
				breakdown_a[key], " B=", breakdown_b.get(key)
			)

	_check(
		"every other contribution is identical between A and B (isolation)",
		isolated
	)
	_check(
		"B's final_score equals A's final_score plus exactly the awareness delta",
		is_equal_approx(
			float(breakdown_b["final_score"]),
			float(breakdown_a["final_score"]) + expected_awareness
		)
	)

	_second_slot_reservable().release(occupant)
	occupant.queue_free()


## PART 2 - decision context proof: does occupancy change which activity
## wins, not just darts' own score in isolation? Run honestly - report
## whatever the real candidate pool actually decides.
func _part_2_decision_context() -> void:
	print("\n--- PART 2: decision context (darts vs socialise, same customer) ---")

	# Needs chosen to favour socialise over darts on every lever socialise
	# has and darts does not (mood, intoxication - darts does not read
	# intoxication at all), so the comparison isolates what proximity
	# (distance + awareness) contributes rather than needs doing the work.
	var needs: CustomerNeeds = _make_needs(0.0, 1.0, 1.0, 90.0)

	# Standing close enough to the darts point for awareness to matter -
	# a customer who would plausibly notice someone already playing.
	var position: Vector2 = darts_point.global_position + Vector2(150, 0)
	var context: ActivityContext = _make_context(
		needs, position, {&"has_social_partner": true}
	)

	seed(20260825)
	var darts_score_a: float = darts_definition.get_utility(context)
	seed(20260825)
	var socialise_score_a: float = socialise_definition.get_utility(context)

	var winner_a: String = (
		"darts" if darts_score_a > socialise_score_a else "socialise"
	)
	print(
		"  Scenario A - darts=%.2f  socialise=%.2f  winner=%s"
		% [darts_score_a, socialise_score_a, winner_a]
	)

	var occupant := Node.new()
	add_child(occupant)
	_second_slot_reservable().reserve(occupant)

	seed(20260825)
	var darts_score_b: float = darts_definition.get_utility(context)
	seed(20260825)
	var socialise_score_b: float = socialise_definition.get_utility(context)

	var winner_b: String = (
		"darts" if darts_score_b > socialise_score_b else "socialise"
	)
	print(
		"  Scenario B - darts=%.2f  socialise=%.2f  winner=%s"
		% [darts_score_b, socialise_score_b, winner_b]
	)

	var awareness_delta: float = darts_score_b - darts_score_a
	print("  awareness raised darts' own score by %.2f" % awareness_delta)

	_check(
		"awareness raised darts' score (occupancy changed darts' own candidacy)",
		awareness_delta > 0.0
	)

	if winner_a != winner_b:
		print(
			"  DECISION FLIPPED: awareness alone changed the winner from '",
			winner_a, "' to '", winner_b, "'."
		)
	else:
		print(
			"  Decision NOT flipped at this distance/needs profile - winner",
			" stayed '", winner_a, "' in both scenarios, margin changed by",
			" %.2f." % awareness_delta,
			" Expected: NearestPointDistanceCondition's falloff (600px, max",
			" +4.0) and NearbyActivityInUseCondition's falloff (300px, max",
			" +2.0) are both driven by the same physical distance, so",
			" distance's own floor wherever awareness is still nonzero",
			" (>= 2.0) already matches awareness's ceiling - awareness is",
			" real and isolated (Part 1) but rarely the sole deciding factor",
			" for darts specifically, because proximity's larger, correlated",
			" distance bonus is usually already doing most of the pulling."
		)

	# Not asserted pass/fail either way - report the true finding rather
	# than requiring a specific answer. What IS asserted is that awareness
	# demonstrably participates in the decision (previous check) and never
	# makes the score worse (sanity bound).
	_check(
		"awareness never lowers a candidate's own score (additive only)",
		darts_score_b >= darts_score_a
	)

	_second_slot_reservable().release(occupant)
	occupant.queue_free()
