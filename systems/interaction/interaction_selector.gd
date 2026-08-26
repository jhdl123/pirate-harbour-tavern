class_name InteractionSelector
extends Node

## Decides which nearby [Interactable] the actor currently means.
##
## This is the brain of the interaction framework and the only place that knows
## about scoring, stickiness, cycling and highlighting. It knows nothing about
## bars, drinks, customers or items - it asks each candidate what it offers and
## hands the chosen action back to the object that offered it.
##
## Responsibilities, in the order they happen each tick:
##
## [codeblock]
## 1. ask the detector which interactables are in range
## 2. discard any that have nothing to offer this actor right now
## 3. score the rest on distance and priority
## 4. keep the current selection unless a rival clearly beats it
## 5. keep the selected object's highlight in step with the actor
## 6. re-read the selected object's primary action and report prompt changes
## [/codeblock]
##
## Input never reaches this node directly. The actor calls
## [method perform_primary] and [method cycle_next], so rebinding keys, adding a
## gamepad, or driving a staff member from AI needs no change here.
##
## The node adds itself to the [code]interaction_selector[/code] group so that
## UI can find it without a scene-wide [NodePath].


## The selected object changed. Either argument may be null.
signal selection_changed(
	previous: Interactable,
	current: Interactable
)

## The text the prompt should show changed.
##
## [param interactable] and [param action] are null when nothing is selected.
signal prompt_changed(
	interactable: Interactable,
	action: InteractionAction
)

## An action was successfully run.
signal interaction_performed(
	interactable: Interactable,
	action: InteractionAction
)


@export_category("Wiring")

## Source of nearby interactables.
@export var detector: InteractionDetector

## Who is interacting. Defaults to this node's parent.
@export var actor: Node

## Selection feel. A default resource is used when this is left empty.
@export var selection_rules: InteractionSelectionRules

## Group joined on ready so the shared prompt UI can find this selector.
@export var selector_group: StringName = &"interaction_selector"


## Generic menu used when the selected object offers more than one action.
##
## Kept as a scene rather than built in code so its layout can be tuned like
## any other menu; nothing here knows what actions look like beyond what
## InteractionAction already exposes.
@export var action_menu_scene: PackedScene = preload(
	"res://scenes/ui/action_choice_menu.tscn"
)


@export_category("Debug")

## Prints every selection change to the Output panel.
@export var show_selection_messages: bool = false


var _selected: Interactable = null
var _current_action: InteractionAction = null
var _current_prompt_text: String = ""
var _current_prompt_available: bool = false

var _is_enabled: bool = true
var _time_since_update: float = 0.0

var _manual_selection: bool = false
var _manual_elapsed: float = 0.0
var _manual_origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	if not is_in_group(selector_group):
		add_to_group(selector_group)

	if actor == null:
		actor = get_parent()

	if selection_rules == null:
		selection_rules = InteractionSelectionRules.new()

	if detector == null:
		detector = _find_detector()

	if detector == null:
		push_error(
			"InteractionSelector '%s' has no InteractionDetector."
			% get_path()
		)
		return

	if not detector.candidates_changed.is_connected(
		_on_candidates_changed
	):
		detector.candidates_changed.connect(
			_on_candidates_changed
		)


func _find_detector() -> InteractionDetector:
	var parent: Node = get_parent()

	if parent == null:
		return null

	for sibling: Node in parent.get_children():
		var found: InteractionDetector = (
			sibling as InteractionDetector
		)

		if found != null:
			return found

	return null


func _process(
	delta: float
) -> void:
	if not _is_enabled or detector == null:
		return

	# Freezing rather than clearing: the highlight and prompt stay exactly as
	# they were, so unpausing does not flicker the selection back into place.
	if not Simulation.accepts_input():
		return

	_time_since_update += delta

	if _time_since_update < selection_rules.selection_interval:
		return

	# The real elapsed time is used rather than the configured interval, so an
	# interval of zero still ages the manual hold correctly.
	var elapsed: float = _time_since_update

	_time_since_update = 0.0

	_update_manual_hold(elapsed)
	_update_selection()
	_refresh_selected()


