class_name CustomerBrain
extends Node

## Runs the brief's Think -> Evaluate -> Choose -> Reserve -> Navigate ->
## Perform -> Re-evaluate loop for one actor.
##
## Deliberately generic states only ([State] below) - never
## [code]CustomerOrderingBeer[/code] or similar. What the actor is actually
## doing is data ([ActivityDefinition]), not a state; the state machine only
## tracks the actor's *relationship* to that data (thinking about it,
## travelling to it, doing it).
##
## [b]Event-driven, not polled.[/b] There is no [method Node._process] here.
## [method think] is called by the actor at real decision points (seated,
## an activity finished, patience ran out) - see
## [code]docs/CUSTOMER_AI_SYSTEM.md[/code] for exactly where [Customer] calls
## it today, and the "Performance considerations" section for why polling
## every frame was rejected.
##
## [b]Reusable by design.[/b] Nothing here is typed to [Customer] - the actor
## is a plain [Node], and everything it needs to expose is either
## [CustomerNeeds] (shared with any future actor that has needs) or the
## optional [code]get_activity_flags()[/code] duck-type (see
## [ActivityContext.domain_flags]). A future bartender or NPC can use this
## same brain with its own registry and its own flags.
##
## [b]Normal vs. mandatory transitions.[/b] Three ways to change activity,
## deliberately distinct:
## - [method think] - normal decision. Every registered activity competes on
##   utility; only ones whose conditions all pass are even candidates.
## - [method enter_activity] - a known-good, deterministic transition where
##   today's loop has no real branch yet (seated -> order; served -> drink).
##   Still skips scoring, but the definition must exist and is entered as-is
##   - it does not re-check conditions, on the assumption the caller already
##   knows this transition is valid right now.
## - [method force_activity] - a mandatory, interrupting transition (patience
##   ran out, the tavern is closing, a fire alarm, guards remove someone).
##   Bypasses conditions entirely, same as [method enter_activity], but is
##   named and logged separately so "the customer was made to leave" is never
##   confused with "leaving happened to win a normal utility contest" when
##   reading logs or tracing a bug. See [member ActivityDefinition.
##   is_terminal] for how an activity reached this way can end the loop.


signal activity_changed(
	previous: ActivityDefinition,
	current: ActivityDefinition
)

signal activity_forced(
	activity_id: StringName,
	reason: StringName
)


enum State {
	## Between activities, about to evaluate what comes next.
	THINKING,

	## Travelling to a chosen activity's destination.
	NAVIGATING,

	## Running the chosen activity's behaviour.
	PERFORMING_ACTIVITY,

	## Chosen an activity that has nothing left to do right now (a reserved
	## destination is occupied by someone else's travel, for instance) and is
	## waiting rather than re-thinking every frame.
	WAITING,

	## On the way out. Reached only through an [ActivityDefinition] with
	## [member ActivityDefinition.is_terminal] set - once here, [method
	## think] and [method enter_activity] both refuse to do anything; only
	## [method force_activity] can still act (a future, more urgent event is
	## allowed to interrupt an ordinary departure; an ordinary decision is
	## not allowed to reopen one).
	LEAVING,
}


var actor: Node = null
var needs: CustomerNeeds = null
var registry: ActivityRegistry = null

## Set from CustomerAIDiagnosticsConfig.console_debug_enabled by whoever
## configures this brain (Customer._configure_ai()). Off by default - see
## docs/CUSTOMER_AI_SYSTEM.md's "Diagnostics" section for what gets logged.
var debug_enabled: bool = false

## Phase 2B: both optional and both null-checked before use everywhere below,
## so normal AI behaviour never depends on either being set - see
## CustomerAIReportManager's own doc comment on why every call into it is
## safe when reporting is disabled.
var report_manager: CustomerAIReportManager = null
var runtime_customer_id: int = -1

var state: State = State.THINKING

var _current_activity: ActivityDefinition = null
var _current_destination: Reservable = null

## The activity_id this actor was last in during this visit, stamped by
## _exit_current() - see ActivityContext.last_activity_id's doc comment.
var _last_activity_id: StringName = &""

## This customer's identity - type, personality, visit intention. Optional:
## a null identity leaves every score exactly as it was before identities
## existed, so an unconfigured test harness still behaves.
var identity: CustomerIdentity = null

## Score floor for weighted selection. An activity scoring below this is
## never selected even if it is the only candidate above the others - the
## brief's "low-scoring nonsensical actions must not be selected merely
## because randomness exists". Falls back to Leave when nothing clears it.
var minimum_selection_score: float = 0.0

