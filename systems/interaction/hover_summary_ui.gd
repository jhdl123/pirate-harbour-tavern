class_name HoverSummaryUI
extends Control

## The world's "what am I looking at" glance layer (DECISIONS.md §32).
##
## Distinct from [InteractionPromptUI]: the prompt says what [E] would do to
## the current reach-limited target; this says what the mouse is currently
## over, anywhere on screen, whether or not it is in reach. Both can be
## visible on the same object at once - a short summary and an action prompt
## answer different questions and are positioned to stack rather than
## overlap.
##
## Sources its text from [method Interactable.get_hover_summary] and its
## world-wide hover state from [method Interactable.get_world_hovered] - no
## new detection system, reusing the shape objects already carry
## (DECISIONS.md §10).


## Offset from the target's interaction point, in world pixels. Sits further
## above the object than the prompt's default -34px offset so the two never
## overlap when both are showing for the same object.
@export var world_offset: Vector2 = Vector2(0.0, -54.0)


@onready var summary_label: Label = $SummaryLabel


var _current: Interactable = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if summary_label == null:
		push_error(
			"HoverSummaryUI '%s' has no SummaryLabel child." % get_path()
		)
	else:
		summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		summary_label.set_anchors_preset(Control.PRESET_TOP_LEFT)

	visible = false


func _process(
	_delta: float
) -> void:
	# Frozen rather than cleared while a deep modal has taken over input, the
	# same choice InteractionSelector makes - see its own doc comment.
	if not Simulation.accepts_input():
		return

	var hovered: Interactable = Interactable.get_world_hovered()

	if hovered != _current:
		_current = hovered
		_refresh_text()

	if _current == null:
		return

	_follow_target()


func _refresh_text() -> void:
	if summary_label == null:
		return

	if _current == null:
		visible = false
		summary_label.text = ""
		return

	summary_label.text = _current.get_hover_summary()
	visible = not summary_label.text.is_empty()

	summary_label.reset_size()


func _follow_target() -> void:
	if summary_label == null or _current == null:
		return

	var viewport: Viewport = get_viewport()

	if viewport == null:
		return

	# Resolved from the cursor's own world position (rather than the object's
	# origin) so a multi-slot object such as the bar counter anchors the
	# summary to the slot nearest wherever the player is actually pointing.
	var world_position: Vector2 = (
		_current.get_interaction_position(get_global_mouse_position())
		+ world_offset
	)

	position = viewport.get_canvas_transform() * world_position

	summary_label.position = -Vector2(
		summary_label.size.x * 0.5,
		summary_label.size.y
	)
