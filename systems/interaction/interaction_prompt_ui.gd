class_name InteractionPromptUI
extends Control

## The one interaction prompt in the game.
##
## World objects no longer carry their own labels. This node listens to an
## [InteractionSelector] and describes whatever is currently selected, which
## means prompt styling, positioning and wording are decided in exactly one
## place for every object that will ever exist.
##
## It finds its selector through the [code]interaction_selector[/code] group, so
## the HUD does not need a [NodePath] into the player scene and nothing breaks
## when the player is spawned rather than placed.
##
## Expected children:
##
## [codeblock]
## InteractionPrompt (this node, inside a CanvasLayer)
##  └── PromptLabel (Label)
## [/codeblock]


## Where the prompt sits on screen.
enum AnchorMode {
	## Above the selected object's interaction point.
	FOLLOW_TARGET,

	## At a fixed screen offset, ignoring the target's position.
	SCREEN_FIXED,
}


@export_category("Wiring")

## Selector to describe. Found through [member selector_group] when empty.
@export var selector: InteractionSelector

## Group searched for a selector when none is assigned.
@export var selector_group: StringName = &"interaction_selector"

## Input action whose key is shown in front of the action text.
@export var primary_action_name: StringName = &"player_interact"


@export_category("Placement")

@export var anchor_mode: AnchorMode = AnchorMode.FOLLOW_TARGET

## Offset from the target's interaction point, in world pixels.
@export var world_offset: Vector2 = Vector2(0.0, -34.0)

## Screen position used by [constant AnchorMode.SCREEN_FIXED].
@export var fixed_screen_position: Vector2 = Vector2(640.0, 620.0)


@export_category("Appearance")

## Colour used for an action that can be run right now.
@export var available_colour: Color = Color(1.0, 1.0, 1.0, 1.0)

## Colour used for an action that is shown but currently blocked.
@export var unavailable_colour: Color = Color(0.75, 0.72, 0.68, 0.85)


@onready var prompt_label: Label = $PromptLabel


var _current_action: InteractionAction = null


func _ready() -> void:
	# The prompt is decoration: it must never eat clicks meant for the world.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if prompt_label == null:
		push_error(
			"InteractionPromptUI '%s' has no PromptLabel child."
			% get_path()
		)
	else:
		prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		prompt_label.set_anchors_preset(Control.PRESET_TOP_LEFT)

	_hide_prompt()

	_connect_selector.call_deferred()


func _connect_selector() -> void:
	if selector == null:
		selector = get_tree().get_first_node_in_group(
			selector_group
		) as InteractionSelector

	if selector == null:
		push_warning(
			"InteractionPromptUI found no InteractionSelector in group '%s'."
			% String(selector_group)
		)
		return

	if not selector.prompt_changed.is_connected(_on_prompt_changed):
		selector.prompt_changed.connect(_on_prompt_changed)

	_on_prompt_changed(
		selector.get_selected(),
		selector.get_current_action()
	)


func _process(
	_delta: float
) -> void:
	if not visible or selector == null:
		return

	if anchor_mode == AnchorMode.SCREEN_FIXED:
		position = fixed_screen_position
		_centre_label()
		return

	_follow_selected_target()


func _follow_selected_target() -> void:
	if selector == null or selector.get_selected() == null:
		return

	# A candidate being removed (a customer served and freed in the same
	# instant, for example - see InteractionDetector.get_candidates()'s own
	# doc comment on this) can trigger a reselection whose prompt update
	# reaches this node before it is fully tree-resident, or after it has
	# started leaving the tree. get_viewport() is null in either case;
	# skipping this frame's reposition is harmless - _process() calls this
	# again every frame this prompt is visible.
	var viewport: Viewport = get_viewport()

	if viewport == null:
		return

	var world_position: Vector2 = (
		selector.get_prompt_world_position() + world_offset
	)

	# The prompt lives on a CanvasLayer, so world space has to be converted
	# through the viewport's canvas transform rather than used directly.
	position = viewport.get_canvas_transform() * world_position

	_centre_label()


## Places the label centred above this node's origin.
##
## Positioning the label rather than this node keeps the anchor point exact
## regardless of how long the text is, so the prompt never drifts sideways as
## the wording changes.
func _centre_label() -> void:
	if prompt_label == null:
		return

	prompt_label.position = -Vector2(
		prompt_label.size.x * 0.5,
		prompt_label.size.y
	)


func _on_prompt_changed(
	_interactable: Interactable,
	action: InteractionAction
) -> void:
	_current_action = action

	if action == null:
		_hide_prompt()
		return

	_show_prompt(action)


func _show_prompt(
	action: InteractionAction
) -> void:
	if prompt_label == null:
		return

	var key_hint: String = InteractionInput.get_action_key_hint(
		primary_action_name
	)

	var text: String = "%s %s" % [key_hint, action.get_label()]

	if not action.is_available and not action.unavailable_reason.is_empty():
		text = "%s (%s)" % [text, action.unavailable_reason]

	prompt_label.text = text

	if action.is_available:
		prompt_label.modulate = available_colour
	else:
		prompt_label.modulate = unavailable_colour

	visible = true

	# The label's size is only correct once it has re-fitted to the new text,
	# and the centring maths needs it this frame rather than next.
	prompt_label.reset_size()

	if anchor_mode == AnchorMode.FOLLOW_TARGET:
		_follow_selected_target()
	else:
		_centre_label()


func _hide_prompt() -> void:
	visible = false

	if prompt_label != null:
		prompt_label.text = ""


## The action currently described, or null when nothing is shown.
func get_current_action() -> InteractionAction:
	return _current_action
