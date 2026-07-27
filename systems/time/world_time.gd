extends Node

## The one authoritative clock, registered as the [code]WorldTime[/code] autoload.
##
## Deliberately thin. The time model is [WorldClock], the booking system is
## [TimeScheduler], the words are [TimeFormatter]; this node drives them from
## the frame loop, gates them on [SimulationController], and announces what
## happened. Keeping the model out of the autoload means it can be tested,
## copied and serialised without a scene tree.
##
## [b]Signals versus the scheduler.[/b] The distinction matters and is the main
## thing to understand before building on this:
##
## [codeblock]
## signals     react to the moment the world is in now.
##             A large skip collapses them - three days do not emit
##             four thousand minute signals - so a listener may miss one.
##
## scheduler   never misses. Every booking inside a skipped window fires,
##             in order, with the clock standing at the booked moment.
## [/codeblock]
##
## So: a HUD reads signals. A wage payment, a delivery or a production run
## books with the scheduler.
##
## [b]No other system should own a clock.[/b] A gameplay [Timer] keeps running
## when the game is paused, ignores time speed, and cannot be skipped or saved.
## Anything that represents world progression books here instead.


## Emitted once for every in-game minute, during ordinary advancement.
##
## Suppressed during a large skip - see the class note.
signal minute_passed(stamp: GameTimeStamp)

## The hour reading changed.
signal hour_changed(stamp: GameTimeStamp)

## The day reading changed.
signal day_changed(stamp: GameTimeStamp)

## Emitted once after any advance, however large. The signal a HUD wants.
signal time_changed(stamp: GameTimeStamp)

## A jump larger than [member GameTimeConfig.maximum_stepped_minutes] happened.
##
## Carries both ends so a listener can work out what it missed.
signal time_skipped(
	from_stamp: GameTimeStamp,
	to_stamp: GameTimeStamp
)

signal speed_changed(multiplier: float)
signal time_paused_changed(is_time_paused: bool)


## Fallback config, used when nothing is assigned in the inspector.
##
## A script autoload never receives exported values, so relying on the export
## alone left the old clock with a null config and silently frozen. Loading a
## known resource, then falling back to defaults, means the clock always runs.
const DEFAULT_CONFIG_PATH: String = (
	"res://Data/time/default_time_config.tres"
)


@export_category("Configuration")

## Calendar and rate settings. Loaded from [constant DEFAULT_CONFIG_PATH] when
## empty.
@export var config: GameTimeConfig


@export_category("Debug")

@export var show_time_messages: bool = false


var _clock: WorldClock = null
var _scheduler: TimeScheduler = null

var _speed_multiplier: float = 1.0
var _is_time_paused: bool = false

var _minute_accumulator: float = 0.0

## Speed to restore when leaving the fast-forward state.
var _speed_before_fast_forward: float = 1.0


func _ready() -> void:
	_resolve_config()

	_clock = WorldClock.create(config)
	_scheduler = TimeScheduler.create(config)

	_speed_multiplier = config.get_default_speed_multiplier()
	_speed_before_fast_forward = _speed_multiplier

	# Time asks the simulation whether it may run. The simulation knows nothing
	# about time, which keeps the dependency pointing one way only.
	if not Simulation.state_changed.is_connected(_on_simulation_state_changed):
		Simulation.state_changed.connect(_on_simulation_state_changed)

	_emit_time_changed()


func _resolve_config() -> void:
	if config != null:
		config.validate_or_warn()
		return

	if ResourceLoader.exists(DEFAULT_CONFIG_PATH):
		config = load(DEFAULT_CONFIG_PATH) as GameTimeConfig

	if config == null:
		push_warning(
			"WorldTime could not load '%s'; using built-in defaults."
			% DEFAULT_CONFIG_PATH
		)

		config = GameTimeConfig.new()

	config.validate_or_warn()


func _process(
	delta: float
) -> void:
	if not can_advance():
		return

	_minute_accumulator += (
		delta
		* config.game_minutes_per_real_second
		* _speed_multiplier
	)

	if _minute_accumulator < 1.0:
		return

	var whole_minutes: int = int(floor(_minute_accumulator))

	_minute_accumulator -= float(whole_minutes)

	advance_minutes(whole_minutes)