## How far below the top score an activity may sit and still be considered.
## 0.0 restores exact argmax; the default keeps genuinely close calls in
## the running without ever admitting a badly-scoring action.
var selection_band: float = 0.25

## True during deterministic diagnostics: selection takes the top score
## rather than a weighted draw, so a run reproduces exactly.
var deterministic_decisions: bool = false

## Verbose per-candidate score logging for the developer menu.
var verbose_scoring: bool = false

## World minutes when the current activity was entered, for the commitment
## floor.
var _activity_entered_at_minutes: float = 0.0

## Rolled duration of the current activity, 0.0 when the behaviour decides.
var _activity_target_minutes: float = 0.0

## activity_id -> world minutes at which its cooldown expires.
var _cooldowns: Dictionary = {}

## Selection RNG. Shared with the identity when there is one, so
## deterministic mode covers decisions as well as traits.
var _rng: RandomNumberGenerator = null

## Un-gated snapshot of the most recent decision, always populated
## regardless of report_manager/diagnostics-export state - see
## CUSTOMER_INSPECTOR.md and Stage 3 of
## docs/history/2026-08-25_CUSTOMER_ARCHITECTURE_AUDIT.md's plan. The
## export-gated report_manager path in [method _report_decision] still
## exists unchanged for the aggregate diagnostic history; this is the
## "right now, for this one customer" equivalent a hover/select panel
## needs, and previously did not exist at all - candidate scores and
## rejection reasons were computed every decision but only reached
## anywhere when export happened to be enabled.
var _last_decision: DecisionRecord = null

## "" (nothing to report) or a short player-facing description of what
## went wrong after the last activity was entered - set by [method _enter]
## when a destination reservation fails. See CUSTOMER_INSPECTOR.md:
## "Reservation and execution outcomes must appear here, not only
## selection."
var _last_execution_outcome: String = ""


func get_last_decision() -> DecisionRecord:
	return _last_decision


func get_last_execution_outcome() -> String:
	return _last_execution_outcome


func configure(
	for_actor: Node,
	for_needs: CustomerNeeds,
	for_registry: ActivityRegistry
) -> void:
	actor = for_actor
	needs = for_needs
	registry = for_registry


func get_current_activity() -> ActivityDefinition:
	return _current_activity


