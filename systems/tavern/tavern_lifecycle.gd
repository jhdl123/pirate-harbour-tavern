class_name TavernLifecycle
extends Node

## The tavern's operating state, and the only authority on whether it is open.
##
## Autoloaded as [code]Tavern[/code]. World time and operating state are
## deliberately different things: [WorldTime] knows it is 00:45, and this knows
## that means last orders. Nothing else in the project should derive one from
## the other, because the moment two systems each decide for themselves what
## "open" means they will eventually disagree.
##
## [b]How a day runs[/b]
##
## [codeblock]
## PREPARING     stock, orders, management. No normal arrivals.
## OPEN          normal trade.
## LAST_ORDERS   arrivals stop; those inside may finish and order once more.
## CLOSING       no new orders; customers wind down. Nobody is deleted.
## CLOSED        service inactive; the End Day action becomes available.
## DAY_COMPLETE  totals finalised, time skipped to the next preparation.
## [/codeblock]
##
## [b]Why states are recomputed rather than driven by timers[/b]
##
## The state is derived from the clock by [method _evaluate], which runs on
## WorldTime's minute signal. That means a large time skip, a speed change, a
## save loaded mid-evening or the game starting at 23:00 all arrive at the
## correct state by the same path - there is no timer to fall out of step, and
## no separate "catch up" branch that only runs sometimes.
##
## DAY_COMPLETE is the one state that is not derived: it is a deliberate player
## action, so it is entered explicitly and left explicitly.


signal preparation_started(day: int)
signal tavern_opened(day: int)
signal last_orders_started(day: int)
signal closing_started(day: int)
signal tavern_closed(day: int)

## The player finalised the day. Emitted before any time is skipped.
signal day_ended(day: int, summary: Dictionary)

## The frozen summary is available to display.
signal summary_available(day: int, summary: Dictionary)

## The next trading day's preparation has begun.
signal new_day_started(day: int)

## Any operating-state change, with the reason. The catch-all for UI.
signal operating_state_changed(
	previous_state: State,
	new_state: State,
	reason: StringName
)


enum State {
	## Before opening. Management only; no normal arrivals.
	PREPARING,

	## Normal trade.
	OPEN,

	## Arrivals stop; those already inside wind down.
	LAST_ORDERS,

	## No new orders; customers move towards leaving.
	CLOSING,

	## Service inactive. End Day is available.
	CLOSED,

	## Trading finished and the day's figures are frozen.
	##
	## Distinct from READY_FOR_NEXT_DAY because the player is reading the
	## summary here, and the transition out of it is theirs to make.
	END_OF_DAY,

	## The summary has been acknowledged; the next day may begin.
	##
	## Entered by [method acknowledge_summary], which the summary screen calls
	## when the player dismisses it. Separating this from END_OF_DAY is what
	## lets the screen own "is the player still reading?" without the lifecycle
	## having to know a screen exists.
	READY_FOR_NEXT_DAY,
}


const DEFAULT_SCHEDULE_PATH: String = (
	"res://Data/tavern/default_schedule.tres"
)

const REASON_SCHEDULED: StringName = &"scheduled"
const REASON_MANUAL: StringName = &"manual"
const REASON_STARTUP: StringName = &"startup"
const REASON_DAY_ENDED: StringName = &"day_ended"


@export var schedule: TavernSchedule = null

## Whether state changes raise a player-facing notification.
@export var announce_transitions: bool = true


var current_state: State = State.PREPARING

## Set while the player has ended the day but the skip has not completed.
var is_day_complete: bool = false

## Trading day number.
##
## Its own counter, not derived from the world day. A trading session runs from
## 18:00 to 01:30 and therefore crosses midnight, so the world day increments
## in the middle of service - deriving the trading day from it meant ending a
## day at 02:00 and starting the next at 17:00 produced no change at all.
##
## Incremented exactly once, in [method advance_to_next_day].
var trading_day: int = 1

