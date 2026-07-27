class_name InteractionDetector
extends Area2D

## Keeps a live list of the [Interactable]s an actor is standing within.
##
## Detection only. It does not score, select, highlight or prompt - that is
## [InteractionSelector]'s job. Splitting the two means reach is a physics
## question answered by this node's collision shape, while "which one do we
## mean" stays a pure data question that is easy to reason about and change.
##
## Attach to the actor with a collision shape describing arm's reach.


## An interactable came into range.
signal candidate_added(interactable: Interactable)

## An interactable left range, was disabled, or was freed.
signal candidate_removed(interactable: Interactable)

## The set of candidates changed in any way.
signal candidates_changed


var _candidates: Array[Interactable] = []


func _ready() -> void:
	monitoring = true

	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

	if not area_exited.is_connected(_on_area_exited):
		area_exited.connect(_on_area_exited)

	# Anything already overlapping when the scene starts never fires
	# area_entered, so the initial state is collected once physics is ready.
	_scan_current_overlaps.call_deferred()


func _scan_current_overlaps() -> void:
	for area: Area2D in get_overlapping_areas():
		_add_candidate(area as Interactable)


func _on_area_entered(
	area: Area2D
) -> void:
	_add_candidate(area as Interactable)


func _on_area_exited(
	area: Area2D
) -> void:
	_remove_candidate(area as Interactable)


func _add_candidate(
	interactable: Interactable
) -> void:
	if interactable == null:
		return

	if _candidates.has(interactable):
		return

	_candidates.append(interactable)

	candidate_added.emit(interactable)
	candidates_changed.emit()


func _remove_candidate(
	interactable: Interactable
) -> void:
	if interactable == null:
		return

	var index: int = _candidates.find(interactable)

	if index < 0:
		return

	_candidates.remove_at(index)

	candidate_removed.emit(interactable)
	candidates_changed.emit()


## Every interactable currently in range.
##
## Freed nodes are pruned here rather than relying on exit signals, because a
## customer that is served and immediately removed can be gone before physics
## reports the exit.
func get_candidates() -> Array[Interactable]:
	var valid_candidates: Array[Interactable] = []
	var pruned_any: bool = false

	for interactable: Interactable in _candidates:
		if is_instance_valid(interactable) and interactable.is_inside_tree():
			valid_candidates.append(interactable)
		else:
			pruned_any = true

	if pruned_any:
		_candidates = valid_candidates.duplicate()
		candidates_changed.emit()

	return valid_candidates


func get_candidate_count() -> int:
	return get_candidates().size()


func has_candidate(
	interactable: Interactable
) -> bool:
	return _candidates.has(interactable)