## Full Evaluate -> Choose -> Reserve -> Perform pass.
##
## Call this at a genuine, ordinary decision point: an activity finished, a
## timer ran out with no particular urgency, nothing else told the actor
## what to do next. Every registered activity is checked, not just the ones
## already known to matter, so a newly-added activity is automatically
## considered without this method changing - see [method
## ActivityRegistry.validate_or_warn] for why [member ActivityRegistry.
## definitions] rather than a cached "available" list is walked directly
## here.
##
## Does nothing once [member state] is [constant State.LEAVING] - see the
## class doc comment on normal vs. mandatory transitions.
func think() -> void:
	if state == State.LEAVING:
		return

	if registry == null or actor == null:
		return

	var previous_id: StringName = (
		_current_activity.activity_id if _current_activity != null else &""
	)

	# Phase 2B.2, mandatory: no money left and nothing left to finish means
	# there is nothing left this visit could still do, so this bypasses
	# normal competitive scoring entirely - the same "mandatory, not a
	# normal decision" reasoning as patience/visit-time expiry, just
	# triggered from here rather than a scheduled event, since "ran out of
	# money" is discovered exactly when a decision is being made rather than
	# on its own timer. See docs/CUSTOMER_AI_SYSTEM.md's Phase 2B.2 section.
	if needs != null and needs.wealth <= 0:
		var probe_context: ActivityContext = _build_context()

		var has_order: bool = bool(
			probe_context.domain_flags.get(&"has_ordered_drink", false)
		)

		var has_drink: bool = bool(
			probe_context.domain_flags.get(&"has_drink_to_consume", false)
		)

		if not has_order and not has_drink:
			force_activity(&"leave", &"out_of_money")
			return

	# Item 4 of docs/history/2026-08-25_CUSTOMER_ARCHITECTURE_AUDIT.md's
	# plan: this was previously computed but never consulted - the
	# commitment floor only worked by accident, via roll_duration_minutes()
	# keeping the current activity's own scheduled completion from firing
	# early. That protects against the activity's own timer but not against
	# some other caller invoking think() mid-commitment. Checked after the
	# out-of-money override above (which must still act regardless of
	# commitment) and before scoring - an ordinary re-decision arriving
	# during the floor simply does nothing, leaving the current activity
	# running; force_activity() is untouched and can still interrupt at any
	# time, matching this method's own doc comment.
	if is_committed(WorldTime.get_total_minutes()):
		return

	_exit_current(false)

	state = State.THINKING

	var context: ActivityContext = _build_context()

	# Stage 2 (CUSTOMER_MODEL.md §4): what do I currently want, chosen once
	# per think() call before any activity is scored. Mandatory pipeline
	# steps (order_drink, drink) and Wander's always-available fallback are
	# exempt from the filter this feeds below - see the
	# `not definition.is_mandatory` check in the loop - so this only
	# decides which *optional* activities even compete this pass. `leave`
	# is also exempt from the filter, but for a different reason - see the
	# stage-1 handling below.
	var motivation: StringName = _select_motivation(context)

	var best: ActivityDefinition = null
	var best_score: float = -INF

	# Stage 1 (CUSTOMER_MODEL.md §4): "should this visit continue" needs
	# leave compared against the true best alternative, not the motivation-
	# thinned field stage 3 uses - otherwise leave wins purely because its
	# rivals were filtered out from under it, not because leaving actually
	# scored better than everything. Tracked across every candidate,
	# unfiltered, in the same pass. Correction from live measurement after
	# `87aa238`: leave was top scorer 433/994 times in the motivation-gated
	# pool at a mean score of -8.30 - it was winning by default, not on
	# merit. See docs/history/2026-08-25_CUSTOMER_ARCHITECTURE_AUDIT.md.
	var unfiltered_best: ActivityDefinition = null
	var unfiltered_best_score: float = -INF

	var eligible_for_report: Array[Dictionary] = []
	var rejected_for_report: Array[Dictionary] = []
	var record_rejections: bool = (
		report_manager != null
		and report_manager.is_export_enabled()
		and report_manager.diagnostics_config != null
		and report_manager.diagnostics_config.record_rejection_reasons
	)

	var contributions_for_report: Dictionary = {}
	var record_contributions: bool = (
		report_manager != null
		and report_manager.is_export_enabled()
		and report_manager.diagnostics_config != null
		and report_manager.diagnostics_config.record_decision_history
	)

	for definition: ActivityDefinition in registry.definitions:
		if definition == null:
			continue

		if not definition.is_available(context):
			var reason: String = definition.get_rejection_reason(context)

			if debug_enabled:
				print(
					"[CustomerBrain] ", _actor_label(),
					" rejected '", definition.activity_id,
					"': ", reason
				)

			if record_rejections:
				rejected_for_report.append({
					"activity_id": String(definition.activity_id),
					"reason": reason,
				})

			continue

		if is_on_cooldown(definition, context.world_minutes):
			if record_rejections:
				rejected_for_report.append({
					"activity_id": String(definition.activity_id),
					"reason": "cooling_down",
				})

			continue

		var score: float = definition.get_utility(context)

		# Visit intention bias. Applied here rather than as another
		# ActivityCondition because it is per-customer runtime data, not
		# authored per-activity - a condition would have needed one .tres
		# per activity per intent.
		if identity != null:
			score += identity.get_activity_bias(definition.activity_id)

		if is_nan(score) or is_inf(score):
			_report_invalid_score(definition, score)
			continue

		eligible_for_report.append({
			"activity_id": String(definition.activity_id),
			"score": score,
		})

		if record_contributions:
			var breakdown: Dictionary = definition.get_utility_breakdown(
				context
			)
			breakdown["activity_id"] = String(definition.activity_id)
			contributions_for_report[String(definition.activity_id)] = (
				breakdown
			)

		# Stage 1 tracking - every scored candidate, leave included,
		# motivation-unfiltered. See the doc comment above.
		if score > unfiltered_best_score:
			unfiltered_best_score = score
			unfiltered_best = definition

		# The terminal (departure) activity already had its fair, unfiltered
		# shot just above and must not compete a second time inside the
		# motivation-thinned stage-3 pool - see the doc comment above.
		# Checked by is_terminal, not a hard-coded activity_id, so a future
		# activity never needs a brain change here - see the extension test
		# in CUSTOMER_MODEL.md §5. Every other mandatory activity and
		# Wander (empty ActivityDefinition.satisfies) remain exempt from
		# the motivation filter itself, unchanged.
		if definition.is_terminal:
			continue

		# Stage 3 filter (CUSTOMER_MODEL.md §4): an optional activity only
		# competes when it serves the motivation stage 2 chose. Mandatory
		# activities and Wander (empty ActivityDefinition.satisfies) are
		# exempt - see ActivityDefinition.serves_motivation().
		if (
			not definition.is_mandatory
			and not definition.serves_motivation(motivation)
		):
			if record_rejections:
				rejected_for_report.append({
					"activity_id": String(definition.activity_id),
					"reason": (
						"does not serve current motivation (%s)"
						% motivation
					),
				})

			continue

		if score > best_score:
			best_score = score
			best = definition

	# Stage 1 decision: the terminal (departure) activity wins outright -
	# taken, not sampled, same as any mandatory activity - only when it
	# beat the true best alternative above, not merely whatever survived
	# stage 3's motivation filter.
	if unfiltered_best != null and unfiltered_best.is_terminal:
		best = unfiltered_best
		best_score = unfiltered_best_score

	# Weighted selection among the strongest candidates.
	#
	# This replaces the old `best` argmax result. Argmax was the single
	# largest cause of customers looking scripted: identical inputs gave an
	# identical activity every time, so every sailor in the room walked the
	# same sequence in the same order. Selecting among near-equal candidates
	# instead keeps the decision sensible while breaking the lockstep.
	#
	# Mandatory activities are exempt - when order_drink or leave wins on
	# score, it is taken, not sampled. Service must not be left to chance.
	if best != null and not best.is_mandatory:
		var sampled: ActivityDefinition = _select_weighted(
			eligible_for_report, best_score
		)

		if sampled != null:
			best = sampled

	if best == null:
		state = State.WAITING

		if debug_enabled:
			print(
				"[CustomerBrain] ", _actor_label(),
				" has no available activity - WAITING"
			)

		CustomerBehaviourEvents.emit_decision_evaluated(
			identity, eligible_for_report, rejected_for_report, &""
		)

		_report_decision(
			previous_id, eligible_for_report, rejected_for_report,
			&"", false, &"", contributions_for_report, motivation
		)

		return

	if debug_enabled or verbose_scoring:
		_print_decision_block(eligible_for_report, best.activity_id)

	# Behaviour events. Emitted here rather than inside _enter() so that a
	# decision is reported even when the entry then fails to reserve a
	# destination - the aggregate report needs to see the decision either
	# way, or "decisions with no valid action" undercounts.
	CustomerBehaviourEvents.emit_decision_evaluated(
		identity, eligible_for_report, rejected_for_report, best.activity_id
	)
	CustomerBehaviourEvents.emit_action_selected(
		identity, best.activity_id, best_score
	)

	_enter(best, context)

	_report_decision(
		previous_id, eligible_for_report, rejected_for_report,
		best.activity_id, false, &"", contributions_for_report, motivation
	)


