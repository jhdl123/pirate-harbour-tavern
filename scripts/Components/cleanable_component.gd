class_name CleanableComponent
extends Node


signal cleaning_started(task: CleaningTask)
signal cleaning_cancelled(task: CleaningTask)
signal task_changed(task: CleaningTask)
signal cleaning_completed
signal complication_triggered(
	task: CleaningTask,
	cost: int
)


@export_category("Configuration")
@export var game_config: GameConfig

@export_category("Starting State")
@export var starting_task: CleaningTask


var current_task: CleaningTask
var is_cleaning: bool = false
var complication_chance_multiplier: float = 1.0


@onready var cleaning_timer: Timer = $CleaningTimer


func _ready() -> void:
	if !cleaning_timer.timeout.is_connected(
		_on_cleaning_timer_timeout
	):
		cleaning_timer.timeout.connect(
			_on_cleaning_timer_timeout
		)

	if starting_task != null:
		set_cleaning_task(starting_task)
	else:
		clear_cleaning_task()


func configure(
	config: GameConfig
) -> void:
	game_config = config


func has_cleaning_task() -> bool:
	return current_task != null


func can_start_cleaning() -> bool:
	return (
		current_task != null
		and !is_cleaning
	)


func set_cleaning_task(
	new_task: CleaningTask,
	chance_multiplier: float = 1.0
) -> void:
	cancel_cleaning()

	current_task = new_task

	complication_chance_multiplier = maxf(
		0.0,
		chance_multiplier
	)

	if current_task == null:
		complication_chance_multiplier = 1.0
		cleaning_completed.emit()
		return

	task_changed.emit(current_task)


func clear_cleaning_task() -> void:
	cancel_cleaning()

	current_task = null
	complication_chance_multiplier = 1.0

	cleaning_completed.emit()


func start_cleaning() -> bool:
	if !can_start_cleaning():
		return false

	is_cleaning = true

	cleaning_timer.start(
		current_task.cleaning_duration
	)

	cleaning_started.emit(current_task)

	return true


func cancel_cleaning() -> void:
	if !is_cleaning:
		return

	var cancelled_task: CleaningTask = current_task

	is_cleaning = false
	cleaning_timer.stop()

	if cancelled_task != null:
		cleaning_cancelled.emit(cancelled_task)


func _on_cleaning_timer_timeout() -> void:
	if current_task == null:
		is_cleaning = false
		complication_chance_multiplier = 1.0
		return

	var completed_task: CleaningTask = current_task

	is_cleaning = false

	if should_trigger_complication(
		completed_task
	):
		var next_task: CleaningTask = (
			completed_task.complication_task
		)

		var complication_cost: int = (
			completed_task.complication_cost
		)

		current_task = next_task
		complication_chance_multiplier = 1.0

		complication_triggered.emit(
			next_task,
			complication_cost
		)

		if current_task != null:
			task_changed.emit(current_task)
		else:
			cleaning_completed.emit()

		return

	current_task = null
	complication_chance_multiplier = 1.0

	cleaning_completed.emit()


func should_trigger_complication(
	task: CleaningTask
) -> bool:
	if task == null:
		return false

	if task.complication_task == null:
		return false

	if task.complication_chance <= 0.0:
		return false

	if (
		game_config != null
		and game_config.disable_broken_glass
	):
		return false

	var final_chance: float = clampf(
		task.complication_chance
		* complication_chance_multiplier,
		0.0,
		1.0
	)

	return randf() < final_chance
