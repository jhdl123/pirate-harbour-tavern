class_name RelaxAtSeatBehaviour
extends ActivityBehaviour

## Keeps a seated customer at their chair for a configurable while, then
## asks CustomerBrain to decide again.
##
## Phase 2A's proof that an activity can run for real time and hand control
## back cleanly, rather than either being a placeholder that never finishes
## (Wander) or bookkeeping for something else's mechanics (Drink). Uses
## WorldTime's scheduler, the same event-driven mechanism OrderDrinkBehaviour
## already relies on via Customer's scheduled events - never a per-frame
## count-down.
##
## Stateless and shared, like every [ActivityBehaviour] - the actual
## [ScheduledTimeEvent] this creates is tracked on [Customer] itself
## ([code]_relax_event[/code]), not here, so two customers relaxing at once
## never share state. Cancelling that event if the customer leaves or is
## freed mid-relax is [Customer]'s job (its existing
## [code]_cancel_all_scheduled()[/code], called from [method Customer.
## begin_leaving] and [method Customer.finish_customer]/[code]_exit_tree()
## [/code]) - this behaviour does not need its own [method
## ActivityBehaviour.on_exit] override for that.


@export_category("Duration")

## World minutes. The actual duration is a random point between this and
## [member maximum_duration_minutes] - see [method Customer.begin_relaxing].
@export_range(1.0, 120.0, 1.0)
var minimum_duration_minutes: float = 5.0

@export_range(1.0, 120.0, 1.0)
var maximum_duration_minutes: float = 12.0


func on_enter(context: ActivityContext) -> void:
	var customer: Customer = context.actor as Customer

	if customer == null:
		return

	# Sourced from the activity's own declared ActivityDefinition.satisfies
	# rather than a field on this behaviour, so there is exactly one place
	# that says what Relax at Seat gives back - see DECISIONS.md §21 and
	# item 3 of docs/history/2026-08-25_CUSTOMER_ARCHITECTURE_AUDIT.md's
	# plan.
	var relaxation_gain: float = 0.0

	if context.activity != null:
		relaxation_gain = float(
			context.activity.satisfies.get("relaxation", 0.0)
		)

	customer.begin_relaxing(
		minimum_duration_minutes,
		maximum_duration_minutes,
		relaxation_gain
	)
