class_name OrderDrinkBehaviour
extends ActivityBehaviour

## Chooses a drink and starts the order-delay/patience clock.
##
## This is [Customer.arrive_at_seat]'s old tail, moved here unchanged: it
## still calls [method Customer.choose_order] and still schedules
## [method Customer._on_order_ready] through [WorldTime] exactly as before.
## Only *where* the call happens changed - from an unconditional line inside
## [method Customer.arrive_at_seat] to [CustomerBrain] entering this activity
## - so a seated customer's observable behaviour today is identical to
## before this system existed.
##
## [b]Current scope, honestly stated.[/b] This one activity currently
## represents the whole "get served" arc, because the underlying mechanic
## (waiting for the player to bring the right drink) has no natural
## sub-decision point yet. [DrinkBehaviour] takes over once the player
## actually serves the drink (see its own doc comment) - splitting the wait
## itself into something a customer could abandon (e.g. queue-jumping,
## ordering something else) is a natural next step, not done in this pass.


func on_enter(context: ActivityContext) -> void:
	var customer: Customer = context.actor as Customer

	if customer == null:
		return

	customer.choose_order()

	if customer.ordered_drink == null:
		customer.handle_invalid_destination()
		return

	customer.begin_waiting_to_order()
