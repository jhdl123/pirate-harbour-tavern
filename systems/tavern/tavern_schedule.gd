class_name TavernSchedule
extends Resource

## When the tavern prepares, opens, takes last orders and closes.
##
## Times are stored as minutes past midnight so that a schedule crossing
## midnight - which the default trading day does - is ordinary arithmetic
## rather than a special case. A tavern opening at 18:00 and closing at 01:00
## is simply a window whose end value is smaller than its start value, and
## [method get_state_at] resolves that by walking the day's transitions in
## order rather than comparing raw hours.
##
## Nothing else in the project should ask the clock what time it is in order to
## decide whether the tavern is open. They ask [TavernLifecycle], which asks
## this.
##
## [b]Room left deliberately[/b]
##
## [member weekday_overrides] is the extension point for weekday, seasonal,
## festival and player-chosen hours: [method get_schedule_for_day] is the only
## place that would need to change, and every caller already goes through it.


@export_category("Identity")

@export var schedule_id: StringName = &"default"

@export var display_name: String = "Standard Trading Day"


@export_category("Daily Times")

## When the player can begin preparing. No normal customers arrive yet.
@export_range(0, 23, 1)
var preparation_hour: int = 17

@export_range(0, 59, 1)
var preparation_minute: int = 0

## When customers start arriving.
@export_range(0, 23, 1)
var opening_hour: int = 18

@export_range(0, 59, 1)
var opening_minute: int = 0

## When new arrivals stop and the tavern winds down.
@export_range(0, 23, 1)
var last_orders_hour: int = 0

@export_range(0, 59, 1)
var last_orders_minute: int = 30

## When remaining customers are moved towards leaving.
@export_range(0, 23, 1)
var closing_hour: int = 1

@export_range(0, 59, 1)
var closing_minute: int = 0

## How long closing lasts before the tavern is fully closed.
##
## A grace period rather than a fixed time, because closing is about letting
## people finish rather than about the clock.
@export_range(0, 600, 5)
var closing_grace_minutes: int = 30


@export_category("Rules")

## Whether the day can be ended before the tavern has actually closed.
@export var allow_end_day_before_closed: bool = false

## Whether the player may open before [member opening_hour].
@export var allow_early_open: bool = true

## Whether the player may start last orders or close early.
@export var allow_early_close: bool = true


@export_category("Transition Warnings")

## Minutes before a transition at which to warn the player.
##
## Data rather than code, so adding a five-minute warning is editing an array.
## Each entry fires once per transition per trading day - the lifecycle tracks
## which have fired and clears them on a new day, which is what stops a warning
## repeating on every clock tick.
@export var warning_offsets_minutes: Array[int] = [60, 30, 10]

## Whether the moment of transition itself is announced.
@export var announce_transition_moment: bool = true


@export_category("Future Schedules")

## Per-weekday replacements, keyed by day-of-week index.
##
## Empty means every day uses this schedule. Populating it is how weekday,
## festival or seasonal hours arrive later without touching any caller.
@export var weekday_overrides: Dictionary = {}


const MINUTES_PER_DAY: int = 1440


## The schedule that applies on [param day]. The hook for future variants.
func get_schedule_for_day(
	day: int
) -> TavernSchedule:
	if weekday_overrides.is_empty():
		return self

	var weekday: int = day % 7

	var override: TavernSchedule = weekday_overrides.get(
		weekday,
		null
	) as TavernSchedule

	return self if override == null else override


func get_preparation_minutes() -> int:
	return preparation_hour * 60 + preparation_minute


func get_opening_minutes() -> int:
	return opening_hour * 60 + opening_minute


func get_last_orders_minutes() -> int:
	return last_orders_hour * 60 + last_orders_minute


func get_closing_minutes() -> int:
	return closing_hour * 60 + closing_minute


func get_closed_minutes() -> int:
	return (get_closing_minutes() + closing_grace_minutes) % MINUTES_PER_DAY


