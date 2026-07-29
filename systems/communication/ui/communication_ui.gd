class_name CommunicationUI
extends CanvasLayer

## The screen side of the communication framework.
##
## Four layers, one service. Every one of them reads [CommMessage] objects out
## of [code]Comms[/code] and writes nothing back except acknowledgement and
## choices, so gameplay never depends on the UI existing. Delete this node and
## the tavern still tracks its alerts correctly; it just stops telling you.
##
## [codeblock]
## Toasts     top centre    brief, self-dismissing, capped so they cannot
##                          bury each other
## Alerts     right edge    persistent conditions, worst first, with
##                          acknowledge buttons and automatic resolution
## Speaker    bottom centre attributed messages, with choice buttons
## History    behind Log    everything that has happened, resolved included
## [/codeblock]
##
## Built in code rather than as a hand-wired scene for the same reason the
## developer panel is: the layout is entirely derived from the config resource,
## and a [code].tscn[/code] full of empty containers would be a second place to
## keep the same numbers.


@export var config: CommunicationConfig


var _toast_box: VBoxContainer
var _alert_panel: PanelContainer
var _alert_box: VBoxContainer
var _alert_empty_label: Label
var _speaker_panel: PanelContainer
var _speaker_box: VBoxContainer
var _history_panel: PanelContainer
var _history_box: VBoxContainer

## message_id -> Control, for the alert rows currently on screen.
var _alert_rows: Dictionary = {}

## Toasts waiting for a free slot.
var _queued_toasts: Array[CommMessage] = []
var _visible_toasts: int = 0

var _speaker_message: CommMessage = null
var _speaker_remaining: float = 0.0

var _is_history_visible: bool = false


func _ready() -> void:
	layer = 60

	# Messages must still be readable while the simulation is paused - a
	# blocking conversation is exactly when the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	if config == null:
		config = Comms.config

	_build()
	_connect_service()
	_refresh_alerts()


func _connect_service() -> void:
	if not Comms.message_posted.is_connected(_on_message_posted):
		Comms.message_posted.connect(_on_message_posted)

	if not Comms.message_updated.is_connected(_on_message_updated):
		Comms.message_updated.connect(_on_message_updated)

	if not Comms.message_resolved.is_connected(_on_message_resolved):
		Comms.message_resolved.connect(_on_message_resolved)


# -----------------------------------------------------------------------------
# Building
# -----------------------------------------------------------------------------

func _build() -> void:
	_build_toasts()
	_build_alerts()
	_build_speaker()
	_build_history()


func _build_toasts() -> void:
	var anchor: Control = Control.new()

	anchor.name = "Toasts"
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.set_anchors_preset(Control.PRESET_TOP_WIDE)
	anchor.offset_top = 16.0
	anchor.offset_bottom = 16.0

	add_child(anchor)

	_toast_box = VBoxContainer.new()
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_toast_box.add_theme_constant_override("separation", 6)
	_toast_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast_box.offset_left = 430.0
	_toast_box.offset_right = -430.0

	anchor.add_child(_toast_box)


