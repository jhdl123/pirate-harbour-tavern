class_name CleaningTask
extends Resource


@export_category("Identity")
@export var display_name: String = "Cleaning Task"
@export_multiline var description: String = ""

@export_category("Visual")
@export var task_texture: Texture2D

@export_category("Cleaning")
@export_range(0.1, 60.0, 0.1)
var cleaning_duration: float = 1.0

@export_category("Complication")
@export_range(0.0, 1.0, 0.01)
var complication_chance: float = 0.0

@export var complication_task: CleaningTask
@export var complication_cost: int = 0
