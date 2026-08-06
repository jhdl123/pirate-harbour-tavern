class_name ActivityDefinition
extends Resource

## One thing a customer (or any future actor) can choose to do.
##
## Deliberately a single, non-subclassed [Resource] rather than one script
## per activity, the same way [OrderCatalogueEntry] does not need a subclass
## per supplier item. Adding a new activity - Play Darts, Watch Musicians,
## Gossip - should ordinarily mean: create one of these, give it a few
## [ActivityCondition]s, point [member behaviour] at a shared or new
## [ActivityBehaviour], and register it in an [ActivityRegistry]. A bespoke
## activity that genuinely needs unique logic still only needs a new
## [ActivityBehaviour] subclass, never a change to this class,
## [ActivityRegistry] or [CustomerBrain].


@export_category("Identity")

## Stable id, e.g. [code]&"order_drink"[/code]. Never the display name -
## matches this project's existing item/order id conventions.
@export var activity_id: StringName = &""

@export var display_name: String = "Unnamed Activity"


@export_category("Scoring")

## Flat starting point before any [ActivityCondition]'s
## [method ActivityCondition.score] is added. Higher means "prefer this by
## default"; see [method get_utility].
@export var base_utility: float = 0.0

## Every condition must be satisfied for this activity to be a candidate at
## all ([method is_available]); every condition's score is added together
## for [method get_utility]. An empty array means always available, scored
## on [member base_utility] alone.
@export var conditions: Array[ActivityCondition] = []


@export_category("Destination")

## Which [Reservable] tag this activity needs reserved before
## [member behaviour]'s [method ActivityBehaviour.on_enter] runs -
## [code]&"chair"[/code], [code]&"bar"[/code], [code]&"fireplace"[/code].
## Empty means this activity needs no destination of its own (it runs
## wherever the actor already is, e.g. Leave, which reuses whichever chair
## is already reserved).
@export var destination_tag: StringName = &""


@export_category("Lifecycle")

## Once [CustomerBrain] enters an activity with this set, it stops
## responding to [method CustomerBrain.think] and [method
## CustomerBrain.enter_activity] entirely ([member CustomerBrain.state]
## becomes [constant CustomerBrain.State.LEAVING]) - only [method
## CustomerBrain.force_activity] can still act on that actor afterwards. Set
## this only on an activity that truly ends the loop, e.g. Leave - never on
## an ordinary activity, or an actor could get permanently stuck the moment
## normal scoring happened to choose it.
@export var is_terminal: bool = false


@export_category("Execution")

## What actually happens while this activity runs. See [ActivityBehaviour].
@export var behaviour: ActivityBehaviour


## Every condition satisfied - a hard "can this even be chosen" gate,
## checked before [method get_utility] is ever computed for this activity.
func is_available(context: ActivityContext) -> bool:
	context.activity = self

	for condition: ActivityCondition in conditions:
		if condition == null:
			continue

		if not condition.is_satisfied(context):
			return false

	return true


## [member base_utility] plus every condition's [method ActivityCondition.
## score]. Only meaningful for an activity that already passed
## [method is_available] - callers are expected to check that first, the
## same way [ItemTransferService] validates before it applies.
func get_utility(context: ActivityContext) -> float:
	context.activity = self

	var utility: float = base_utility

	for condition: ActivityCondition in conditions:
		if condition == null:
			continue

		utility += condition.score(context)

	return utility


## Phase 2C, diagnostics only: the same total as [method get_utility], but
## broken into named buckets by each condition's
## [member ActivityCondition.contribution_label] - a condition with no label
## set folds into [code]"other_contribution"[/code] rather than vanishing,
## so the breakdown's total always reconciles with the final score. Only
## called when a decision is actually being recorded
## ([member CustomerBrain.report_manager] is set and export is enabled) -
## see [code]CustomerBrain._report_decision()[/code].
func get_utility_breakdown(context: ActivityContext) -> Dictionary:
	context.activity = self

	var breakdown: Dictionary = {"base_score": base_utility}
	var total: float = base_utility

	for condition: ActivityCondition in conditions:
		if condition == null:
			continue

		var contribution: float = condition.score(context)
		var label: StringName = condition.contribution_label

		if label.is_empty():
			label = &"other_contribution"

		breakdown[String(label)] = breakdown.get(String(label), 0.0) + contribution
		total += contribution

	breakdown["final_score"] = total

	return breakdown