# -----------------------------------------------------------------------------
# Selection
# -----------------------------------------------------------------------------

func _update_selection() -> void:
	var candidates: Array[Interactable] = _get_valid_candidates()

	if candidates.is_empty():
		_set_selected(null)
		return

	# Mouse hover wins outright (DECISIONS.md §29): it is a deliberate choice
	# by the player and should override both automatic scoring and a manual
	# cycle hold, not merely compete with them.
	var hovered: Interactable = _get_hovered_candidate(candidates)

	if hovered != null:
		_clear_manual_hold()
		_set_selected(hovered)
		return

	# A manually cycled target keeps its place until it stops being valid or
	# the hold is released, otherwise scoring would undo the player's choice.
	if _manual_selection and candidates.has(_selected):
		return

	var best: Interactable = null
	var best_score: float = -INF

	for candidate: Interactable in candidates:
		var score: float = _score_candidate(candidate)

		if score > best_score:
			best_score = score
			best = candidate

	_set_selected(best)


## The nearest candidate the mouse is currently over, or null.
##
## Only candidates already in reach are considered - hover chooses among what
## the player could act on, it does not extend reach itself. Nearest breaks
## ties when two overlapping shapes are both hovered at once.
func _get_hovered_candidate(
	candidates: Array[Interactable]
) -> Interactable:
	var actor_position: Vector2 = _get_actor_position()

	var nearest: Interactable = null
	var nearest_distance: float = INF

	for candidate: Interactable in candidates:
		if not candidate.is_mouse_hovered():
			continue

		var distance: float = actor_position.distance_to(
			candidate.get_interaction_position(actor_position)
		)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate

	return nearest


## Every in-range interactable that has something to offer the actor now.
func _get_valid_candidates() -> Array[Interactable]:
	var valid_candidates: Array[Interactable] = []

	if detector == null:
		return valid_candidates

	for candidate: Interactable in detector.get_candidates():
		if _has_available_action(candidate):
			valid_candidates.append(candidate)

	return valid_candidates


func _has_available_action(
	candidate: Interactable
) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false

	var request: InteractionRequest = _build_request(candidate)

	if not candidate.can_interact(request):
		return false

	return not candidate.get_actions(request).is_empty()


func _score_candidate(
	candidate: Interactable
) -> float:
	var actor_position: Vector2 = _get_actor_position()

	var distance: float = actor_position.distance_to(
		candidate.get_interaction_position(actor_position)
	)

	var score: float = (
		selection_rules.distance_weight
		* selection_rules.get_closeness(distance)
	)

	score += (
		selection_rules.priority_weight
		* float(candidate.interaction_priority)
	)

	if candidate == _selected:
		score += selection_rules.sticky_bonus

	return score


func _set_selected(
	new_selection: Interactable
) -> void:
	if new_selection == _selected:
		return

	var previous: Interactable = _selected

	if previous != null and is_instance_valid(previous):
		previous.set_highlighted(false, _build_request(previous))

		if previous.availability_changed.is_connected(
			_on_selected_availability_changed
		):
			previous.availability_changed.disconnect(
				_on_selected_availability_changed
			)

	_selected = new_selection

	if _selected != null:
		if not _selected.availability_changed.is_connected(
			_on_selected_availability_changed
		):
			_selected.availability_changed.connect(
				_on_selected_availability_changed
			)

		_selected.set_highlighted(true, _build_request(_selected))
	else:
		_clear_manual_hold()

	if show_selection_messages:
		print(
			"Interaction selection: ",
			"none" if _selected == null else _selected.get_display_name()
		)

	selection_changed.emit(previous, _selected)

	_refresh_prompt()