func _build_alerts() -> void:
	_alert_panel = PanelContainer.new()
	_alert_panel.name = "Alerts"
	_alert_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_alert_panel.offset_left = -336.0
	_alert_panel.offset_right = -16.0
	_alert_panel.offset_top = 330.0
	_alert_panel.offset_bottom = 330.0
	_alert_panel.add_theme_stylebox_override("panel", _make_panel_style())

	add_child(_alert_panel)

	var margin: MarginContainer = _make_margin(10)

	_alert_panel.add_child(margin)

	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)

	margin.add_child(rows)

	var header: HBoxContainer = HBoxContainer.new()

	rows.add_child(header)

	var title: Label = Label.new()
	title.text = "TAVERN ALERTS"
	title.add_theme_font_size_override("font_size", 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	header.add_child(title)

	var log_button: Button = Button.new()
	log_button.text = "Log"
	log_button.tooltip_text = "Show recent notifications, alerts and messages"
	log_button.pressed.connect(_toggle_history)

	header.add_child(log_button)

	_alert_box = VBoxContainer.new()
	_alert_box.add_theme_constant_override("separation", 4)

	rows.add_child(_alert_box)

	_alert_empty_label = Label.new()
	_alert_empty_label.text = "Nothing needs your attention."
	_alert_empty_label.add_theme_font_size_override("font_size", 11)
	_alert_empty_label.modulate = Color(1.0, 1.0, 1.0, 0.55)

	rows.add_child(_alert_empty_label)


func _build_speaker() -> void:
	_speaker_panel = PanelContainer.new()
	_speaker_panel.name = "Speaker"
	_speaker_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_speaker_panel.offset_left = 380.0
	_speaker_panel.offset_right = -380.0
	_speaker_panel.offset_top = -150.0
	_speaker_panel.offset_bottom = -24.0
	_speaker_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_speaker_panel.visible = false

	add_child(_speaker_panel)

	var margin: MarginContainer = _make_margin(12)

	_speaker_panel.add_child(margin)

	_speaker_box = VBoxContainer.new()
	_speaker_box.add_theme_constant_override("separation", 6)

	margin.add_child(_speaker_box)


func _build_history() -> void:
	_history_panel = PanelContainer.new()
	_history_panel.name = "History"
	_history_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_history_panel.offset_left = -336.0
	_history_panel.offset_right = -16.0
	_history_panel.offset_top = 96.0
	_history_panel.offset_bottom = 320.0
	_history_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_history_panel.visible = false

	add_child(_history_panel)

	var margin: MarginContainer = _make_margin(10)

	_history_panel.add_child(margin)

	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)

	margin.add_child(rows)

	var title: Label = Label.new()
	title.text = "MESSAGE LOG"
	title.add_theme_font_size_override("font_size", 13)

	rows.add_child(title)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 180.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	rows.add_child(scroll)

	_history_box = VBoxContainer.new()
	_history_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_box.add_theme_constant_override("separation", 2)

	scroll.add_child(_history_box)


func _make_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()

	style.bg_color = Color(0.08, 0.065, 0.05, 0.90)
	style.border_color = Color(0.55, 0.44, 0.28, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)

	return style


func _make_margin(
	amount: int
) -> MarginContainer:
	var margin: MarginContainer = MarginContainer.new()

	for side: String in [
		"margin_left",
		"margin_right",
		"margin_top",
		"margin_bottom",
	]:
		margin.add_theme_constant_override(side, amount)

	return margin


# -----------------------------------------------------------------------------
# Service events
# -----------------------------------------------------------------------------

func _on_message_posted(
	message: CommMessage
) -> void:
	match message.type:
		CommMessage.Type.ALERT:
			_refresh_alerts()

		CommMessage.Type.SPEAKER:
			_show_speaker(message)

		_:
			_enqueue_toast(message)

	_refresh_history()


func _on_message_updated(
	message: CommMessage
) -> void:
	if message.type == CommMessage.Type.ALERT:
		_refresh_alerts()

	if message == _speaker_message:
		_show_speaker(message)


func _on_message_resolved(
	message: CommMessage
) -> void:
	if message.type == CommMessage.Type.ALERT:
		_refresh_alerts()

	if message == _speaker_message:
		_hide_speaker()

	_refresh_history()


# -----------------------------------------------------------------------------
# Toasts
# -----------------------------------------------------------------------------

func _enqueue_toast(
	message: CommMessage
) -> void:
	if _visible_toasts >= config.maximum_visible_toasts:
		_queued_toasts.append(message)

		while _queued_toasts.size() > config.maximum_queued_toasts:
			_queued_toasts.pop_front()

		return

	_show_toast(message)


func _show_toast(
	message: CommMessage
) -> void:
	var panel: PanelContainer = PanelContainer.new()

	var style: StyleBoxFlat = _make_panel_style()

	style.border_color = config.get_severity_colour(message.severity)
	style.set_border_width_all(2)

	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var margin: MarginContainer = _make_margin(8)

	panel.add_child(margin)

	var label: Label = Label.new()
	label.text = _get_toast_text(message)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override(
		"font_color",
		config.get_severity_colour(message.severity)
	)

	margin.add_child(label)

	_toast_box.add_child(panel)

	_visible_toasts += 1

	var seconds: float = maxf(
		message.auto_dismiss_seconds,
		config.default_toast_seconds
	)

	# Real seconds via a SceneTree timer that ignores pause: the toast is
	# interface, not simulation, and freezing it mid-read helps nobody.
	var timer: SceneTreeTimer = get_tree().create_timer(
		seconds,
		true,
		false,
		true
	)

	timer.timeout.connect(_on_toast_expired.bind(panel))


