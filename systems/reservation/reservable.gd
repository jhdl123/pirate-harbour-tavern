class_name Reservable
extends Node

## Marks anything in the world as claimable by exactly one actor.
##
## The old seat logic lived inside [Chair] as a three-value enum and a
## [code]customer[/code] field. That worked for chairs and for nothing else, so
## queue positions, station approach points and future workstations would each
## have grown their own copy of the same three states.
##
## This component is that logic, extracted and made generic. A chair holds one.
## An [ApproachPoint] holds one. A queue slot will hold one. A crafting bench
## will hold one. None of them share a base class, and none of them contain any
## claiming logic of their own.
##
## Two-stage claiming matters:
##
## [codeblock]
## reserve()  the actor is on its way    - nobody else may take it
## occupy()   the actor has arrived      - it is genuinely in use
## release()  finished, or gave up
## [/codeblock]
##
## Without the middle stage, two actors walk to the same chair. Without an
## expiry on the first stage, an actor that dies en route locks the chair for
## the rest of the session.


signal reserved(actor: Node)
signal occupied(actor: Node)
signal released(actor: Node)

## The reservation timed out before the actor arrived.
signal expired(actor: Node)


enum State {
	## Nobody has claimed this.
	FREE,

	## Claimed by an actor that has not arrived yet.
	RESERVED,

	## Claimed by an actor that is here and using it.
	OCCUPIED,
}


@export_category("Identity")

## Free-form categories used when searching, for example
## [code]seat[/code], [code]approach[/code], [code]queue[/code].
##
## Data rather than subclasses, so a new kind of reservable never needs a script.
@export var reservation_tags: Array[StringName] = []


@export_category("Recovery")

## Seconds a reservation may sit unclaimed before it expires. 0 disables expiry.
##
## This is the safety net for an actor that is removed, blocked, or gives up
## without releasing cleanly. Without it, one lost customer permanently costs
## the tavern a seat.
@export_range(0.0, 300.0, 1.0)
var reservation_timeout_seconds: float = 45.0


var _state: State = State.FREE
var _holder: Node = null
var _reserved_elapsed: float = 0.0


func _ready() -> void:
	set_process(reservation_timeout_seconds > 0.0)


func _process(
	delta: float
) -> void:
	# A holder that was freed without releasing is the common case, and is
	# cheaper to notice here than to guard against everywhere else.
	if _holder != null and not is_instance_valid(_holder):
		_force_release()
		return

	if _state != State.RESERVED:
		return

	if reservation_timeout_seconds <= 0.0:
		return

	_reserved_elapsed += delta

	if _reserved_elapsed < reservation_timeout_seconds:
		return

	var previous_holder: Node = _holder

	_force_release()

	expired.emit(previous_holder)


# -----------------------------------------------------------------------------
# Claiming
# -----------------------------------------------------------------------------

## Claims this for [param actor] while it travels here.
##
## Returns false when something else already holds it. Re-reserving with the
## same actor succeeds and resets the expiry, which is what an actor that
## re-plans its route wants.
func reserve(
	actor: Node
) -> bool:
	if actor == null:
		return false

	if _holder == actor:
		_reserved_elapsed = 0.0
		return true

	if _state != State.FREE:
		return false

	_holder = actor
	_state = State.RESERVED
	_reserved_elapsed = 0.0

	reserved.emit(actor)

	return true


## Promotes a reservation to active use, now that [param actor] has arrived.
##
## Only the holder may occupy, so a second actor cannot arrive and take over a
## seat that is already spoken for.
func occupy(
	actor: Node
) -> bool:
	if actor == null:
		return false

	if _holder != actor:
		return false

	_state = State.OCCUPIED
	_reserved_elapsed = 0.0

	occupied.emit(actor)

	return true


## Claims and immediately occupies, for an actor that is already here.
func reserve_and_occupy(
	actor: Node
) -> bool:
	if not reserve(actor):
		return false

	return occupy(actor)


## Gives this up.
##
## Passing an actor releases only if that actor is the holder, which stops a
## departing customer from freeing a seat that has already been handed on.
## Passing null releases unconditionally.
func release(
	actor: Node = null
) -> void:
	if _state == State.FREE:
		return

	if actor != null and _holder != actor:
		return

	_force_release()


func _force_release() -> void:
	var previous_holder: Node = _holder

	_holder = null
	_state = State.FREE
	_reserved_elapsed = 0.0

	released.emit(previous_holder)


# -----------------------------------------------------------------------------
# Reading
# -----------------------------------------------------------------------------

func get_state() -> State:
	return _state


func is_free() -> bool:
	return _state == State.FREE


func is_reserved() -> bool:
	return _state == State.RESERVED


func is_occupied() -> bool:
	return _state == State.OCCUPIED


## The actor holding this, or null.
func get_holder() -> Node:
	if _holder != null and not is_instance_valid(_holder):
		return null

	return _holder


func is_held_by(
	actor: Node
) -> bool:
	return actor != null and get_holder() == actor


func has_tag(
	tag: StringName
) -> bool:
	return reservation_tags.has(tag)


## The node this reservable belongs to, normally its parent.
func get_subject() -> Node:
	return get_parent()
