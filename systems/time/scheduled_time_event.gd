class_name ScheduledTimeEvent
extends RefCounted

## One thing waiting to happen at a world time.
##
## Returned by every [TimeScheduler] booking so the caller has a handle it can
## cancel, inspect or reschedule without having to remember the exact
## [Callable] it passed in. Comparing Callables to find "the one I booked" is
## fragile; holding a handle is not.


enum Repeat {
	## Fires once, then retires.
	ONCE,

	## Fires every [member interval_minutes] forever.
	INTERVAL,

	## Fires at the same clock time every day.
	DAILY,
}


## Unique within the scheduler that issued it.
var id: int = 0

## World time, in total minutes, at which this next fires.
var trigger_minutes: int = 0

var repeat_mode: Repeat = Repeat.ONCE

## Gap between firings for [constant Repeat.INTERVAL].
var interval_minutes: int = 0

## Clock time for [constant Repeat.DAILY].
var daily_hour: int = 0
var daily_minute: int = 0

## What to run. Not serialisable - see [method TimeScheduler.to_dictionary].
var callback: Callable = Callable()

## Caller-supplied label, for debugging and for save/load re-registration.
##
## Example: [code]&"tavern_opening"[/code], [code]&"delivery_window"[/code].
var tag: StringName = &""

var is_cancelled: bool = false


## Stops this event firing again.
##
## Safe to call from inside the callback, and safe to call twice.
func cancel() -> void:
	is_cancelled = true


## True when this can still fire.
##
## A callback whose object has been freed is treated as cancelled rather than
## as an error: customers, staff and world objects are removed all the time,
## and a schedule outliving its owner should quietly retire.
func is_live() -> bool:
	if is_cancelled:
		return false

	return callback.is_valid()


func is_due(
	current_minutes: int
) -> bool:
	return current_minutes >= trigger_minutes


## Moves this event to its next firing, or retires it.
##
## Returns false when the event is finished and should be dropped.
func advance_to_next_occurrence(
	config: GameTimeConfig
) -> bool:
	match repeat_mode:
		Repeat.ONCE:
			return false

		Repeat.INTERVAL:
			if interval_minutes <= 0:
				return false

			trigger_minutes += interval_minutes

			return true

		Repeat.DAILY:
			if config == null:
				return false

			var stamp: GameTimeStamp = GameTimeStamp.from_total_minutes(
				trigger_minutes + 1,
				config
			)

			trigger_minutes = stamp.next_daily_occurrence(
				daily_hour,
				daily_minute
			).total_minutes

			return true

		_:
			return false


func get_description() -> String:
	var label: String = String(tag)

	if label.is_empty():
		label = "event %d" % id

	return "%s at minute %d" % [label, trigger_minutes]


## Everything except the callback, for a save file.
##
## The callback is intentionally absent: a Callable cannot be serialised, and
## restoring one would mean the save file naming methods on live objects. The
## correct pattern is that each system re-registers its own schedules on load
## and the framework restores the *times* - see the documentation.
func to_dictionary() -> Dictionary:
	return {
		"tag": String(tag),
		"trigger_minutes": trigger_minutes,
		"repeat_mode": int(repeat_mode),
		"interval_minutes": interval_minutes,
		"daily_hour": daily_hour,
		"daily_minute": daily_minute
	}