func _get_toast_text(
	message: CommMessage
) -> String:
	if message.title.is_empty():
		return message.body

	return "%s - %s" % [message.title, message.body]


func _on_toast_expired(
	panel: Control
) -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()

	_visible_toasts = maxi(_visible_toasts - 1, 0)

	if _queued_toasts.is_empty():
		return

	var next: CommMessage = _queued_toasts.pop_front()

	# A message that resolved while it was queued should never surface.
	if next != null and next.is_active():
		_show_toast(next)


# -----------------------------------------------------------------------------
# Alerts
# -----------------------------------------------------------------------------

func _refresh_alerts() -> void:
	for child: Node in _alert_box.get_children():
		child.queue_free()

	_alert_rows.clear()

	var alerts: Array[CommMessage] = Comms.get_active_alerts()

	_alert_empty_label.visible = alerts.is_empty()

	var shown: int = 0

	for message: CommMessage in alerts:
		if shown >= config.maximum_visible_alerts:
			var more: Label = Label.new()

			more.text = "+ %d more" % (alerts.size() - shown)
			more.add_theme_font_size_override("font_size", 11)
			more.modulate = Color(1.0, 1.0, 1.0, 0.6)

			_alert_box.add_child(more)
			break

		var row: Control = _build_alert_row(message)

		_alert_box.add_child(row)
		_alert_rows[message.message_id] = row

		shown += 1


func _build_alert_row(
	message: CommMessage
) -> Control:
	var row: VBoxContainer = VBoxContainer.new()

	row.add_theme_constant_override("separation", 2)

	var header: HBoxContainer = HBoxContainer.new()

	row.add_child(header)

	var title: Label = Label.new()

	title.text = message.title
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override(
		"font_color",
		config.get_severity_colour(message.severity)
	)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	header.add_child(title)

	if not message.is_acknowledged:
		var acknowledge: Button = Button.new()

		acknowledge.text = "OK"
		acknowledge.tooltip_text = (
			"Acknowledge. The alert stays until the condition clears."
		)

		acknowledge.pressed.connect(
			func() -> void:
				Comms.acknowledge(message)
				_refresh_alerts()
		)

		header.add_child(acknowledge)
	else:
		var ticked: Label = Label.new()

		ticked.text = "seen"
		ticked.add_theme_font_size_override("font_size", 10)
		ticked.modulate = Color(1.0, 1.0, 1.0, 0.45)

		header.add_child(ticked)

	var body: Label = Label.new()

	body.text = _get_alert_body(message)
	body.add_theme_font_size_override("font_size", 11)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.modulate = Color(1.0, 1.0, 1.0, 0.82)

	row.add_child(body)

	return row


func _get_alert_body(
	message: CommMessage
) -> String:
	var lines: Array[String] = []

	if not message.speaker_name.is_empty():
		lines.append("%s: \"%s\"" % [message.speaker_name, message.body])
	elif not message.body.is_empty():
		lines.append(message.body)

	for detail: String in message.details:
		lines.append(detail)

	return "\n".join(lines)


# -----------------------------------------------------------------------------
# Speaker
# -----------------------------------------------------------------------------

