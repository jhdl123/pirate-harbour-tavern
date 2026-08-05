class_name VesselPool
extends Node

## Tracks how many drinking vessels the tavern has and what state they are in.
##
## Deliberately small. The brief asks that a recipe or serving format can
## require an available vessel and get one back when the drink is finished -
## not for a washing simulation, breakage or durability. So a vessel here is a
## count per container id in one of four states, and nothing more.
##
## [codeblock]
## AVAILABLE   clean and ready
## IN_USE      out with a customer
## DIRTY       returned, needs cleaning
## UNAVAILABLE broken or otherwise gone
## [/codeblock]
##
## The existing cleaning framework already turns dirty tableware back into
## clean tableware through [CleanableComponent]; this pool exposes
## [method mark_available] so that path can hand vessels back without knowing
## anything about beverages.


signal vessel_reserved(container_id: StringName)
signal vessel_returned(container_id: StringName, dirty: bool)
signal vessel_shortage(container_id: StringName)


enum State {
	AVAILABLE,
	IN_USE,
	DIRTY,
	UNAVAILABLE,
}


@export_category("Registry")

@export var registry: BeverageRegistry


@export_category("Starting Stock")

## Vessels the tavern starts with, as container id to count.
##
## Authored in the inspector or seeded at runtime by [method set_stock].
@export var starting_counts: Dictionary = {}


@export_category("Behaviour")

## Whether a finished serving returns its vessel dirty rather than available.
##
## True routes vessels through the cleaning system. False returns them straight
## to the available pool, which is the sensible setting until cleaning is
## wired up for tableware.
@export var finished_vessels_become_dirty: bool = false


var _counts: Dictionary = {}


func _ready() -> void:
	add_to_group(&"vessel_pool")

	for key: Variant in starting_counts:
		set_stock(StringName(String(key)), int(starting_counts[key]))


## Sets the total number of [param container_id] vessels the tavern owns.
func set_stock(container_id: StringName, total: int) -> void:
	if container_id.is_empty():
		return

	var record: Dictionary = _get_record(container_id)

	record[State.AVAILABLE] = maxi(total, 0)
	record[State.IN_USE] = 0
	record[State.DIRTY] = 0
	record[State.UNAVAILABLE] = 0


func add_stock(container_id: StringName, amount: int) -> void:
	if container_id.is_empty() or amount == 0:
		return

	var record: Dictionary = _get_record(container_id)

	record[State.AVAILABLE] = maxi(
		int(record[State.AVAILABLE]) + amount, 0
	)


func get_count(container_id: StringName, state: State) -> int:
	if not _counts.has(container_id):
		return 0

	return int(_counts[container_id].get(state, 0))


func get_available(container_id: StringName) -> int:
	return get_count(container_id, State.AVAILABLE)


func get_total(container_id: StringName) -> int:
	if not _counts.has(container_id):
		return 0

	var record: Dictionary = _counts[container_id]
	var total: int = 0

	for key: Variant in record:
		total += int(record[key])

	return total


func has_available(container_id: StringName, amount: int = 1) -> bool:
	if container_id.is_empty():
		# A format with no vessel requirement always passes. That is what lets
		# a drink be served without inventing a vessel for it.
		return true

	return get_available(container_id) >= amount


## Takes [param amount] vessels out of the available pool.
##
## Returns false and emits [signal vessel_shortage] when there are not enough,
## which is the graceful failure the brief asks for: the caller reports a
## missing vessel rather than serving a drink out of nothing.
func reserve(container_id: StringName, amount: int = 1) -> bool:
	if container_id.is_empty():
		return true

	if amount <= 0:
		return true

	if not has_available(container_id, amount):
		vessel_shortage.emit(container_id)
		return false

	var record: Dictionary = _get_record(container_id)

	record[State.AVAILABLE] = int(record[State.AVAILABLE]) - amount
	record[State.IN_USE] = int(record[State.IN_USE]) + amount

	vessel_reserved.emit(container_id)

	return true


