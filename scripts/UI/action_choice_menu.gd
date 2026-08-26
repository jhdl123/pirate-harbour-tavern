class_name ActionChoiceMenu
extends InteractionMenuView

## Generic panel listing every action a multi-action interactable currently
## offers (DECISIONS.md §28). Opened by [InteractionSelector] through
## [code]InteractionMenu[/code] exactly like any other context-specific menu -
## it knows nothing about what kind of object it is describing beyond
## [InteractionAction]'s own fields.


var _list: VBoxContainer = null


func _ready() -> void:
	_build_ui()


func setup(context: Dictionary) -> void:
	super.setup(context)

	var title: String = String(context.get("title", "Choose an action"))
	var actions: Array = context.get("actions", [])

	_populate(title, actions)


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var shade := ColorRect.new()
	shade.color = UITheme.COLOR_DIM_OVERLAY
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(_on_shade_input)

	add_child(shade)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)

	centre.add_child(panel)

	var margin := MarginContainer.new()

	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)

	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)

	margin.add_child(rows)

	var title_label := Label.new()
	title_label.name = "TitleLabel"
	title_label.theme_type_variation = &"HeadingLabel"

	rows.add_child(title_label)
	rows.add_child(HSeparator.new())

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)

	rows.add_child(_list)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void: request_close())

	rows.add_child(cancel)


func _populate(
	title: String,
	actions: Array
) -> void:
	if _list == null:
		return

	var title_label: Label = _find_title_label()

	if title_label != null:
		title_label.text = title

	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	for action_variant: Variant in actions:
		var action: InteractionAction = action_variant as InteractionAction

		if action == null:
			continue

		_list.add_child(_build_action_button(action))


func _find_title_label() -> Label:
	var rows: Node = _list.get_parent()

	if rows == null:
		return null

	for child: Node in rows.get_children():
		if child.name == "TitleLabel":
			return child as Label

	return null


func _build_action_button(
	action: InteractionAction
) -> Button:
	var button := Button.new()
	button.text = action.get_label()
	button.disabled = not action.is_available
	button.custom_minimum_size = Vector2(0, 36)

	if not action.is_available and not action.unavailable_reason.is_empty():
		button.tooltip_text = action.unavailable_reason

	button.pressed.connect(
		func() -> void:
			request_close({
				"action_id": action.id,
				"action_data": action.data,
			})
	)

	return button


func _on_shade_input(
	event: InputEvent
) -> void:
	if event is InputEventMouseButton and event.pressed:
		request_close()
