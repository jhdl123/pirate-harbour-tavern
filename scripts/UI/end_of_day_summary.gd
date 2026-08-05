class_name EndOfDaySummary
extends CanvasLayer

## The player-facing end-of-day review.
##
## [b]Why this exists[/b]
##
## [signal TavernLifecycle.summary_available] had no listeners at all in the
## previous build, and [method TavernLifecycle.end_day] was called only from
## the F10 panel. The frozen record was complete and correct and nothing ever
## showed it to anybody. This is the listener.
##
## [b]It reads the frozen record only[/b]
##
## Every figure comes from [method TavernLifecycle.get_frozen_summary], taken
## once when the screen opens. Live counters keep running behind it - the staff
## are still finishing up - and the screen must not move while it is being
## read.
##
## Built entirely in code so no scene file has to be edited by hand.


## The player pressed Start Next Day.
signal next_day_requested


const PANEL_SIZE: Vector2 = Vector2(760, 560)


var _root: Control = null
var _content: VBoxContainer = null
var _continue_button: Button = null
var _next_day_button: Button = null

## Guards against a double-click starting two days.
var _action_in_flight: bool = false

var _is_open: bool = false


func _ready() -> void:
	# Must work while the simulation is paused, since opening pauses it.
	process_mode = Node.PROCESS_MODE_ALWAYS

	layer = 90

	_build()

	Tavern.summary_available.connect(_on_summary_available)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false

	add_child(_root)

	# A dimmer that also swallows clicks, so the tavern cannot be played
	# behind the summary.
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP

	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.pivot_offset = PANEL_SIZE * 0.5
	panel.position = -PANEL_SIZE * 0.5

	_root.add_child(panel)

	var margin := MarginContainer.new()

	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)

	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)

	margin.add_child(column)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 430)

	column.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 4)

	scroll.add_child(_content)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)

	column.add_child(buttons)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.tooltip_text = (
		"Acknowledge the day's results. You can reopen this from the control bar."
	)
	_continue_button.pressed.connect(_on_continue_pressed)

	buttons.add_child(_continue_button)

	_next_day_button = Button.new()
	_next_day_button.text = "Start Next Day"
	_next_day_button.pressed.connect(_on_next_day_pressed)

	buttons.add_child(_next_day_button)


# -----------------------------------------------------------------------------
# Opening and closing
# -----------------------------------------------------------------------------

func _on_summary_available(
	_day: int,
	_summary: Dictionary
) -> void:
	open_summary()


## Shows the frozen record. Safe to call repeatedly.
##
## There is one screen, reused. Opening it twice refreshes the content rather
## than producing a second instance stacked on the first.
func open_summary() -> bool:
	var summary: Dictionary = Tavern.get_frozen_summary()

	if summary.is_empty():
		return false

	_populate(summary)

	if not _is_open:
		_is_open = true
		_root.visible = true

		Simulation.push_state(SimulationState.State.PAUSED)

	_action_in_flight = false

	_refresh_buttons()

	_next_day_button.grab_focus()

	return true


func close_summary() -> void:
	if not _is_open:
		return

	_is_open = false
	_root.visible = false

	Simulation.pop_state()


func is_open() -> bool:
	return _is_open


func _refresh_buttons() -> void:
	var acknowledged: bool = (
		Tavern.get_state() == TavernLifecycle.State.READY_FOR_NEXT_DAY
	)

	_continue_button.disabled = acknowledged or _action_in_flight

	_next_day_button.disabled = _action_in_flight

	_next_day_button.tooltip_text = (
		"Begin the next trading day."
		if acknowledged
		else "Begins the next day. Pressing Continue first is optional."
	)


func _on_continue_pressed() -> void:
	if _action_in_flight:
		return

	Tavern.acknowledge_summary()

	_refresh_buttons()


func _on_next_day_pressed() -> void:
	# The guard that stops a rapid double-click advancing two days. The
	# lifecycle refuses the second call as well, so this is belt and braces -
	# but the button should not look like it worked twice either.
	if _action_in_flight:
		return

	_action_in_flight = true

	_refresh_buttons()

	close_summary()

	next_day_requested.emit()

	Tavern.advance_to_next_day()

	_action_in_flight = false


# -----------------------------------------------------------------------------
# Content
# -----------------------------------------------------------------------------