## True when the clock is free to run right now.
##
## Two independent gates: the simulation must be in a state that advances time,
## and time must not be separately paused. The first is the game's state, the
## second is a local override for debugging or for a future cutscene that wants
## the world visible but frozen.
func can_advance() -> bool:
	if _clock == null:
		return false

	if _is_time_paused:
		return false

	return Simulation.is_running()


# -----------------------------------------------------------------------------
# Advancing
# -----------------------------------------------------------------------------

## Moves the world forward by [param minutes], firing everything in between.
##
## The single entry point for time moving. Ordinary ticking, a debug skip and a
## scripted jump all come through here, so scheduled events cannot be missed by
## one route and honoured by another.
func advance_minutes(
	minutes: int
) -> void:
	if minutes <= 0 or _clock == null:
		return

	_advance_to(_clock.total_minutes + minutes)


## Moves the world forward to an exact moment.
##
## Ignored when the moment is in the past: time never runs backwards, because
## every "has this happened yet" comparison in the game depends on it.
func skip_to(
	day: int,
	hour: int,
	minute: int
) -> void:
	var target: GameTimeStamp = GameTimeStamp.from_day_time(
		day,
		hour,
		minute,
		config
	)

	if target.total_minutes <= _clock.total_minutes:
		push_warning(
			"WorldTime cannot skip backwards to %s."
			% target.get_full_text()
		)
		return

	_advance_to(target.total_minutes)


func skip_to_next_hour() -> void:
	advance_minutes(_clock.get_minutes_until_next_hour())


func skip_to_next_day() -> void:
	advance_minutes(_clock.get_minutes_until_next_day())


## Advances in steps, pausing at every booked event on the way.
##
## Stepping rather than jumping is what makes a long skip correct: an event
## booked for 09:00 runs with the clock reading 09:00, not with the clock
## already at 17:00. A day's worth of wages, deliveries and reports therefore
## happen in the right order and see the right world.
func _advance_to(
	target_minutes: int
) -> void:
	var iterations: int = 0
	var maximum_iterations: int = 4096

	while iterations < maximum_iterations:
		iterations += 1

		# Anything already due fires before the clock moves again.
		_scheduler.process_until(_clock.total_minutes)

		if _clock.total_minutes >= target_minutes:
			break

		var step_target: int = target_minutes
		var next_event: ScheduledTimeEvent = _scheduler.get_next_event()

		if (
			next_event != null
			and next_event.trigger_minutes < target_minutes
		):
			step_target = maxi(
				next_event.trigger_minutes,
				_clock.total_minutes + 1
			)

		var previous_minutes: int = _clock.total_minutes

		_clock.set_total_minutes(step_target)

		_emit_advancement_signals(previous_minutes, step_target)

	if iterations >= maximum_iterations:
		push_warning(
			"WorldTime advancement hit its iteration limit."
		)

	_emit_time_changed()


func _emit_advancement_signals(
	previous_minutes: int,
	new_minutes: int
) -> void:
	var elapsed: int = new_minutes - previous_minutes

	if elapsed <= 0:
		return

	var previous_stamp: GameTimeStamp = GameTimeStamp.from_total_minutes(
		previous_minutes,
		config
	)

	var new_stamp: GameTimeStamp = GameTimeStamp.from_total_minutes(
		new_minutes,
		config
	)

	if elapsed > config.maximum_stepped_minutes:
		# Collapse. Emitting a signal per minute across a multi-day skip would
		# cost thousands of emissions to tell listeners something they can read
		# from the clock in one call.
		time_skipped.emit(previous_stamp, new_stamp)

		if new_stamp.get_hour() != previous_stamp.get_hour():
			hour_changed.emit(new_stamp)

		if new_stamp.get_day() != previous_stamp.get_day():
			day_changed.emit(new_stamp)

		return

	for offset: int in range(1, elapsed + 1):
		var stamp: GameTimeStamp = GameTimeStamp.from_total_minutes(
			previous_minutes + offset,
			config
		)

		var earlier: GameTimeStamp = GameTimeStamp.from_total_minutes(
			previous_minutes + offset - 1,
			config
		)

		minute_passed.emit(stamp)

		if stamp.get_hour() != earlier.get_hour():
			hour_changed.emit(stamp)

		if stamp.get_day() != earlier.get_day():
			day_changed.emit(stamp)