## Manual overrides applied today, cleared each new day.
##
## An early open must not be undone by the next scheduled evaluation deciding
## it is still technically before opening time.
var _manual_state_floor: State = State.PREPARING
var _has_manual_override: bool = false

## World minute a manual CLOSING began, so the grace period can elapse.
##
## Without this the floor pinned the tavern in CLOSING until the schedule
## happened to reach closing time on its own, which for an early close could be
## most of a day away.
var _manual_closing_started_minutes: float = -1.0

## Transitions this session, for the diagnostic export. Bounded.
var _transition_log: Array[Dictionary] = []

## Totals gathered for the end-of-day summary, reset each trading day.
var _day_metrics: Dictionary = {}

## State announcements already made, so each is communicated once.
var _announced_states: Dictionary = {}

## Per-trading-day figures. Owned here because this is what knows when a day
## begins and ends.
var stats: DailyStatistics = null

## Warning offsets already fired, keyed by "state:offset", cleared each day.
var _fired_warnings: Dictionary = {}

## The frozen record, available from END_OF_DAY until the next day starts.
var _frozen_summary: Dictionary = {}

## Bounded chronological history of significant lifecycle events.
var _event_history: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_resolve_schedule()

	# Deferred so every other autoload and the main scene exist before the
	# first evaluation announces anything.
	_initialise.call_deferred()


func _resolve_schedule() -> void:
	if schedule == null and ResourceLoader.exists(DEFAULT_SCHEDULE_PATH):
		schedule = load(DEFAULT_SCHEDULE_PATH) as TavernSchedule

	if schedule == null:
		push_warning(
			"TavernLifecycle could not load "
			+ DEFAULT_SCHEDULE_PATH
			+ " - falling back to built-in default hours."
		)

		schedule = TavernSchedule.new()

		return

	schedule.validate_or_warn()


func _initialise() -> void:
	trading_day = maxi(WorldTime.get_day(), 1)

	_reset_day_metrics()

	stats = DailyStatistics.new(trading_day)

	# The game may legitimately start at any hour, including mid-evening or
	# after closing. Deriving the state rather than assuming PREPARING is what
	# makes that work without a special case.
	var derived: State = _derive_state()

	_apply_state(derived, REASON_STARTUP)

	WorldTime.minute_passed.connect(_on_minute_passed)
	WorldTime.day_changed.connect(_on_day_changed)

	# Also on time_changed, which is the signal any direct clock manipulation
	# emits - set_time(), a loaded save, a developer jump backwards. Listening
	# only to minute_passed left the state stale whenever the clock moved
	# without ticking forward, which is exactly the "lifecycle state does not
	# match the current time" fault the health checks are meant to catch.
	WorldTime.time_changed.connect(_on_time_changed)


# -----------------------------------------------------------------------------
# Evaluation
# -----------------------------------------------------------------------------

func _on_minute_passed(
	_stamp: GameTimeStamp
) -> void:
	_evaluate()
	_check_transition_warnings()


## Fires configured countdown warnings once each per trading day.
##
## Driven by minutes-until-next-transition rather than by absolute times, so
## the same code covers opening, last orders and closing without knowing which
## is which - and a schedule change needs no corresponding change here.
func _check_transition_warnings() -> void:
	if is_day_complete or current_state == State.CLOSED:
		return

	var active: TavernSchedule = get_active_schedule()

	if active.warning_offsets_minutes.is_empty():
		return

	var remaining: int = get_minutes_until_next_transition()
	var next_state: State = get_next_state()

	for offset: int in active.warning_offsets_minutes:
		if remaining != offset:
			continue

		var key: String = "%s:%d:%d" % [
			State.keys()[next_state],
			offset,
			trading_day,
		]

		if _fired_warnings.has(key):
			return

		_fired_warnings[key] = true

		_announce_warning(next_state, offset)

		return


