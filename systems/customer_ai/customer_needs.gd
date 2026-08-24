class_name CustomerNeeds
extends RefCounted

## One customer's live, changing state - not authored content.
##
## This is deliberately a plain [RefCounted], not a [Resource]. A [Resource] is
## shared-by-reference content an artist or designer authors once (a drink, a
## customer archetype); this is the opposite - private, constantly-mutating
## data that must never accidentally be shared between two customers the way
## an un-duplicated [Resource] would be. Every [Customer] creates its own with
## [method seed_from], the same pattern [ActorMovement]/[ActorNavigation]
## already use for their profiles ([code]_create_private_profiles[/code]).
##
## Every value is 0.0-1.0 except [member wealth] (a plain money amount) and
## [member remaining_visit_minutes]/[member visit_duration_minutes] (world
## minutes). Values exist now even though today's activities only read a few
## of them - that is the point: future activities (gambling, conversation,
## drinking to excess) read and write the same shared record without
## customer.gd growing new fields for each one.
##
## [b]"Satisfaction" is [member mood].[/b] Phase 2B's brief calls this need
## "satisfaction"; it is the exact same field Phase 1 named [member mood]
## ("nudged by service speed, drink quality, waiting too long") - renaming it
## would have meant re-pointing [code]leave_mood_scoring.tres[/code] for no
## behavioural gain, so it stays [member mood] in code with this note as the
## bridge between the two names.

signal need_changed(need_id: StringName, value: float)


## 0 (miserable) - 1 (delighted) - "satisfaction", see the class doc comment.
## Nudged by successful service (up) and running out of patience (down) -
## see Customer._on_patience_expired() and the drink-serving path in
## Customer.interact(). Amounts are configured on CustomerAIBalanceConfig.
var mood: float = 0.7

## Plain currency the customer carries. Spent on drinks and, eventually,
## other purchases. Not clamped to 0-1 like the rest.
var wealth: int = 0

## 0 (out of patience) - 1 (very patient). Falls while waiting for service;
## today's patience-bar countdown is the concrete expression of this.
var patience: float = 1.0

## 0 (exhausted) - 1 (fully energetic). Falls over the course of a visit;
## a future "tired" state or early departure would read this.
var energy: float = 1.0

## 0 (sober) - 1 (very drunk). Rises by DrinkDefinition.alcohol_strength
## (scaled by CustomerAIBalanceConfig.intoxication_gain_scale and
## Personality.temperance) each time a drink finishes. Order Drink gates
## and scores against this, and Leave scores higher as it rises - see
## Data/customer_ai/conditions/intoxication_order_gate.tres and
## intoxication_leave_scoring.tres.
var intoxication: float = 0.0

## 0 (not thirsty) - 1 (very thirsty). Phase 2B: seeded from
## CustomerAIBalanceConfig's starting-thirst range, reduced by
## thirst_reduction_per_drink each time a drink finishes. Order Drink scores
## higher as this rises; Relax and Leave score higher as it falls.
var thirst: float = 0.7

## 0 (avoids people) - 1 (seeks company). Static personality trait carried
## into needs so activities can weigh it the same way as a fluctuating need;
## a future "join a conversation" activity would score against this.
var social_tendency: float = 0.5

## World minutes remaining before this customer intends to leave regardless
## of what they're doing, refreshed on demand by
## [method update_remaining_visit_time] rather than ticking down on a timer
## of its own - see that method's doc comment.
var remaining_visit_minutes: float = 30.0

## The total visit length rolled at spawn - what [member remaining_visit_minutes]
## counts down from. Kept separate so scoring conditions can compare "how
## much is left" against "how much there was" if a future activity needs a
## ratio rather than an absolute number.
var visit_duration_minutes: float = 30.0

## World-clock minutes ([code]WorldTime.get_total_minutes()[/code]) at the
## moment this visit's clock started (arrival at the seat) - the anchor
## [method update_remaining_visit_time] measures elapsed time against.
var _visit_started_at_minutes: float = 0.0

## Why this customer came in. A free-form tag rather than an enum, so a
## future "meet a merchant" or "hire crew" purpose needs no change here -
## just a new tag and an activity that checks for it.
var visit_purpose: StringName = &"drink"

## Drinks this customer has personally favoured, independent of the shared
## [member CustomerType.preferred_drink]. Nothing writes to this yet; the
## intended future use is "remembers what they liked last time" once
## save/load exists. Not part of [method set_need]/[method get_need]'s
## float-only API - it is a list, not a single value.
var preferred_drinks: Array[DrinkDefinition] = []

## Activity ids ([member ActivityDefinition.activity_id]) this customer
## favours. Nothing writes to this yet; the intended future use is a soft
## utility bonus in [method ActivityDefinition.get_utility] so two customers
## with identical needs still behave a little differently.
var favourite_activity_tags: Array[StringName] = []

## Other actors this customer has a relationship with. Stubbed as an empty
## array of [Node], deliberately untyped to a future Relationship resource
## that does not exist yet - the brief asks only to leave room for it.
var relationships: Array[Node] = []

