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
