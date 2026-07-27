class_name InteractionAction
extends RefCounted

## One thing the player could do to an interactable right now.
##
## An action is a lightweight, throw-away description produced fresh every time
## the interaction system asks an object what it offers. It carries no gameplay
## logic and no state: it says what the action is called, whether it is possible,
## and which object-specific detail the object needs back when the action is
## actually run.
##
## Objects never keep these around. Building them on demand means an action is
## always correct for the current world state.
##
## Only [constant Kind.PRIMARY] is wired to input today. Objects may already
## return secondary and context actions - nothing reads them yet, and nothing
## needs to change in this class when they do.


## How an action is expected to be reached by the player.
##
## The kind is a hint for input and UI layers, never a rule the object enforces.
enum Kind {
	## Bound to the primary interaction key. One per object at a time.
	PRIMARY,

	## Reserved for a future secondary key or modifier.
	SECONDARY,

	## Reserved for a future context menu, verb wheel or mouse interaction.
	CONTEXT,
}


## Stable identifier the object recognises, for example "place", "take",
## "pour", "serve".
##
## Passed straight back to the object inside an [InteractionRequest], so the
## object never has to re-derive which action the player chose.
var id: StringName = &"primary"

## Which input route this action expects. See [enum Kind].
var kind: Kind = Kind.PRIMARY

## What the player does, for example "Pick up", "Place", "Pour", "Serve".
var verb: String = "Use"

## What the action is done to, for example "Grog", "Customer", "Bar Counter".
##
## May be empty for actions that read fine as a bare verb.
var subject: String = ""

## Higher wins when several actions share the same [member kind].
var priority: int = 0

## False when the action is worth showing but cannot be run right now.
##
## The prompt UI can grey these out. The selector never runs one.
var is_available: bool = true

## Short player-facing explanation used when [member is_available] is false.
var unavailable_reason: String = ""

## Object-specific payload returned to the object when the action is run.
##
## Example: the bar counter puts the chosen service slot index in here, so the
## slot the prompt described is exactly the slot that receives the item.
var data: Dictionary = {}


## Builds a ready-to-return action.
##
## Objects should use this rather than constructing and assigning field by
## field, so an added field never silently defaults in one object only.
static func create(
	action_id: StringName,
	action_verb: String,
	action_subject: String = "",
	action_data: Dictionary = {},
	action_kind: Kind = Kind.PRIMARY
) -> InteractionAction:
	var action: InteractionAction = InteractionAction.new()

	action.id = action_id
	action.verb = action_verb
	action.subject = action_subject
	action.data = action_data.duplicate(true)
	action.kind = action_kind

	return action


## Marks the action as visible but not currently possible.
##
## Returns self so it can be chained onto [method create].
func as_unavailable(
	reason: String
) -> InteractionAction:
	is_available = false
	unavailable_reason = reason

	return self


## Sets [member priority] and returns self, for chaining onto [method create].
func with_priority(
	new_priority: int
) -> InteractionAction:
	priority = new_priority

	return self


## The player-facing text, without any key hint.
##
## The prompt UI adds the key, so the same action reads correctly whether it is
## shown as "[E] Pour Grog", as a context menu entry, or as a verb wheel label.
func get_label() -> String:
	if subject.is_empty():
		return verb

	return "%s %s" % [verb, subject]


func is_primary() -> bool:
	return kind == Kind.PRIMARY
