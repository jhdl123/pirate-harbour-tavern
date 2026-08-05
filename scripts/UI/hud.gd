extends CanvasLayer


@export var economy_manager: EconomyManager


@onready var money_label: Label = $MoneyLabel


## Compact daily-cycle readout, built in code so no scene edit is required.
##
## Deliberately one line that changes shape with the state rather than a
## permanent block of statistics: the player needs to know what the tavern is
## doing and how long they have, not to read a dashboard during service.
var cycle_label: Label = null


func _build_cycle_display() -> void:
	cycle_label = Label.new()
	cycle_label.name = "DailyCycleLabel"
	cycle_label.position = Vector2(16, 44)
	cycle_label.add_theme_font_size_override("font_size", 14)

	add_child(cycle_label)

	# Event-driven, plus a slow tick for the countdown. Nothing here recomputes
	# per frame.
	Tavern.operating_state_changed.connect(
		func(_p, _n, _r) -> void: _refresh_cycle_display()
	)

	WorldTime.minute_passed.connect(
		func(_stamp) -> void: _refresh_cycle_display()
	)

	_refresh_cycle_display()


func _refresh_cycle_display() -> void:
	if cycle_label == null:
		return

	var remaining: int = Tavern.get_minutes_until_next_transition()
	var day: int = Tavern.trading_day

	var text: String = ""

	match Tavern.get_state():
		TavernLifecycle.State.PREPARING:
			text = "Day %d  |  Preparation - opens in %s" % [
				day, _format_minutes(remaining)
			]

		TavernLifecycle.State.OPEN:
			text = "Day %d  |  Open - %s  |  last orders in %s" % [
				day, _describe_demand(), _format_minutes(remaining)
			]

		TavernLifecycle.State.LAST_ORDERS:
			text = "Day %d  |  Last orders - %s remaining" % [
				day, _format_minutes(remaining)
			]

		TavernLifecycle.State.CLOSING:
			text = "Day %d  |  Closing - finish remaining service" % day

		TavernLifecycle.State.CLOSED:
			text = "Day %d  |  Closed - review today's results" % day

		TavernLifecycle.State.END_OF_DAY:
			text = "Day %d complete - ready for day %d" % [day, day + 1]

		_:
			text = "Day %d  |  %s" % [day, Tavern.get_state_name()]

	cycle_label.text = "%s  |  %s" % [WorldTime.get_clock_text(), text]


## Never shows a negative countdown, which would happen for one frame on a
## transition boundary.
func _format_minutes(
	minutes: int
) -> String:
	var safe: int = maxi(minutes, 0)

	if safe >= 60:
		return "%dh %02dm" % [safe / 60, safe % 60]

	return "%d min" % safe


func _describe_demand() -> String:
	var demand: float = Modifiers.evaluate(
		ModifierTargets.CUSTOMER_ARRIVAL_RATE,
		1.0
	)

	if demand < 0.5:
		return "quiet"

	if demand < 1.0:
		return "steady"

	if demand < 1.5:
		return "busy"

	return "peak trade"


func _ready() -> void:
	if economy_manager == null:
		push_error(
			"HUD has no EconomyManager assigned."
		)
		return

	if not economy_manager.money_changed.is_connected(
		_on_money_changed
	):
		economy_manager.money_changed.connect(
			_on_money_changed
		)

	update_money_display(
		economy_manager.get_money()
	)

	_build_cycle_display()

func _on_money_changed(
	_previous_amount: int,
	current_amount: int,
	_change_amount: int
) -> void:
	update_money_display(
		current_amount
	)


func update_money_display(
	amount: int
) -> void:
	money_label.text = "£" + str(amount)