## Direct transition to a named activity, bypassing scoring but not
## conditions' meaning - only ever call this for a transition that is
## already known to be valid (see the class doc comment). Refuses once
## [member state] is [constant State.LEAVING], the same as [method think].
##
## For a transition that must happen regardless of whether it would
## ordinarily be considered valid, use [method force_activity] instead.
func enter_activity(activity_id: StringName) -> bool:
	if state == State.LEAVING:
		return false

	var definition: ActivityDefinition = _get_definition_or_warn(
		activity_id,
		"enter_activity"
	)

	if definition == null:
		return false

	var previous_id: StringName = (
		_current_activity.activity_id if _current_activity != null else &""
	)

	_exit_current(false)

	_enter(definition, _build_context())

	_report_decision(previous_id, [], [], activity_id, false, &"", {}, &"")

	return true


## Mandatory, interrupting transition - for an event that must happen no
## matter what any [ActivityCondition] would say and no matter what the
## actor is currently doing, including already leaving. [param reason] is a
## short tag for diagnostics/logging (e.g. [code]&"patience_expired"[/code],
## [code]&"tavern_closing"[/code], [code]&"fire_alarm"[/code],
## [code]&"removed_by_guards"[/code]) - purely informational, never read by
## any condition.
##
## Deliberately still goes through the same reserve-then-[method
## ActivityBehaviour.on_enter] pipeline as [method think] and [method
## enter_activity] - a forced transition is not a special code path, it is
## an ordinary activity entered without the ordinary gate.
func force_activity(
	activity_id: StringName,
	reason: StringName = &""
) -> bool:
	var definition: ActivityDefinition = _get_definition_or_warn(
		activity_id,
		"force_activity"
	)

	if definition == null:
		return false

	if debug_enabled:
		print(
			"[CustomerBrain] ", _actor_label(),
			" FORCED into '", activity_id,
			"' (reason: ", (
				String(reason) if not reason.is_empty() else "unspecified"
			), ")"
		)

	activity_forced.emit(activity_id, reason)

	var previous_id: StringName = (
		_current_activity.activity_id if _current_activity != null else &""
	)

	_exit_current(false)

	_enter(definition, _build_context())

	_report_decision(previous_id, [], [], activity_id, true, reason, {}, &"")

	return true


