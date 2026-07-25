class_name ActionRunner
extends Node

signal action_started(action: ActionDefinition)
signal action_progressed(
	action: ActionDefinition,
	progress: float,
	remaining_seconds: float
)
signal action_completed(action: ActionDefinition)
signal action_cancelled(action: ActionDefinition)

var current_action: ActionDefinition = null
var elapsed_seconds: float = 0.0
var is_running: bool = false


func _process(delta: float) -> void:
	if not is_running:
		return

	if current_action == null:
		_clear_action()
		return

	elapsed_seconds += delta

	var duration: float = current_action.duration_seconds
	var progress: float = 1.0

	if duration > 0.0:
		progress = clampf(elapsed_seconds / duration, 0.0, 1.0)

	var remaining_seconds: float = maxf(
		duration - elapsed_seconds,
		0.0
	)

	action_progressed.emit(
		current_action,
		progress,
		remaining_seconds
	)

	if elapsed_seconds >= duration:
		_complete_current_action()


func start_action(action: ActionDefinition) -> bool:
	if action == null:
		push_warning("ActionRunner received a null ActionDefinition.")
		return false

	if is_running:
		return false

	current_action = action
	elapsed_seconds = 0.0
	is_running = true

	action_started.emit(current_action)

	if current_action.duration_seconds <= 0.0:
		_complete_current_action()

	return true


func cancel_current_action() -> bool:
	if not is_running or current_action == null:
		return false

	if not current_action.can_cancel:
		return false

	var cancelled_action: ActionDefinition = current_action

	_clear_action()
	action_cancelled.emit(cancelled_action)

	return true


func force_cancel_current_action() -> bool:
	if not is_running or current_action == null:
		return false

	var cancelled_action: ActionDefinition = current_action

	_clear_action()
	action_cancelled.emit(cancelled_action)

	return true


func get_progress() -> float:
	if not is_running or current_action == null:
		return 0.0

	if current_action.duration_seconds <= 0.0:
		return 1.0

	return clampf(
		elapsed_seconds / current_action.duration_seconds,
		0.0,
		1.0
	)


func get_remaining_seconds() -> float:
	if not is_running or current_action == null:
		return 0.0

	return maxf(
		current_action.duration_seconds - elapsed_seconds,
		0.0
	)


func is_movement_blocked() -> bool:
	return (
		is_running
		and current_action != null
		and current_action.blocks_movement
	)


func _complete_current_action() -> void:
	var completed_action: ActionDefinition = current_action

	_clear_action()
	action_completed.emit(completed_action)


func _clear_action() -> void:
	current_action = null
	elapsed_seconds = 0.0
	is_running = false
	
func is_action_running() -> bool:
	return current_action != null
