class_name CustomerDossierUI
extends CanvasLayer

## The player-facing customer dossier (DECISIONS.md §34/§36/§37).
##
## Renders only a [CustomerDossierData] snapshot - see that class for the
## architecture rule. Instantiated lazily on first use, the same way the
## developer [CustomerInspectorUI] is, so there is exactly one dossier
## instance shared by every entry point (`docs/DECISIONS_UI_UX_APPEND.md`
## §42: in-world Inspect and the future office ledger both open this same
## class).
##
## Opening pauses the simulation; closing (Esc, the Close button, or the
## dimmed backdrop) resumes it - the same push/pop idiom
## [code]BarManagementMenu[/code] already uses, so this cannot disagree with
## another open modal about who gets to un-pause.


const PANEL_SIZE: Vector2 = Vector2(620, 460)
const PORTRAIT_SIZE: Vector2 = Vector2(160, 160)


var _screen: Control = null
var _name_label: Label = null
var _type_label: Label = null
var _status_label: Label = null
var _description_label: Label = null
var _portrait: TextureRect = null
var _relationship_section: Control = null
var _relationship_label: Label = null
var _history_section: Control = null
var _history_list: VBoxContainer = null

var _is_open: bool = false
var _paused_by_this_screen: bool = false
var _shown_customer_name: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 55

	_build()


func _unhandled_input(
	event: InputEvent
) -> void:
	if not _is_open:
		return

	if not event.is_action_pressed(&"ui_cancel"):
		return

	close_dossier()
	get_viewport().set_input_as_handled()


# -----------------------------------------------------------------------------
# Building
# -----------------------------------------------------------------------------

func _build() -> void:
	_screen = Control.new()
	_screen.visible = false
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP

	add_child(_screen)

	var dim := ColorRect.new()
	dim.color = UITheme.COLOR_DIM_OVERLAY
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)

	_screen.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_screen.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE

	centre.add_child(panel)

	var margin := MarginContainer.new()

	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)

	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)

	margin.add_child(column)

	_build_header(column)
	column.add_child(HSeparator.new())
	_build_body(column)


func _build_header(
	column: VBoxContainer
) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)

	column.add_child(header)

	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	header.add_child(identity)

	_name_label = Label.new()
	_name_label.theme_type_variation = &"TitleLabel"

	identity.add_child(_name_label)

	_type_label = Label.new()
	_type_label.theme_type_variation = &"MutedLabel"

	identity.add_child(_type_label)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(90, 34)
	close_button.pressed.connect(close_dossier)

	header.add_child(close_button)


func _build_body(
	column: VBoxContainer
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL

	column.add_child(row)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = PORTRAIT_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var portrait_frame := PanelContainer.new()
	portrait_frame.custom_minimum_size = PORTRAIT_SIZE
	portrait_frame.add_theme_stylebox_override(
		&"panel", UITheme.make_inset_panel_style()
	)
	portrait_frame.add_child(_portrait)

	row.add_child(portrait_frame)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 8)

	row.add_child(details)

	_status_label = Label.new()
	_status_label.theme_type_variation = &"HeadingLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	details.add_child(_status_label)

	_description_label = Label.new()
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	details.add_child(_description_label)

	_relationship_section = _build_section(
		details, "RELATIONSHIP"
	)
	_relationship_label = Label.new()
	_relationship_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_relationship_section.add_child(_relationship_label)

	_history_section = _build_section(details, "HISTORY")
	_history_list = VBoxContainer.new()
	_history_list.add_theme_constant_override("separation", 2)
	_history_section.add_child(_history_list)


## A titled sub-section, hidden by default until it has content -
## `docs/DECISIONS_UI_UX_APPEND.md` §33: unknown information is hidden, not
## shown as a placeholder.
func _build_section(
	parent: VBoxContainer,
	heading_text: String
) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.visible = false
	section.add_theme_constant_override("separation", 4)

	parent.add_child(section)

	var heading := Label.new()
	heading.text = heading_text
	heading.theme_type_variation = &"MutedLabel"

	section.add_child(heading)

	return section


# -----------------------------------------------------------------------------
# Opening and closing
# -----------------------------------------------------------------------------

## Shows [param data]. Reused for every customer - opening it again while
## already open simply replaces the content, matching the developer
## inspector's own "one panel, always current" behaviour.
func show_dossier(
	data: CustomerDossierData
) -> void:
	if data == null:
		return

	_populate(data)

	if not _is_open:
		_is_open = true
		_screen.visible = true

		if not Simulation.is_paused():
			Simulation.push_state(SimulationState.State.PAUSED)
			_paused_by_this_screen = true
		else:
			_paused_by_this_screen = false


func close_dossier() -> void:
	if not _is_open:
		return

	_is_open = false
	_screen.visible = false
	_shown_customer_name = ""

	if _paused_by_this_screen:
		Simulation.pop_state()
		_paused_by_this_screen = false


## Opens [param data] if the dossier is closed or showing someone else;
## closes it if it is already open on this same customer - pressing the
## interaction key again on the same customer closes their own dossier,
## matching the developer inspector's existing toggle behaviour.
func toggle_dossier(
	data: CustomerDossierData
) -> void:
	if data == null:
		return

	if _is_open and _shown_customer_name == data.customer_name:
		close_dossier()
		return

	_shown_customer_name = data.customer_name

	show_dossier(data)


func is_open() -> bool:
	return _is_open


func _on_dim_input(
	event: InputEvent
) -> void:
	if event is InputEventMouseButton and event.pressed:
		close_dossier()


# -----------------------------------------------------------------------------
# Content
# -----------------------------------------------------------------------------

func _populate(
	data: CustomerDossierData
) -> void:
	_name_label.text = (
		data.customer_name if not data.customer_name.is_empty() else "Customer"
	)

	_type_label.text = data.type_display_name

	_status_label.text = data.status_line

	_description_label.visible = not data.description.is_empty()
	_description_label.text = data.description

	_portrait.texture = data.portrait_texture

	_relationship_section.visible = not data.relationship_label.is_empty()
	_relationship_label.text = data.relationship_label

	_history_section.visible = not data.history_lines.is_empty()

	for child: Node in _history_list.get_children():
		_history_list.remove_child(child)
		child.queue_free()

	for line: String in data.history_lines:
		var entry := Label.new()
		entry.text = line
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		_history_list.add_child(entry)
