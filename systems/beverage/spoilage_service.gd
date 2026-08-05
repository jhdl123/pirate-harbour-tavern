class_name SpoilageService
extends Node

## Decides when stock has gone off, without checking every frame.
##
## Two rules keep this cheap:
##
## [codeblock]
## 1  freshness is DERIVED on read, never stored and ticked
## 2  a batch that can spoil books ONE scheduled event for the moment it will
## [/codeblock]
##
## So a cellar full of casks costs nothing until something looks at it, and a
## prepared punch bowl costs exactly one entry in [TimeScheduler] rather than a
## per-frame timer. Nothing in this class runs in [method Node._process].
##
## When spoilage is disabled - which is the default for sealed spirits and most
## bottled wine - every field is still safe to read: freshness returns 1.0 and
## no event is ever booked.


signal batch_spoiled(batch: FilledContainer)
signal serving_spoiled(serving: SharedServing)


@export_category("Registry")

@export var registry: BeverageRegistry


@export_category("Scheduling")

## Whether spoilage is evaluated at all.
##
## A single switch for balancing and for tests that want deterministic stock.
@export var spoilage_enabled: bool = true

## Tag used for every event this service books, so they can be cancelled
## together on a load or a reset.
@export var scheduler_tag: StringName = &"spoilage"


var _tracked_batches: Array[FilledContainer] = []
var _tracked_servings: Array[SharedServing] = []


func _ready() -> void:
	add_to_group(&"spoilage_service")


# --- Reading -----------------------------------------------------------------

## Freshness of [param batch] right now, 1.0 to 0.0.
func get_freshness(
	batch: FilledContainer,
	storage_modifier: float = 1.0
) -> float:
	if batch == null or not spoilage_enabled:
		return 1.0

	return batch.get_freshness(
		_get_world_minutes(), registry, storage_modifier
	)


func is_spoiled(
	batch: FilledContainer,
	storage_modifier: float = 1.0
) -> bool:
	if batch == null or not spoilage_enabled:
		return false

	return batch.is_spoiled(_get_world_minutes(), registry, storage_modifier)


# --- Tracking ----------------------------------------------------------------

## Starts watching [param batch] and books its one spoilage check.
##
## Safe to call on anything, including stock that cannot spoil - it simply does
## nothing, which is why callers never have to ask first.
func track_batch(
	batch: FilledContainer,
	storage_modifier: float = 1.0
) -> void:
	if batch == null or not spoilage_enabled:
		return

	var profile: SpoilageProfileDefinition = batch.get_spoilage_profile(registry)

	if profile == null or not profile.is_enabled():
		return

	if not _tracked_batches.has(batch):
		_tracked_batches.append(batch)

	_schedule_batch_check(batch, storage_modifier)


func untrack_batch(batch: FilledContainer) -> void:
	_tracked_batches.erase(batch)


func track_serving(serving: SharedServing) -> void:
	if serving == null or not spoilage_enabled:
		return

	if not serving.can_spoil or serving.spoilage_profile == null:
		return

	if not serving.spoilage_profile.is_enabled():
		return

	if not _tracked_servings.has(serving):
		_tracked_servings.append(serving)

	var minutes: int = serving.get_minutes_until_spoiled(_get_world_minutes())

	if minutes < 0:
		return

	_schedule(minutes, _on_serving_due.bind(serving))


func untrack_serving(serving: SharedServing) -> void:
	_tracked_servings.erase(serving)


func clear_tracking() -> void:
	_tracked_batches.clear()
	_tracked_servings.clear()

	var scheduler: Node = _get_scheduler()

	if scheduler != null and scheduler.has_method(&"cancel_tag"):
		scheduler.call(&"cancel_tag", scheduler_tag)


# --- Manual evaluation -------------------------------------------------------

## Checks everything tracked right now. Used by the debug panel and on load.
##
## Returns how many things were newly found spoiled.
func evaluate_all() -> int:
	if not spoilage_enabled:
		return 0

	var spoiled_count: int = 0
	var world_minutes: int = _get_world_minutes()

	for batch: FilledContainer in _tracked_batches.duplicate():
		if batch == null:
			_tracked_batches.erase(batch)
			continue

		if batch.is_spoiled(world_minutes, registry):
			spoiled_count += 1
			batch_spoiled.emit(batch)

	for serving: SharedServing in _tracked_servings.duplicate():
		if not is_instance_valid(serving):
			_tracked_servings.erase(serving)
			continue

		if serving.check_spoilage(world_minutes):
			spoiled_count += 1
			serving_spoiled.emit(serving)

	return spoiled_count


## Every tracked thing and its freshness, for the diagnostics panel.
func get_summary() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var world_minutes: int = _get_world_minutes()

	for batch: FilledContainer in _tracked_batches:
		if batch == null:
			continue

		rows.append({
			"kind": "batch",
			"name": batch.get_display_name(registry),
			"freshness": batch.get_freshness(world_minutes, registry),
			"spoiled": batch.is_spoiled(world_minutes, registry),
		})

	for serving: SharedServing in _tracked_servings:
		if not is_instance_valid(serving):
			continue

		rows.append({
			"kind": "serving",
			"name": serving.get_display_name(),
			"freshness": serving.get_freshness(world_minutes),
			"spoiled": serving.is_spoiled(),
		})

	return rows


# --- Internals ---------------------------------------------------------------

func _schedule_batch_check(
	batch: FilledContainer,
	storage_modifier: float
) -> void:
	var profile: SpoilageProfileDefinition = batch.get_spoilage_profile(registry)

	if profile == null:
		return

	if batch.sealed and profile.sealed_state_pauses_spoilage:
		return

	if batch.filled_at_minutes < 0:
		return

	var elapsed: int = maxi(
		_get_world_minutes() - batch.filled_at_minutes, 0
	)
	var minutes: int = profile.get_minutes_until_spoiled(
		elapsed, storage_modifier
	)

	if minutes < 0:
		return

	_schedule(minutes, _on_batch_due.bind(batch))


func _schedule(minutes: int, callback: Callable) -> void:
	var scheduler: Node = _get_scheduler()

	if scheduler == null or not scheduler.has_method(&"schedule_in"):
		return

	scheduler.call(&"schedule_in", maxi(minutes, 0), callback, scheduler_tag)


func _on_batch_due(batch: FilledContainer) -> void:
	if batch == null or not _tracked_batches.has(batch):
		return

	if batch.is_spoiled(_get_world_minutes(), registry):
		batch_spoiled.emit(batch)


func _on_serving_due(serving: SharedServing) -> void:
	if not is_instance_valid(serving):
		_tracked_servings.erase(serving)
		return

	if serving.check_spoilage(_get_world_minutes()):
		serving_spoiled.emit(serving)


func _get_world_minutes() -> int:
	var world_time: Node = get_node_or_null(^"/root/WorldTime")

	if world_time == null or not world_time.has_method(&"get_timestamp"):
		return 0

	var stamp: Variant = world_time.call(&"get_timestamp")

	if stamp == null:
		return 0

	return int(stamp.total_minutes)


func _get_scheduler() -> Node:
	var world_time: Node = get_node_or_null(^"/root/WorldTime")

	if world_time == null:
		return null

	if world_time.has_method(&"schedule_in"):
		return world_time

	var scheduler: Variant = world_time.get(&"scheduler")

	return scheduler as Node
