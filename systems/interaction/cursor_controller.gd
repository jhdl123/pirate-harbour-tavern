extends Node

## Contextual cursor states (DECISIONS.md §51): normal, interactable, and
## clickable UI.
##
## No custom cursor art exists in the project yet, so this uses the engine's
## own built-in cursor shapes rather than placeholder bitmaps that would look
## worse than no art at all - the contextual *behaviour* is what this pass
## establishes; swapping in themed pixel-art cursors later needs no change
## beyond the shapes passed to [method Input.set_custom_mouse_cursor] here.
##
## Registered as the [code]CursorController[/code] autoload so it applies
## uniformly regardless of which scene is loaded, the same reasoning as
## [code]UITheme[/code].


func _process(
	_delta: float
) -> void:
	if not Simulation.accepts_input():
		return

	if _is_over_clickable_ui():
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		return

	if _is_over_interactable_target():
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		return

	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _is_over_clickable_ui() -> bool:
	var viewport: Viewport = get_viewport()

	if viewport == null:
		return false

	return viewport.gui_get_hovered_control() != null


## True when the world object under the mouse is also the actor's current,
## actionable interaction target - the case where clicking would feel
## meaningful, as opposed to merely hovering something for a glance.
func _is_over_interactable_target() -> bool:
	var hovered: Interactable = Interactable.get_world_hovered()

	if hovered == null:
		return false

	var selector: InteractionSelector = get_tree().get_first_node_in_group(
		&"interaction_selector"
	) as InteractionSelector

	if selector == null or selector.get_selected() != hovered:
		return false

	if selector.has_multiple_actions():
		return true

	var action: InteractionAction = selector.get_current_action()

	return action != null and action.is_available
