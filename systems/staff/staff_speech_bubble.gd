class_name StaffSpeechBubble
extends Node2D

## A short line of text above an actor's head.
##
## Presentation only, and deliberately the lightest possible layer. A low-stock
## warning is a real [CommMessage] that lives in the communication service
## whether or not anybody is looking at the worker; this just makes the world
## feel like the warning came from a person.
##
## That separation is why a worker can be off-screen, busy, paused or absent
## and the warning still reaches the player.


@export_range(0.5, 30.0, 0.5)
var display_seconds: float = 4.0

## Pixels above the actor's origin.
@export var vertical_offset: float = -34.0

@export var maximum_width: float = 180.0


var _label: Label = null
var _panel: PanelContainer = null
var _remaining: float = 0.0


func _ready() -> void:
	z_index = 30

	_build()

	visible = false

	set_process(false)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style: StyleBoxFlat = StyleBoxFlat.new()

	style.bg_color = Color(0.09, 0.07, 0.05, 0.88)
	style.border_color = Color(0.85, 0.72, 0.45, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(5)

	_panel.add_theme_stylebox_override("panel", style)

	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(maximum_width, 0.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 11)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel.add_child(_label)

	add_child(_panel)


func show_text(
	text: String
) -> void:
	if _label == null:
		return

	_label.text = text

	# Sized after the text is set so the bubble hugs the line rather than
	# always being the maximum width.
	await get_tree().process_frame

	if not is_instance_valid(self) or _panel == null:
		return

	_panel.position = Vector2(
		-_panel.size.x * 0.5,
		vertical_offset - _panel.size.y
	)

	visible = true

	_remaining = display_seconds

	set_process(true)


func hide_bubble() -> void:
	visible = false
	_remaining = 0.0

	set_process(false)


func _process(
	delta: float
) -> void:
	# Real seconds, not world minutes: a speech bubble is a piece of interface
	# feedback, and it should not linger for an in-game hour during a
	# fast-forward or freeze solid while the game is paused.
	_remaining -= delta

	if _remaining > 0.0:
		return

	hide_bubble()