## Diagnostics only - never used for gating. The first condition currently
## blocking this activity, or an empty string if it is actually available.
## [CustomerBrain.think] calls this only when [member CustomerBrain.
## debug_enabled] is on, so it costs nothing during normal play.
func get_rejection_reason(context: ActivityContext) -> String:
	context.activity = self

	for condition: ActivityCondition in conditions:
		if condition == null:
			continue

		if not condition.is_satisfied(context):
			return condition.get_rejection_reason(context)

	return ""


func validate_or_warn() -> bool:
	var is_valid: bool = true

	if activity_id.is_empty():
		push_error(
			"ActivityDefinition "
			+ resource_path
			+ " has no activity_id."
		)

		is_valid = false

	if behaviour == null:
		push_warning(
			"ActivityDefinition '"
			+ String(activity_id)
			+ "' has no behaviour - it will be chosen and do nothing."
		)

	return is_valid


@export_category("Identity Foundation - Pacing")

## World minutes this activity must run before the brain will reconsider.
##
## Without a commitment floor, weighted selection makes customers twitch:
## a re-decision arriving a second after the last one can flip to a
## near-equal-scoring activity, and the customer visibly dithers. Zero keeps
## the old immediate-reconsideration behaviour.
@export_range(0.0, 120.0, 0.5)
var minimum_commitment_minutes: float = 0.0

## Target duration before the activity ends of its own accord. Zero means
## the behaviour decides, as it does today.
@export_range(0.0, 240.0, 0.5)
var target_duration_minutes: float = 0.0

## Hard ceiling on the duration. Zero means no ceiling. Guards against the
## endless actions the brief rules out.
@export_range(0.0, 480.0, 0.5)
var maximum_duration_minutes: float = 0.0

## World minutes after this activity ends before it may be selected again.
##
## This is the hard version of what [RepeatDecayCondition] does softly. Decay
## makes a repeat progressively less attractive; a cooldown makes it
## impossible for a while. Both are useful: decay for "getting bored of
## relaxing", a cooldown for "you cannot possibly want another darts match
## thirty seconds later".
@export_range(0.0, 240.0, 0.5)
var cooldown_minutes: float = 0.0

## When true, this activity is exempt from cooldown and commitment checks.
##
## [b]Mandatory lifecycle work sets this.[/b] Ordering, drinking, paying and
## leaving must never be blocked because an optional-activity pacing rule
## happened to be counting down - that would strand a customer mid-service.
## Set on order_drink, drink and leave.
@export var is_mandatory: bool = false


## How long this activity should run for one customer, in world minutes.
##
## Rolled per entry rather than fixed, so a room full of customers does not
## complete the same activity on the same tick - which is what made the old
## behaviour look scripted. Restless customers finish sooner; the intent's
## own pacing is applied by the caller.
##
## Returns 0.0 when no target is authored, meaning "the behaviour decides",
## which is the pre-existing path for every activity that ends on its own
## condition rather than a clock.
func roll_duration_minutes(
	context: ActivityContext,
	rng: RandomNumberGenerator
) -> float:
	if target_duration_minutes <= 0.0:
		return 0.0

	var duration: float = target_duration_minutes

	if rng != null:
		# +/-25% spread around the authored target.
		duration *= rng.randf_range(0.75, 1.25)

	if context != null and context.needs != null:
		var restlessness: float = 0.5
		var identity: Variant = context.get(&"identity")

		if identity != null and identity.personality != null:
			restlessness = identity.personality.restlessness

		# Restless customers cut it short, patient ones stretch it:
		# 0.0 restlessness -> x1.25, 1.0 -> x0.75.
		duration *= 1.25 - (restlessness * 0.5)

	duration = maxf(duration, minimum_commitment_minutes)

	if maximum_duration_minutes > 0.0:
		duration = minf(duration, maximum_duration_minutes)

	return maxf(0.0, duration)
