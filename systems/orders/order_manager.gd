class_name OrderManager
extends Node

signal order_submitted(order: Dictionary)
signal order_rejected(reason: String)
signal order_delivered(order: Dictionary)
signal delivery_partially_received(order: Dictionary)

@export var economy_manager: EconomyManager
@export_range(1, 10080, 1) var default_delivery_minutes: int = 180

var pending_orders: Array[Dictionary] = []
var delivered_orders: Array[Dictionary] = []
var _next_order_number: int = 1

func _ready() -> void:
	WorldTime.time_changed.connect(_on_time_changed)
	WorldTime.time_skipped.connect(func(_a, _b): process_due_orders())

func submit_order(supplier: SupplierDefinition, quantities: Dictionary) -> Dictionary:
	if supplier == null or not supplier.is_valid(): return _reject("The supplier catalogue is not configured.")
	if economy_manager == null: return _reject("The order system has no EconomyManager.")
	var lines: Array[Dictionary] = []
	var total_cost := 0
	for entry in supplier.entries:
		if entry == null or not entry.is_valid(): continue
		# Offers are keyed generically: a filled container has no item to read
		# an id from, so both shapes go through get_offer_id().
		var offer_id := entry.get_offer_id()
		if offer_id.is_empty(): continue
		var quantity := clampi(int(quantities.get(offer_id, 0)), 0, entry.get_maximum_quantity())
		if quantity <= 0: continue
		var unit_price := entry.get_unit_price()
		lines.append({
			"item_id": offer_id,
			"display_name": entry.get_display_name(_get_beverage_registry()),
			"detail_text": entry.get_detail_text(_get_beverage_registry()),
			"quantity": quantity,
			"remaining_quantity": quantity,
			"unit_price": unit_price,
			"line_total": unit_price * quantity,
			"item_definition": entry.item,
			"catalogue_entry": entry,
		})
		total_cost += unit_price * quantity
	if lines.is_empty(): return _reject("Choose at least one item before submitting.")
	if not economy_manager.can_afford(total_cost): return _reject("You need £%d but only have £%d." % [total_cost, economy_manager.get_money()])
	if not economy_manager.spend_money(total_cost, &"stock_order"): return _reject("The payment could not be completed.")
	var placed := WorldTime.get_timestamp()
	var expected_minutes := placed.total_minutes + default_delivery_minutes
	var order := {"order_number": _next_order_number, "supplier_id": supplier.supplier_id, "supplier_name": supplier.display_name, "lines": lines, "total_cost": total_cost, "placed_at_minutes": placed.total_minutes, "placed_at_text": placed.get_full_text(), "expected_at_minutes": expected_minutes, "expected_at_text": _format_minutes(expected_minutes), "status": &"pending"}
	_next_order_number += 1
	pending_orders.append(order)
	order_submitted.emit(order)
	return {"success": true, "message": "Order #%d placed. Expected %s." % [order.order_number, order.expected_at_text], "order": order}

func process_due_orders() -> void:
	var now := WorldTime.get_timestamp().total_minutes
	# Shallow duplicate only: pending_orders holds Dictionaries, which are
	# reference types in GDScript. Iterating a *shallow* copy lets us erase
	# from the real array mid-loop while still mutating the real order
	# objects. A deep duplicate() (as this used to use) hands _deliver_order
	# a disconnected copy - any partial-delivery quantity written onto it is
	# silently lost, so the next pass re-delivers the full original quantity
	# and duplicates stock. See CLEANUP_REPORT.md.
	for order in pending_orders.duplicate():
		if int(order.expected_at_minutes) <= now:
			_deliver_order(order)

func complete_next_delivery() -> bool:
	if pending_orders.is_empty(): return false
	return _deliver_order(pending_orders[0])

func complete_all_deliveries() -> int:
	var count := 0
	# Shallow duplicate - see process_due_orders() above for why.
	for order in pending_orders.duplicate():
		if _deliver_order(order): count += 1
	return count

func _deliver_order(order: Dictionary) -> bool:
	var storage := _get_storage()
	if storage == null:
		return false
	var all_received := true
	for line in order.lines:
		var remaining := int(line.get("remaining_quantity", line.quantity))
		var moved := 0

		# A line is either a plain item bound for the item storage, or a
		# filled container bound for a BeverageStorage. The order dictionary
		# carries the catalogue entry so delivery can tell which without the
		# ordering system knowing anything about casks.
		var entry: OrderCatalogueEntry = line.get("catalogue_entry")

		if entry != null and entry.is_filled_container():
			moved = _deliver_filled_containers(entry, remaining)
		else:
			moved = storage.add_item(line.item_definition, remaining)

		line.remaining_quantity = remaining - moved
		if line.remaining_quantity > 0: all_received = false
	if all_received:
		order.status = &"delivered"
		pending_orders.erase(order)
		delivered_orders.append(order)
		order_delivered.emit(order)
	else:
		order.status = &"partially_received"
		delivery_partially_received.emit(order)
	return true

