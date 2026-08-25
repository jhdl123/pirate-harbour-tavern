class_name ActivityContext
extends RefCounted

## Everything a condition, a scorer or a behaviour needs to do its job.
##
## Mirrors [InteractionRequest] from the interaction framework: one small
## parameter object instead of every [ActivityCondition] and
## [ActivityBehaviour] method taking four or five separate arguments. Building
## one is cheap ([RefCounted], not a [Resource]) so [CustomerBrain] creates a
## fresh one every think cycle and every tick.


## The customer this context belongs to. Untyped [Node] rather than
## [Customer] on purpose: nothing in the activity system is allowed to assume
## its actor is a customer specifically, so a future staff member or NPC can
## reuse every condition, behaviour and the brain itself unchanged.
var actor: Node

## The actor's needs. Present for anything that reuses [CustomerNeeds];
## null for an actor type that does not have needs yet.
var needs: CustomerNeeds

## World position the actor is deciding from. Read once per think cycle
## rather than every condition re-reading [code]actor.global_position[/code].
var actor_position: Vector2

## Seconds since the last tick. Zero outside [method ActivityBehaviour.tick].
var delta: float = 0.0

## The activity currently being scored or run, once one has been chosen.
## Null while [CustomerBrain] is still evaluating candidates.
var activity: ActivityDefinition = null

## Whatever concrete, actor-specific flags this actor's own conditions need
## (e.g. [code]&"has_ordered_drink"[/code], [code]&"is_seated"[/code]).
## Populated by [CustomerBrain] via [param actor]'s optional
## [code]get_activity_flags() -> Dictionary[/code] method, if it has one.
## This is the escape hatch that keeps [ActivityCondition] itself generic:
## the framework never hard-codes what a customer, or a future staff member,
## considers meaningful - each actor type defines its own flags.
var domain_flags: Dictionary = {}

## Phase 2C: the [Reservable] [CustomerBrain._enter] just reserved for this
## activity, when [member ActivityDefinition.destination_tag] is not empty -
## null otherwise, and null while still just being scored (only set once an
## activity is actually entered). Lets a behaviour like
## [VisitTavernActivityBehaviour] reach the exact reserved spot (and, via
## [method Reservable.get_parent], whatever world object owns it) without
## re-running its own [DestinationBroker] search and potentially finding a
## different one.
var reserved_destination: Reservable = null


static func create(
	for_actor: Node,
	for_needs: CustomerNeeds,
	position: Vector2
) -> ActivityContext:
	var context := ActivityContext.new()

	context.actor = for_actor
	context.needs = for_needs
	context.actor_position = position

	return context


## This customer's identity for the visit - type, personality and visit
## intention. Null on a customer configured without one (a bare test
## harness), and every reader must tolerate that: a null identity means
## "no bias", so scoring falls back to exactly the pre-identity behaviour.
var identity: CustomerIdentity = null


## World minutes now, used for cooldown and commitment arithmetic. Supplied
## by CustomerBrain from the existing world clock rather than an independent
## timer, per the single-authoritative-clock rule.
var world_minutes: float = 0.0


## The activity_id this actor was last in during this visit, or &"" if none
## yet. Set by CustomerBrain._exit_current() - the one place every activity
## exit already passes through - and read by PreviousActivityAffinityCondition
## so "just finished drinking" can nudge socialising, "just finished darts"
## can nudge another drink, and so on, without CustomerBrain itself knowing
## anything about specific activities.
var last_activity_id: StringName = &""


## Stage 2's motivation weights (CUSTOMER_MODEL.md §4) for this decision -
## {&"thirst": float, &"social": float, &"entertainment": float,
## &"relaxation": float} - set by [method CustomerBrain._select_motivation]
## purely for diagnostics/inspector visibility. Never read by
## [ActivityCondition]s; the chosen motivation itself already did its work
## by the time any condition runs.
var motivation_weights: Dictionary = {}
