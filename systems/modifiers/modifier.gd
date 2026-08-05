class_name Modifier
extends RefCounted

## One adjustment to one value.
##
## Modifiers are created by events, time profiles, reputation, weather and
## anything else that wants to nudge a number without the system that owns the
## number knowing it exists. The owning system just asks
## [code]Modifiers.evaluate(target, base_value, context)[/code].
##
## [b]Operation order[/b]
##
## Fixed and documented, because "why is this value 1.56?" must have exactly
## one answer:
##
## [codeblock]
## 1. base value
## 2. all ADD modifiers, in priority order
## 3. all MULTIPLY modifiers, in priority order
## 4. MINIMUM and MAXIMUM limits
## 5. OVERRIDE, highest priority wins, applied last and ignoring everything
## [/codeblock]
##
## Override is last and absolute on purpose: it exists for cases like "the
## tavern is closed, arrival rate is zero regardless of any festival", where
## being outvoted by a stack of multipliers would be a bug.


enum Operation {
	## Added to the running total.
	ADD,

	## Multiplied into the running total.
	MULTIPLY,

	## Result may not fall below [member value].
	MINIMUM,

	## Result may not rise above [member value].
	MAXIMUM,

	## Result is [member value], whatever else applied.
	OVERRIDE,
}


enum Stacking {
	## Only one modifier with this id may exist. A second is refused.
	NONE,

	## A new one from the same source replaces the old.
	REPLACE,

	## A new one from the same source resets the old one's expiry.
	REFRESH,

	## Stack up to [member maximum_stacks].
	STACK_LIMITED,

	## Stack without limit. Rarely correct; say so explicitly.
	STACK_UNLIMITED,
}


## Unique within its source. Combined with [member source_id] for stacking.
var modifier_id: StringName = &""

## Who applied this - an event, a time profile, a reputation tier.
var source_id: StringName = &""

## Which value this adjusts. See [ModifierTargets].
var target: StringName = &""

var operation: Operation = Operation.MULTIPLY

var value: float = 1.0

## Higher applies later within its operation group, and wins for OVERRIDE.
var priority: int = 0

var stacking: Stacking = Stacking.REPLACE

var maximum_stacks: int = 1

## Current stack count, for STACK_LIMITED.
var stacks: int = 1


# --- Lifetime ----------------------------------------------------------------

## World minute this becomes active. Negative means "already active".
var start_minutes: float = -1.0

## World minute this expires. Negative means "never".
var end_minutes: float = -1.0


# --- Scope -------------------------------------------------------------------

## Tags the context must have for this to apply. Empty means "always".
##
## This is what makes a modifier selective: a festival that only affects
## sailors carries the tag [code]sailor[/code], and the arrival controller
## passes the archetype's tags when it evaluates.
var required_tags: Array[StringName] = []

## Tags that prevent this applying even if the required tags match.
var excluded_tags: Array[StringName] = []

## Optional narrower scope, for example a specific archetype or room id.
##
## Only checked when the evaluating context supplies a [code]scope[/code] of
## its own. A modifier scoped to a room does not stop applying just because
## the caller asked a tag-based question.
var scope: StringName = &""

## Distinguishes stack keys without affecting whether a modifier applies.
##
## A preset that adjusts two archetypes needs two independent modifiers on one
## target from one source. Folding that distinction into [member scope] made
## them stop matching tag-only contexts, so the two concerns are separate
## fields: this one is bookkeeping, [member scope] is meaning.
var stack_scope: StringName = &""


## Shown in the modifier breakdown. Should read like a sentence fragment.
var label: String = ""


static func create(
	source_id: StringName,
	target: StringName,
	operation: Operation,
	value: float,
	label: String = ""
) -> Modifier:
	var modifier: Modifier = Modifier.new()

	modifier.source_id = source_id
	modifier.modifier_id = StringName(
		"%s:%s" % [String(source_id), String(target)]
	)
	modifier.target = target
	modifier.operation = operation
	modifier.value = value
	modifier.label = (
		label if not label.is_empty() else String(source_id)
	)

	return modifier


## Unique key used for stacking decisions.
func get_stack_key() -> String:
	return "%s|%s|%s|%s" % [
		String(source_id),
		String(target),
		String(scope),
		String(stack_scope),
	]


func is_active_at(
	world_minutes: float
) -> bool:
	if start_minutes >= 0.0 and world_minutes < start_minutes:
		return false

	if end_minutes >= 0.0 and world_minutes >= end_minutes:
		return false

	return true


func is_expired_at(
	world_minutes: float
) -> bool:
	return end_minutes >= 0.0 and world_minutes >= end_minutes


## True when this modifier applies in [param context].
##
## Context is a plain Dictionary carrying whatever the calling system knows -
## typically [code]{ tags: Array[StringName], scope: StringName }[/code]. A
## modifier with no tag requirements applies everywhere, which keeps the common
## case free of ceremony.
func matches_context(
	context: Dictionary
) -> bool:
	# Scope narrows only when the caller is asking a scoped question. A
	# tag-based query should not be silently excluded by a scope it never
	# mentioned.
	if not scope.is_empty() and context.has("scope"):
		if StringName(context["scope"]) != scope:
			return false

	if required_tags.is_empty() and excluded_tags.is_empty():
		return true

	var tags: Array = context.get("tags", [])

	for excluded: StringName in excluded_tags:
		if tags.has(excluded):
			return false

	for required: StringName in required_tags:
		if not tags.has(required):
			return false

	return true


## The contribution this makes, scaled by stack count.
##
## Stacking two ×1.5 modifiers gives ×2.25, not ×3.0 - the operation is applied
## repeatedly rather than the value being multiplied, which is what stacking
## means for a multiplier and stops two stacks of a small buff behaving like
## one enormous one.
func get_effective_value() -> float:
	if stacks <= 1:
		return value

	match operation:
		Operation.ADD:
			return value * float(stacks)

		Operation.MULTIPLY:
			return pow(value, float(stacks))

	return value


func to_dictionary() -> Dictionary:
	return {
		"modifier_id": String(modifier_id),
		"source_id": String(source_id),
		"target": String(target),
		"operation": Operation.keys()[operation],
		"value": value,
		"effective_value": get_effective_value(),
		"priority": priority,
		"stacking": Stacking.keys()[stacking],
		"stacks": stacks,
		"maximum_stacks": maximum_stacks,
		"start_minutes": start_minutes,
		"end_minutes": end_minutes,
		"required_tags": required_tags.duplicate(),
		"excluded_tags": excluded_tags.duplicate(),
		"scope": String(scope),
		"stack_scope": String(stack_scope),
		"label": label,
	}