## Standing with the tavern - tips well, causes trouble, is a regular.
## Stubbed at 0.0; nothing reads or writes it yet.
var reputation: float = 0.0

## Phase 2B.2: how many times Relax at Seat has completed this visit -
## RepeatDecayCondition reads this to make repeated relaxing progressively
## less attractive. Incremented in Customer.begin_relaxing().
var relax_count: float = 0.0

## Phase 2C: how many times Socialise at Seat / Darts have completed this
## visit - same repetition-tracking role as relax_count, read by their own
## RepeatDecayCondition instances.
var socialise_count: float = 0.0
var darts_count: float = 0.0

## Phase 2B.2: how many drinks have been consumed this visit - mirrors
## Customer.drinks_consumed_this_visit as a scoreable need, so Leave (and
## potentially other activities) can read it the same way as any other
## need rather than needing a bespoke domain flag. Incremented in
## Customer._on_drink_finished().
var drinks_consumed: float = 0.0

## Phase 2C: seeded from Personality.travel_willingness at spawn - a plain
## field rather than routed through get_need()/set_need() like the others,
## since nothing ever changes it mid-visit the way mood or thirst does.
## Read directly by NearestPointDistanceCondition.
var travel_willingness: float = 1.0

## Phase 2C: "reasons to stay" - temporary positive engagement from
## something the customer is currently enjoying (a completed Socialise or
## Darts visit). Raised by TavernActivityPoint.engagement_effect /
## SocialiseAtSeatBehaviour on completion; decayed a little every time a
## decision is made (see decay_engagement()) rather than on its own timer,
## so two customers who both got engaged never drift out of sync with an
## independent clock each. Never gates Leave and never grows without bound
## - see leave_engagement_scoring.tres for how it pulls Leave down, and the
## class doc comment on why this is a need like any other rather than a
## special case.
var engagement: float = 0.0

## Seeded from CustomerAIBalanceConfig.engagement_decay_per_decision in
## seed_from() - stored here rather than read by CustomerBrain each time so
## CustomerBrain never needs its own reference to CustomerAIBalanceConfig,
## consistent with it already only holding needs/registry/report_manager.
var _engagement_decay_per_decision: float = 0.05


## Seeds every starting value at spawn. [param balance] and [param personality]
## are both optional - a null [param balance] leaves the Phase 1 defaults
## above untouched (money 0, thirst 0.7, etc.), so a test or a future actor
## configured without Phase 2B's balancing resource still works.
func seed_from(
	customer_type: CustomerType,
	personality: Personality,
	balance: CustomerAIBalanceConfig = null
) -> void:
	var wealth_multiplier: float = 1.0
	var appetite_multiplier: float = 1.0
	var duration_multiplier: float = 1.0

	if personality != null:
		mood = personality.baseline_mood
		energy = personality.baseline_energy
		social_tendency = personality.social_tendency
		wealth_multiplier = personality.wealth_multiplier
		appetite_multiplier = personality.drink_appetite
		duration_multiplier = personality.visit_duration_multiplier
		travel_willingness = personality.travel_willingness

	if balance != null:
		_engagement_decay_per_decision = balance.engagement_decay_per_decision

		wealth = roundi(
			randf_range(
				float(balance.minimum_starting_money),
				float(balance.maximum_starting_money)
			) * wealth_multiplier
		)

		thirst = clampf(
			randf_range(
				balance.minimum_starting_thirst,
				balance.maximum_starting_thirst
			) * appetite_multiplier,
			0.0,
			1.0
		)

		mood = clampf(
			randf_range(
				balance.minimum_starting_satisfaction,
				balance.maximum_starting_satisfaction
			),
			0.0,
			1.0
		)

		# Per-type band first, global range only as the fallback. A type that
		# leaves both at 0 behaves exactly as before.
		var duration_floor: float = float(
			balance.minimum_visit_duration_minutes
		)
		var duration_ceiling: float = float(
			balance.maximum_visit_duration_minutes
		)

		if (
			customer_type != null
			and customer_type.visit_duration_minimum_minutes > 0
			and customer_type.visit_duration_maximum_minutes > 0
		):
			duration_floor = float(
				customer_type.visit_duration_minimum_minutes
			)
			duration_ceiling = float(
				customer_type.visit_duration_maximum_minutes
			)

		if duration_ceiling < duration_floor:
			duration_ceiling = duration_floor

		visit_duration_minutes = maxf(
			1.0,
			randf_range(
				duration_floor,
				duration_ceiling
			) * duration_multiplier
		)
	elif customer_type != null:
		# Phase 1 fallback, unchanged, for a customer configured without
		# CustomerAIBalanceConfig.
		visit_duration_minutes = float(
			customer_type.patience_duration_minutes
			+ customer_type.order_delay_minutes
		) * 2.0

	remaining_visit_minutes = visit_duration_minutes


