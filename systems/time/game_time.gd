extends Node

signal time_changed(day: int, hour: int, minute: int)
signal minute_changed(day: int, hour: int, minute: int)
signal hour_changed(day: int, hour: int)
signal day_changed(day: int)

signal pause_changed(is_paused: bool)
signal speed_changed(speed_multiplier: float)

const MINUTES_PER_HOUR: int = 60
const HOURS_PER_DAY: int = 24
const MINUTES_PER_DAY: int = MINUTES_PER_HOUR * HOURS_PER_DAY

@export var config: GameTimeConfig

var total_elapsed_minutes: int = 0
var current_speed_multiplier: float = 1.0
var is_time_paused: bool = false

var _minute_accumulator: float = 0.0


func _ready() -> void:
	if config == null:
		push_error("GameTime requires a GameTimeConfig resource.")
		set_process(false)
		return

	reset_to_starting_time()


func _process(delta: float) -> void:
	if is_time_paused:
		return

	var minutes_this_frame: float = (
		delta
		* config.game_minutes_per_real_second
		* current_speed_multiplier
	)

	_minute_accumulator += minutes_this_frame

	if _minute_accumulator < 1.0:
		return

	var completed_minutes: int = int(floor(_minute_accumulator))
	_minute_accumulator -= float(completed_minutes)

	advance_minutes(completed_minutes)


func advance_minutes(minutes: int) -> void:
	if minutes <= 0:
		return

	var previous_day: int = get_day()
	var previous_hour: int = get_hour()

	for minute_index: int in range(minutes):
		total_elapsed_minutes += 1

		var new_day: int = get_day()
		var new_hour: int = get_hour()
		var new_minute: int = get_minute()

		minute_changed.emit(new_day, new_hour, new_minute)

		if new_hour != previous_hour:
			previous_hour = new_hour
			hour_changed.emit(new_day, new_hour)

		if new_day != previous_day:
			previous_day = new_day
			day_changed.emit(new_day)

	time_changed.emit(get_day(), get_hour(), get_minute())


func set_time_paused(should_pause: bool) -> void:
	if is_time_paused == should_pause:
		return

	is_time_paused = should_pause
	pause_changed.emit(is_time_paused)


func toggle_pause() -> void:
	set_time_paused(not is_time_paused)


func set_speed_multiplier(multiplier: float) -> void:
	if multiplier <= 0.0:
		push_warning("Game-time speed multiplier must be greater than zero.")
		return

	if is_equal_approx(current_speed_multiplier, multiplier):
		return

	current_speed_multiplier = multiplier
	speed_changed.emit(current_speed_multiplier)


func set_speed_from_config(speed_index: int) -> void:
	if config == null:
		return

	if speed_index < 0 or speed_index >= config.available_speed_multipliers.size():
		push_warning("Invalid game-time speed index: %s" % speed_index)
		return

	set_speed_multiplier(config.available_speed_multipliers[speed_index])


func reset_to_starting_time() -> void:
	if config == null:
		return

	var completed_days: int = config.starting_day - 1

	total_elapsed_minutes = (
		completed_days * MINUTES_PER_DAY
		+ config.starting_hour * MINUTES_PER_HOUR
		+ config.starting_minute
	)

	_minute_accumulator = 0.0
	current_speed_multiplier = 1.0
	is_time_paused = false

	time_changed.emit(get_day(), get_hour(), get_minute())


func get_day() -> int:
	return int(total_elapsed_minutes / MINUTES_PER_DAY) + 1


func get_hour() -> int:
	var minutes_today: int = total_elapsed_minutes % MINUTES_PER_DAY
	return int(minutes_today / MINUTES_PER_HOUR)


func get_minute() -> int:
	return total_elapsed_minutes % MINUTES_PER_HOUR


func get_minutes_today() -> int:
	return total_elapsed_minutes % MINUTES_PER_DAY


func get_formatted_time() -> String:
	return "%02d:%02d" % [get_hour(), get_minute()]


func get_formatted_date_and_time() -> String:
	return "Day %d — %s" % [get_day(), get_formatted_time()]


func is_between_hours(start_hour: int, end_hour: int) -> bool:
	var current_hour: int = get_hour()

	if start_hour <= end_hour:
		return current_hour >= start_hour and current_hour < end_hour

	return current_hour >= start_hour or current_hour < end_hour
