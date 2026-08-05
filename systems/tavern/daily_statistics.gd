class_name DailyStatistics
extends RefCounted

## Per-trading-day figures, and the frozen record made at end of day.
##
## Owned by [TavernLifecycle] rather than living in its own manager: there is
## exactly one trading day in progress, and the thing that knows when a day
## starts and ends should own the numbers for it. [StatisticsTracker] keeps the
## lifetime totals and is untouched - this is deliberately the per-day layer on
## top, not a second copy of it.
##
## [b]Everything here is recorded from gameplay events.[/b] Nothing is derived
## by scanning UI labels or the scene tree at close of business, which is what
## makes the frozen record trustworthy after the customers have gone.
##
## [b]Freezing[/b]
##
## [method freeze] takes a deep copy and latches it. Later calls to
## [method record] still update the live counters but can no longer alter the
## frozen record, so the summary screen cannot change under the player while
## they are reading it. That property is asserted by the test suite.


## Counters that are simple running totals.
const COUNTER_KEYS: Array[StringName] = [
	&"sales_income",
	&"tips",
	&"drinks_sold",
	&"transactions_completed",
	&"customers_served",
	&"customers_lost",
	&"customers_lost_patience",
	&"customers_lost_no_seating",
	&"customers_lost_no_stock",
	&"customers_lost_other",
	&"customers_sent_home",
	&"groups_served",
	&"groups_lost",
	&"breakages",
	&"stock_used",
	&"deliveries_received",
	&"arrivals_rejected",
	&"customers_entered",
	&"staff_tasks_completed",
]


var trading_day: int = 1

## Simple totals, keyed by the names above.
var counters: Dictionary = {}

## item_id -> quantity sold.
var sales_by_item: Dictionary = {}

## item_id -> money taken.
var income_by_item: Dictionary = {}

## item_id -> servings or units consumed.
var stock_used_by_item: Dictionary = {}

## Peaks, tracked as maxima rather than totals.
var peaks: Dictionary = {}

## Clock strings, captured at the moment the state was entered.
var service_started_at: String = ""
var service_ended_at: String = ""

## World minutes, so open duration is a real number rather than a string diff.
var service_start_minutes: float = -1.0
var service_end_minutes: float = -1.0

## Set once [method freeze] has run.
var is_frozen: bool = false

var _frozen_record: Dictionary = {}

## Stable ids of customers who have bought something today, so
## customers_served counts people rather than payments.
var _served_customer_ids: Dictionary = {}


func _init(
	day: int = 1
) -> void:
	reset(day)


## Clears the per-day figures. Persistent money and stock are untouched.
func reset(
	day: int
) -> void:
	trading_day = day

	counters.clear()

	for key: StringName in COUNTER_KEYS:
		counters[String(key)] = 0.0

	sales_by_item.clear()
	income_by_item.clear()
	stock_used_by_item.clear()

	peaks = {
		"peak_occupancy": 0.0,
		"peak_waiting_customers": 0.0,
		"peak_demand_multiplier": 0.0,
	}

	service_started_at = ""
	service_ended_at = ""
	service_start_minutes = -1.0
	service_end_minutes = -1.0

	is_frozen = false
	_frozen_record.clear()
	_served_customer_ids.clear()


# -----------------------------------------------------------------------------
# Recording
# -----------------------------------------------------------------------------

## Adds to a running total.
##
## Unknown keys are accepted and created rather than dropped, so a new
## statistic is one call site rather than a change here as well - but they are
## listed in [constant COUNTER_KEYS] so the summary and the report always show
## a zero rather than omitting the row entirely.
func record(
	key: StringName,
	amount: float = 1.0
) -> void:
	var name: String = String(key)

	counters[name] = float(counters.get(name, 0.0)) + amount


## Raises a peak if [param value] beats it.
func record_peak(
	key: StringName,
	value: float
) -> void:
	var name: String = String(key)

	peaks[name] = maxf(float(peaks.get(name, 0.0)), value)


## One drink sold to one customer.
##
## The single authoritative entry point for a sale, so income, count and the
## per-item breakdown can never disagree with each other.
## One drink sold to one customer.
##
## [param customer_id] separates two things that were previously conflated:
##
## [codeblock]
## customers_served        unique people who bought at least one drink
## transactions_completed  successful sales
## drinks_sold             units moved
## [/codeblock]
##
## A customer buying three rounds is one served customer and three
## transactions. Counting them as three served made average spend read as the
## price of a single drink and the service rate look better than it was.
func record_sale(
	item_id: StringName,
	price: float,
	tip: float = 0.0,
	customer_id: StringName = &""
) -> void:
	record(&"sales_income", price)
	record(&"tips", tip)
	record(&"drinks_sold", 1.0)
	record(&"transactions_completed", 1.0)

	# Unique by stable id, so a repeat customer is not counted twice.
	if not customer_id.is_empty():
		if not _served_customer_ids.has(customer_id):
			_served_customer_ids[customer_id] = true

			record(&"customers_served", 1.0)

	var name: String = String(item_id)

	sales_by_item[name] = int(sales_by_item.get(name, 0)) + 1
	income_by_item[name] = float(income_by_item.get(name, 0.0)) + price


