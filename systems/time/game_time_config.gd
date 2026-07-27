class_name GameTimeConfig
extends Resource

## Every number the world clock and simulation need, in one resource.
##
## Nothing in the time framework contains a hard-coded constant. The length of
## an hour, the length of a day, how fast time runs and which speeds the player
## can choose are all data, so a tavern that runs on twenty-hour days or a
## debug build that runs a day in ten seconds needs no code change.
##
## Kept as a Resource rather than constants so the same framework can later
## serve a different calendar - a festival week, a dream sequence, a tutorial
## that runs at a fixed hour - by swapping the resource.


@export_category("Calendar")

## In-game minutes in one in-game hour.
##
## Sixty is conventional, but nothing in the framework assumes it. All
## conversion goes through [WorldClock], which reads this.
@export_range(1, 240, 1)
var minutes_per_hour: int = 60

## In-game hours in one in-game day.
@export_range(1, 48, 1)
var hours_per_day: int = 24


@export_category("Starting Point")

## The day number a new game begins on.
@export_range(1, 9999, 1)
var starting_day: int = 1

## Clock time a new game begins at.
@export_range(0, 47, 1)
var starting_hour: int = 8

@export_range(0, 239, 1)
var starting_minute: int = 0


@export_category("Rate")

## In-game minutes that pass per real second at speed multiplier 1.0.
##
## The one number that decides how long a day feels. At 1.0 a
## twenty-four hour day takes twenty-four real minutes.
@export_range(0.01, 600.0, 0.01)
var game_minutes_per_real_second: float = 1.0

## Speeds the player can cycle through.
##
## Index 0 is normal speed by convention, but [member default_speed_index]
## decides what a new game starts on.
@export var available_speed_multipliers: Array[float] = [
	1.0,
	2.0,
	4.0
]

## Which entry of [member available_speed_multipliers] a new game starts on.
@export_range(0, 16, 1)
var default_speed_index: int = 0

## Speed applied while the simulation is in its fast-forward state.
##
## Separate from the player's chosen speed, so leaving fast-forward restores
## whatever they had selected rather than snapping to normal.
@export_range(0.1, 100.0, 0.1)
var fast_forward_speed_multiplier: float = 6.0


@export_category("Advancement")

## Largest jump that still emits a signal for every individual minute.
##
## Beyond this the clock emits [signal WorldTime.time_skipped] plus one
## boundary signal per hour and day crossed, instead of thousands of minute
## signals. Skipping three days would otherwise emit over four thousand.
##
## Scheduled events always fire in full, however large the jump.
@export_range(1, 1440, 1)
var maximum_stepped_minutes: int = 120


@export_category("Formatting")

## Whether times read as 14:30 or as 2:30 pm.
@export var use_24_hour_clock: bool = true

## Format string for a day label. Receives the day number.
@export var day_label_format: String = "Day %d"


## Total in-game minutes in one in-game day.
func get_minutes_per_day() -> int:
	return minutes_per_hour * hours_per_day


## The starting point expressed in total elapsed minutes.
func get_starting_total_minutes() -> int:
	var completed_days: int = maxi(starting_day - 1, 0)

	return (
		completed_days * get_minutes_per_day()
		+ starting_hour * minutes_per_hour
		+ starting_minute
	)


## The speed a new game begins at.
func get_default_speed_multiplier() -> float:
	if available_speed_multipliers.is_empty():
		return 1.0

	var index: int = clampi(
		default_speed_index,
		0,
		available_speed_multipliers.size() - 1
	)

	return available_speed_multipliers[index]


## Warns about settings that would produce a broken clock.
##
## Called once by [WorldTime] on ready rather than on every access, so a bad
## resource is reported at startup instead of silently misbehaving.
func validate_or_warn() -> bool:
	var is_valid: bool = true

	if minutes_per_hour <= 0 or hours_per_day <= 0:
		push_error(
			"GameTimeConfig has a zero-length hour or day."
		)
		is_valid = false

	if starting_hour >= hours_per_day:
		push_warning(
			"GameTimeConfig starting_hour %d is outside a %d hour day."
			% [starting_hour, hours_per_day]
		)
		is_valid = false

	if starting_minute >= minutes_per_hour:
		push_warning(
			"GameTimeConfig starting_minute %d is outside a %d minute hour."
			% [starting_minute, minutes_per_hour]
		)
		is_valid = false

	if available_speed_multipliers.is_empty():
		push_warning(
			"GameTimeConfig has no speed multipliers; 1.0 will be used."
		)

	for multiplier: float in available_speed_multipliers:
		if multiplier <= 0.0:
			push_warning(
				"GameTimeConfig contains a non-positive speed multiplier."
			)
			is_valid = false

	return is_valid