func _announce_warning(
	next_state: State,
	minutes: int
) -> void:
	if not is_instance_valid(Comms):
		return

	var what: String = ""

	match next_state:
		State.OPEN:
			what = "The tavern opens"

		State.LAST_ORDERS:
			what = "Last orders begin"

		State.CLOSING:
			what = "The tavern closes"

		State.CLOSED:
			what = "The doors close"

	if what.is_empty():
		return

	var when: String = (
		"in one hour" if minutes == 60
		else "in %d minutes" % minutes
	)

	Comms.notify("%s %s." % [what, when], CommMessage.Category.SYSTEM)

	_record_event(&"transition_warning", {
		"next_state": State.keys()[next_state],
		"minutes": minutes,
	})


func _on_day_changed(
	_stamp: GameTimeStamp
) -> void:
	_evaluate()


func _on_time_changed(
	_stamp: GameTimeStamp
) -> void:
	_evaluate()


## Recomputes the state from the clock and applies it if it changed.
func _evaluate() -> void:
	# A completed day is a held state: the player has finished trading and is
	# looking at the summary. Only advance_to_next_day() leaves it.
	if is_day_complete:
		return

	var derived: State = _derive_state()

	if derived == current_state:
		return

	_apply_state(derived, REASON_SCHEDULED)


func _derive_state() -> State:
	var active: TavernSchedule = get_active_schedule()

	var minutes: int = WorldTime.get_hour() * 60 + WorldTime.get_minute()

	var scheduled: State = active.get_state_at(minutes)

	# A manual close is a stage, not a resting state: once the configured
	# grace period has run, the tavern finishes closing on its own rather than
	# waiting for the schedule to catch up.
	if _manual_closing_started_minutes >= 0.0:
		var elapsed: float = (
			WorldTime.get_total_minutes_precise()
			- _manual_closing_started_minutes
		)

		if elapsed >= float(active.closing_grace_minutes):
			_manual_state_floor = State.CLOSED
			_manual_closing_started_minutes = -1.0

	# An early open must not be reverted by the next evaluation noticing that
	# the clock has not reached opening time yet. The manual action raises a
	# floor for the rest of the trading day.
	if _has_manual_override and scheduled < _manual_state_floor:
		return _manual_state_floor

	return scheduled


func _apply_state(
	new_state: State,
	reason: StringName
) -> void:
	var previous: State = current_state

	if previous == new_state:
		return

	current_state = new_state

	_transition_log.append({
		"world_minutes": WorldTime.get_total_minutes_precise(),
		"clock": WorldTime.get_clock_text(),
		"day": WorldTime.get_day(),
		"trading_day": trading_day,
		"from": State.keys()[previous],
		"to": State.keys()[new_state],
		"reason": String(reason),
	})

	while _transition_log.size() > 200:
		_transition_log.pop_front()

	operating_state_changed.emit(previous, new_state, reason)

	_emit_state_signal(new_state)

	if announce_transitions:
		_announce(new_state)


func _emit_state_signal(
	new_state: State
) -> void:
	match new_state:
		State.PREPARING:
			preparation_started.emit(trading_day)

		State.OPEN:
			stats.mark_service_started()

			tavern_opened.emit(trading_day)

		State.LAST_ORDERS:
			last_orders_started.emit(trading_day)

		State.CLOSING:
			closing_started.emit(trading_day)

		State.CLOSED:
			stats.mark_service_ended()

			tavern_closed.emit(trading_day)


## One notification per transition, through the existing communication service.
func _announce(
	new_state: State
) -> void:
	if not is_instance_valid(Comms):
		return

	var text: String = ""

	match new_state:
		State.PREPARING:
			text = "The tavern is preparing to open."

		State.OPEN:
			text = "The tavern is now open."

		State.LAST_ORDERS:
			text = "Last orders!"

		State.CLOSING:
			text = "The tavern is closing."

		State.CLOSED:
			text = "The tavern is now closed. End the day when ready."

	if text.is_empty():
		return

	# One announcement per state per trading day. A state re-entered after a
	# manual action must not produce a second identical toast.
	var key: String = "%s_%d" % [State.keys()[new_state], trading_day]

	if _announced_states.has(key):
		return

	_announced_states[key] = true

	Comms.notify(text, CommMessage.Category.SYSTEM)


