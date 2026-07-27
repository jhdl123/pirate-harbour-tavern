class_name Interactable
extends Area2D

## Marks a region of the world as something the player can interact with.
##
## This node is the entire public surface of an object as far as the interaction
## framework is concerned. [InteractionDetector] finds it, [InteractionSelector]
## scores and selects it, [InteractionPromptUI] describes it. None of them know
## what the object actually is.
##
## The gameplay lives in the [b]provider[/b] - normally the object's root node.
## A provider opts into the framework by implementing any of these methods. All
## of them are optional and duck-typed, so an object implements only what it
## needs and never inherits from a base class it does not want.
##
## [codeblock]
## get_interaction_display_name() -> String
##     Player-facing object name. Falls back to the exported display_name.
##
## get_interaction_point(from_position: Vector2) -> Vector2
##     Where the interaction happens. Used for distance scoring and for
##     positioning the prompt. Defaults to this node's global position.
##     The bar counter returns its nearest service slot.
##
## can_interact(request: InteractionRequest) -> bool
##     Cheap early-out. An object with no available actions is skipped anyway,
##     so only implement this when the check is cheaper than listing actions.
##
## get_interaction_actions(request: InteractionRequest)
##         -> Array[InteractionAction]
##     Everything this actor could do right now. Build fresh each call.
##
## perform_interaction(request: InteractionRequest) -> bool
##     Run the action named by request.action_id. Return true if something
##     actually happened.
##
## set_interaction_highlighted(
##         enabled: bool, request: InteractionRequest) -> void
##     Custom highlight. Called repeatedly while selected, so it must be
##     idempotent. Omit it to get the InteractionHighlight node behaviour.
## [/codeblock]
##
## [b]Legacy providers.[/b] An object that has none of the above but does have
## [code]interact(player)[/code] still works: it is offered a single primary
## action built from [member fallback_verb], and running it calls
## [code]interact[/code]. That is what keeps chairs and customers selectable
## while they wait their turn to be migrated properly.


## The object's available actions may have changed.
##
## Providers call [method notify_state_changed] after anything that alters what
## the player could do - an item placed, a state transition, stock running out.
## The selector re-reads the actions and the prompt updates immediately, rather
## than on the next polling tick.
signal availability_changed(interactable: Interactable)

## An action was successfully run on this object.
signal interaction_performed(
	action: InteractionAction,
	actor: Node
)


@export_category("Identity")

## Player-facing name, used when the provider does not supply one.
##
## Leave empty to fall back to the provider node's name.
@export var display_name: String = ""

## Breaks ties between objects at a similar distance. Higher wins.
##
## Keep this small and meaningful: a customer waiting to be served deserves a
## nudge over the counter they are sitting at, but nothing should be so high
## that the player cannot reach past it.
@export_range(-10, 10, 1)
var interaction_priority: int = 0

## Turns the object off without removing it from the world.
##
## A disabled interactable is never selected and never shows a prompt.
@export var is_interaction_enabled: bool = true


@export_category("Wiring")

## The node holding the gameplay. Defaults to this node's parent.
##
## Only set this when the [Interactable] is not a direct child of the object
## root - for example an interaction area nested under a sub-node.
@export var provider_path: NodePath

## Optional [InteractionHighlight] to drive.
##
## Leave empty to search this node's parent for one.
@export var highlight_path: NodePath


@export_category("Legacy Fallback")

## Verb used for the synthesised action when the provider only has
## [code]interact(player)[/code].
##
## Example: "Clean" on a chair, "Serve" on a customer.
@export var fallback_verb: String = "Use"

## Whether the synthesised action names the object after the verb.
##
## "Serve Customer" reads well, "Clean Chair" does not add much. Off means the
## prompt is just the verb.
@export var fallback_includes_subject: bool = true


var _provider: Node = null
var _highlight: InteractionHighlight = null
var _is_highlighted: bool = false


func _ready() -> void:
	if not is_in_group(&"interactable"):
		add_to_group(&"interactable")

	_resolve_provider()
	_resolve_highlight()


func _resolve_provider() -> void:
	if not provider_path.is_empty():
		_provider = get_node_or_null(provider_path)

		if _provider == null:
			push_warning(
				"Interactable '%s' could not resolve its provider '%s'."
				% [get_path(), provider_path]
			)

	if _provider == null:
		_provider = get_parent()

	if _provider == null:
		push_error(
			"Interactable '%s' has no provider node."
			% get_path()
		)


func _resolve_highlight() -> void:
	if not highlight_path.is_empty():
		_highlight = get_node_or_null(
			highlight_path
		) as InteractionHighlight

		if _highlight != null:
			return

		push_warning(
			"Interactable '%s' could not resolve highlight '%s'."
			% [get_path(), highlight_path]
		)

	if _provider == null:
		return

	for child: Node in _provider.get_children():
		var highlight: InteractionHighlight = (
			child as InteractionHighlight
		)

		if highlight != null:
			_highlight = highlight
			return


# -----------------------------------------------------------------------------
# Provider access
# -----------------------------------------------------------------------------

