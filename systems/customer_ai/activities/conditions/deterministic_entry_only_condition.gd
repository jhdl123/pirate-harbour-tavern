class_name DeterministicEntryOnlyCondition
extends ActivityCondition

## Hard gate, always false: for an activity meant to be entered only via
## [method CustomerBrain.enter_activity]/[method CustomerBrain.force_activity]
## (which never call [method ActivityDefinition.is_available]), never through
## normal [method CustomerBrain.think] competition.
##
## Found via a real bug: [code]return_to_seat.tres[/code] had zero
## conditions, so it was unconditionally "available" - most of the time
## harmless, since something else usually outscores an activity with no
## conditions and base_utility 0, but a customer whose other options were
## all gated out (nothing affordable, no partner, activity unavailable)
## could have [code]think()[/code] pick it normally while already sitting at
## its own chair. "Returning" from exactly where it already is resolves
## instantly, re-triggering think() immediately - an oscillation that reads
## as "Chosen: return_to_seat" printed dozens of times in a burst rather
## than a hang, but it never actually decides anything else.


func is_satisfied(_context: ActivityContext) -> bool:
	return false


func get_rejection_reason(_context: ActivityContext) -> String:
	return "deterministic-entry-only activity"