## Starts the visit-time clock. Call once, when the customer actually settles
## - seated ([method Customer.arrive_at_seat]) or standing in a group
## formation slot ([code]Customer._on_reached_group_slot()[/code]) - not at
## spawn, so walking to the table does not eat into the intended visit length.
##
## Restarts the clock unconditionally. Use [method ensure_visit_clock_started]
## from any path that might run more than once per visit.
func start_visit_clock(current_world_minutes: float) -> void:
	_visit_started_at_minutes = current_world_minutes
	remaining_visit_minutes = visit_duration_minutes


## Whether this visit's clock has begun counting down yet.
##
## Exists because "never started" and "expired" both read
## [member remaining_visit_minutes] == 0.0, which is not a distinction any
## caller can make from the value alone - and the two want opposite
## behaviour from every visit-time gate.
func has_visit_clock_started() -> bool:
	return _visit_started_at_minutes > 0.0


## Starts the visit clock only if it has not already started.
##
## A group member can reach its formation slot several times in one visit -
## after a delivery step-back, after darts, after a reform - and each arrival
## runs the same settle path. Calling [method start_visit_clock] there
## directly would hand that member a fresh full-length visit every time it
## sat back down, so it would never leave.
func ensure_visit_clock_started(current_world_minutes: float) -> void:
	if has_visit_clock_started():
		return

	start_visit_clock(current_world_minutes)


## Refreshes [member remaining_visit_minutes] against elapsed world time.
## Deliberately not a per-frame or repeating-timer countdown (the brief
## explicitly asks to avoid that) - this is plain elapsed-time arithmetic,
## cheap enough to call every time CustomerBrain builds a decision context,
## which is the only time the value needs to be current.
##
## A customer whose clock has not started yet reports its FULL duration
## rather than zero. Previously the subtraction ran against
## _visit_started_at_minutes = 0.0, so remaining collapsed to zero once the
## world clock passed the rolled duration - within the first game-hour of a
## session. Every unsettled customer then looked like it was out of time:
## Visit Tavern Activity was gated out (it needs 8 minutes left),
## leave_end_of_visit_pressure was maxed, and every visit-time scoring
## condition read 0. That was 68% of all customer-samples.
func update_remaining_visit_time(current_world_minutes: float) -> void:
	if not has_visit_clock_started():
		remaining_visit_minutes = visit_duration_minutes
		return

	remaining_visit_minutes = maxf(
		0.0,
		visit_duration_minutes
		- (current_world_minutes - _visit_started_at_minutes)
	)


func adjust(
	need_id: StringName,
	delta: float
) -> void:
	set_need(need_id, get_need(need_id) + delta)


func set_need(
	need_id: StringName,
	value: float
) -> void:
	var clamped: float = value

	if (
		need_id != &"wealth"
		and need_id != &"remaining_visit_minutes"
		and need_id != &"relax_count"
		and need_id != &"drinks_consumed"
		and need_id != &"socialise_count"
		and need_id != &"darts_count"
	):
		clamped = clampf(value, 0.0, 1.0)

	match need_id:
		&"mood": mood = clamped
		&"wealth": wealth = int(clamped)
		&"patience": patience = clamped
		&"energy": energy = clamped
		&"intoxication": intoxication = clamped
		&"thirst": thirst = clamped
		&"social_tendency": social_tendency = clamped
		&"remaining_visit_minutes": remaining_visit_minutes = clamped
		&"relax_count": relax_count = clamped
		&"drinks_consumed": drinks_consumed = clamped
		&"socialise_count": socialise_count = clamped
		&"darts_count": darts_count = clamped
		&"engagement": engagement = clamped
		_:
			push_warning(
				"CustomerNeeds has no need called '"
				+ String(need_id)
				+ "'."
			)
			return

	need_changed.emit(need_id, clamped)


func get_need(need_id: StringName) -> float:
	match need_id:
		&"mood": return mood
		&"wealth": return float(wealth)
		&"patience": return patience
		&"energy": return energy
		&"intoxication": return intoxication
		&"thirst": return thirst
		&"social_tendency": return social_tendency
		&"remaining_visit_minutes": return remaining_visit_minutes
		&"relax_count": return relax_count
		&"drinks_consumed": return drinks_consumed
		&"socialise_count": return socialise_count
		&"darts_count": return darts_count
		&"engagement": return engagement
		_:
			push_warning(
				"CustomerNeeds has no need called '"
				+ String(need_id)
				+ "'."
			)
			return 0.0


## Called once per decision (CustomerBrain._build_context()) rather than on
## its own timer - see [member engagement]'s doc comment for why. A small,
## configurable multiplicative decay: engagement halves roughly every
## [code]log(0.5)/log(1-decay_rate)[/code] decisions, never reaches exactly
## zero, and never goes negative.
func decay_engagement() -> void:
	if _engagement_decay_per_decision <= 0.0:
		return

	engagement = maxf(
		0.0,
		engagement * (1.0 - _engagement_decay_per_decision)
	)
