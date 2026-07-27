class_name GameTimeStamp
extends RefCounted

## A moment in world time, as a value.
##
## Systems that need to talk about time - a delivery window, a shift start, a
## production finish - should pass one of these rather than three loose ints or
## a raw minute count. It compares, it does arithmetic, and it formats, so no
## future system has to reimplement "is it later than", "how long until", or
## "what does that read as".
##
## Backed by a single integer total-minute count, which is what makes
## comparison exact and serialisation trivial. Day, hour and minute are always
## derived, never stored, so the three can never disagree.
##
## Immutable by convention: arithmetic returns a new stamp rather than mutating.


## Minutes since the very beginning of world time, day one at 00:00.
var total_minutes: int = 0

## The calendar this stamp is measured against.
##
## Two stamps built from different configs are not comparable, which the
## comparison methods do not police - one calendar per game is assumed.
var config: GameTimeConfig = null


static func from_total_minutes(
	minutes: int,
	time_config: GameTimeConfig
) -> GameTimeStamp:
	var stamp: GameTimeStamp = GameTimeStamp.new()

	stamp.total_minutes = maxi(minutes, 0)
	stamp.config = time_config

	return stamp


static func from_day_time(
	day: int,
	hour: int,
	minute: int,
	time_config: GameTimeConfig
) -> GameTimeStamp:
	if time_config == null:
		push_error("GameTimeStamp requires a GameTimeConfig.")
		return from_total_minutes(0, null)

	var completed_days: int = maxi(day - 1, 0)

	var minutes: int = (
		completed_days * time_config.get_minutes_per_day()
		+ hour * time_config.minutes_per_hour
		+ minute
	)

	return from_total_minutes(minutes, time_config)


# -----------------------------------------------------------------------------
# Reading
# -----------------------------------------------------------------------------

## Day number, counting from 1.
func get_day() -> int:
	if config == null:
		return 1

	@warning_ignore("integer_division")
	var day_index: int = total_minutes / config.get_minutes_per_day()

	return day_index + 1


func get_hour() -> int:
	if config == null:
		return 0

	@warning_ignore("integer_division")
	var hour: int = get_minutes_into_day() / config.minutes_per_hour

	return hour


func get_minute() -> int:
	if config == null:
		return 0

	return total_minutes % config.minutes_per_hour


## Minutes elapsed since the start of this day.
func get_minutes_into_day() -> int:
	if config == null:
		return 0

	return total_minutes % config.get_minutes_per_day()


## How far through the day this is, 0.0 at midnight and 1.0 at the next.
##
## Ready-made for anything that fades across a day - future lighting, ambience,
## a clock hand - without that system needing to know how long a day is.
func get_day_progress() -> float:
	if config == null:
		return 0.0

	var minutes_per_day: int = config.get_minutes_per_day()

	if minutes_per_day <= 0:
		return 0.0

	return float(get_minutes_into_day()) / float(minutes_per_day)


# -----------------------------------------------------------------------------
# Arithmetic and comparison
# -----------------------------------------------------------------------------

## A new stamp [param minutes] later. Negative values move backwards.
func added_minutes(
	minutes: int
) -> GameTimeStamp:
	return from_total_minutes(total_minutes + minutes, config)


func added_hours(
	hours: int
) -> GameTimeStamp:
	if config == null:
		return from_total_minutes(total_minutes, config)

	return added_minutes(hours * config.minutes_per_hour)


func added_days(
	days: int
) -> GameTimeStamp:
	if config == null:
		return from_total_minutes(total_minutes, config)

	return added_minutes(days * config.get_minutes_per_day())


## Minutes from this stamp to [param other]. Negative when other is earlier.
func minutes_until(
	other: GameTimeStamp
) -> int:
	if other == null:
		return 0

	return other.total_minutes - total_minutes


func is_before(
	other: GameTimeStamp
) -> bool:
	return other != null and total_minutes < other.total_minutes


func is_after(
	other: GameTimeStamp
) -> bool:
	return other != null and total_minutes > other.total_minutes


func equals(
	other: GameTimeStamp
) -> bool:
	return other != null and total_minutes == other.total_minutes


## The next occurrence of [param hour]:[param minute] at or after this stamp.
##
## The building block for anything that happens at the same time every day -
## opening hours, shift starts, a supplier's rounds - without that system doing
## day-rollover arithmetic itself.
func next_daily_occurrence(
	hour: int,
	minute: int
) -> GameTimeStamp:
	if config == null:
		return from_total_minutes(total_minutes, config)

	var minutes_per_day: int = config.get_minutes_per_day()

	var target_into_day: int = (
		hour * config.minutes_per_hour + minute
	)

	var day_start: int = total_minutes - get_minutes_into_day()
	var candidate: int = day_start + target_into_day

	if candidate < total_minutes:
		candidate += minutes_per_day

	return from_total_minutes(candidate, config)


## True when this stamp's hour falls in [param start_hour, end_hour).
##
## Handles windows that wrap past midnight, so a night shift needs no special
## case at the call site.
func is_between_hours(
	start_hour: int,
	end_hour: int
) -> bool:
	var hour: int = get_hour()

	if start_hour <= end_hour:
		return hour >= start_hour and hour < end_hour

	return hour >= start_hour or hour < end_hour


# -----------------------------------------------------------------------------
# Presentation and persistence
# -----------------------------------------------------------------------------

func get_clock_text() -> String:
	return TimeFormatter.format_clock(self)


func get_full_text() -> String:
	return TimeFormatter.format_day_and_clock(self)


func duplicate_stamp() -> GameTimeStamp:
	return from_total_minutes(total_minutes, config)


## The whole stamp, ready for a save file.
##
## Only the minute count is stored. The config is deliberately not serialised:
## it is content, not save data, and a stamp is restored against whatever
## calendar the game is running when it loads.
func to_dictionary() -> Dictionary:
	return {
		"total_minutes": total_minutes
	}


static func from_dictionary(
	data: Dictionary,
	time_config: GameTimeConfig
) -> GameTimeStamp:
	return from_total_minutes(
		int(data.get("total_minutes", 0)),
		time_config
	)


func _to_string() -> String:
	return "GameTimeStamp(%s)" % get_full_text()
