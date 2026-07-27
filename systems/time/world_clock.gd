class_name WorldClock
extends RefCounted

## The world's time model. No node, no signals, no engine dependency.
##
## This is deliberately not the autoload. [WorldTime] is a thin driver that owns
## one of these and announces what it does; the model itself is a plain object,
## which means it can be unit tested without a scene tree, serialised directly,
## and - occasionally useful - instantiated a second time to answer a question
## like "what day would it be after three more shifts" without disturbing the
## world.
##
## One authoritative rule: [member total_minutes] is the only mutable state.
## Day, hour and minute are always derived from it, so they can never drift
## apart and a save file is one integer.


## Minutes since day one at 00:00.
var total_minutes: int = 0

## The calendar this clock runs on.
var config: GameTimeConfig = null


static func create(
	time_config: GameTimeConfig
) -> WorldClock:
	var clock: WorldClock = WorldClock.new()

	clock.config = time_config
	clock.reset_to_start()

	return clock


## Returns the clock to the config's starting point.
func reset_to_start() -> void:
	if config == null:
		total_minutes = 0
		return

	total_minutes = config.get_starting_total_minutes()


# -----------------------------------------------------------------------------
# Advancing
# -----------------------------------------------------------------------------

## Moves the clock forward. Returns the number of minutes actually applied.
##
## Never moves backwards: time going backwards would break every scheduled
## event and every "has this happened yet" comparison in the game. Use
## [method set_total_minutes] for loading a save or for debug jumps.
func advance_minutes(
	minutes: int
) -> int:
	if minutes <= 0:
		return 0

	total_minutes += minutes

	return minutes


## Jumps to an exact point. Used by save loading and debug tools.
func set_total_minutes(
	minutes: int
) -> void:
	total_minutes = maxi(minutes, 0)


func set_day_time(
	day: int,
	hour: int,
	minute: int
) -> void:
	set_total_minutes(
		GameTimeStamp.from_day_time(
			day,
			hour,
			minute,
			config
		).total_minutes
	)


# -----------------------------------------------------------------------------
# Reading
# -----------------------------------------------------------------------------

## The current moment as a value object.
##
## The preferred way for gameplay to read time: one call, and everything about
## that moment travels together.
func get_timestamp() -> GameTimeStamp:
	return GameTimeStamp.from_total_minutes(total_minutes, config)


func get_day() -> int:
	return get_timestamp().get_day()


func get_hour() -> int:
	return get_timestamp().get_hour()


func get_minute() -> int:
	return get_timestamp().get_minute()


func get_minutes_into_day() -> int:
	return get_timestamp().get_minutes_into_day()


func get_day_progress() -> float:
	return get_timestamp().get_day_progress()


## Minutes from now until the start of the next day.
func get_minutes_until_next_day() -> int:
	if config == null:
		return 0

	return config.get_minutes_per_day() - get_minutes_into_day()


## Minutes from now until the top of the next hour.
func get_minutes_until_next_hour() -> int:
	if config == null:
		return 0

	return config.minutes_per_hour - get_minute()


# -----------------------------------------------------------------------------
# Persistence
# -----------------------------------------------------------------------------

func to_dictionary() -> Dictionary:
	return {
		"total_minutes": total_minutes
	}


func apply_dictionary(
	data: Dictionary
) -> void:
	set_total_minutes(int(data.get("total_minutes", 0)))
