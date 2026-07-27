class_name SimulationStateRules
extends Resource

## What each simulation state permits.
##
## Listing state identifiers per capability, rather than one boolean per state
## per capability, keeps this readable in the inspector and means adding a
## state does not add three more exports. A state absent from a list simply does
## not have that capability.
##
## This is the single place the question "should this be running right now" is
## answered for the whole game.


@export_category("Capabilities")

## States in which the world clock advances.
##
## Everything time-driven follows from this: production, deliveries, shifts,
## opening hours, daily reports.
@export var states_that_advance_time: Array[StringName] = [
	&"playing",
	&"fast_forward",
]

## States in which the player may act on the world.
##
## Interaction, movement and world input should check this rather than
## inventing their own pause flag.
@export var states_that_accept_input: Array[StringName] = [
	&"playing",
	&"fast_forward",
]

## States in which AI actors think and move.
##
## Separate from time because a cutscene may want actors animating along a
## script while the clock stands still.
@export var states_that_update_actors: Array[StringName] = [
	&"playing",
	&"fast_forward",
	&"cutscene",
]

## States in which the world is on screen at all.
##
## Lets UI decide between a front end, a loading screen and the game.
@export var states_that_show_world: Array[StringName] = [
	&"playing",
	&"fast_forward",
	&"paused",
	&"dialogue",
	&"cutscene",
]


func advances_time(
	state: SimulationState.State
) -> bool:
	return states_that_advance_time.has(
		SimulationState.get_state_id(state)
	)


func accepts_input(
	state: SimulationState.State
) -> bool:
	return states_that_accept_input.has(
		SimulationState.get_state_id(state)
	)


func updates_actors(
	state: SimulationState.State
) -> bool:
	return states_that_update_actors.has(
		SimulationState.get_state_id(state)
	)


func shows_world(
	state: SimulationState.State
) -> bool:
	return states_that_show_world.has(
		SimulationState.get_state_id(state)
	)