func get_pending_orders() -> Array[Dictionary]: return pending_orders.duplicate(true)
func get_delivered_orders() -> Array[Dictionary]: return delivered_orders.duplicate(true)

func _get_storage() -> StockStorage:
	var nodes := get_tree().get_nodes_in_group(&"stock_storage")
	return nodes[0] as StockStorage if not nodes.is_empty() else null


## Delivers [param count] filled containers into a compatible location.
##
## Returns how many were actually accepted. A destination that is full stops
## the delivery cleanly and the rest stays on the order as outstanding, which
## is the same partial-delivery behaviour plain items already had.
func _deliver_filled_containers(
	entry: OrderCatalogueEntry,
	count: int
) -> int:
	var registry := _get_beverage_registry()

	if registry == null:
		return 0

	var delivered := 0

	for _index in range(count):
		var batch := entry.create_filled_container(
			registry, _get_world_minutes()
		)

		if batch == null:
			break

		var destination := _find_storage_for(batch, entry)

		if destination == null:
			break

		if not destination.add_batch(batch):
			break

		delivered += 1
		_track_spoilage(batch, destination)

	return delivered


## The best BeverageStorage for [param batch].
##
## Prefers a location matching the entry's destination tags, so premium
## bottles land in locked storage rather than the first place with room.
func _find_storage_for(
	batch: FilledContainer,
	entry: OrderCatalogueEntry
) -> BeverageStorage:
	var fallback: BeverageStorage = null

	# Highest priority first, so a specific visible store (the ale cask stack,
	# the wine crates) is offered the batch before the general Cellar and the
	# Cellar only takes what nothing else will hold. Group order is arbitrary,
	# so without this sort the winner depends on scene-tree ordering.
	var candidates: Array[BeverageStorage] = []

	for node in get_tree().get_nodes_in_group(&"beverage_storage"):
		var storage := node as BeverageStorage

		if storage != null and storage.accepts(batch):
			candidates.append(storage)

	candidates.sort_custom(
		func(a: BeverageStorage, b: BeverageStorage) -> bool:
			return a.storage_priority > b.storage_priority
	)

	for storage: BeverageStorage in candidates:
		if entry.destination_storage_tags.is_empty():
			return storage

		if ItemTags.has_any(
			storage.storage_tags, entry.destination_storage_tags
		):
			return storage

		if fallback == null:
			fallback = storage

	return fallback


func _track_spoilage(
	batch: FilledContainer,
	storage: BeverageStorage
) -> void:
	for node in get_tree().get_nodes_in_group(&"spoilage_service"):
		var service := node as SpoilageService

		if service != null:
			service.track_batch(batch, storage.spoilage_modifier)
			return


func _get_beverage_registry() -> BeverageRegistry:
	for node in get_tree().get_nodes_in_group(&"beverage_storage"):
		var storage := node as BeverageStorage

		if storage != null and storage.registry != null:
			return storage.registry

	return load("res://Data/beverage/beverage_registry.tres")


func _get_world_minutes() -> int:
	var world_time := get_node_or_null(^"/root/WorldTime")

	if world_time == null or not world_time.has_method(&"get_timestamp"):
		return -1

	var stamp: Variant = world_time.call(&"get_timestamp")

	return int(stamp.total_minutes) if stamp != null else -1

func _on_time_changed(_stamp: GameTimeStamp) -> void: process_due_orders()
func _format_minutes(total: int) -> String:
	var cfg: GameTimeConfig = WorldTime.config
	var day_minutes: int = cfg.hours_per_day * cfg.minutes_per_hour
	@warning_ignore("integer_division")
	var day: int = int(total / day_minutes) + 1
	var within: int = total % day_minutes
	@warning_ignore("integer_division")
	var hour: int = int(within / cfg.minutes_per_hour)
	var minute: int = within % cfg.minutes_per_hour

	return "Day %d — %02d:%02d" % [day, hour, minute]


func _reject(reason: String) -> Dictionary:
	order_rejected.emit(reason)
	return {"success": false, "message": reason}
