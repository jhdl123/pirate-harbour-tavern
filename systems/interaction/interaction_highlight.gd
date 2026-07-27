class_name InteractionHighlight
extends Node

## Default "this object is selected" visual, shared by every interactable.
##
## Drop this node under an object and [Interactable] will find it and drive it.
## It tints one or more [CanvasItem] nodes and can additionally show an overlay
## node such as an outline sprite or a polygon.
##
## An object only needs to write its own highlight code when the default is not
## enough - the bar counter does, because it highlights whichever service slot
## the player is standing nearest rather than the whole counter. Objects that do
## so implement [code]set_interaction_highlighted[/code] and that takes
## priority; this node is the fallback for everything else.
##
## Original modulate values are captured on ready and restored on unhighlight,
## so this never fights with gameplay code that also tints a sprite.


@export_category("Targets")

## Nodes to tint. Must be [CanvasItem]s.
##
## When left empty, every direct [CanvasItem] sibling of this node is used,
## which covers the usual "one Sprite2D on the object root" case.
@export var target_paths: Array[NodePath] = []

## Optional node made visible only while highlighted.
##
## Use for an outline sprite, a glow, or a selection ring.
@export var overlay_path: NodePath


@export_category("Appearance")

## Multiplied into each target's original modulate while highlighted.
@export var highlight_tint: Color = Color(1.35, 1.3, 1.05, 1.0)

## Extra scale applied to the targets while highlighted. 1.0 disables it.
@export_range(1.0, 1.5, 0.01)
var highlight_scale: float = 1.0


var _targets: Array[CanvasItem] = []
var _original_modulates: Array[Color] = []
var _original_scales: Array[Vector2] = []
var _overlay: CanvasItem = null
var _is_highlighted: bool = false


func _ready() -> void:
	_resolve_targets()
	_resolve_overlay()

	set_highlighted(false)


func _resolve_targets() -> void:
	_targets.clear()
	_original_modulates.clear()
	_original_scales.clear()

	if target_paths.is_empty():
		_collect_sibling_canvas_items()
	else:
		for target_path: NodePath in target_paths:
			var target: CanvasItem = get_node_or_null(
				target_path
			) as CanvasItem

			if target == null:
				push_warning(
					"InteractionHighlight on '%s' could not resolve '%s'."
					% [get_path(), target_path]
				)
				continue

			_targets.append(target)

	for target: CanvasItem in _targets:
		_original_modulates.append(target.modulate)

		var target_node_2d: Node2D = target as Node2D

		if target_node_2d != null:
			_original_scales.append(target_node_2d.scale)
		else:
			_original_scales.append(Vector2.ONE)

	if _targets.is_empty():
		push_warning(
			"InteractionHighlight on '%s' has no targets to tint."
			% get_path()
		)


func _collect_sibling_canvas_items() -> void:
	var parent: Node = get_parent()

	if parent == null:
		return

	for sibling: Node in parent.get_children():
		if sibling == self:
			continue

		var canvas_item: CanvasItem = sibling as CanvasItem

		if canvas_item != null:
			_targets.append(canvas_item)


func _resolve_overlay() -> void:
	if overlay_path.is_empty():
		return

	_overlay = get_node_or_null(overlay_path) as CanvasItem

	if _overlay == null:
		push_warning(
			"InteractionHighlight on '%s' could not resolve overlay '%s'."
			% [get_path(), overlay_path]
		)


## Turns the highlight on or off. Called by [Interactable].
func set_highlighted(
	enabled: bool
) -> void:
	_is_highlighted = enabled

	for target_index: int in range(_targets.size()):
		var target: CanvasItem = _targets[target_index]

		if not is_instance_valid(target):
			continue

		var original_modulate: Color = _original_modulates[target_index]

		if enabled:
			target.modulate = original_modulate * highlight_tint
		else:
			target.modulate = original_modulate

		if is_equal_approx(highlight_scale, 1.0):
			continue

		var target_node_2d: Node2D = target as Node2D

		if target_node_2d == null:
			continue

		var original_scale: Vector2 = _original_scales[target_index]

		if enabled:
			target_node_2d.scale = original_scale * highlight_scale
		else:
			target_node_2d.scale = original_scale

	if _overlay != null and is_instance_valid(_overlay):
		_overlay.visible = enabled


func is_highlighted() -> bool:
	return _is_highlighted


## Re-reads the current modulate values as the new "unhighlighted" baseline.
##
## Call this if gameplay code permanently recolours a target while it happens
## to be highlighted.
func rebase_original_appearance() -> void:
	var was_highlighted: bool = _is_highlighted

	set_highlighted(false)
	_resolve_targets()
	set_highlighted(was_highlighted)
