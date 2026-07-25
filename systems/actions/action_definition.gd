class_name ActionDefinition
extends Resource


@export_category("Identity")

## Stable identifier used by gameplay systems and save data.
##
## Examples:
## clean_empty_glass
## repair_chair
## prepare_grog
@export var action_id: StringName = &""

## Name displayed in progress UI and interaction prompts.
@export var display_name: String = "Action"

## Optional explanation for menus, tooltips and debugging.
@export_multiline var description: String = ""


@export_category("Real-Time Behaviour")

## Real-world seconds the actor remains occupied.
@export_range(0.0, 600.0, 0.1)
var duration_seconds: float = 1.0

## Whether the actor should be prevented from moving.
@export var blocks_movement: bool = true

## Whether normal player input can cancel the action.
@export var can_cancel: bool = true


@export_category("Simulated Time")

## In-game minutes advanced after the action completes successfully.
##
## Leave at zero for actions that should happen inside the running clock
## without adding extra simulated time.
@export_range(0, 1440, 1)
var game_minutes_on_completion: int = 0


func is_valid() -> bool:
	return (
		not action_id.is_empty()
		and not display_name.strip_edges().is_empty()
		and duration_seconds >= 0.0
		and game_minutes_on_completion >= 0
	)