## Stock consumed, by item.
func record_stock_used(
	item_id: StringName,
	quantity: float = 1.0
) -> void:
	record(&"stock_used", quantity)

	var name: String = String(item_id)

	stock_used_by_item[name] = float(
		stock_used_by_item.get(name, 0.0)
	) + quantity


## A customer left without being served, with the reason where known.
##
## Reasons are separated because "we were full" and "we were too slow" call for
## completely different responses from the player, and a single
## "customers lost" figure hides which one happened.
func record_customer_lost(
	reason: StringName
) -> void:
	record(&"customers_lost")

	match reason:
		&"patience":
			record(&"customers_lost_patience")

		&"no_seating":
			record(&"customers_lost_no_seating")

		&"no_stock":
			record(&"customers_lost_no_stock")

		_:
			record(&"customers_lost_other")


func mark_service_started() -> void:
	if service_start_minutes >= 0.0:
		return

	service_started_at = WorldTime.get_clock_text()
	service_start_minutes = WorldTime.get_total_minutes_precise()


func mark_service_ended() -> void:
	if service_end_minutes >= 0.0:
		return

	service_ended_at = WorldTime.get_clock_text()
	service_end_minutes = WorldTime.get_total_minutes_precise()


# -----------------------------------------------------------------------------
# Derived figures
# -----------------------------------------------------------------------------

func get_total_income() -> float:
	return (
		float(counters.get("sales_income", 0.0))
		+ float(counters.get("tips", 0.0))
	)


func get_open_duration_minutes() -> float:
	if service_start_minutes < 0.0:
		return 0.0

	var end: float = service_end_minutes

	if end < 0.0:
		end = WorldTime.get_total_minutes_precise()

	return maxf(end - service_start_minutes, 0.0)


## Average spend per unique served customer.
func get_average_spend() -> float:
	var served: float = float(counters.get("customers_served", 0.0))

	if served <= 0.0:
		return 0.0

	return float(counters.get("sales_income", 0.0)) / served


## Average value of one transaction.
func get_average_transaction() -> float:
	var transactions: float = float(
		counters.get("transactions_completed", 0.0)
	)

	if transactions <= 0.0:
		return 0.0

	return float(counters.get("sales_income", 0.0)) / transactions


func get_average_tip() -> float:
	var served: float = float(counters.get("customers_served", 0.0))

	if served <= 0.0:
		return 0.0

	return float(counters.get("tips", 0.0)) / served


## Served as a fraction of everyone who came in and wanted serving.
func get_service_rate() -> float:
	var served: float = float(counters.get("customers_served", 0.0))
	var lost: float = float(counters.get("customers_lost", 0.0))

	var total: float = served + lost

	if total <= 0.0:
		return 0.0

	return served / total


# -----------------------------------------------------------------------------
# The record
# -----------------------------------------------------------------------------

## The current figures as a plain, node-free Dictionary.
##
## No node references anywhere, so the summary survives the customers being
## freed and the record is already save-ready.
func build_record() -> Dictionary:
	return {
		"trading_day": trading_day,
		"counters": counters.duplicate(true),
		"sales_by_item": sales_by_item.duplicate(true),
		"income_by_item": income_by_item.duplicate(true),
		"stock_used_by_item": stock_used_by_item.duplicate(true),
		"peaks": peaks.duplicate(true),
		"service_started_at": service_started_at,
		"service_ended_at": service_ended_at,
		"open_duration_minutes": get_open_duration_minutes(),
		"total_income": get_total_income(),
		"average_spend": get_average_spend(),
		"average_transaction": get_average_transaction(),
		"average_tip": get_average_tip(),
		"service_rate": get_service_rate(),
		"is_frozen": is_frozen,
	}


## Latches the current figures as the day's final record.
##
## Idempotent: calling it twice returns the first result unchanged, which is
## what stops a repeated End Day press producing a second, different summary.
func freeze() -> Dictionary:
	if is_frozen:
		return _frozen_record.duplicate(true)

	mark_service_ended()

	is_frozen = true

	_frozen_record = build_record()
	_frozen_record["is_frozen"] = true

	return _frozen_record.duplicate(true)


## The frozen record, or the live one if the day has not been finalised.
func get_record() -> Dictionary:
	if is_frozen:
		return _frozen_record.duplicate(true)

	return build_record()
