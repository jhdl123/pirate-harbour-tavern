class_name SimulationState
extends RefCounted

## The set of states the game can be in, and their names.
##
## Deliberately just the vocabulary. What each state *means* - whether time
## runs, whether actors think, whether input is accepted - is data, and lives in
## [SimulationStateRules]. Splitting them means adding a state is an enum entry
## plus a resource edit, and changing what a state permits is a resource edit
## alone.
##
## No system should ever decide for itself whether it should be updating. It
## asks [SimulationController], which answers from these rules.


enum State {
	## Assets or a save file are being brought in. Nothing simulates.
	LOADING,

	## Front end. The world is not running.
	MAIN_MENU,

	## Normal play.
	PLAYING,

	## Explicitly paused by the player. The world is visible but frozen.
	PAUSED,

	## Accelerated play. Still play - see the note in the documentation about
	## why this is a state and speed is separately a property of the clock.
	FAST_FORWARD,

	## Reserved. A conversation is open; the world holds still behind it.
	DIALOGUE,

	## Reserved. A scripted sequence is playing.
	CUTSCENE,
}


## Stable identifiers, used by [SimulationStateRules] and by save files.
##
## Names rather than raw enum integers, so inserting a state later cannot
## silently change the meaning of an existing save or resource.
const STATE_IDS: Dictionary = {
	State.LOADING: &"loading",
	State.MAIN_MENU: &"main_menu",
	State.PLAYING: &"playing",
	State.PAUSED: &"paused",
	State.FAST_FORWARD: &"fast_forward",
	State.DIALOGUE: &"dialogue",
	State.CUTSCENE: &"cutscene",
}


## The stable identifier for [param state].
static func get_state_id(
	state: State
) -> StringName:
	return STATE_IDS.get(state, &"unknown")


## The enum value for a stable identifier, for loading a save.
static func get_state_from_id(
	id: StringName
) -> State:
	for state: Variant in STATE_IDS:
		if STATE_IDS[state] == id:
			return state

	push_warning(
		"Unknown simulation state id '%s'; defaulting to MAIN_MENU."
		% String(id)
	)

	return State.MAIN_MENU


## A readable label, for debug output and UI.
static func get_display_name(
	state: State
) -> String:
	return String(get_state_id(state)).capitalize()
