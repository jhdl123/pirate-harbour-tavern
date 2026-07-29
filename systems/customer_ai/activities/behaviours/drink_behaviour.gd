class_name DrinkBehaviour
extends ActivityBehaviour

## Bookkeeping only, for now - the mechanics still live on [Customer].
##
## [method Customer.interact] is the interaction framework's actual entry
## point (the player clicks the customer while carrying the right drink); it
## still does 100% of the validation, item consumption, patience cancellation,
## chair hand-off and [method Customer._on_drink_finished] scheduling itself,
## completely unchanged by this pass. All this behaviour does is exist, so
## [CustomerBrain.enter_activity] can record "this customer is now Drinking"
## as a real, queryable [ActivityDefinition] instead of an untracked engine
## state - which is what the brief's activity list asked for.
##
## Splitting the validated serving transaction out of [method Customer.
## interact] and into this behaviour is a reasonable next step once a second
## thing can happen during drinking (nursing a drink slowly, a spilled-drink
## complication) - not done here, to avoid touching working, ticklish
## player-interaction code without a way to test the change live. See
## [code]docs/CUSTOMER_AI_SYSTEM.md[/code].
