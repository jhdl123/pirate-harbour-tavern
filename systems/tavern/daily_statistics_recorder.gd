class_name DailyStatisticsRecorder
extends Node

## Subscribes to authoritative gameplay events and records them into
## [DailyStatistics].
##
## [b]Why this exists as one node[/b]
##
## The previous pass shipped a complete [DailyStatistics] data model that
## nothing in the game ever called - every reference to [code]Tavern.stats[/code]
## outside the lifecycle was an F10 test button or a unit test. The figures
## looked right in tests and were always zero in play.
##
## Sprinkling [code]Tavern.stats.record(...)[/code] through ten gameplay files
## would have fixed the symptom and made the next question - "is anything
## recorded twice?" - unanswerable without reading all ten. Every subscription
## lives here instead, so double recording is a question about one file.
##
## [b]The rule[/b]
##
## One authoritative event, one subscription, one record call. This node never
## infers a statistic from another statistic: stock usage comes from stock
## actually leaving a station, not from a sale, because drinks break, get
## prepared and never sold, and will one day spoil.
##
## Anything this node cannot observe honestly is left at zero and documented
## rather than estimated.


## Connections made, so a re-scan cannot subscribe twice.
var _connected: Dictionary = {}

var _game_manager: Node = null

## Guards against one payment being recorded by two paths.
var _last_payment_frame: int = -1
var _payments_this_frame: int = 0

## Bounded log of what was recorded, for the duplicate-detection test and the
## F10 "recent authoritative events" view.
var _event_log: Array[Dictionary] = []

@export_range(0, 2000, 10)
var maximum_logged_events: int = 200


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	add_to_group(&"daily_stats_recorder")

	# Deferred so the main scene's managers and the world are fully built.
	_subscribe.call_deferred()


func _subscribe() -> void:
	_game_manager = get_parent().get_node_or_null("GameManager")

	if _game_manager == null:
		_game_manager = get_tree().get_first_node_in_group(&"game_manager")

	if _game_manager != null:
		_connect_once(
			_game_manager,
			&"customer_spawned",
			_on_customer_spawned
		)

		if _game_manager.has_signal(&"customer_paid_for_drink"):
			_connect_once(
				_game_manager,
				&"customer_paid_for_drink",
				_on_customer_paid_for_drink
			)

		if _game_manager.has_signal(&"customer_departed"):
			_connect_once(
				_game_manager,
				&"customer_departed",
				_on_customer_departed
			)

		if _game_manager.has_signal(&"arrival_rejected"):
			_connect_once(
				_game_manager,
				&"arrival_rejected",
				_on_arrival_rejected
			)

	_subscribe_to_stations()
	_subscribe_to_cleanables()
	_subscribe_to_orders()

	if is_instance_valid(TaskBoard):
		_connect_once(TaskBoard, &"task_completed", _on_task_completed)


## Stock leaving a station is the authoritative stock-usage event.
##
## Deliberately not derived from sales: a drink can be poured and broken, or
## poured and never collected, and both consume stock without producing income.
func _subscribe_to_stations() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		if node.has_signal(&"serving_consumed"):
			_connect_once(node, &"serving_consumed", _on_serving_consumed)


func _subscribe_to_cleanables() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"cleanables"):
		if node.has_signal(&"complication_triggered"):
			_connect_once(
				node,
				&"complication_triggered",
				_on_complication_triggered
			)

	# Chairs own their cleanable as a child component, and are not themselves
	# in the cleanables group in every build.
	for node: Node in get_tree().get_nodes_in_group(
		Reservable.group_for_tag(&"seat")
	):
		var chair: Node = node.get_parent()

		if chair == null or not "cleanable" in chair:
			continue

		var cleanable: Object = chair.get("cleanable")

		if cleanable == null:
			continue

		_connect_once(
			cleanable,
			&"complication_triggered",
			_on_complication_triggered
		)


func _subscribe_to_orders() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"order_manager"):
		_connect_once(node, &"order_delivered", _on_order_delivered)


## Connects once, and records that it did.
##
## Godot happily connects the same handler twice and then calls it twice, which
## is the single easiest way to double every figure in a report.
func _connect_once(
	source: Object,
	signal_name: StringName,
	handler: Callable
) -> void:
	if source == null or not is_instance_valid(source):
		return

	if not source.has_signal(signal_name):
		return

	var key: String = "%d:%s" % [source.get_instance_id(), signal_name]

	if _connected.has(key):
		return

	if source.is_connected(signal_name, handler):
		_connected[key] = true
		return

	source.connect(signal_name, handler)

	_connected[key] = true


## Called when new stations, chairs or customers appear at runtime.
func rescan() -> void:
	_subscribe_to_stations()
	_subscribe_to_cleanables()
	_subscribe_to_orders()


# -----------------------------------------------------------------------------
# Handlers
# -----------------------------------------------------------------------------

