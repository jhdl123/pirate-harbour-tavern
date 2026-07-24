class_name PatienceBar
extends Control


@export_category("Colours")
@export var high_patience_colour: Color = Color(
	0.25,
	0.75,
	0.25
)

@export var medium_patience_colour: Color = Color(
	0.95,
	0.75,
	0.15
)

@export var low_patience_colour: Color = Color(
	0.9,
	0.2,
	0.15
)

@export_category("Thresholds")
@export_range(0.0, 1.0, 0.01)
var medium_threshold: float = 0.6

@export_range(0.0, 1.0, 0.01)
var low_threshold: float = 0.3


@onready var fill: ColorRect = $Fill


var maximum_fill_width: float = 30.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	maximum_fill_width = maxf(
		size.x - 2.0,
		0.0
	)

	hide_bar()


func set_patience_ratio(ratio: float) -> void:
	var safe_ratio: float = clampf(
		ratio,
		0.0,
		1.0
	)

	# Whole-pixel changes keep the bar crisp.
	fill.size.x = roundf(
		maximum_fill_width * safe_ratio
	)

	if safe_ratio <= low_threshold:
		fill.color = low_patience_colour
	elif safe_ratio <= medium_threshold:
		fill.color = medium_patience_colour
	else:
		fill.color = high_patience_colour


func show_bar() -> void:
	set_patience_ratio(1.0)
	visible = true


func hide_bar() -> void:
	visible = false