## Re-applies the highlight and re-reads the prompt for the current selection.
##
## Objects with a moving highlight rely on this being called every tick.
func _refresh_selected() -> void:
	if _selected == null or not is_instance_valid(_selected):
		return

	_selected.set_highlighted(true, _build_request(_selected))

	_refresh_prompt()


func _refresh_prompt() -> void:
	var action: InteractionAction = null

	var new_text: String = ""
	var new_is_available: bool = false

	if _selected != null and is_instance_valid(_selected):
		var actions: Array[InteractionAction] = _selected.get_actions(
			_build_request(_selected)
		)

		if actions.size() > 1:
			# A specific verb would misdescribe what the key actually does
			# here (open a choice, not run one action) - the object's own
			# name reads correctly either way: "[E] Bar Counter".
			new_text = _selected.get_display_name()
			new_is_available = actions.any(
				func(candidate: InteractionAction) -> bool:
					return candidate.is_available
			)
		else:
			action = _selected.get_primary_action(
				_build_request(_selected)
			)

	if action != null:
		new_text = action.get_label()
		new_is_available = action.is_available

	# Actions are rebuilt every tick, so they are compared by content rather
	# than by identity. Without this the prompt would re-emit constantly.
	var is_unchanged: bool = (
		new_text == _current_prompt_text
		and new_is_available == _current_prompt_available
	)

	_current_action = action

	if is_unchanged:
		return

	_current_prompt_text = new_text
	_current_prompt_available = new_is_available

	prompt_changed.emit(_selected, action)


func _on_candidates_changed() -> void:
	if not _is_enabled:
		return

	# React immediately rather than waiting for the next tick, so a customer
	# walking up or an object being removed is reflected at once.
	_update_selection()


func _on_selected_availability_changed(
	_interactable: Interactable
) -> void:
	_refresh_selected()


# -----------------------------------------------------------------------------
# Manual cycling
# -----------------------------------------------------------------------------

## Moves the selection to the next valid interactable in range.
##
## Ordering is by score, so repeated presses walk outwards from the nearest
## object and then wrap around.
func cycle_next() -> bool:
	if not _is_enabled:
		return false

	var candidates: Array[Interactable] = _get_valid_candidates()

	if candidates.size() < 2:
		return false

	candidates.sort_custom(_compare_by_score)

	var current_index: int = candidates.find(_selected)
	var next_index: int = (current_index + 1) % candidates.size()

	_set_selected(candidates[next_index])
	_begin_manual_hold()

	return true


func _compare_by_score(
	first: Interactable,
	second: Interactable
) -> bool:
	return _score_candidate(first) > _score_candidate(second)


func _begin_manual_hold() -> void:
	_manual_selection = true
	_manual_elapsed = 0.0
	_manual_origin = _get_actor_position()


func _clear_manual_hold() -> void:
	_manual_selection = false
	_manual_elapsed = 0.0


func _update_manual_hold(
	delta: float
) -> void:
	if not _manual_selection:
		return

	if _selected == null or not is_instance_valid(_selected):
		_clear_manual_hold()
		return

	_manual_elapsed += delta

	if (
		selection_rules.manual_hold_seconds > 0.0
		and _manual_elapsed >= selection_rules.manual_hold_seconds
	):
		_clear_manual_hold()
		return

	if selection_rules.manual_release_distance <= 0.0:
		return

	var travelled: float = _get_actor_position().distance_to(
		_manual_origin
	)

	if travelled >= selection_rules.manual_release_distance:
		_clear_manual_hold()


# -----------------------------------------------------------------------------
# Execution
# -----------------------------------------------------------------------------

## True when the selected object currently offers more than one action.
##
## The primary-interaction key should open the contextual action menu instead
## of running a single action when this is true (DECISIONS.md §28).
func has_multiple_actions() -> bool:
	if _selected == null or not is_instance_valid(_selected):
		return false

	return _selected.get_actions(_build_request(_selected)).size() > 1