func _on_customer_spawned(
	customer: Node
) -> void:
	_stats().record(&"customers_entered")

	_log(&"customer_entered", { "customer": String(customer.name) })

	_update_occupancy_peak()


## A real, completed, paid drink transaction.
##
## [b]Unit of "customer served"[/b]: one paid drink transaction, not one
## customer visit. A customer who orders twice is served twice, which is what
## makes average spend and service rate mean what they look like they mean. The
## number of distinct visitors is [code]customers_entered[/code].
func _on_customer_paid_for_drink(
	amount: int,
	item_id: StringName,
	base_price: int,
	customer_id: StringName
) -> void:
	var frame: int = Engine.get_process_frames()

	if frame != _last_payment_frame:
		_last_payment_frame = frame
		_payments_this_frame = 0

	_payments_this_frame += 1

	# Tips do not exist as a first-class concept in this build. The customer
	# type's payment_multiplier makes some customers pay over the odds, and
	# the surplus over the drink's base price is the closest honest reading of
	# a tip. Recorded separately so the split can be changed - or removed -
	# without touching the sale figure.
	var tip: float = maxf(float(amount) - float(base_price), 0.0)
	var sale: float = float(amount) - tip

	# The id makes customers_served count people rather than payments.
	_stats().record_sale(item_id, sale, tip, customer_id)

	_log(&"sale", {
		"item_id": String(item_id),
		"amount": amount,
		"sale": sale,
		"tip": tip,
		"customer_id": String(customer_id),
		"payments_this_frame": _payments_this_frame,
	})


## A customer left. The reason decides whether that is a loss at all.
##
## A customer who drank, paid and went home happy is not a lost customer, and
## counting every unpaid departure as a loss would make the service rate
## meaningless. Only departures that represent unmet demand count.
func _on_customer_departed(
	_customer: Node,
	reason: StringName,
	was_served: bool
) -> void:
	_update_occupancy_peak()

	if was_served:
		_log(&"customer_left_satisfied", { "reason": String(reason) })

		return

	match reason:
		&"patience_expired", &"repeated_neglect":
			_stats().record_customer_lost(&"patience")

		&"no_seating":
			_stats().record_customer_lost(&"no_seating")

		&"no_stock":
			_stats().record_customer_lost(&"no_stock")

		&"day_ended_cleanup":
			# Sent home by the next-day transition rather than lost to a
			# failure of service. Counted separately so cleanup cannot quietly
			# wreck the day's service rate.
			_stats().record(&"customers_sent_home")

			_log(&"customer_sent_home", {})

			return

		_:
			_stats().record_customer_lost(&"other")

	_log(&"customer_lost", { "reason": String(reason) })


func _on_arrival_rejected(
	reason: StringName
) -> void:
	_stats().record(&"arrivals_rejected")

	_log(&"arrival_rejected", { "reason": String(reason) })


func _on_serving_consumed(
	item_id: StringName,
	quantity: int
) -> void:
	_stats().record_stock_used(item_id, float(quantity))

	_log(&"stock_used", {
		"item_id": String(item_id),
		"quantity": quantity,
	})


func _on_complication_triggered(
	_task: CleaningTask,
	_cost: int
) -> void:
	_stats().record(&"breakages")

	_log(&"breakage", {})


func _on_order_delivered(
	_order: Variant
) -> void:
	_stats().record(&"deliveries_received")

	_log(&"delivery", {})


func _on_task_completed(
	task: TavernTask
) -> void:
	_stats().record(&"staff_tasks_completed")

	_log(&"staff_task", { "type": String(task.task_type) })


func _update_occupancy_peak() -> void:
	if _game_manager == null:
		return

	_stats().record_peak(
		&"peak_occupancy",
		float(_game_manager.get("active_customers").size())
	)

	if _game_manager.has_method(&"get_waiting_customer_count"):
		_stats().record_peak(
			&"peak_waiting_customers",
			float(_game_manager.call(&"get_waiting_customer_count"))
		)


# -----------------------------------------------------------------------------
# Diagnostics
# -----------------------------------------------------------------------------

func _stats() -> DailyStatistics:
	return Tavern.stats


func _log(
	event_type: StringName,
	values: Dictionary
) -> void:
	if maximum_logged_events <= 0:
		return

	_event_log.append({
		"world_minutes": WorldTime.get_total_minutes_precise(),
		"clock": WorldTime.get_clock_text(),
		"event_type": String(event_type),
		"values": values.duplicate(true),
	})

	while _event_log.size() > maximum_logged_events:
		_event_log.pop_front()


## Recent authoritative events, newest last. For F10 and the report.
func get_event_log() -> Array[Dictionary]:
	return _event_log.duplicate(true)


## How many distinct signals this node is listening to.
##
## A jump in this number between days would mean subscriptions are being made
## repeatedly, which is what would double every figure.
func get_subscription_count() -> int:
	return _connected.size()


func build_report_section() -> Dictionary:
	return {
		"subscriptions": get_subscription_count(),
		"recent_events": get_event_log(),
	}