func _emit_time_changed() -> void:
	if _clock == null:
		return

	if show_time_messages:
		print("WorldTime: ", get_timestamp().get_full_text())

	time_changed.emit(get_timestamp())


# -----------------------------------------------------------------------------
# Reading
# -----------------------------------------------------------------------------

## The current moment. The preferred way for gameplay to read time.
func get_timestamp() -> GameTimeStamp:
	if _clock == null:
		return GameTimeStamp.from_total_minutes(0, config)

	return _clock.get_timestamp()


func get_day() -> int:
	return get_timestamp().get_day()


func get_hour() -> int:
	return get_timestamp().get_hour()


func get_minute() -> int:
	return get_timestamp().get_minute()


func get_total_minutes() -> int:
	if _clock == null:
		return 0

	return _clock.total_minutes


## How far through the day it is, 0.0 to 1.0.
func get_day_progress() -> float:
	return get_timestamp().get_day_progress()


func get_clock_text() -> String:
	return TimeFormatter.format_clock(get_timestamp())


func get_full_text() -> String:
	return TimeFormatter.format_day_and_clock(get_timestamp())


## Total minutes including the fraction of the current minute.
##
## The integer count is the authority for scheduling and saving; this is for
## anything that needs to move smoothly between minutes, such as a patience bar
## or a production gauge. Reading whole minutes for those would visibly step.
func get_total_minutes_precise() -> float:
	return float(get_total_minutes()) + _minute_accumulator


## Multiplier that world-driven motion and durations should apply.
##
## Zero when the world is not advancing, so a system can multiply by this and
## get freezing for free rather than writing a separate pause branch.
##
## Note what does NOT use this: the player. Time speed scales the world, not the
## person walking through it, so serving stays precise while the tavern runs at
## six times speed.
func get_world_time_scale() -> float:
	if not can_advance():
		return 0.0

	return _speed_multiplier


## A real frame delta converted into world time.
##
## The one call a system needs to become time-aware: pass the engine delta in,
## use what comes out, and pausing and speed both work.
func get_world_delta(
	real_delta: float
) -> float:
	return real_delta * get_world_time_scale()


## The underlying model, for tests, tools and save code.
func get_clock() -> WorldClock:
	return _clock


func get_scheduler() -> TimeScheduler:
	return _scheduler


func get_config() -> GameTimeConfig:
	return config


# -----------------------------------------------------------------------------
# Setting time
# -----------------------------------------------------------------------------

## Places the clock at an exact moment, without firing anything in between.
##
## For loading a save or for a debug jump. Ordinary gameplay should use
## [method advance_minutes] or [method skip_to] so scheduled events are honoured.
func set_time(
	day: int,
	hour: int,
	minute: int
) -> void:
	if _clock == null:
		return

	_clock.set_day_time(day, hour, minute)
	_minute_accumulator = 0.0

	_emit_time_changed()


func reset_to_start() -> void:
	if _clock == null:
		return

	_clock.reset_to_start()
	_minute_accumulator = 0.0

	_emit_time_changed()


# -----------------------------------------------------------------------------
# Pause and speed
# -----------------------------------------------------------------------------

## Freezes the clock without changing the simulation state.
##
## A local override. To pause the whole game - AI, input, production - use
## [code]Simulation.pause()[/code] instead.
func pause() -> void:
	set_time_paused(true)


func resume() -> void:
	set_time_paused(false)


func set_time_paused(
	should_pause: bool
) -> void:
	if _is_time_paused == should_pause:
		return

	_is_time_paused = should_pause

	time_paused_changed.emit(_is_time_paused)


func is_paused() -> bool:
	return _is_time_paused


func toggle_pause() -> void:
	set_time_paused(not _is_time_paused)


func get_speed() -> float:
	return _speed_multiplier


