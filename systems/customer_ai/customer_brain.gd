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

	_exit_current(false)

	state = State.THINKING

	var context: ActivityContext = _build_context()
	var best: ActivityDefinition = null
	var best_score: float = -INF

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

		var score: float = definition.get_utility(context)

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

		if score > best_score:
			best_score = score
			best = definition

	if best == null:
		state = State.WAITING

		if debug_enabled:
			print(
				"[CustomerBrain] ", _actor_label(),
				" has no available activity - WAITING"
			)

		_report_decision(
			previous_id, eligible_for_report, rejected_for_report,
			&"", false, &"", contributions_for_report
		)

		return

	if debug_enabled:
		_print_decision_block(eligible_for_report, best.activity_id)

	_enter(best, context)

	_report_decision(
		previous_id, eligible_for_report, rejected_for_report,
		best.activity_id, false, &"", contributions_for_report
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

	_report_decision(previous_id, [], [], activity_id, false, &"", {})

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

	_report_decision(previous_id, [], [], activity_id, true, reason, {})

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
		_current_activity = definition
		_current_destination = null

		state = State.LEAVING if definition.is_terminal else State.PERFORMING_ACTIVITY

		activity_changed.emit(null, definition)

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

	_current_activity = definition
	_current_destination = reserved
	context.reserved_destination = reserved

	state = State.LEAVING if definition.is_terminal else State.PERFORMING_ACTIVITY

	activity_changed.emit(null, definition)

	if definition.behaviour != null:
		definition.behaviour.on_enter(context)


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

	var finished: ActivityDefinition = _current_activity
	var context: ActivityContext = _build_context()

	if finished.behaviour != null:
		finished.behaviour.on_exit(context, completed)

	if _current_destination != null:
		_current_destination.release(actor)

	_current_activity = null
	_current_destination = null

	activity_changed.emit(finished, null)


func _build_context() -> ActivityContext:
	var position: Vector2 = Vector2.ZERO

	var actor_2d: Node2D = actor as Node2D

	if actor_2d != null:
		position = actor_2d.global_position

	if needs != null:
		needs.update_remaining_visit_time(WorldTime.get_total_minutes())
		needs.decay_engagement()

	var context: ActivityContext = ActivityContext.create(
		actor,
		needs,
		position
	)

	if actor != null and actor.has_method("get_activity_flags"):
		context.domain_flags = actor.get_activity_flags()

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
	contributions: Dictionary
) -> void:
	if report_manager == null or not report_manager.is_export_enabled():
		return

	var record := DecisionRecord.new()
	record.customer_id = runtime_customer_id
	record.game_time_minutes = WorldTime.get_total_minutes()
	record.previous_activity_id = String(previous_id)
	record.eligible_activities = eligible
	record.rejected_activities = rejected
	record.selected_activity_id = String(selected_id)
	record.was_forced = was_forced
	record.forced_reason = String(forced_reason)

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
		record.engagement = needs.engagement

		report_manager.record_engagement(runtime_customer_id, needs.engagement)

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
		record.return_to_seat_required = (
			record.selected_activity_point_id != ""
		)

	record.recent_activity_history = report_manager.get_recent_activity_history(
		runtime_customer_id
	)

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