## The node holding this object's gameplay.
func get_provider() -> Node:
	return _provider


## True when the provider implements the modern action protocol.
##
## False means the object is running on the legacy [code]interact[/code] path.
func uses_action_protocol() -> bool:
	return (
		_provider != null
		and _provider.has_method(&"get_interaction_actions")
	)


func _provider_has(
	method_name: StringName
) -> bool:
	return _provider != null and _provider.has_method(method_name)


# -----------------------------------------------------------------------------
# Description
# -----------------------------------------------------------------------------

## The name shown to the player.
func get_display_name() -> String:
	if _provider_has(&"get_interaction_display_name"):
		var provider_name: String = String(
			_provider.call(&"get_interaction_display_name")
		)

		if not provider_name.is_empty():
			return provider_name

	if not display_name.is_empty():
		return display_name

	if _provider != null:
		return String(_provider.name).capitalize()

	return "Object"


## Where the interaction is considered to happen, in world space.
##
## Used for distance scoring and for anchoring the shared prompt. Objects with
## several interaction points return the one nearest [param from_position].
func get_interaction_position(
	from_position: Vector2
) -> Vector2:
	if _provider_has(&"get_interaction_point"):
		var point: Variant = _provider.call(
			&"get_interaction_point",
			from_position
		)

		if point is Vector2:
			return point

		push_warning(
			"Provider '%s' returned a non-Vector2 interaction point."
			% _provider.name
		)

	return global_position


# -----------------------------------------------------------------------------
# Availability and actions
# -----------------------------------------------------------------------------

## True when this object is worth offering to [param request]'s actor at all.
func can_interact(
	request: InteractionRequest
) -> bool:
	if not is_interaction_enabled:
		return false

	if _provider == null or not is_instance_valid(_provider):
		return false

	if _provider_has(&"can_interact"):
		return bool(_provider.call(&"can_interact", request))

	return true


## Everything [param request]'s actor could do to this object right now.
##
## Always freshly built. An empty array means "nothing to offer", and the
## selector will look elsewhere.
func get_actions(
	request: InteractionRequest
) -> Array[InteractionAction]:
	var actions: Array[InteractionAction] = []

	if not can_interact(request):
		return actions

	if uses_action_protocol():
		var provider_actions: Variant = _provider.call(
			&"get_interaction_actions",
			request
		)

		if provider_actions is Array:
			var returned_actions: Array = provider_actions

			for entry in returned_actions:
				var action: InteractionAction = (
					entry as InteractionAction
				)

				if action != null:
					actions.append(action)

		return actions

	var fallback: InteractionAction = _build_fallback_action()

	if fallback != null:
		actions.append(fallback)

	return actions


## The single action the primary interaction key would run, or null.
func get_primary_action(
	request: InteractionRequest
) -> InteractionAction:
	var best: InteractionAction = null

	for action: InteractionAction in get_actions(request):
		if not action.is_primary():
			continue

		if best == null or action.priority > best.priority:
			best = action

	return best


func _build_fallback_action() -> InteractionAction:
	if not _provider_has(&"interact"):
		return null

	var subject: String = ""

	if fallback_includes_subject:
		subject = get_display_name()

	return InteractionAction.create(
		&"primary",
		fallback_verb,
		subject
	)


# -----------------------------------------------------------------------------
# Execution
# -----------------------------------------------------------------------------

## Runs [param request]'s action against the provider.
##
## Returns true when the object reports that something actually happened.
func perform(
	request: InteractionRequest
) -> bool:
	if not can_interact(request):
		return false

	var performed: bool = false

	if _provider_has(&"perform_interaction"):
		performed = bool(
			_provider.call(&"perform_interaction", request)
		)

	elif _provider_has(&"interact"):
		# Legacy path: no return value and no action id, so the object is
		# trusted to have done whatever it does.
		_provider.call(&"interact", request.actor)
		performed = true

	else:
		push_warning(
			"Interactable '%s' has no way to perform an interaction."
			% get_path()
		)

	if performed:
		var action: InteractionAction = get_primary_action(request)

		interaction_performed.emit(action, request.actor)

	return performed


## Tells the framework that this object's available actions may have changed.
func notify_state_changed() -> void:
	availability_changed.emit(self)


# -----------------------------------------------------------------------------
# Highlight
# -----------------------------------------------------------------------------

## Turns the selected-object visual on or off.
##
## Called repeatedly while the object stays selected so that objects with a
## moving highlight, such as the bar counter's per-slot highlight, can follow
## the player. Implementations must therefore be idempotent.
func set_highlighted(
	enabled: bool,
	request: InteractionRequest
) -> void:
	_is_highlighted = enabled

	if _provider_has(&"set_interaction_highlighted"):
		_provider.call(
			&"set_interaction_highlighted",
			enabled,
			request
		)
		return

	if _highlight != null and is_instance_valid(_highlight):
		_highlight.set_highlighted(enabled)


func is_highlighted() -> bool:
	return _is_highlighted
