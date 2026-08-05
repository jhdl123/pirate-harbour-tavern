class_name GroupStandingArea
extends Node2D

## An authored spot where a group can stand together.
##
## Everything positional is a child marker, so the whole area moves as one node
## and nothing in code refers to a world coordinate. Duplicate it, drag it, and
## it works - which matters because the bar layout is going to be redesigned.
##
## Expected children (all optional; sensible fallbacks if absent):
##
## [codeblock]
## Centre       Marker2D  where the group gathers      (defaults to self)
## Entry        Marker2D  where members walk in from   (defaults to Centre)
## ServingPoint Marker2D  where a shared cask sits     (defaults to Centre)
## Reservable   Reservable  booking, so two groups cannot share it
## [/codeblock]
##
## Reservation reuses the existing [Reservable] rather than inventing a second
## booking system, so a standing area behaves like a chair as far as the
## reservation service is concerned.


signal area_reserved(group_id: StringName)
signal area_released(group_id: StringName)


@export_category("Identity")

## Stable id used by save data and diagnostics.
@export var area_id: StringName = &""

@export var display_name: String = "Standing Area"


@export_category("Capacity")

@export_range(1, 50, 1)
var minimum_group_size: int = 2

@export_range(1, 50, 1)
var maximum_group_size: int = 8


@export_category("Formation")

## How far members stand from the centre.
@export_range(8.0, 256.0, 1.0)
var formation_radius: float = 40.0

@export var layout: GroupFormation.Layout = GroupFormation.Layout.LOOSE_CIRCLE

## Random positional variation per slot, in pixels. Zero is perfectly even.
@export_range(0.0, 32.0, 0.5)
var formation_variation: float = 6.0


@export_category("Filtering")

## Group tags this area accepts. Empty means any group.
@export var allowed_group_tags: Array[StringName] = []


@export_category("Debug")

## Draw the area in-game. Useful while positioning; off for normal play.
@export var draw_debug_gizmo: bool = false


var _reservable: Reservable = null
var _holder_group_id: StringName = &""


func _ready() -> void:
	add_to_group(&"group_standing_areas")

	_reservable = get_node_or_null(^"Reservable") as Reservable

	if _reservable == null:
		# Built at runtime when the scene does not author one, so an area
		# dropped in by hand still cannot be double-booked.
		_reservable = Reservable.new()
		_reservable.name = "Reservable"
		_reservable.reservation_tags = [&"standing_area"]
		add_child(_reservable)

	if area_id.is_empty():
		area_id = StringName(name.to_snake_case())

	queue_redraw()


func _draw() -> void:
	if not draw_debug_gizmo:
		return

	draw_circle(Vector2.ZERO, formation_radius, Color(0.3, 0.8, 1.0, 0.12))
	draw_arc(
		Vector2.ZERO, formation_radius, 0.0, TAU, 32,
		Color(0.3, 0.8, 1.0, 0.5), 1.5
	)


# --- Positions ---------------------------------------------------------------

func get_centre_position() -> Vector2:
	var marker: Node2D = get_node_or_null(^"Centre") as Node2D

	return marker.global_position if marker != null else global_position


func get_entry_position() -> Vector2:
	var marker: Node2D = get_node_or_null(^"Entry") as Node2D

	return marker.global_position if marker != null else get_centre_position()


## Where a shared cask or bowl is placed.
func get_serving_position() -> Vector2:
	var marker: Node2D = get_node_or_null(^"ServingPoint") as Node2D

	return marker.global_position if marker != null else get_centre_position()


## Standing positions for [param count] members.
##
## Seeded from the area id so the same area always produces the same shape.
func get_formation_slots(count: int) -> Array[Vector2]:
	return GroupFormation.build_slots(
		get_centre_position(),
		count,
		formation_radius,
		layout,
		formation_variation,
		hash(area_id)
	)


# --- Capacity and filtering --------------------------------------------------

func can_hold(size: int) -> bool:
	return size >= minimum_group_size and size <= maximum_group_size


func accepts_group_tags(tags: Array[StringName]) -> bool:
	if allowed_group_tags.is_empty():
		return true

	return ItemTags.has_any(tags, allowed_group_tags)


## Whether [param size] could take this area right now.
func is_available_for(size: int, tags: Array[StringName] = []) -> bool:
	return is_free() and can_hold(size) and accepts_group_tags(tags)


func is_free() -> bool:
	return _reservable == null or _reservable.is_free()


func is_reserved() -> bool:
	return not is_free()


func get_holder_group_id() -> StringName:
	return _holder_group_id


# --- Reservation -------------------------------------------------------------

## Books this area for [param holder]. Returns false when already taken.
func reserve_for(holder: Node, group_id: StringName) -> bool:
	if _reservable == null or not _reservable.is_free():
		return false

	if not _reservable.reserve(holder):
		return false

	_holder_group_id = group_id

	area_reserved.emit(group_id)

	return true


func release_for(holder: Node) -> void:
	if _reservable == null:
		return

	if not _reservable.is_held_by(holder):
		return

	var released_group: StringName = _holder_group_id

	_reservable.release(holder)
	_holder_group_id = &""

	area_released.emit(released_group)


## Force-clears the booking. Used by the orphan sweep only.
func force_release() -> void:
	if _reservable == null:
		return

	var holder: Node = _reservable.get_holder()

	if holder != null:
		_reservable.release(holder)

	_holder_group_id = &""


# --- Lookup ------------------------------------------------------------------

## The best free area for a group of [param size] in [param tree].
##
## Prefers the smallest area that still fits, so a pair does not occupy the
## space a crew will need.
static func find_best_free(
	tree: SceneTree,
	size: int,
	tags: Array[StringName] = []
) -> GroupStandingArea:
	var best: GroupStandingArea = null

	for node: Node in tree.get_nodes_in_group(&"group_standing_areas"):
		var area: GroupStandingArea = node as GroupStandingArea

		if area == null or not area.is_available_for(size, tags):
			continue

		if best == null or area.maximum_group_size < best.maximum_group_size:
			best = area

	return best


func get_summary() -> Dictionary:
	return {
		"area_id": area_id,
		"display_name": display_name,
		"free": is_free(),
		"holder_group_id": _holder_group_id,
		"minimum_size": minimum_group_size,
		"maximum_size": maximum_group_size,
		"centre": get_centre_position(),
	}
