class_name CustomerInspectorUI
extends CanvasLayer

## Developer-tier customer inspection panel - built now as a debugging
## instrument, later becomes the information UI's foundation. See
## CUSTOMER_INSPECTOR.md.
##
## [b]Renders only.[/b] This class never reads a [Customer], [CustomerBrain],
## [CustomerNeeds] or [ActivityRegistry] - it only ever displays whatever
## [CustomerInspectionData] it is given (DECISIONS.md §25). That is what
## lets the decision architecture change again without this class changing.
##
## Instantiated lazily by [method Customer.perform_interaction] on first
## use rather than authored into a scene - a single always-current text
## panel is the whole developer-tier surface CUSTOMER_INSPECTOR.md asks
## for this pass, so a hand-built .tscn would add authoring risk for no
## behavioural gain. Gated behind [code]OS.is_debug_build()[/code] at the
## call site, same as the F10 panel.


var _label: RichTextLabel = null
var _panel: PanelContainer = null


func _ready() -> void:
	layer = 50

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-380, 20)
	_panel.custom_minimum_size = Vector2(360, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	style.set_content_margin_all(10.0)
	style.set_border_width_all(1.0)
	style.border_color = Color(0.5, 0.5, 0.6, 0.8)
	_panel.add_theme_stylebox_override(&"panel", style)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = false
	_label.fit_content = true
	_label.scroll_active = false
	_label.custom_minimum_size = Vector2(340, 0)
	_label.add_theme_font_size_override(&"normal_font_size", 13)
	_label.add_theme_color_override(&"default_color", Color(0.9, 0.9, 0.95))

	_panel.add_child(_label)
	add_child(_panel)


func show_inspection(data: CustomerInspectionData) -> void:
	if _label == null or data == null:
		return

	_label.text = data.to_display_text()
	_panel.visible = true


func hide_inspection() -> void:
	if _panel != null:
		_panel.visible = false


## Shows [param data] if the panel is hidden or showing a different
## customer; hides it if it is already showing this same customer -
## selecting the same customer twice closes the panel.
func toggle_inspection(data: CustomerInspectionData) -> void:
	if _panel == null or _label == null or data == null:
		return

	if _panel.visible and _label.text == data.to_display_text():
		hide_inspection()
		return

	show_inspection(data)