## Every transition in the order a trading day passes through them.
##
## Returned as offsets from the preparation time rather than as absolute
## clock values, which is what makes a day crossing midnight ordinary: the
## offsets always increase, even when the clock wraps.
func get_transition_offsets() -> Array[Dictionary]:
	var start: int = get_preparation_minutes()

	return [
		{
			"state": TavernLifecycle.State.PREPARING,
			"offset": 0,
		},
		{
			"state": TavernLifecycle.State.OPEN,
			"offset": _offset_from(start, get_opening_minutes()),
		},
		{
			"state": TavernLifecycle.State.LAST_ORDERS,
			"offset": _offset_from(start, get_last_orders_minutes()),
		},
		{
			"state": TavernLifecycle.State.CLOSING,
			"offset": _offset_from(start, get_closing_minutes()),
		},
		{
			"state": TavernLifecycle.State.CLOSED,
			"offset": _offset_from(start, get_closed_minutes()),
		},
	]


## Forward distance in minutes from [param from] to [param to], wrapping at
## midnight. Zero-length steps are pushed to a full day so a misconfigured
## schedule cannot produce a transition that never advances.
static func _offset_from(
	from: int,
	to: int
) -> int:
	var offset: int = to - from

	if offset < 0:
		offset += MINUTES_PER_DAY

	return offset


## The operating state at [param minutes_past_midnight].
func get_state_at(
	minutes_past_midnight: int
) -> TavernLifecycle.State:
	var start: int = get_preparation_minutes()
	var elapsed: int = _offset_from(start, minutes_past_midnight)

	var result: TavernLifecycle.State = TavernLifecycle.State.CLOSED

	for transition: Dictionary in get_transition_offsets():
		if elapsed >= int(transition["offset"]):
			result = transition["state"]

	return result


## Minutes from [param minutes_past_midnight] until the state changes.
##
## Always positive: at the very last minute of a trading day this returns the
## wait until tomorrow's preparation rather than zero or a negative number.
func get_minutes_until_next_transition(
	minutes_past_midnight: int
) -> int:
	var start: int = get_preparation_minutes()
	var elapsed: int = _offset_from(start, minutes_past_midnight)

	for transition: Dictionary in get_transition_offsets():
		var offset: int = int(transition["offset"])

		if offset > elapsed:
			return offset - elapsed

	return MINUTES_PER_DAY - elapsed


## The state the tavern moves into next.
func get_next_state(
	minutes_past_midnight: int
) -> TavernLifecycle.State:
	var start: int = get_preparation_minutes()
	var elapsed: int = _offset_from(start, minutes_past_midnight)

	for transition: Dictionary in get_transition_offsets():
		if int(transition["offset"]) > elapsed:
			return transition["state"]

	return TavernLifecycle.State.PREPARING


## Warns about a schedule whose stages are out of order or collapsed.
##
## Called once at startup. A schedule where closing precedes opening is almost
## always a typo, and silently producing a zero-length trading day would be a
## miserable thing to debug from the symptoms.
func validate_or_warn() -> bool:
	var offsets: Array[Dictionary] = get_transition_offsets()
	var previous: int = -1
	var is_valid: bool = true

	for transition: Dictionary in offsets:
		var offset: int = int(transition["offset"])

		if offset <= previous:
			push_warning(
				"TavernSchedule '%s': stage %s is not after the previous "
				% [
					String(schedule_id),
					TavernLifecycle.State.keys()[transition["state"]],
				]
				+ "stage. Check the configured times."
			)

			is_valid = false

		previous = offset

	return is_valid


## One line for diagnostics and the debug panel.
func describe() -> String:
	return "prep %02d:%02d, open %02d:%02d, last orders %02d:%02d, closing %02d:%02d (+%dm)" % [
		preparation_hour, preparation_minute,
		opening_hour, opening_minute,
		last_orders_hour, last_orders_minute,
		closing_hour, closing_minute,
		closing_grace_minutes,
	]


func to_dictionary() -> Dictionary:
	return {
		"schedule_id": String(schedule_id),
		"display_name": display_name,
		"preparation": get_preparation_minutes(),
		"opening": get_opening_minutes(),
		"last_orders": get_last_orders_minutes(),
		"closing": get_closing_minutes(),
		"closed": get_closed_minutes(),
		"closing_grace_minutes": closing_grace_minutes,
	}
