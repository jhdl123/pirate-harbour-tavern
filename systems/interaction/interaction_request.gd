class_name InteractionRequest
extends RefCounted

## Everything an interactable needs to know about who is asking, and what for.
##
## One request type is used for both questions the framework asks an object:
##
## [codeblock]
## "What could this actor do to you?"   -> get_interaction_actions(request)
## "Do this specific action."           -> perform_interaction(request)
## [/codeblock]
##
## Passing a request object rather than loose arguments means new information -
## a facing direction, a mouse position, a staff member instead of the player -
## can be added later without touching a single interactable.
##
## [b]Note:[/b] [member interactable] is typed as [Node] rather than
## [Interactable] on purpose. [Interactable] already depends on this class, and
## a mutual dependency between two [code]class_name[/code] scripts is a
## needless risk. It always holds an [Interactable].


## Who is interacting. The player today, staff later.
##
## Interactables should duck-type what they need from the actor
## ([code]get_item_carrier[/code], [code]get_action_runner[/code]) rather than
## assume it is the player.
var actor: Node = null

## Where the actor is in world space.
##
## Objects with several interaction points, such as the bar counter's service
## slots, use this to decide which point the request refers to.
var actor_position: Vector2 = Vector2.ZERO

## The [Interactable] node being asked. See the class note above.
var interactable: Node = null

## Which action is being run. Empty while actions are only being listed.
var action_id: StringName = &""

## The chosen action's [member InteractionAction.data], passed straight back.
var data: Dictionary = {}


static func create(
	request_actor: Node,
	request_interactable: Node,
	request_action_id: StringName = &"",
	action_data: Dictionary = {}
) -> InteractionRequest:
	var request: InteractionRequest = InteractionRequest.new()

	request.actor = request_actor
	request.interactable = request_interactable
	request.action_id = request_action_id
	request.data = action_data

	var actor_node_2d: Node2D = request_actor as Node2D

	if actor_node_2d != null:
		request.actor_position = actor_node_2d.global_position

	return request


## Reads an object-specific value out of [member data].
func get_data(
	key: StringName,
	default_value: Variant = null
) -> Variant:
	return data.get(key, default_value)


## True when the actor exposes [param method_name].
##
## Interactables use this instead of checking for a concrete player class.
func actor_has_method(
	method_name: StringName
) -> bool:
	return actor != null and actor.has_method(method_name)


## The actor's [ItemCarrier], or null when the actor cannot carry items.
##
## A convenience for the common case. Interactables that need something else
## from the actor should duck-type it themselves.
func get_actor_carrier() -> ItemCarrier:
	if not actor_has_method(&"get_item_carrier"):
		return null

	return actor.get_item_carrier() as ItemCarrier
