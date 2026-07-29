class_name ActivityBehaviour
extends Resource

## What actually happens while an [ActivityDefinition] is running.
##
## [ActivityDefinition] is data: identity, scoring, which destination it
## needs. This is the other half - what the customer actually does. Splitting
## them means a designer can retune an activity's scoring without touching
## behaviour code, and a new activity that behaves identically to an existing
## one (say, two different "watch a performer" variants) can share one
## behaviour and differ only in data.
##
## A plain [Resource], not a [Node]: stateless and shareable, the same as
## [ActivityCondition]. Nothing here may store per-customer state on
## [code]self[/code] - two customers running the same activity share the same
## behaviour instance. Any state belongs on [ActivityContext.actor] or
## [ActivityContext.needs].
##
## [b]Event-driven, not polled.[/b] [method tick] exists for an activity that
## genuinely has nothing to react to (a slow environmental effect, a future
## Wander repositioning itself every so often) - it is deliberately not
## called every frame for every running activity. [CustomerBrain] currently
## re-evaluates only at real decision points (seated, activity finished,
## patience expired), matching this project's existing avoid-polling
## convention elsewhere ([WorldTime]'s scheduler, [ActionRunner]'s
## world-time-scaled progress). See [code]docs/CUSTOMER_AI_SYSTEM.md[/code]
## for how each concrete behaviour signals that it is done.


## Called once, the moment [CustomerBrain] switches to this activity, after
## any destination reservation succeeds. This is where an order gets placed,
## a drink starts being served, or an exit begins.
func on_enter(_context: ActivityContext) -> void:
	pass


## Called by [CustomerBrain] on whatever cadence a specific activity needs
## (most do not need this at all - see the class doc comment). Return true
## once this activity is finished and [CustomerBrain] should re-evaluate.
func tick(_context: ActivityContext) -> bool:
	return true


## Called once, the moment this activity stops running - because it finished
## naturally ([param completed] true) or because [CustomerBrain] interrupted
## it for something more urgent ([param completed] false, e.g. patience
## running out mid-Wander). Release anything this activity was holding that
## [CustomerBrain] does not already release itself (it always releases the
## destination reservation - see [method CustomerBrain._exit_current]).
func on_exit(_context: ActivityContext, _completed: bool) -> void:
	pass