## Hands a vessel back once a serving is finished.
func release(container_id: StringName, amount: int = 1) -> void:
	if container_id.is_empty() or amount <= 0:
		return

	var record: Dictionary = _get_record(container_id)
	var returning: int = mini(amount, int(record[State.IN_USE]))

	if returning <= 0:
		return

	record[State.IN_USE] = int(record[State.IN_USE]) - returning

	if finished_vessels_become_dirty:
		record[State.DIRTY] = int(record[State.DIRTY]) + returning
	else:
		record[State.AVAILABLE] = int(record[State.AVAILABLE]) + returning

	vessel_returned.emit(container_id, finished_vessels_become_dirty)


## Moves dirty vessels back to available. Called by the cleaning system.
func mark_available(container_id: StringName, amount: int = 1) -> void:
	if container_id.is_empty() or amount <= 0:
		return

	var record: Dictionary = _get_record(container_id)
	var cleaning: int = mini(amount, int(record[State.DIRTY]))

	if cleaning <= 0:
		return

	record[State.DIRTY] = int(record[State.DIRTY]) - cleaning
	record[State.AVAILABLE] = int(record[State.AVAILABLE]) + cleaning


func mark_dirty(container_id: StringName, amount: int = 1) -> void:
	if container_id.is_empty() or amount <= 0:
		return

	var record: Dictionary = _get_record(container_id)
	var soiling: int = mini(amount, int(record[State.AVAILABLE]))

	if soiling <= 0:
		return

	record[State.AVAILABLE] = int(record[State.AVAILABLE]) - soiling
	record[State.DIRTY] = int(record[State.DIRTY]) + soiling


## Whether the vessel a serving format needs is free.
func can_serve_format(format: ServingFormatDefinition) -> bool:
	if format == null:
		return false

	return has_available(format.required_container_id)


func reserve_for_format(format: ServingFormatDefinition) -> bool:
	if format == null:
		return false

	return reserve(format.required_container_id)


func release_for_format(format: ServingFormatDefinition) -> void:
	if format == null:
		return

	release(format.required_container_id)


## Every tracked vessel, for the management UI and diagnostics panel.
func get_summary() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	for key: Variant in _counts:
		var container_id: StringName = key
		var container: ContainerDefinition = (
			registry.get_container(container_id) if registry != null else null
		)

		rows.append({
			"container_id": container_id,
			"display_name": (
				container.get_display_name_with_explanation()
				if container != null
				else String(container_id)
			),
			"available": get_count(container_id, State.AVAILABLE),
			"in_use": get_count(container_id, State.IN_USE),
			"dirty": get_count(container_id, State.DIRTY),
			"unavailable": get_count(container_id, State.UNAVAILABLE),
			"total": get_total(container_id),
		})

	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["display_name"]) < String(b["display_name"])
	)

	return rows


func to_save_dict() -> Dictionary:
	var data: Dictionary = {}

	for key: Variant in _counts:
		var record: Dictionary = _counts[key]

		data[String(key)] = {
			"available": int(record[State.AVAILABLE]),
			"in_use": int(record[State.IN_USE]),
			"dirty": int(record[State.DIRTY]),
			"unavailable": int(record[State.UNAVAILABLE]),
		}

	return data


func from_save_dict(data: Dictionary) -> void:
	_counts.clear()

	for key: Variant in data:
		var record: Dictionary = _get_record(StringName(String(key)))
		var saved: Dictionary = data[key]

		record[State.AVAILABLE] = int(saved.get("available", 0))
		record[State.IN_USE] = int(saved.get("in_use", 0))
		record[State.DIRTY] = int(saved.get("dirty", 0))
		record[State.UNAVAILABLE] = int(saved.get("unavailable", 0))


func _get_record(container_id: StringName) -> Dictionary:
	if not _counts.has(container_id):
		_counts[container_id] = {
			State.AVAILABLE: 0,
			State.IN_USE: 0,
			State.DIRTY: 0,
			State.UNAVAILABLE: 0,
		}

	return _counts[container_id]
