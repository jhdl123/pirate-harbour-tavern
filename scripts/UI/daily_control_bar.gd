class_name DailyControlBar
extends CanvasLayer

## The player's controls for the trading day.
##
## Before this existed, [method TavernLifecycle.end_day] and
## [method TavernLifecycle.advance_to_next_day] were reachable only from the
## F10 developer panel, which meant the daily loop was not a gameplay feature
## at all - it was a debug facility. This bar is what makes it playable.
##
## Also the single unified day/time/money readout (`DECISIONS.md` §43): the
## HUD and a standalone clock label used to show overlapping, slightly
## inconsistent versions of the same information in three places at once.
## This bar is the one place that owns it now.
##
## [b]It calls public APIs only.[/b] No button here writes to a lifecycle
## variable; each one asks the lifecycle to do something and then re-reads the
## state, so the bar can never disagree with the authority.
##
## Built in code so no scene file has to be hand-edited.


@export var economy_manager: EconomyManager


const BUTTON_SPECS: Array[Dictionary] = [
	{ "id": &"debug", "text": "F10 / Debug" },
	{ "id": &"open", "text": "Open Tavern" },
	{ "id": &"last_orders", "text": "Last Orders" },
	{ "id": &"close", "text": "Close Tavern" },
	{ "id": &"end_day", "text": "End Day" },
	{ "id": &"summary", "text": "View Summary" },
	{ "id": &"next_day", "text": "Start Next Day" },
]


var _panel: PanelContainer = null
var _status_label: Label = null
var _buttons: Dictionary = {}

## Set while an action is running, so a double-click cannot fire twice.
var _action_in_flight: bool = false

var _summary_screen: EndOfDaySummary = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	layer = 50

	_build()

	Tavern.operating_state_changed.connect(_on_state_changed)

	WorldTime.minute_passed.connect(
		func(_stamp: GameTimeStamp) -> void: _refresh_status()
	)

	if economy_manager != null:
		economy_manager.money_changed.connect(
			func(_p, _c, _d) -> void: _refresh_status()
		)

	_locate_summary_screen.call_deferred()

	_refresh()


func _locate_summary_screen() -> void:
	var root: Node = get_parent()

	for child: Node in root.get_children():
		var screen: EndOfDaySummary = child as EndOfDaySummary

		if screen != null:
			_summary_screen = screen
			return


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.offset_top = 0.0
	_panel.offset_bottom = 44.0

	add_child(_panel)

	var margin := MarginContainer.new()

	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 8)

	_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	margin.add_child(row)

	_status_label = Label.new()
	_status_label.theme_type_variation = &"HeadingLabel"
	_status_label.custom_minimum_size = Vector2(420, 0)
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	row.add_child(_status_label)

	for spec: Dictionary in BUTTON_SPECS:
		var button := Button.new()
		button.text = String(spec["text"])

		var id: StringName = spec["id"]

		button.pressed.connect(func() -> void: _on_pressed(id))

		row.add_child(button)

		_buttons[id] = button


# -----------------------------------------------------------------------------
# Actions
# -----------------------------------------------------------------------------

func _on_pressed(
	id: StringName
) -> void:
	# A disabled button should never act even if something contrives to emit
	# its signal.
	var button: Button = _buttons.get(id) as Button

	if button != null and button.disabled:
		return

	if _action_in_flight:
		return

	_action_in_flight = true

	match id:
		&"debug":
			_toggle_debug_panel()

		&"open":
			Tavern.open_early()

		&"last_orders":
			Tavern.begin_last_orders_early()

		&"close":
			Tavern.close_early()

		&"end_day":
			# The summary screen opens itself in response to
			# summary_available, so nothing here has to know it exists.
			Tavern.end_day()

		&"summary":
			if _summary_screen != null:
				_summary_screen.open_summary()

		&"next_day":
			if _summary_screen != null and _summary_screen.is_open():
				_summary_screen.close_summary()

			Tavern.advance_to_next_day()

	_action_in_flight = false

	_refresh()


