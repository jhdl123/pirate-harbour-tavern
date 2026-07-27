class_name TimeScheduler
extends RefCounted

## "Call me at this world time." The reason this is a simulation framework and
## not a clock.
##
## Almost every system the game will grow needs one of three things from time:
##
## [codeblock]
## what time is it now          -> read WorldClock
## tell me when the hour turns  -> connect to a WorldTime signal
## call me at 09:00 every day   -> book it here
## [/codeblock]
##
## Without the third, every future system writes its own [code]_on_hour_changed[/code]
## handler with a manual comparison, quietly reinventing a timer - which is
## exactly what the framework exists to prevent. Deliveries, shifts, opening
## hours, production, daily reports, festivals and NPC routines are all the
## same problem, so they all book here.
##
## [b]Skipping time never skips events.[/b] However far the clock jumps, every
## event inside the window fires, in chronological order, before the clock is
## reported as having moved. A three-day skip still pays three days of wages.


## Events are kept sorted by trigger time, so checking whether anything is due
## is a single comparison against the front of the queue.
var _events: Array[ScheduledTimeEvent] = []

var _next_id: int = 1
var _config: GameTimeConfig = null

## Guards against a callback that advances time re-entering the pump.
var _is_processing: bool = false


static func create(
	config: GameTimeConfig
) -> TimeScheduler:
	var scheduler: TimeScheduler = TimeScheduler.new()

	scheduler._config = config

	return scheduler


# -----------------------------------------------------------------------------
# Booking
# -----------------------------------------------------------------------------

## Fires once, at an exact world time.
func schedule_at(
	stamp: GameTimeStamp,
	callback: Callable,
	tag: StringName = &""
) -> ScheduledTimeEvent:
	if stamp == null:
		push_warning("TimeScheduler was given a null timestamp.")
		return null

	return _add_event(
		stamp.total_minutes,
		ScheduledTimeEvent.Repeat.ONCE,
		callback,
		tag
	)


## Fires once, [param minutes] of world time from [param current_minutes].
##
## The replacement for a gameplay [Timer]: a production run that takes forty
## in-game minutes finishes forty in-game minutes later, whether the player is
## running at normal speed, at six times speed, or skipped the afternoon.
func schedule_in(
	current_minutes: int,
	minutes: int,
	callback: Callable,
	tag: StringName = &""
) -> ScheduledTimeEvent:
	return _add_event(
		current_minutes + maxi(minutes, 0),
		ScheduledTimeEvent.Repeat.ONCE,
		callback,
		tag
	)


## Fires at the same clock time every day, starting with the next occurrence.
func schedule_daily(
	current_minutes: int,
	hour: int,
	minute: int,
	callback: Callable,
	tag: StringName = &""
) -> ScheduledTimeEvent:
	if _config == null:
		push_error("TimeScheduler has no GameTimeConfig.")
		return null

	var next: GameTimeStamp = GameTimeStamp.from_total_minutes(
		current_minutes,
		_config
	).next_daily_occurrence(hour, minute)

	var event: ScheduledTimeEvent = _add_event(
		next.total_minutes,
		ScheduledTimeEvent.Repeat.DAILY,
		callback,
		tag
	)

	if event != null:
		event.daily_hour = hour
		event.daily_minute = minute

	return event


## Fires every [param interval_minutes] of world time, forever.
func schedule_repeating(
	current_minutes: int,
	interval_minutes: int,
	callback: Callable,
	tag: StringName = &""
) -> ScheduledTimeEvent:
	if interval_minutes <= 0:
		push_warning(
			"TimeScheduler repeating interval must be greater than zero."
		)
		return null

	var event: ScheduledTimeEvent = _add_event(
		current_minutes + interval_minutes,
		ScheduledTimeEvent.Repeat.INTERVAL,
		callback,
		tag
	)

	if event != null:
		event.interval_minutes = interval_minutes

	return event


func _add_event(
	trigger_minutes: int,
	repeat_mode: ScheduledTimeEvent.Repeat,
	callback: Callable,
	tag: StringName
) -> ScheduledTimeEvent:
	if not callback.is_valid():
		push_warning(
			"TimeScheduler was given an invalid callback for '%s'."
			% String(tag)
		)
		return null

	var event: ScheduledTimeEvent = ScheduledTimeEvent.new()

	event.id = _next_id
	event.trigger_minutes = trigger_minutes
	event.repeat_mode = repeat_mode
	event.callback = callback
	event.tag = tag

	_next_id += 1

	_events.append(event)
	_sort_events()

	return event