## Ends the loop entirely without entering a new activity - for a caller
## that wants to stop everything but has no replacement [ActivityDefinition]
## to hand it (a plain engine-level shutdown). Prefer [method force_activity]
## with a real "leave"-shaped, [member ActivityDefinition.is_terminal]
## activity when one exists, since that still runs its behaviour's
## [method ActivityBehaviour.on_enter].
func begin_leaving_permanently() -> void:
	_exit_current(false)
	state = State.LEAVING


func _get_definition_or_warn(
	activity_id: StringName,
	caller_name: String
) -> ActivityDefinition:
	if registry == null:
		return null

	var definition: ActivityDefinition = registry.get_definition(
		activity_id
	)

	if definition == null:
		push_warning(
			"CustomerBrain." + caller_name
			+ "() received an unknown activity id '"
			+ String(activity_id)
			+ "'."
		)

	return definition


func _enter(
	definition: ActivityDefinition,
	context: ActivityContext
) -> void:
	if definition.behaviour == null and debug_enabled:
		print(
			"[CustomerBrain] ", _actor_label(),
			" entering '", definition.activity_id,
			"' which has no behaviour assigned - it will do nothing."
		)

	if definition.destination_tag.is_empty():
		_last_execution_outcome = ""

		_current_activity = definition
		_current_destination = null

		state = State.LEAVING if definition.is_terminal else State.PERFORMING_ACTIVITY

		activity_changed.emit(null, definition)

		CustomerBehaviourEvents.emit_activity_started(
			identity, definition.activity_id
		)

		if definition.behaviour != null:
			definition.behaviour.on_enter(context)

		return

	state = State.NAVIGATING

	var tree: SceneTree = actor.get_tree()
	var reserved: Reservable = null

	if tree != null:
		reserved = DestinationBroker.reserve_nearest(
			definition.destination_tag,
			actor,
			context.actor_position,
			tree
		)

	if reserved == null:
		# Its DestinationAvailableCondition should have ruled this out
		# already; treat losing the race to another actor the same way as
		# never having had a candidate, rather than getting stuck.
		state = State.WAITING

		# Un-gated, for the inspector - see CUSTOMER_INSPECTOR.md's
		# "Reservation and execution outcomes must appear here, not
		# only selection." The report_manager path below still exists
		# unchanged for the aggregate diagnostic history.
		_last_execution_outcome = (
			"reservation failed: no free '%s' destination"
			% definition.destination_tag
		)

		if debug_enabled:
			print(
				"[CustomerBrain] ", _actor_label(),
				" could not reserve a '", definition.destination_tag,
				"' destination for '", definition.activity_id,
				"' - WAITING"
			)

		if report_manager != null:
			report_manager.record_activity_failure(runtime_customer_id)
			report_manager.report_issue(
				runtime_customer_id,
				&"activity_selected_but_unable_to_start",
				"Could not reserve a '%s' destination for '%s'." % [
					definition.destination_tag, definition.activity_id
				]
			)

		return

	_last_execution_outcome = ""

	_current_activity = definition
	_current_destination = reserved
	context.reserved_destination = reserved

	# Pacing state for this entry. Rolled per entry, not per definition, so
	# two customers starting the same activity together still finish apart.
	_activity_entered_at_minutes = context.world_minutes
	_activity_target_minutes = definition.roll_duration_minutes(
		context, _get_rng()
	)

	if identity != null and identity.visit_intent != null:
		# A celebrating crew lingers; a quick drink does not.
		_activity_target_minutes *= (
			identity.visit_intent.visit_duration_multiplier
		)

	CustomerBehaviourEvents.emit_activity_started(
		identity, definition.activity_id
	)

	state = State.LEAVING if definition.is_terminal else State.PERFORMING_ACTIVITY

	activity_changed.emit(null, definition)

	if definition.behaviour != null:
		definition.behaviour.on_enter(context)


