class_name LeaveBehaviour
extends ActivityBehaviour

## Starts the walk to the door.
##
## Calls [method Customer.begin_leaving], completely unchanged - the same
## method [method Customer._on_drink_finished] and
## [method Customer._on_patience_expired] used to call directly. Both call
## sites now call [method CustomerBrain.think] instead and let scoring choose
## this activity, which is what turns "always leave after one drink" from a
## hard-coded fact into an outcome [ActivityRegistry] happens to produce
## today - see [code]Data/customer_ai/activities/leave.tres[/code]'s
## [member ActivityDefinition.base_utility] and the
## [NeedThresholdCondition] on mood for how close that outcome is to
## changing without any code edit.


func on_enter(context: ActivityContext) -> void:
	var customer: Customer = context.actor as Customer

	if customer == null:
		return

	customer.begin_leaving()
