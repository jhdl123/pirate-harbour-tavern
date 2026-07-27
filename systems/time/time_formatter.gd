class_name TimeFormatter
extends RefCounted

## Turns world time into text, in one place.
##
## Formatting lived inside the old clock, which meant a twelve-hour option or a
## translated day label would have meant editing the clock. Here every system
## that shows time - the HUD, a debug panel, a future shift roster, a delivery
## tooltip - produces identical strings from the same rules, and the rules are
## read from [GameTimeConfig] rather than hard-coded.
##
## Static and stateless.


## "14:30", or "2:30 pm" when the config asks for a twelve-hour clock.
static func format_clock(
	stamp: GameTimeStamp
) -> String:
	if stamp == null or stamp.config == null:
		return "--:--"

	var hour: int = stamp.get_hour()
	var minute: int = stamp.get_minute()

	if stamp.config.use_24_hour_clock:
		return "%02d:%02d" % [hour, minute]

	return _format_twelve_hour(hour, minute)


static func _format_twelve_hour(
	hour: int,
	minute: int
) -> String:
	var suffix: String = "am"
	var display_hour: int = hour

	if hour >= 12:
		suffix = "pm"

		if hour > 12:
			display_hour = hour - 12

	if display_hour == 0:
		display_hour = 12

	return "%d:%02d %s" % [display_hour, minute, suffix]


## "Day 3", using the config's label format.
static func format_day(
	stamp: GameTimeStamp
) -> String:
	if stamp == null or stamp.config == null:
		return "Day ?"

	return stamp.config.day_label_format % stamp.get_day()


## "Day 3  14:30".
static func format_day_and_clock(
	stamp: GameTimeStamp
) -> String:
	if stamp == null:
		return "--"

	return "%s  %s" % [
		format_day(stamp),
		format_clock(stamp)
	]


## A length of time as "2h 15m", "45m" or "3d 4h".
##
## For anything that counts down rather than reads a clock: production timers,
## delivery windows, remaining shift length.
static func format_duration(
	minutes: int,
	config: GameTimeConfig
) -> String:
	if config == null or minutes <= 0:
		return "0m"

	var minutes_per_day: int = config.get_minutes_per_day()

	@warning_ignore("integer_division")
	var days: int = minutes / minutes_per_day

	var remainder: int = minutes % minutes_per_day

	@warning_ignore("integer_division")
	var hours: int = remainder / config.minutes_per_hour

	var remaining_minutes: int = remainder % config.minutes_per_hour

	if days > 0:
		return "%dd %dh" % [days, hours]

	if hours > 0:
		return "%dh %02dm" % [hours, remaining_minutes]

	return "%dm" % remaining_minutes


## "x1", "x2.5". Trailing zeroes trimmed so common speeds read cleanly.
static func format_speed(
	multiplier: float
) -> String:
	if is_equal_approx(multiplier, roundf(multiplier)):
		return "x%d" % int(roundf(multiplier))

	return "x%s" % String.num(multiplier, 2)