## Records that this actor is already participating in [param definition]
## via [param reservable] - for a co-opted second participant (e.g. a darts
## partner) who was invited directly rather than choosing this through
## [method think]/[method _enter]. Deliberately does not call [param
## definition]'s [member ActivityDefinition.behaviour] - the initiator's
## own [code]on_enter()[/code] already ran and is what invited this actor;
## calling it again here would re-run partner search recursively. Only sets
## the same bookkeeping [method _enter] would have, so this actor's own
## eventual [method _exit_current] still releases [param reservable] and
## stamps [member _last_activity_id] correctly, the same as if it had
## entered normally.
func assume_activity(
	definition: ActivityDefinition,
	reservable: Reservable
) -> void:
	_current_activity = definition
	_current_destination = reservable

	var context: ActivityContext = _build_context()

	_activity_entered_at_minutes = context.world_minutes
	_activity_target_minutes = definition.roll_duration_minutes(
		context, _get_rng()
	)

	if identity != null and identity.visit_intent != null:
		_activity_target_minutes *= (
			identity.visit_intent.visit_duration_multiplier
		)

	CustomerBehaviourEvents.emit_activity_started(
		identity, definition.activity_id
	)

	state = State.LEAVING if definition.is_terminal else State.PERFORMING_ACTIVITY

	activity_changed.emit(null, definition)


## Releases whatever destination reservation and behaviour the current
## activity holds, without entering a replacement or re-evaluating - for a
## caller (Customer, recovering from a failed journey to an activity point)
## that needs the reservation gone right now and will decide what happens
## next itself. Leaves [member state] as [constant State.THINKING] so a
## subsequent [method think] or [method enter_activity] behaves normally.
func abandon_current_activity() -> void:
	_exit_current(false)
	state = State.THINKING


func _exit_current(completed: bool) -> void:
	if _current_activity == null:
		return

	# Cooldown starts when the activity ends, not when it began, so a long
	# activity is not already re-selectable the moment it finishes.
	begin_cooldown(_current_activity, WorldTime.get_total_minutes())

	CustomerBehaviourEvents.emit_activity_ended(
		identity,
		_current_activity.activity_id,
		completed
	)

	var finished: ActivityDefinition = _current_activity

	_last_activity_id = finished.activity_id

	var context: ActivityContext = _build_context()

	if finished.behaviour != null:
		finished.behaviour.on_exit(context, completed)

	if _current_destination != null:
		_current_destination.release(actor)

	_current_activity = null
	_current_destination = null

	activity_changed.emit(finished, null)


## Stage 2 of CUSTOMER_MODEL.md §4: which named motivation is currently
## most worth pursuing. All four needs are demand-shaped (high means
## wanted) since the 2026-08-25 correction - see
## [member CustomerNeeds.social]'s doc comment for why the original
## satisfaction-shaped/[code]1.0 - value[/code] version was wrong - so all
## four are read directly and identically here.
## Personality/visit-intent bias nudges the weights the same way
## [method CustomerIdentity.get_activity_bias] nudges stage 3, one stage
## earlier. Group context already reaches darts specifically through the
## existing, unchanged [code]group_not_drinking_scoring.tres[/code]
## condition at stage 3 - deliberately not duplicated here, to avoid
## penalising group cohesion twice for the same fact.
func _select_motivation(context: ActivityContext) -> StringName:
	var weights: Dictionary = {
		&"thirst": (needs.thirst if needs != null else 0.0),
		&"social": (needs.social if needs != null else 0.0),
		&"entertainment": (needs.entertainment if needs != null else 0.0),
		&"relaxation": (needs.relaxation if needs != null else 0.0),
	}

	if identity != null:
		for motivation_id: StringName in weights.keys():
			weights[motivation_id] = maxf(
				0.0,
				(
					float(weights[motivation_id])
					+ identity.get_motivation_bias(motivation_id)
				)
			)

	if context != null:
		context.motivation_weights = weights

	return _weighted_pick_motivation(weights)


## Weighted-random among the four motivation weights, the same
## selection-among-near-equal-candidates principle [method _select_weighted]
## already applies at stage 3 - a motivation is not always simply the
## single highest-weighted one, so customers stay unpredictable at this
## stage too. Falls back to the highest weight in deterministic mode or
## when every weight is zero.
func _weighted_pick_motivation(weights: Dictionary) -> StringName:
	if deterministic_decisions:
		return _argmax_motivation(weights)

	var total: float = 0.0

	for value: Variant in weights.values():
		total += maxf(0.0, float(value))

	if total <= 0.0:
		return _argmax_motivation(weights)

	var roll: float = _get_rng().randf() * total
	var running: float = 0.0

	for motivation_id: StringName in weights.keys():
		running += maxf(0.0, float(weights[motivation_id]))

		if roll <= running:
			return motivation_id

	return _argmax_motivation(weights)


func _argmax_motivation(weights: Dictionary) -> StringName:
	var best_id: StringName = &"thirst"
	var best_weight: float = -INF

	for motivation_id: StringName in weights.keys():
		var weight: float = float(weights[motivation_id])

		if weight > best_weight:
			best_weight = weight
			best_id = motivation_id

	return best_id


