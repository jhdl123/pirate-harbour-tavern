class_name StatisticsTracker
extends Node


signal statistic_changed(
	statistic_id: StringName,
	new_value: int
)

signal daily_statistics_reset


var customers_served_total: int = 0
var customers_served_today: int = 0
var money_earned_total: int = 0
var days_operated: int = 1
var highest_active_customers: int = 0


func _ready() -> void:
	if not WorldTime.day_changed.is_connected(
		_on_world_day_changed
	):
		WorldTime.day_changed.connect(
			_on_world_day_changed
		)


func record_customer_served(
	payment_amount: int
) -> void:
	customers_served_total += 1
	customers_served_today += 1
	money_earned_total += maxi(payment_amount, 0)

	statistic_changed.emit(
		&"customers_served_total",
		customers_served_total
	)

	statistic_changed.emit(
		&"customers_served_today",
		customers_served_today
	)

	statistic_changed.emit(
		&"money_earned_total",
		money_earned_total
	)


func update_active_customer_peak(
	active_customer_count: int
) -> void:
	if active_customer_count <= highest_active_customers:
		return

	highest_active_customers = active_customer_count

	statistic_changed.emit(
		&"highest_active_customers",
		highest_active_customers
	)


func get_customers_served_total() -> int:
	return customers_served_total


func get_customers_served_today() -> int:
	return customers_served_today


func get_money_earned_total() -> int:
	return money_earned_total


func get_days_operated() -> int:
	return days_operated


func get_highest_active_customers() -> int:
	return highest_active_customers


func _on_world_day_changed(
	stamp: GameTimeStamp
) -> void:
	customers_served_today = 0
	days_operated = stamp.day

	statistic_changed.emit(
		&"customers_served_today",
		customers_served_today
	)

	statistic_changed.emit(
		&"days_operated",
		days_operated
	)

	daily_statistics_reset.emit()