# -----------------------------------------------------------------------------
# Reading
# -----------------------------------------------------------------------------

func get_active_schedule() -> TavernSchedule:
	return schedule.get_schedule_for_day(WorldTime.get_day())


func get_state() -> State:
	return current_state


func get_state_name() -> String:
	return State.keys()[current_state]


## True when normal customers should be arriving.
##
## The single question the arrival controller asks. Nothing else needs to know
## which state that corresponds to.
func is_accepting_arrivals() -> bool:
	return current_state == State.OPEN


## True when customers already inside may still place orders.
func is_accepting_orders() -> bool:
	return (
		current_state == State.OPEN
		or current_state == State.LAST_ORDERS
	)


## True when customers should be winding down and heading out.
func is_winding_down() -> bool:
	return (
		current_state == State.CLOSING
		or current_state == State.CLOSED
	)


func is_open_for_business() -> bool:
	return is_accepting_orders()


func get_minutes_until_next_transition() -> int:
	var minutes: int = WorldTime.get_hour() * 60 + WorldTime.get_minute()

	return get_active_schedule().get_minutes_until_next_transition(minutes)


func get_next_state() -> State:
	if current_state == State.CLOSED or is_day_complete:
		return State.END_OF_DAY

	var minutes: int = WorldTime.get_hour() * 60 + WorldTime.get_minute()

	return get_active_schedule().get_next_state(minutes)


func can_end_day() -> bool:
	if is_day_complete:
		return false

	if current_state == State.CLOSED:
		return true

	return get_active_schedule().allow_end_day_before_closed


## Records a significant lifecycle event. Bounded.
func _record_event(
	event_type: StringName,
	values: Dictionary = {}
) -> void:
	_event_history.append({
		"world_minutes": WorldTime.get_total_minutes_precise(),
		"clock": WorldTime.get_clock_text(),
		"trading_day": trading_day,
		"event_type": String(event_type),
		"state": get_state_name(),
		"values": values.duplicate(true),
	})

	while _event_history.size() > 300:
		_event_history.pop_front()


func get_event_history() -> Array[Dictionary]:
	return _event_history.duplicate(true)


func get_transition_log() -> Array[Dictionary]:
	return _transition_log.duplicate(true)


# -----------------------------------------------------------------------------
# Manual actions
# -----------------------------------------------------------------------------

## Opens before the scheduled time.
func open_early() -> bool:
	if current_state != State.PREPARING:
		return false

	if not get_active_schedule().allow_early_open:
		return false

	return _apply_manual_state(State.OPEN)


func begin_last_orders_early() -> bool:
	if current_state != State.OPEN:
		return false

	if not get_active_schedule().allow_early_close:
		return false

	return _apply_manual_state(State.LAST_ORDERS)


func close_early() -> bool:
	if current_state == State.CLOSED or is_day_complete:
		return false

	if not get_active_schedule().allow_early_close:
		return false

	return _apply_manual_state(State.CLOSING)


func _apply_manual_state(
	new_state: State
) -> bool:
	_has_manual_override = true
	_manual_state_floor = new_state

	_manual_closing_started_minutes = (
		WorldTime.get_total_minutes_precise()
		if new_state == State.CLOSING
		else -1.0
	)

	_apply_state(new_state, REASON_MANUAL)

	return true


## Finalises the trading day.
##
## Emits [signal day_ended] with the summary before any time moves, so a
## listener can read totals that are still current. The skip itself is a
## separate, explicit call so the player can read the summary first.
## Finalises the trading day.
##
## Idempotent. A second call - a double-click, a repeated debug command -
## returns the same frozen record rather than producing a second summary or
## re-running cleanup. That property is what makes the developer controls safe
## to mash.
func end_day() -> Dictionary:
	if is_day_complete:
		return _frozen_summary.duplicate(true)

	if not can_end_day():
		_record_event(&"unsafe_transition_attempt", {
			"action": "end_day",
			"state": get_state_name(),
			"blockers": get_next_day_blockers(),
		})

		return {}

	# Freeze first, then change state: the record should describe the day that
	# was traded, not the moment after it ended.
	var frozen: Dictionary = stats.freeze()

	_frozen_summary = build_day_summary()
	_frozen_summary["statistics"] = frozen

	is_day_complete = true

	_apply_state(State.END_OF_DAY, REASON_DAY_ENDED)

	_record_event(&"summary_finalised", {
		"trading_day": trading_day,
		"total_income": frozen.get("total_income", 0.0),
	})

	day_ended.emit(trading_day, _frozen_summary)
	summary_available.emit(trading_day, _frozen_summary)

	return _frozen_summary.duplicate(true)