func _toggle_debug_panel() -> void:
	var panel: Node = get_tree().get_first_node_in_group(&"dev_panel")

	if panel == null:
		for child: Node in get_parent().get_children():
			if child.get_script() == null:
				continue

			if String(child.get_script().resource_path).ends_with(
				"stock_dev_panel.gd"
			):
				panel = child
				break

	if panel == null:
		return

	if panel.has_method(&"toggle_panel"):
		panel.call(&"toggle_panel")
		return

	if "visible" in panel:
		panel.set("visible", not bool(panel.get("visible")))


# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

func _on_state_changed(
	_previous: TavernLifecycle.State,
	_new_state: TavernLifecycle.State,
	_reason: StringName
) -> void:
	_refresh()


func _refresh() -> void:
	_refresh_status()
	_refresh_buttons()


func _refresh_status() -> void:
	if _status_label == null:
		return

	var money_text: String = (
		"£%d" % economy_manager.get_money()
		if economy_manager != null
		else "£—"
	)

	_status_label.text = "Day %d   %s   %s   %s" % [
		Tavern.trading_day,
		WorldTime.get_clock_text(),
		money_text,
		get_state_text(),
	]


## Player-facing wording for a lifecycle state.
##
## Raw enum names must never reach the screen: "READY_FOR_NEXT_DAY" is a
## programming detail, not something to show somebody running a tavern.
static func get_state_text() -> String:
	match Tavern.get_state():
		TavernLifecycle.State.PREPARING:
			return "Preparing to open"

		TavernLifecycle.State.OPEN:
			return "Open for business"

		TavernLifecycle.State.LAST_ORDERS:
			return "Last orders"

		TavernLifecycle.State.CLOSING:
			return "Closing"

		TavernLifecycle.State.CLOSED:
			return "Closed - end the day when ready"

		TavernLifecycle.State.END_OF_DAY:
			return "Day complete - review the results"

		TavernLifecycle.State.READY_FOR_NEXT_DAY:
			return "Day complete - start the next day when ready"

	return "Unknown"


## Enables each button for the current state, with a reason when disabled.
##
## The tooltip on a disabled button is the point: a control that is greyed out
## with no explanation is indistinguishable from one that is broken.
func _refresh_buttons() -> void:
	var state: TavernLifecycle.State = Tavern.get_state()

	_set_button(
		&"open",
		state == TavernLifecycle.State.PREPARING,
		"The tavern is already open or the day has ended."
	)

	_set_button(
		&"last_orders",
		state == TavernLifecycle.State.OPEN,
		"Last orders can only be called while the tavern is open."
	)

	_set_button(
		&"close",
		(
			state == TavernLifecycle.State.OPEN
			or state == TavernLifecycle.State.LAST_ORDERS
			or state == TavernLifecycle.State.CLOSING
		),
		"The tavern is not currently trading."
	)

	var can_end: bool = Tavern.can_end_day()

	var end_reason: String = "The tavern must be closed before ending the day."

	var blockers: Array[String] = Tavern.get_next_day_blockers()

	if not blockers.is_empty():
		end_reason = ", ".join(blockers)

	_set_button(&"end_day", can_end, end_reason)

	var has_summary: bool = not Tavern.get_frozen_summary().is_empty()

	_set_button(
		&"summary",
		has_summary,
		"There is no completed day to review yet."
	)

	_set_button(
		&"next_day",
		Tavern.can_start_next_day(),
		(
			"Review the day's summary first."
			if has_summary
			else "End the day first."
		)
	)

	var debug_button: Button = _buttons.get(&"debug") as Button

	if debug_button != null:
		debug_button.disabled = false
		debug_button.tooltip_text = "Open the developer panel (F10)."


func _set_button(
	id: StringName,
	enabled: bool,
	disabled_reason: String
) -> void:
	var button: Button = _buttons.get(id) as Button

	if button == null:
		return

	button.disabled = not enabled

	button.tooltip_text = "" if enabled else disabled_reason


## Whether a button is currently enabled. For tests.
func is_button_enabled(
	id: StringName
) -> bool:
	var button: Button = _buttons.get(id) as Button

	return button != null and not button.disabled


func set_bar_visible(
	is_visible: bool
) -> void:
	_panel.visible = is_visible