func _populate(
	summary: Dictionary
) -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	var stats: Dictionary = summary.get("statistics", {})
	var counters: Dictionary = stats.get("counters", {})
	var peaks: Dictionary = stats.get("peaks", {})

	_heading("DAY %d COMPLETE" % int(summary.get("trading_day", 0)), 26)

	_line("Service ran %s to %s (%.0f minutes)" % [
		stats.get("service_started_at", "?"),
		stats.get("service_ended_at", "?"),
		stats.get("open_duration_minutes", 0.0),
	])

	_heading("FINANCIAL")
	_stat("Sales income", counters.get("sales_income", 0.0))
	_stat("Tips", counters.get("tips", 0.0))
	_stat("Total income", stats.get("total_income", 0.0))

	_heading("CUSTOMERS")
	_stat("Customers entered", counters.get("customers_entered", 0.0))
	_stat("Customers served (unique)", counters.get("customers_served", 0.0))
	_stat("Transactions", counters.get("transactions_completed", 0.0))
	_stat("Customers lost", counters.get("customers_lost", 0.0))

	# Only show reasons that actually happened, so the panel does not become a
	# wall of zeroes.
	for reason: String in [
		"customers_lost_patience",
		"customers_lost_no_seating",
		"customers_lost_no_stock",
		"customers_lost_other",
	]:
		var value: float = float(counters.get(reason, 0.0))

		if value > 0.0:
			_stat("   %s" % reason.replace("customers_lost_", "").capitalize(), value)

	if float(counters.get("customers_sent_home", 0.0)) > 0.0:
		_stat(
			"Sent home at close (not lost)",
			counters.get("customers_sent_home", 0.0)
		)

	_stat("Service success rate", stats.get("service_rate", 0.0) * 100.0, "%")
	_stat("Average spend per customer", stats.get("average_spend", 0.0))
	_stat("Average per transaction", stats.get("average_transaction", 0.0))
	_stat("Average tip", stats.get("average_tip", 0.0))

	_heading("OPERATIONS")
	_stat("Drinks sold", counters.get("drinks_sold", 0.0))

	_sub_list("Sales by item", stats.get("sales_by_item", {}))
	_sub_list("Stock used by item", stats.get("stock_used_by_item", {}))

	_stat("Breakages", counters.get("breakages", 0.0))
	_stat("Deliveries received", counters.get("deliveries_received", 0.0))
	_stat("Staff tasks completed", counters.get("staff_tasks_completed", 0.0))
	_stat("Peak occupancy", peaks.get("peak_occupancy", 0.0))
	_stat("Peak waiting customers", peaks.get("peak_waiting_customers", 0.0))
	_stat("Peak demand", peaks.get("peak_demand_multiplier", 0.0))
	_stat("Arrivals turned away", counters.get("arrivals_rejected", 0.0))

	_heading("DAY CONTEXT")

	var schedule: Dictionary = summary.get("schedule", {})

	if not schedule.is_empty():
		_line("Opening %s, last orders %s, closing %s" % [
			_clock(schedule.get("opening", 0)),
			_clock(schedule.get("last_orders", 0)),
			_clock(schedule.get("closing", 0)),
		])

	var modifiers: Array = summary.get("active_modifiers", [])

	if modifiers.is_empty():
		_line("No temporary modifiers were active.")
	else:
		for entry: Variant in modifiers:
			_line("   %s" % str(entry))

	var cleanup: Dictionary = summary.get("cleanup", {})

	if not cleanup.is_empty():
		_line("Cleanup: %s" % str(cleanup))


func _clock(
	minutes: Variant
) -> String:
	var total: int = int(minutes)

	return "%02d:%02d" % [total / 60, total % 60]


func _heading(
	text: String,
	size: int = 18
) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)

	_content.add_child(spacer)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)

	_content.add_child(label)


func _line(
	text: String
) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_content.add_child(label)


func _stat(
	label_text: String,
	value: Variant,
	suffix: String = ""
) -> void:
	var row := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	row.add_child(name_label)

	var value_label := Label.new()

	var number: float = float(value)

	value_label.text = (
		"%d%s" % [int(number), suffix]
		if is_equal_approx(number, roundf(number))
		else "%.1f%s" % [number, suffix]
	)

	row.add_child(value_label)

	_content.add_child(row)


func _sub_list(
	title: String,
	values: Dictionary
) -> void:
	if values.is_empty():
		return

	_line(title)

	for key: Variant in values.keys():
		_stat("   %s" % str(key), values[key])