## The frozen summary, or an empty Dictionary before the day is finalised.
func get_frozen_summary() -> Dictionary:
	return _frozen_summary.duplicate(true)


## Reasons the next day cannot safely begin. Empty means it can.
##
## Reported rather than enforced silently: a blocked transition that gives no
## reason is indistinguishable from a broken button.
func get_next_day_blockers() -> Array[String]:
	var blockers: Array[String] = []

	if not is_day_complete and current_state != State.CLOSED:
		if not get_active_schedule().allow_end_day_before_closed:
			blockers.append(
				"The tavern is still %s." % get_state_name().to_lower()
			)

	return blockers


## Skips to the next preparation period.
##
## Uses [method WorldTime.skip_to], which walks the interval event by event in
## chronological order - so deliveries, orders and any other scheduled work
## land exactly once and in the right order, even across several days. There is
## deliberately no separate catch-up path here.
## Skips to the next preparation period and starts a new trading day.
##
## Uses [method WorldTime.skip_to], which walks the interval event by event in
## chronological order - so deliveries and any other scheduled work land
## exactly once and in the right order, even across several days. There is
## deliberately no separate catch-up path here.
##
## [b]Cleanup rule[/b]
##
## Any customers still present are asked to leave through their own normal
## departure path, not deleted. Staff tasks referring to them then invalidate
## themselves through the ordinary task-board validation. The number affected
## is recorded, because a day that regularly ends with people still inside is
## telling the player something.
## Dismisses the summary and permits the next day to begin.
##
## Idempotent, and safe to call from a button that can be pressed twice.
func acknowledge_summary() -> bool:
	if current_state != State.END_OF_DAY:
		return current_state == State.READY_FOR_NEXT_DAY

	_apply_state(State.READY_FOR_NEXT_DAY, REASON_MANUAL)

	_record_event(&"summary_acknowledged", { "trading_day": trading_day })

	return true


## True when the next day may begin right now.
func can_start_next_day() -> bool:
	return (
		is_day_complete
		and current_state == State.READY_FOR_NEXT_DAY
	)


func advance_to_next_day() -> Dictionary:
	# Acknowledging is part of the flow rather than a second thing to
	# remember, so a caller that skips the summary screen still works.
	if current_state == State.END_OF_DAY:
		acknowledge_summary()

	if not is_day_complete:
		_record_event(&"unsafe_transition_attempt", {
			"action": "advance_to_next_day",
			"state": get_state_name(),
		})

		return {}

	var cleanup: Dictionary = _clean_up_for_new_day()

	var active: TavernSchedule = get_active_schedule()

	var target_minutes: int = active.get_preparation_minutes()

	var now: int = WorldTime.get_hour() * 60 + WorldTime.get_minute()

	var day_offset: int = 1 if target_minutes <= now else 0

	var before_total: int = WorldTime.get_total_minutes()

	WorldTime.skip_to(
		WorldTime.get_day() + day_offset,
		target_minutes / 60,
		target_minutes % 60
	)

	var skipped: int = WorldTime.get_total_minutes() - before_total

	is_day_complete = false
	_has_manual_override = false
	_manual_state_floor = State.PREPARING
	_manual_closing_started_minutes = -1.0

	trading_day += 1

	# Per-day state only. Money, stock and progression are deliberately
	# untouched - they belong to the tavern, not to the day.
	_reset_day_metrics()
	_announced_states.clear()
	_fired_warnings.clear()
	_frozen_summary.clear()

	stats.reset(trading_day)

	_apply_state(State.PREPARING, REASON_DAY_ENDED)

	_record_event(&"new_day_started", {
		"trading_day": trading_day,
		"minutes_skipped": skipped,
		"cleanup": cleanup,
	})

	new_day_started.emit(trading_day)

	return {
		"trading_day": trading_day,
		"minutes_skipped": skipped,
		"resumed_at": WorldTime.get_clock_text(),
		"cleanup": cleanup,
	}