## Opens the generic contextual action menu for the selected object.
##
## Falls back to [method perform_primary] if the object turns out to have
## zero or one action after all - a stale caller should still do something
## sensible rather than silently fail.
func open_action_menu() -> bool:
	if _selected == null or not is_instance_valid(_selected):
		return false

	var interactable: Interactable = _selected
	var actions: Array[InteractionAction] = interactable.get_actions(
		_build_request(interactable)
	)

	if actions.size() < 2:
		return perform_primary()

	if action_menu_scene == null:
		push_warning(
			"InteractionSelector has no action_menu_scene assigned."
		)
		return false

	if not InteractionMenu.menu_closed.is_connected(_on_action_menu_closed):
		InteractionMenu.menu_closed.connect(_on_action_menu_closed)

	return InteractionMenu.open_menu(
		action_menu_scene,
		{
			"interactable": interactable,
			"actions": actions,
			"title": interactable.get_display_name(),
		}
	)


func _on_action_menu_closed(
	result: Dictionary
) -> void:
	var action_id: StringName = result.get("action_id", &"")

	# Empty means the player cancelled rather than chose - opening the menu
	# does not commit to running anything.
	if action_id == &"":
		return

	if _selected == null or not is_instance_valid(_selected):
		return

	var interactable: Interactable = _selected

	var request: InteractionRequest = _build_request(
		interactable,
		action_id,
		result.get("action_data", {})
	)

	var chosen_action: InteractionAction = null

	for candidate_action: InteractionAction in interactable.get_actions(request):
		if candidate_action.id == action_id:
			chosen_action = candidate_action
			break

	var performed: bool = interactable.perform(request)

	if performed:
		interaction_performed.emit(interactable, chosen_action)

	_update_selection()
	_refresh_selected()


## Runs the selected object's primary action.
##
## Returns false when nothing is selected, the action is unavailable, or the
## object reported that nothing happened.
func perform_primary() -> bool:
	if not _is_enabled:
		return false

	if _selected == null or not is_instance_valid(_selected):
		return false

	var query: InteractionRequest = _build_request(_selected)
	var action: InteractionAction = _selected.get_primary_action(query)

	if action == null or not action.is_available:
		return false

	var request: InteractionRequest = _build_request(
		_selected,
		action.id,
		action.data
	)

	var interactable: Interactable = _selected
	var performed: bool = interactable.perform(request)

	if performed:
		interaction_performed.emit(interactable, action)

	# The world may have changed underneath the selection - an item moved, a
	# customer served and freed - so re-evaluate before the next tick.
	_update_selection()
	_refresh_selected()

	return performed


# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

## Turns selection off, clearing the highlight and the prompt.
##
## Used while the actor is busy with a timed action.
func set_enabled(
	enabled: bool
) -> void:
	if _is_enabled == enabled:
		return

	_is_enabled = enabled

	if not _is_enabled:
		_set_selected(null)


func is_enabled() -> bool:
	return _is_enabled


func get_selected() -> Interactable:
	return _selected


## The action the primary key would run right now, or null.
func get_current_action() -> InteractionAction:
	return _current_action


## Where the prompt should be drawn, in world space.
func get_prompt_world_position() -> Vector2:
	if _selected == null or not is_instance_valid(_selected):
		return Vector2.ZERO

	return _selected.get_interaction_position(
		_get_actor_position()
	)


func _build_request(
	interactable: Interactable,
	action_id: StringName = &"",
	action_data: Dictionary = {}
) -> InteractionRequest:
	var request: InteractionRequest = InteractionRequest.create(
		actor,
		interactable,
		action_id,
		action_data
	)

	request.actor_position = _get_actor_position()

	return request


func _get_actor_position() -> Vector2:
	var actor_node_2d: Node2D = actor as Node2D

	if actor_node_2d == null:
		return Vector2.ZERO

	return actor_node_2d.global_position