func _sort_events() -> void:
	_events.sort_custom(
		func(first: ScheduledTimeEvent, second: ScheduledTimeEvent) -> bool:
			if first.trigger_minutes == second.trigger_minutes:
				# Stable within a minute: booked first, fired first.
				return first.id < second.id

			return first.trigger_minutes < second.trigger_minutes
	)


# -----------------------------------------------------------------------------
# Cancelling
# -----------------------------------------------------------------------------

func cancel(
	event: ScheduledTimeEvent
) -> void:
	if event == null:
		return

	event.cancel()


## Cancels every event carrying [param tag].
##
## Lets a system tear down all of its own schedules without tracking handles -
## useful on a day rollover, a shift end, or when a save is loaded.
func cancel_tag(
	tag: StringName
) -> int:
	var cancelled: int = 0

	for event: ScheduledTimeEvent in _events:
		if event.tag == tag and not event.is_cancelled:
			event.cancel()
			cancelled += 1

	return cancelled


## Cancels every event whose callback belongs to [param target].
##
## The safety net when an object leaves the world. Freed objects retire
## automatically anyway, but doing it explicitly is cheaper and clearer.
func cancel_all_for(
	target: Object
) -> int:
	var cancelled: int = 0

	for event: ScheduledTimeEvent in _events:
		if event.is_cancelled:
			continue

		if event.callback.get_object() == target:
			event.cancel()
			cancelled += 1

	return cancelled


func cancel_everything() -> void:
	for event: ScheduledTimeEvent in _events:
		event.cancel()

	_events.clear()


# -----------------------------------------------------------------------------
# Pumping
# -----------------------------------------------------------------------------

## Fires everything due at or before [param current_minutes].
##
## Returns how many callbacks ran. Events are fired strictly in time order, so
## a delivery booked for 09:00 always runs before a report booked for 17:00
## even when both are crossed in the same skip.
func process_until(
	current_minutes: int
) -> int:
	if _is_processing:
		# A callback advanced time and re-entered. The outer pump will pick up
		# whatever it booked, so unwinding here keeps ordering intact.
		return 0

	_is_processing = true

	var fired: int = 0

	# Bounded so a repeating event with a tiny interval crossed by a huge skip
	# cannot lock the frame. Anything left over fires on the next pump.
	var safety_limit: int = 4096

	while fired < safety_limit:
		var event: ScheduledTimeEvent = _take_next_due(current_minutes)

		if event == null:
			break

		event.callback.call()

		fired += 1

		if event.advance_to_next_occurrence(_config):
			_events.append(event)
			_sort_events()

	if fired >= safety_limit:
		push_warning(
			"TimeScheduler hit its per-pump limit; remaining events deferred."
		)

	_prune_dead_events()

	_is_processing = false

	return fired


## Removes and returns the next live, due event.
func _take_next_due(
	current_minutes: int
) -> ScheduledTimeEvent:
	while not _events.is_empty():
		var event: ScheduledTimeEvent = _events[0]

		if not event.is_due(current_minutes):
			return null

		_events.remove_at(0)

		if event.is_live():
			return event

		# Dead: cancelled, or its object was freed. Drop it and keep looking.

	return null


func _prune_dead_events() -> void:
	var live_events: Array[ScheduledTimeEvent] = []

	for event: ScheduledTimeEvent in _events:
		if event.is_live():
			live_events.append(event)

	_events = live_events


# -----------------------------------------------------------------------------
# Reading
# -----------------------------------------------------------------------------

func get_pending_count() -> int:
	var count: int = 0

	for event: ScheduledTimeEvent in _events:
		if event.is_live():
			count += 1

	return count


## The soonest live event, or null.
func get_next_event() -> ScheduledTimeEvent:
	for event: ScheduledTimeEvent in _events:
		if event.is_live():
			return event

	return null


func get_events_with_tag(
	tag: StringName
) -> Array[ScheduledTimeEvent]:
	var matching: Array[ScheduledTimeEvent] = []

	for event: ScheduledTimeEvent in _events:
		if event.is_live() and event.tag == tag:
			matching.append(event)

	return matching


## Every pending event, minus the callbacks, for a save file.
##
## Restoring these is deliberately not automatic. See the documentation for the
## re-registration pattern that makes save/load correct rather than clever.
func to_dictionary() -> Dictionary:
	var entries: Array = []

	for event: ScheduledTimeEvent in _events:
		if event.is_live():
			entries.append(event.to_dictionary())

	return {
		"events": entries
	}
