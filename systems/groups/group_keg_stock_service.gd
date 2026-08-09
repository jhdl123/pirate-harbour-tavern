class_name GroupKegStockService
extends Node

## Books one filled keg out of real storage on behalf of a group.
##
## The smallest reservation layer that does the job, deliberately. The project
## already has [Reservable] for nodes and [ItemSlot] for stacks, but neither
## can hold "one of the four kegs in this crate is spoken for" - a slot is a
## stack, not a queue of claims. So this keeps a ledger of outstanding claims
## per storage container and subtracts it from the real count.
##
## Nothing is removed from storage here. The stack only moves when a worker
## actually collects it, through the ordinary [method ItemCarrier.take_from]
## transaction every other collection uses. A reservation is a promise, not a
## withdrawal, which is what makes releasing one free and makes a crash or a
## cancelled visit cost the tavern nothing.


signal reservation_created(reservation: Dictionary)
signal reservation_released(reservation: Dictionary)


@export_category("Item")

## The stock item a group keg is drawn from.
@export var keg_item: ItemDefinition

## Fallback path used when [member keg_item] is not wired in the inspector.
@export var keg_item_path: String = (
	"res://Data/items/group_servings/small_beer_table_keg.tres"
)


@export_category("Starting stock")

## Filled kegs put into storage when the tavern opens.
##
## A finite number on purpose. Running out is a real state the group system
## has to handle, so the development scene starts stocked rather than starting
## infinite.
@export_range(0, 99, 1)
var starting_keg_count: int = 6


var _next_reservation_number: int = 1

## Outstanding claims, keyed by reservation id.
var _reservations: Dictionary = {}


func _ready() -> void:
	add_to_group(&"group_keg_stock_service")

	if keg_item == null and not keg_item_path.is_empty():
		if ResourceLoader.exists(keg_item_path):
			keg_item = load(keg_item_path) as ItemDefinition

	# Deferred because storage containers add themselves to the group in
	# their own _ready(), which may not have run yet.
	call_deferred(&"_grant_starting_stock")


func _grant_starting_stock() -> void:
	if starting_keg_count <= 0:
		return

	var added: int = grant_test_stock(starting_keg_count)

	if added > 0:
		print("[GroupKeg] %d starting keg(s) placed in storage." % added)


func get_keg_item() -> ItemDefinition:
	return keg_item


## Every storage container that accepts the keg item.
func get_storage_containers() -> Array[Node]:
	var found: Array[Node] = []

	for node: Node in get_tree().get_nodes_in_group(&"stock_storage"):
		if is_instance_valid(node):
			found.append(node)

	return found


## Kegs physically present in [param storage], ignoring claims.
func count_in_storage(storage: Node) -> int:
	if storage == null or keg_item == null:
		return 0

	if not storage.has_method(&"count_item"):
		return 0

	return int(storage.call(&"count_item", keg_item.item_id))


## Claims already outstanding against [param storage].
func count_reserved(storage: Node) -> int:
	var total: int = 0

	for key: Variant in _reservations:
		var record: Dictionary = _reservations[key]

		if record.get("storage_ref", null) == null:
			continue

		var held: Node = (record["storage_ref"] as WeakRef).get_ref() as Node

		if held == storage:
			total += int(record.get("quantity", 1))

	return total


## Kegs in [param storage] that nobody has claimed yet.
func count_available(storage: Node) -> int:
	return maxi(count_in_storage(storage) - count_reserved(storage), 0)


## Kegs available anywhere in the tavern.
func count_available_everywhere() -> int:
	var total: int = 0

	for storage: Node in get_storage_containers():
		total += count_available(storage)

	return total


## Books one keg for [param group], or returns an empty Dictionary.
##
## The claim is what stops two groups ordering the last keg. Because the
## ledger is consulted before the count, a second group asking in the same
## minute sees one fewer than the shelf actually holds - which is correct,
## because one of them is already promised.
func reserve_keg(group: Node) -> Dictionary:
	if keg_item == null:
		return {}

	for storage: Node in get_storage_containers():
		if count_available(storage) <= 0:
			continue

		var reservation_id: StringName = StringName(
			"kegres_%05d" % _next_reservation_number
		)

		_next_reservation_number += 1

		var record: Dictionary = {
			"reservation_id": reservation_id,
			"storage_ref": weakref(storage),
			"storage_name": String(storage.name),
			"item_id": keg_item.item_id,
			"quantity": 1,
			"group_id": String(group.get(&"group_id")) if group != null else "",
			"created_minutes": _world_minutes(),
			"collected": false,
		}

		_reservations[reservation_id] = record

		print(
			"[GroupKeg] stock reservation %s created: 1 x %s from %s."
			% [
				String(reservation_id),
				String(keg_item.item_id),
				String(storage.name),
			]
		)

		reservation_created.emit(record)

		return record

	return {}


func get_reservation(reservation_id: StringName) -> Dictionary:
	return _reservations.get(reservation_id, {})


## Whether this claim still points at a storage container that holds the item.
func is_reservation_valid(reservation_id: StringName) -> bool:
	var record: Dictionary = get_reservation(reservation_id)

	if record.is_empty():
		return false

	var storage: Node = get_reservation_storage(reservation_id)

	if storage == null:
		return false

	# The claim is only good while the goods are still on the shelf. A player
	# who empties the crate by hand invalidates it, which is the honest
	# answer rather than a delivery of nothing.
	return count_in_storage(storage) >= 1


func get_reservation_storage(reservation_id: StringName) -> Node:
	var record: Dictionary = get_reservation(reservation_id)

	if record.is_empty():
		return null

	var reference: WeakRef = record.get("storage_ref", null) as WeakRef

	if reference == null:
		return null

	return reference.get_ref() as Node


## Marks a claim as collected. The stack itself moves through the carrier.
func mark_collected(reservation_id: StringName) -> void:
	var record: Dictionary = get_reservation(reservation_id)

	if record.is_empty():
		return

	record["collected"] = true

	_reservations[reservation_id] = record

	print(
		"[GroupKeg] keg collected against reservation %s."
		% String(reservation_id)
	)


## Drops a claim. Idempotent, and never returns anything to storage.
##
## Releasing twice cannot restore a keg twice because nothing was ever taken:
## the ledger entry simply stops existing. That is the whole reason the
## reservation is a claim rather than a withdrawal.
func release_reservation(reservation_id: StringName) -> bool:
	if not _reservations.has(reservation_id):
		return false

	var record: Dictionary = _reservations[reservation_id]

	_reservations.erase(reservation_id)

	print(
		"[GroupKeg] stock reservation %s released."
		% String(reservation_id)
	)

	reservation_released.emit(record)

	return true


func get_outstanding_count() -> int:
	return _reservations.size()


func get_outstanding_reservations() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	for key: Variant in _reservations:
		rows.append(_reservations[key])

	return rows


## Adds development stock so the group loop can be exercised repeatedly.
func grant_test_stock(quantity: int = 5) -> int:
	if keg_item == null:
		return 0

	var containers: Array[Node] = get_storage_containers()

	if containers.is_empty():
		return 0

	var storage: Node = containers[0]

	if not storage.has_method(&"add_item"):
		return 0

	return int(storage.call(&"add_item", keg_item, quantity))


func _world_minutes() -> int:
	var world_time: Node = get_node_or_null(^"/root/WorldTime")

	if world_time == null or not world_time.has_method(&"get_timestamp"):
		return 0

	var stamp: Variant = world_time.call(&"get_timestamp")

	return int(stamp.total_minutes) if stamp != null else 0
