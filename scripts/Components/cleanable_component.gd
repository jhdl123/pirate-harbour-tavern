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


var current_task: CleaningTask = null
var is_cleaning: bool = false

var complication_chance_multiplier: float = 1.0

var active_action_runner: ActionRunner = null
var active_action: ActionDefinition = null


func _ready() -> void:
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
		and not is_cleaning
		and current_task.has_valid_action()
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


func start_cleaning(
	action_runner: ActionRunner
) -> bool:
	if not can_start_cleaning():
		return false

	if action_runner == null:
		push_warning(
			"CleanableComponent received no ActionRunner."
		)
		return false

	if action_runner.is_running:
		return false

	var requested_action: ActionDefinition = (
		current_task.get_action()
	)

	if requested_action == null:
		push_warning(
			current_task.display_name
			+ " has no ActionDefinition assigned."
		)
		return false

	active_action_runner = action_runner
	active_action = requested_action
	is_cleaning = true

	connect_action_runner_signals()

	var action_started_successfully: bool = (
		active_action_runner.start_action(
			active_action
		)
	)

	if not action_started_successfully:
		disconnect_action_runner_signals()

		active_action_runner = null
		active_action = null
		is_cleaning = false

		return false

	cleaning_started.emit(current_task)

	return true


func cancel_cleaning() -> void:
	if not is_cleaning:
		return

	if active_action_runner != null:
		if active_action_runner.is_running:
			active_action_runner.force_cancel_current_action()
			return

	finish_cancellation()


func connect_action_runner_signals() -> void:
	if active_action_runner == null:
		return

	if not active_action_runner.action_completed.is_connected(
		_on_action_completed
	):
		active_action_runner.action_completed.connect(
			_on_action_completed
		)

	if not active_action_runner.action_cancelled.is_connected(
		_on_action_cancelled
	):
		active_action_runner.action_cancelled.connect(
			_on_action_cancelled
		)


func disconnect_action_runner_signals() -> void:
	if active_action_runner == null:
		return

	if active_action_runner.action_completed.is_connected(
		_on_action_completed
	):
		active_action_runner.action_completed.disconnect(
			_on_action_completed
		)

	if active_action_runner.action_cancelled.is_connected(
		_on_action_cancelled
	):
		active_action_runner.action_cancelled.disconnect(
			_on_action_cancelled
		)


func _on_action_completed(
	completed_action: ActionDefinition
) -> void:
	if not is_cleaning:
		return

	if completed_action != active_action:
		return

	disconnect_action_runner_signals()

	active_action_runner = null
	active_action = null
	is_cleaning = false

	resolve_completed_cleaning()


func _on_action_cancelled(
	cancelled_action: ActionDefinition
) -> void:
	if not is_cleaning:
		return

	if cancelled_action != active_action:
		return

	finish_cancellation()


func finish_cancellation() -> void:
	var cancelled_task: CleaningTask = current_task

	disconnect_action_runner_signals()

	active_action_runner = null
	active_action = null
	is_cleaning = false

	if cancelled_task != null:
		cleaning_cancelled.emit(cancelled_task)


func resolve_completed_cleaning() -> void:
	if current_task == null:
		complication_chance_multiplier = 1.0
		return

	var completed_task: CleaningTask = current_task

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