func set_speed(
	multiplier: float
) -> void:
	if multiplier <= 0.0:
		push_warning("WorldTime speed must be greater than zero.")
		return

	if is_equal_approx(_speed_multiplier, multiplier):
		return

	_speed_multiplier = multiplier

	speed_changed.emit(_speed_multiplier)


## Selects one of the config's speeds by index.
func set_speed_index(
	index: int
) -> void:
	if config.available_speed_multipliers.is_empty():
		return

	var clamped: int = clampi(
		index,
		0,
		config.available_speed_multipliers.size() - 1
	)

	set_speed(config.available_speed_multipliers[clamped])


## Moves to the next configured speed, wrapping around.
func cycle_speed() -> void:
	var speeds: Array[float] = config.available_speed_multipliers

	if speeds.is_empty():
		return

	var current_index: int = 0

	for index: int in range(speeds.size()):
		if is_equal_approx(speeds[index], _speed_multiplier):
			current_index = index
			break

	set_speed_index((current_index + 1) % speeds.size())


func get_speed_text() -> String:
	return TimeFormatter.format_speed(_speed_multiplier)


## Applies and restores the fast-forward speed as the simulation state changes.
##
## Speed is a property of the clock; fast-forward is a state of the game. They
## are kept separate so that leaving fast-forward returns the player to the
## speed they had chosen rather than snapping to normal.
func _on_simulation_state_changed(
	previous_state: SimulationState.State,
	current_state: SimulationState.State
) -> void:
	if current_state == SimulationState.State.FAST_FORWARD:
		_speed_before_fast_forward = _speed_multiplier

		set_speed(config.fast_forward_speed_multiplier)

		return

	if previous_state == SimulationState.State.FAST_FORWARD:
		set_speed(_speed_before_fast_forward)


# -----------------------------------------------------------------------------
# Scheduling
# -----------------------------------------------------------------------------
#
# Thin pass-throughs so callers never need to reach for the scheduler and never
# need to know the current minute count.

## Books [param callback] for an exact world moment.
func schedule_at(
	stamp: GameTimeStamp,
	callback: Callable,
	tag: StringName = &""
) -> ScheduledTimeEvent:
	return _scheduler.schedule_at(stamp, callback, tag)


## Books [param callback] for [param minutes] of world time from now.
##
## The correct replacement for a gameplay [Timer].
func schedule_in(
	minutes: int,
	callback: Callable,
	tag: StringName = &""
) -> ScheduledTimeEvent:
	return _scheduler.schedule_in(
		get_total_minutes(),
		minutes,
		callback,
		tag
	)


## Books [param callback] for the same clock time every day.
func schedule_daily(
	hour: int,
	minute: int,
	callback: Callable,
	tag: StringName = &""
) -> ScheduledTimeEvent:
	return _scheduler.schedule_daily(
		get_total_minutes(),
		hour,
		minute,
		callback,
		tag
	)


## Books [param callback] to repeat every [param interval_minutes].
func schedule_repeating(
	interval_minutes: int,
	callback: Callable,
	tag: StringName = &""
) -> ScheduledTimeEvent:
	return _scheduler.schedule_repeating(
		get_total_minutes(),
		interval_minutes,
		callback,
		tag
	)


func cancel_scheduled(
	event: ScheduledTimeEvent
) -> void:
	_scheduler.cancel(event)


func cancel_scheduled_tag(
	tag: StringName
) -> int:
	return _scheduler.cancel_tag(tag)


# -----------------------------------------------------------------------------
# Persistence
# -----------------------------------------------------------------------------

## The whole clock, ready for a save file.
##
## Pending scheduled events are included for inspection but are not restored
## automatically - see the documentation for why re-registration is the correct
## pattern rather than a limitation.
func to_dictionary() -> Dictionary:
	return {
		"clock": _clock.to_dictionary(),
		"speed_multiplier": _speed_multiplier,
		"is_time_paused": _is_time_paused,
		"scheduler": _scheduler.to_dictionary()
	}


func apply_dictionary(
	data: Dictionary
) -> void:
	_clock.apply_dictionary(data.get("clock", {}))

	_minute_accumulator = 0.0

	set_speed(float(data.get("speed_multiplier", 1.0)))
	set_time_paused(bool(data.get("is_time_paused", false)))

	_emit_time_changed()
