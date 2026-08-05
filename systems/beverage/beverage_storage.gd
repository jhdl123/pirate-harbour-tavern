class_name BeverageStorage
extends Node

## A place that holds filled containers.
##
## The cellar, the space behind the bar and the locked cabinet are all this
## node with different tags. Which stock may live here is decided by the
## intersection of this location's [member storage_tags] and a batch's
## [StorageProfileDefinition] - so adding a new storage location is a scene
## edit and a tag, never a script.
##
## Deliberately separate from [ItemContainer]. Items are counted; liquid is
## measured, and a part-full hogshead is not four-tenths of an item. Ingredients
## and vessels stay in the normal item system exactly as before.


signal batch_added(batch: FilledContainer)
signal batch_removed(batch: FilledContainer)
signal contents_changed


@export_category("Identity")

## Stable id used by save data and by a batch's storage_location_id.
@export var location_id: StringName = &"cellar"

@export var display_name: String = "Cellar"


@export_category("Compatibility")

## Storage tags this location offers - see [BeverageTags].
@export var storage_tags: Array[StringName] = [BeverageTags.CELLAR_STORAGE]

## Maximum batches this location holds. Zero means unlimited.
@export_range(0, 999, 1)
var capacity: int = 0


@export_category("Conditions")

## Multiplier applied to the spoilage rate of everything stored here.
##
## Below 1.0 preserves. A cool cellar is the reason to set this.
@export_range(0.0, 10.0, 0.05)
var spoilage_modifier: float = 1.0


@export_category("Registry")

@export var registry: BeverageRegistry


var _batches: Array[FilledContainer] = []


func _ready() -> void:
	add_to_group(&"beverage_storage")


# --- Contents ----------------------------------------------------------------

func get_batches() -> Array[FilledContainer]:
	return _batches


func get_batch_count() -> int:
	return _batches.size()


func is_full() -> bool:
	if capacity <= 0:
		return false

	return _batches.size() >= capacity


## Every batch holding [param content_id].
func get_batches_with_content(
	content_id: StringName
) -> Array[FilledContainer]:
	var found: Array[FilledContainer] = []

	for batch: FilledContainer in _batches:
		if batch != null and batch.content_id == content_id:
			found.append(batch)

	return found


## Total measures of [param content_id] here, including reserved.
func count_content(content_id: StringName) -> int:
	var total: int = 0

	for batch: FilledContainer in _batches:
		if batch != null and batch.content_id == content_id:
			total += batch.quantity

	return total


## Measures of [param content_id] actually available to take.
func count_available_content(content_id: StringName) -> int:
	return BeverageTransferService.count_available(_batches, content_id)


# --- Adding and removing -----------------------------------------------------

## Whether [param batch] is allowed to be stored here.
func accepts(batch: FilledContainer) -> bool:
	if batch == null or batch.container == null:
		return false

	if is_full():
		return false

	var profile: StorageProfileDefinition = _get_storage_profile(batch)

	if profile == null:
		# No profile configured means no restriction. Stock is never stranded
		# just because someone has not authored a profile for it yet.
		return true

	return profile.is_compatible_with_location(storage_tags)


func add_batch(batch: FilledContainer) -> bool:
	if not accepts(batch):
		return false

	if _batches.has(batch):
		return true

	batch.storage_location_id = location_id
	_batches.append(batch)

	batch_added.emit(batch)
	contents_changed.emit()

	return true


func remove_batch(batch: FilledContainer) -> bool:
	if batch == null or not _batches.has(batch):
		return false

	_batches.erase(batch)

	batch_removed.emit(batch)
	contents_changed.emit()

	return true


## Drops every empty container, returning how many were cleared.
func remove_empty_batches() -> int:
	var removed: int = 0

	for batch: FilledContainer in _batches.duplicate():
		if batch != null and batch.is_empty():
			remove_batch(batch)
			removed += 1

	return removed


func clear() -> void:
	_batches.clear()
	contents_changed.emit()


# --- Display -----------------------------------------------------------------

## One row per batch, for the management UI and diagnostics panel.
func get_summary() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	for batch: FilledContainer in _batches:
		if batch == null:
			continue

		rows.append({
			"batch_id": batch.batch_id,
			"display_name": batch.get_display_name(registry),
			"container_name": (
				batch.container.get_display_name_with_explanation()
				if batch.container != null
				else "Unknown"
			),
			"content_id": batch.content_id,
			"quantity": batch.quantity,
			"maximum": batch.get_maximum_quantity(),
			"reserved": batch.reserved_quantity,
			"available": batch.get_available_quantity(),
			"fill": batch.get_fill_fraction(),
			"sealed": batch.sealed,
		})

	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["display_name"]) < String(b["display_name"])
	)

	return rows


# --- Persistence -------------------------------------------------------------

func to_save_dict() -> Dictionary:
	var saved: Array = []

	for batch: FilledContainer in _batches:
		if batch != null:
			saved.append(batch.to_save_dict())

	return {
		"location_id": String(location_id),
		"batches": saved,
	}


func from_save_dict(data: Dictionary) -> void:
	_batches.clear()

	var saved: Array = data.get("batches", [])

	for entry: Variant in saved:
		if not entry is Dictionary:
			continue

		var batch: FilledContainer = FilledContainer.from_save_dict(
			entry, registry
		)

		if batch != null:
			batch.storage_location_id = location_id
			_batches.append(batch)

	contents_changed.emit()


func _get_storage_profile(
	batch: FilledContainer
) -> StorageProfileDefinition:
	if registry == null:
		return null

	var content: BeverageContentDefinition = batch.get_content(registry)

	if content == null:
		return null

	# The content decides where it belongs. A container never does: the same
	# hogshead is cellar stock when it holds rum and cellar stock when it
	# holds Madeira, but a crate of bottles is not.
	#
	# The MOST SPECIFIC profile wins, not the first one in the list. Brandy is
	# both a spirit and a luxury; matching on first-found sent it to the bulk
	# cask profile and straight past the locked cabinet. Counting overlapping
	# tags makes the luxury profile win because it matches more of what brandy
	# actually is.
	var best: StorageProfileDefinition = null
	var best_score: int = 0

	for profile: StorageProfileDefinition in registry.storage_profiles:
		if profile == null:
			continue

		var score: int = profile.get_match_score(
			content.tags, batch.container.category
		)

		if score > best_score:
			best = profile
			best_score = score

	return best