## Sends any remaining customers home through their own departure path.
func _clean_up_for_new_day() -> Dictionary:
	var asked_to_leave: int = 0
	var could_not_leave: int = 0

	for node: Node in get_tree().get_nodes_in_group(&"customers"):
		if node == null or not is_instance_valid(node):
			continue

		if node.has_method(&"finish_customer"):
			# Marked before the call so the departure signal carries the right
			# reason. A customer sent home by the day ending is not a customer
			# the tavern failed to serve, and must not damage the service rate.
			if "departure_reason" in node:
				node.set("departure_reason", &"day_ended_cleanup")

			node.call(&"finish_customer")

			asked_to_leave += 1
		else:
			could_not_leave += 1

	return {
		"customers_asked_to_leave": asked_to_leave,
		"customers_without_departure_path": could_not_leave,
		"open_tasks_at_close": (
			0 if not is_instance_valid(TaskBoard)
			else TaskBoard.get_open_task_count()
		),
	}


# -----------------------------------------------------------------------------
# Daily summary
# -----------------------------------------------------------------------------

func _reset_day_metrics() -> void:
	_day_metrics = {
		"trading_day": trading_day,
		"opened_at": "",
		"closed_at": "",
		"customers_entered": 0,
		"customers_served": 0,
		"customers_left_unserved": 0,
		"peak_occupancy": 0,
		"peak_demand_multiplier": 0.0,
		"arrivals_rejected": 0,
	}


## Records a day metric. Called by the arrival controller and game manager.
##
## Deliberately a generic counter rather than a fixed set of methods, so a new
## daily figure is one call site rather than a change here as well.
## Records a day metric.
##
## Delegates to [member stats]. Phase 4 kept a second per-day dictionary here
## alongside DailyStatistics, which meant two places to look and two places to
## forget to reset. There is now one store.
func record_day_metric(
	key: StringName,
	amount: float = 1.0
) -> void:
	stats.record(key, amount)


func record_day_peak(
	key: StringName,
	value: float
) -> void:
	stats.record_peak(key, value)


## The end-of-day figures.
##
## Only values the project genuinely tracks. Wages, rent and net result are
## deliberately absent rather than invented.
func build_day_summary() -> Dictionary:
	var summary: Dictionary = _day_metrics.duplicate(true)

	summary["trading_day"] = trading_day
	summary["world_day"] = WorldTime.get_day()
	summary["ended_at"] = WorldTime.get_clock_text()
	summary["schedule"] = get_active_schedule().to_dictionary()
	summary["state_transitions"] = get_transition_log()

	if is_instance_valid(TaskBoard):
		var board: Dictionary = TaskBoard.get_summary()

		summary["staff_tasks_completed"] = board.get("tasks_completed", 0)
		summary["staff_tasks_open_at_close"] = board.get("tasks_open", 0)

	return summary


func build_report_section() -> Dictionary:
	return {
		"current_state": get_state_name(),
		"trading_day": trading_day,
		"schedule": get_active_schedule().to_dictionary(),
		"minutes_until_next_transition": get_minutes_until_next_transition(),
		"next_state": State.keys()[get_next_state()],
		"transitions": get_transition_log(),
		"day_metrics": _day_metrics.duplicate(true),
		"statistics": stats.get_record(),
		"event_history": get_event_history(),
		"is_day_complete": is_day_complete,
		"summary_frozen": stats.is_frozen,
		"next_day_blockers": get_next_day_blockers(),
		"warnings_fired": _fired_warnings.keys(),
	}