func _build_context() -> ActivityContext:
	var position: Vector2 = Vector2.ZERO

	var actor_2d: Node2D = actor as Node2D

	if actor_2d != null:
		position = actor_2d.global_position

	if needs != null:
		var world_minutes_now: float = WorldTime.get_total_minutes()

		needs.update_remaining_visit_time(world_minutes_now)
		needs.update_motivational_needs(world_minutes_now)

	var context: ActivityContext = ActivityContext.create(
		actor,
		needs,
		position
	)

	if actor != null and actor.has_method("get_activity_flags"):
		context.domain_flags = actor.get_activity_flags()

	context.identity = identity
	context.world_minutes = WorldTime.get_total_minutes()
	context.last_activity_id = _last_activity_id

	return context


func _actor_label() -> String:
	if actor != null:
		return actor.name

	return "<unknown actor>"


## The brief's console format: one block per decision, easy to read during a
## live playtest. The per-candidate print()s above (considered/rejected)
## stay too - this is a summary on top, not a replacement.
func _print_decision_block(
	eligible: Array[Dictionary],
	chosen_id: StringName
) -> void:
	print("Customer ", _actor_label(), ":")

	if needs != null:
		print("Money: £", needs.wealth)
		print("Visit Time Remaining: ", roundi(needs.remaining_visit_minutes), "m")
		print("Thirst: ", roundi(needs.thirst * 100))
		print("Intoxication: ", roundi(needs.intoxication * 100))
		print("Satisfaction: ", roundi(needs.mood * 100))

	print("")

	var scores: Array[float] = []

	for entry: Dictionary in eligible:
		print(
			"%s: %.1f" % [entry["activity_id"], entry["score"]]
		)
		scores.append(float(entry["score"]))

	scores.sort()
	scores.reverse()

	print("")

	if scores.size() >= 2:
		print("Margin: %.1f" % (scores[0] - scores[1]))

	print("Chosen: ", chosen_id)
	print("")


func _report_decision(
	previous_id: StringName,
	eligible: Array[Dictionary],
	rejected: Array[Dictionary],
	selected_id: StringName,
	was_forced: bool,
	forced_reason: StringName,
	contributions: Dictionary,
	motivation: StringName = &""
) -> void:
	# Built unconditionally - see [member _last_decision]'s doc comment on
	# why this no longer depends on report_manager/export being enabled.
	var record := DecisionRecord.new()
	record.customer_id = runtime_customer_id
	record.game_time_minutes = WorldTime.get_total_minutes()
	record.previous_activity_id = String(previous_id)
	record.eligible_activities = eligible
	record.rejected_activities = rejected
	record.selected_activity_id = String(selected_id)
	record.was_forced = was_forced
	record.forced_reason = String(forced_reason)
	record.motivation = String(motivation)

	if not contributions.is_empty():
		var typed_contributions: Array[Dictionary] = []

		for value: Dictionary in contributions.values():
			typed_contributions.append(value)

		record.utility_contributions = typed_contributions

	var scores: Array[float] = []

	for entry: Dictionary in eligible:
		scores.append(float(entry["score"]))

	scores.sort()
	scores.reverse()

	record.top_score = scores[0] if scores.size() >= 1 else 0.0
	record.second_score = scores[1] if scores.size() >= 2 else 0.0
	record.margin = record.top_score - record.second_score

	if needs != null:
		record.money = needs.wealth
		record.thirst = needs.thirst
		record.satisfaction = needs.mood
		record.intoxication = needs.intoxication
		record.visit_time_remaining_minutes = needs.remaining_visit_minutes
		record.social = needs.social
		record.entertainment = needs.entertainment
		record.relaxation = needs.relaxation

		if report_manager != null:
			report_manager.record_motivational_needs(
				runtime_customer_id, needs.social, needs.entertainment,
				needs.relaxation
			)

	if actor != null and actor.has_method("get_diagnostics_snapshot"):
		var snapshot: Dictionary = actor.get_diagnostics_snapshot()
		record.drinks_consumed = snapshot.get("drinks_consumed", 0)
		record.has_active_order = snapshot.get("has_active_order", false)
		record.selected_activity_point_id = snapshot.get(
			"current_activity_point", ""
		)
		record.social_partner_customer_id = snapshot.get(
			"social_partner_customer_id", -1
		)
		record.activity_partner_customer_id = snapshot.get(
			"activity_partner_customer_id", -1
		)
		record.return_to_seat_required = (
			record.selected_activity_point_id != ""
		)

	record.execution_outcome = _last_execution_outcome

	if report_manager != null:
		record.recent_activity_history = (
			report_manager.get_recent_activity_history(runtime_customer_id)
		)

	_last_decision = record

	if report_manager != null and report_manager.is_export_enabled():
		report_manager.record_decision(record)


