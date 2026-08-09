class_name CarriedItemPolicy
extends Resource

## What a worker does with something it is still holding when the task that
## gave it to it ends.
##
## Phase 3A had no answer to this question, and the gap produced the bug this
## refinement exists to fix: a serving task was cancelled after the drink had
## been collected, the worker went straight back to the board, and it cleaned
## chairs with a pint of ale in its hand for the rest of the session.
##
## The outcomes are tried in the order listed in [member outcome_order], and
## the first one that succeeds wins. Every one of them moves the item through
## a real inventory transaction - there is no branch anywhere that simply
## clears the slot and hopes.
##
## The policy is a Resource so a future cook holding a raw ingredient, or a
## stock runner holding a keg, can be given completely different priorities
## without a line of code changing.


enum Outcome {
	## Hand it to another waiting customer who ordered the same thing.
	##
	## The best outcome by a distance: the drink is already poured and already
	## in somebody's hands, so reassigning it costs nothing and saves the
	## player from pouring a second one.
	REASSIGN,

	## Put it back in a free bar service slot.
	##
	## Restores the pre-collection situation exactly. The player can pick it
	## up again, and the scoring bonus for an already-prepared drink means the
	## next matching order will find it.
	RETURN_TO_SERVICE_SLOT,

	## Give it back to the station that produces it.
	##
	## Uses the station's own "put back" transaction - the same one the player
	## gets when they walk up to a station holding a drink it serves.
	RETURN_TO_SOURCE_STATION,

	## Put it into general stock storage, if storage will accept it.
	##
	## Rarely applicable to prepared drinks, which storage rejects by tag, but
	## it is the natural home for a future ingredient or tool.
	RETURN_TO_STORAGE,

	## Keep holding it.
	##
	## Only chosen when the worker may legitimately carry it while doing
	## something else, or when nothing better is available and
	## [member allow_retaining_as_last_resort] is on.
	RETAIN,

	## Destroy it, and say so loudly.
	##
	## The explicit fallback. It exists so that "nowhere to put it" can never
	## become "worker permanently jammed", but it always writes a diagnostic
	## event, and it is off unless [member allow_disposal] is enabled.
	DISPOSE,
}


@export_category("Identity")

## Shown in diagnostics so a report can tell two policies apart.
@export var policy_id: StringName = &"default_carried_item_policy"


@export_category("Recovery Order")

## Outcomes to attempt, best first.
##
## Removing an entry disables that route entirely. Reordering changes what the
## worker prefers without changing what it is capable of.
@export var outcome_order: Array[Outcome] = [
	Outcome.REASSIGN,
	Outcome.RETURN_TO_SERVICE_SLOT,
	Outcome.RETURN_TO_SOURCE_STATION,
	Outcome.RETURN_TO_STORAGE,
	Outcome.RETAIN,
]


@export_category("Reassignment")

## How far the worker will look for another customer wanting the same item.
##
## Zero means no limit. A limit stops a worker crossing the whole tavern to
## reassign one drink while more urgent work sits next to it.
@export_range(0.0, 4000.0, 10.0)
var maximum_reassignment_distance: float = 0.0

## Whether reassignment may claim a task another worker has already taken.
##
## Off, and it should stay off: stealing a claim to save one drink causes far
## more churn than pouring another.
@export var may_steal_claimed_tasks: bool = false


@export_category("Fallbacks")

## Whether the worker may keep carrying an item when nothing else works.
##
## On by default. Holding a drink is untidy but harmless, and it keeps the
## item in the world where the player can still take it back.
@export var allow_retaining_as_last_resort: bool = true

## Whether the worker may destroy the item when every other route failed.
##
## Off by default. Turn it on only if a jam is worse than the loss.
@export var allow_disposal: bool = false


@export_category("Behaviour While Carrying")

## Whether a worker holding an unrelated item may still take other work.
##
## Off is the fix for the Phase 3A bug. Leaving it off means the worker deals
## with what is in its hands before doing anything else, which is both correct
## and what a person would do.
@export var may_work_while_holding_unrelated_item: bool = false

## Seconds a failed recovery waits before being retried.
##
## Stops a worker with an unreturnable item spinning on the same failing
## attempt every frame.
## How many times recovery may fail before the worker stops re-planning.
##
## Without a bound, a carried item nothing will accept re-plans forever on the
## retry timer: EVALUATING_TASKS -> RECOVERING_ITEM -> EVALUATING_TASKS, with
## the worker never doing anything else. The retry delay throttles that loop
## but never ends it. After this many failures the worker makes one last
## unfiltered attempt at any destination, then gives up on putting the item
## down and returns to normal work still holding it.
@export_range(1, 20, 1)
var maximum_recovery_attempts: int = 3

## Whether the final attempt may ignore the preferred outcome order.
##
## The ordered strategies exist to put an item somewhere sensible. Once they
## have all failed, somewhere is better than nowhere - so the last attempt
## takes any destination that will accept the item rather than insisting on
## the nicest one.
@export var escalate_to_any_destination: bool = true

@export_range(0.0, 120.0, 0.5)
var recovery_retry_seconds: float = 5.0


func get_outcome_order() -> Array[Outcome]:
	if outcome_order.is_empty():
		# An empty list would silently disable recovery altogether, which is
		# exactly the failure this policy exists to prevent.
		return [
			Outcome.RETURN_TO_SERVICE_SLOT,
			Outcome.RETAIN,
		]

	return outcome_order


static func get_outcome_name(
	outcome: Outcome
) -> String:
	return Outcome.keys()[outcome]
