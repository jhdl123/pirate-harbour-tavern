class_name CleaningTask
extends Resource


@export_category("Identity")
@export var display_name: String = "Cleaning Task"

@export_multiline
var description: String = ""


@export_category("Action")
@export var action_definition: ActionDefinition


@export_category("Visual")
@export var task_texture: Texture2D





@export_category("Complication")

@export_range(0.0, 1.0, 0.01)
var complication_chance: float = 0.0

@export var complication_task: CleaningTask

@export_range(0, 100000, 1)
var complication_cost: int = 0


func get_action() -> ActionDefinition:
	return action_definition


func has_valid_action() -> bool:
	return (
		action_definition != null
		and action_definition.is_valid()
	)