func _show_speaker(
	message: CommMessage
) -> void:
	_speaker_message = message

	for child: Node in _speaker_box.get_children():
		child.queue_free()

	var header: HBoxContainer = HBoxContainer.new()

	_speaker_box.add_child(header)

	if message.portrait != null:
		var portrait: TextureRect = TextureRect.new()

		portrait.texture = message.portrait
		portrait.custom_minimum_size = Vector2(32.0, 32.0)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		header.add_child(portrait)

	var speaker_label: Label = Label.new()

	speaker_label.text = (
		message.speaker_name if not message.speaker_name.is_empty()
		else message.title
	)

	speaker_label.add_theme_font_size_override("font_size", 14)
	speaker_label.add_theme_color_override(
		"font_color",
		config.get_severity_colour(message.severity)
	)
	speaker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	header.add_child(speaker_label)

	var body: Label = Label.new()

	body.text = message.get_full_text()
	body.add_theme_font_size_override("font_size", 12)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_speaker_box.add_child(body)

	if not message.choices.is_empty():
		var choices: HBoxContainer = HBoxContainer.new()

		choices.add_theme_constant_override("separation", 8)
		choices.alignment = BoxContainer.ALIGNMENT_END

		_speaker_box.add_child(choices)

		for choice: Dictionary in message.choices:
			var button: Button = Button.new()

			button.text = String(choice.get("label", "..."))

			button.pressed.connect(
				func() -> void:
					Comms.select_choice(
						message,
						StringName(choice.get("id", &"dismiss"))
					)
			)

			choices.add_child(button)

	_speaker_panel.visible = true

	# A message offering choices waits for one. Anything else times out, so a
	# passing remark never sits on screen forever.
	_speaker_remaining = (
		0.0 if not message.choices.is_empty()
		else maxf(message.auto_dismiss_seconds, 1.0)
	)

	set_process(_speaker_remaining > 0.0)

	if (
		message.pauses_game
		or (
			not message.choices.is_empty()
			and config.speaker_choices_pause_game
		)
	):
		Simulation.pause()


func _hide_speaker() -> void:
	_speaker_message = null
	_speaker_panel.visible = false
	_speaker_remaining = 0.0

	set_process(false)


func _process(
	delta: float
) -> void:
	if _speaker_message == null or _speaker_remaining <= 0.0:
		return

	_speaker_remaining -= delta

	if _speaker_remaining > 0.0:
		return

	Comms.resolve(_speaker_message, &"expired")


# -----------------------------------------------------------------------------
# History
# -----------------------------------------------------------------------------

func _toggle_history() -> void:
	_is_history_visible = not _is_history_visible

	_history_panel.visible = _is_history_visible

	if _is_history_visible:
		_refresh_history()


func _refresh_history() -> void:
	if not _is_history_visible or _history_box == null:
		return

	for child: Node in _history_box.get_children():
		child.queue_free()

	var entries: Array[CommMessage] = Comms.get_history()

	entries.append_array(Comms.get_active_messages())

	entries.sort_custom(
		func(a: CommMessage, b: CommMessage) -> bool:
			return a.created_minutes > b.created_minutes
	)

	if entries.is_empty():
		var empty: Label = Label.new()

		empty.text = "Nothing yet."
		empty.add_theme_font_size_override("font_size", 11)
		empty.modulate = Color(1.0, 1.0, 1.0, 0.5)

		_history_box.add_child(empty)
		return

	for message: CommMessage in entries:
		var label: Label = Label.new()

		label.text = "[%s] %s%s%s" % [
			message.get_severity_name().substr(0, 1),
			(
				"" if message.speaker_name.is_empty()
				else message.speaker_name + ": "
			),
			(
				message.body if message.title.is_empty()
				else "%s - %s" % [message.title, message.body]
			),
			(" (resolved)" if message.is_resolved else ""),
		]

		label.add_theme_font_size_override("font_size", 10)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		label.modulate = (
			Color(1.0, 1.0, 1.0, 0.5) if message.is_resolved
			else Color(1.0, 1.0, 1.0, 0.9)
		)

		_history_box.add_child(label)


## Opens or closes the log from outside, for the developer panel.
## True when the message log panel is on screen.
func is_history_visible() -> bool:
	return _is_history_visible


## Shows or hides the message log, and returns the state it settled on.
##
## Returning the state means a caller that toggles - the F10 panel does - never
## has to guess what it just did.
func set_history_visible(
	visible_state: bool
) -> bool:
	_is_history_visible = visible_state
	_history_panel.visible = visible_state

	if visible_state:
		_refresh_history()

	return _is_history_visible