func _report_invalid_score(
	definition: ActivityDefinition,
	score: float
) -> void:
	push_warning(
		"CustomerBrain: '"
		+ String(definition.activity_id)
		+ "' produced an invalid utility score ("
		+ str(score)
		+ ") and was skipped this think() pass."
	)

	if report_manager != null:
		report_manager.report_issue(
			runtime_customer_id,
			&"invalid_score",
			"Activity '%s' produced score %s." % [
				definition.activity_id, score
			]
		)


## Picks among the candidates within [member selection_band] of the top
## score, weighted by how far each sits above [member minimum_selection_score].
##
## Weighting by score-above-floor rather than by raw score matters: raw
## scores can be negative or clustered far from zero, and weighting by those
## directly makes the draw either meaningless or degenerate. Distance above
## the floor is always positive and always proportional to "how much better
## than barely-acceptable this is".
##
## Returns null when nothing qualifies, leaving the caller's argmax result
## in place.
func _select_weighted(
	eligible: Array[Dictionary],
	best_score: float
) -> ActivityDefinition:
	if eligible.size() <= 1:
		return null

	if deterministic_decisions:
		return null

	if best_score < minimum_selection_score:
		return null

	var threshold: float = maxf(
		minimum_selection_score,
		best_score - (absf(best_score) * selection_band)
	)

	var candidates: Array[ActivityDefinition] = []
	var weights: Array[float] = []
	var total: float = 0.0

	for entry: Dictionary in eligible:
		var score: float = float(entry["score"])

		if score < threshold:
			continue

		var definition: ActivityDefinition = registry.get_definition(
			StringName(entry["activity_id"])
		)

		if definition == null or definition.is_mandatory:
			continue

		var weight: float = maxf(
			0.01, score - minimum_selection_score
		)

		candidates.append(definition)
		weights.append(weight)
		total += weight

	if candidates.size() <= 1 or total <= 0.0:
		return null

	var roll: float = _get_rng().randf() * total
	var running: float = 0.0

	for index: int in candidates.size():
		running += weights[index]

		if roll <= running:
			return candidates[index]

	return candidates[candidates.size() - 1]


## True when [param definition] is still cooling down and may not be
## re-selected. Mandatory activities are never on cooldown.
func is_on_cooldown(
	definition: ActivityDefinition,
	world_minutes: float
) -> bool:
	if definition == null or definition.is_mandatory:
		return false

	if not _cooldowns.has(definition.activity_id):
		return false

	return world_minutes < float(_cooldowns[definition.activity_id])


## True when the current activity has not yet run for its committed minimum
## and should not be interrupted by an ordinary re-decision.
##
## Mandatory activities and an explicit [method force_activity] both bypass
## this - a commitment floor must never be able to keep a customer in an
## optional activity while the tavern is closing or their group is leaving.
func is_committed(world_minutes: float) -> bool:
	if _current_activity == null:
		return false

	if _current_activity.is_mandatory:
		return false

	if _current_activity.minimum_commitment_minutes <= 0.0:
		return false

	var elapsed: float = world_minutes - _activity_entered_at_minutes

	return elapsed < _current_activity.minimum_commitment_minutes


## True when the current activity has run past its rolled target duration
## and should end. Callers poll this from their existing state handling
## rather than a per-frame timer here.
func has_exceeded_duration(world_minutes: float) -> bool:
	if _current_activity == null or _activity_target_minutes <= 0.0:
		return false

	return (world_minutes - _activity_entered_at_minutes) >= _activity_target_minutes


## Starts [param definition]'s cooldown from now.
func begin_cooldown(
	definition: ActivityDefinition,
	world_minutes: float
) -> void:
	if definition == null or definition.cooldown_minutes <= 0.0:
		return

	_cooldowns[definition.activity_id] = (
		world_minutes + definition.cooldown_minutes
	)


func get_cooldowns() -> Dictionary:
	return _cooldowns.duplicate()


## The RNG used for selection - the identity's when there is one, so
## deterministic mode covers traits and decisions together, otherwise a
## private randomized instance.
func _get_rng() -> RandomNumberGenerator:
	if identity != null and identity.rng != null:
		return identity.rng

	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()

	return _rng
