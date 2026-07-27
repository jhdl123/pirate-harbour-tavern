extends Node

## The authoritative answer to "is the game running right now".
##
## Registered as the [code]Simulation[/code] autoload. Every system that could
## meaningfully pause - the world clock, AI, production, input - asks this
## rather than keeping its own flag. One flag in one place cannot disagree with
## itself; seven flags in seven scripts always eventually do.
##
## [b]Why a stack.[/b] A conversation opening over play, a menu over a
## conversation, a cutscene over a menu: each wants to suspend what was
## happening and then put it back exactly as it was. Callers that
## [method push_state] and [method pop_state] never have to remember what they
## interrupted, which is what stops "resume" bugs.
##
## [b]Why not [code]get_tree().paused[/code].[/b] Engine pause is all or
## nothing and is opted out of node by node. The simulation needs finer
## answers - UI keeps running while actors freeze, animation may or may not
## follow the clock - so this framework owns the decision and exposes it as
## data. [member mirror_to_engine_pause] is available for systems that genuinely
## want the engine flag too, off by default.


## The state changed. Both arguments are [enum SimulationState.State].
signal state_changed(
	previous_state: SimulationState.State,
	current_state: SimulationState.State
)

## Convenience signals over the top of [signal state_changed], so a listener
## that only cares about one transition does not need a comparison.
signal simulation_started
signal simulation_paused
signal simulation_resumed

## Any capability changed as a result of a state change.
##
## Systems that care about "may I update" rather than about a specific state
## should use this.
signal capabilities_changed


@export_category("Configuration")

## What each state permits. A default is built when left empty.
@export var state_rules: SimulationStateRules

## State the game begins in.
@export var initial_state: SimulationState.State = (
	SimulationState.State.PLAYING
)

## Whether the engine's own pause flag follows the simulation.
##
## Off by default: engine pause stops UI and tweens too, which is rarely what
## a management game wants. Turn on only if a system genuinely needs it.
@export var mirror_to_engine_pause: bool = false


@export_category("Debug")

@export var show_state_messages: bool = false


var _current_state: SimulationState.State = SimulationState.State.LOADING

## States suspended beneath the current one, most recent last.
var _state_stack: Array[SimulationState.State] = []


func _ready() -> void:
	if state_rules == null:
		state_rules = SimulationStateRules.new()

	# Deferred so every other autoload and the first scene are listening before
	# the opening transition is announced. Without this the very first
	# state_changed would be emitted into an empty room.
	_apply_initial_state.call_deferred()


func _apply_initial_state() -> void:
	set_state(initial_state)


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

func get_state() -> SimulationState.State:
	return _current_state


## Replaces the current state, clearing anything suspended beneath it.
##
## For genuine transitions - entering the game, returning to the menu. To
## overlay something temporary, use [method push_state].
func set_state(
	new_state: SimulationState.State
) -> void:
	if new_state == _current_state:
		return

	_state_stack.clear()

	_transition_to(new_state)


## Suspends the current state and switches to [param new_state].
##
## The suspended state is restored by [method pop_state].
func push_state(
	new_state: SimulationState.State
) -> void:
	if new_state == _current_state:
		return

	_state_stack.append(_current_state)

	_transition_to(new_state)


## Returns to the state suspended by the last [method push_state].
##
## Returns false when there was nothing to go back to, which is a caller bug
## worth knowing about rather than silently absorbing.
func pop_state() -> bool:
	if _state_stack.is_empty():
		push_warning(
			"Simulation.pop_state() was called with an empty state stack."
		)
		return false

	var previous: SimulationState.State = _state_stack.pop_back()

	_transition_to(previous)

	return true


## Convenience: pause play without losing what was underneath.
func pause() -> void:
	if is_paused():
		return

	push_state(SimulationState.State.PAUSED)


## Convenience: undo [method pause].
func resume() -> void:
	if not is_paused():
		return

	if not pop_state():
		set_state(SimulationState.State.PLAYING)


func toggle_pause() -> void:
	if is_paused():
		resume()
	else:
		pause()


# -----------------------------------------------------------------------------
# Queries
# -----------------------------------------------------------------------------

## True when the world clock should be advancing.
func is_running() -> bool:
	return state_rules.advances_time(_current_state)


func is_paused() -> bool:
	return _current_state == SimulationState.State.PAUSED


## True when the player may act on the world.
func accepts_input() -> bool:
	return state_rules.accepts_input(_current_state)


## True when AI actors should be thinking and moving.
func updates_actors() -> bool:
	return state_rules.updates_actors(_current_state)


## True when the world is on screen.
func shows_world() -> bool:
	return state_rules.shows_world(_current_state)


func is_state(
	state: SimulationState.State
) -> bool:
	return _current_state == state


func get_state_name() -> String:
	return SimulationState.get_display_name(_current_state)


func get_stack_depth() -> int:
	return _state_stack.size()


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------

func _transition_to(
	new_state: SimulationState.State
) -> void:
	var previous_state: SimulationState.State = _current_state

	_current_state = new_state

	if mirror_to_engine_pause:
		get_tree().paused = not is_running()

	if show_state_messages:
		print(
			"Simulation: ",
			SimulationState.get_display_name(previous_state),
			" -> ",
			SimulationState.get_display_name(new_state)
		)

	state_changed.emit(previous_state, new_state)
	capabilities_changed.emit()

	_emit_convenience_signals(previous_state, new_state)


func _emit_convenience_signals(
	previous_state: SimulationState.State,
	new_state: SimulationState.State
) -> void:
	var was_running: bool = state_rules.advances_time(previous_state)
	var is_now_running: bool = state_rules.advances_time(new_state)

	if new_state == SimulationState.State.PAUSED:
		simulation_paused.emit()
		return

	if previous_state == SimulationState.State.PAUSED and is_now_running:
		simulation_resumed.emit()
		return

	if is_now_running and not was_running:
		simulation_started.emit()


# -----------------------------------------------------------------------------
# Persistence
# -----------------------------------------------------------------------------

## The whole controller, ready for a save file.
func to_dictionary() -> Dictionary:
	var stack_ids: Array = []

	for state: SimulationState.State in _state_stack:
		stack_ids.append(String(SimulationState.get_state_id(state)))

	return {
		"state": String(SimulationState.get_state_id(_current_state)),
		"stack": stack_ids
	}


## Restores from [method to_dictionary], emitting a normal transition.
func apply_dictionary(
	data: Dictionary
) -> void:
	_state_stack.clear()

	for entry: Variant in data.get("stack", []):
		_state_stack.append(
			SimulationState.get_state_from_id(StringName(entry))
		)

	_transition_to(
		SimulationState.get_state_from_id(
			StringName(data.get("state", "playing"))
		)
	)
