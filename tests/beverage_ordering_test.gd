extends Node

## Drives the full order -> delivery -> cellar -> station path.
##
## The framework and station tests prove the pieces. This proves the loop the
## brief actually names: order a bulk Kill-Devil container, receive it into a
## valid storage location, transfer it into a service cask, and serve from it.

var passed: int = 0
var failed: int = 0

var registry: BeverageRegistry
var order_manager: OrderManager
var economy: EconomyManager
var cellar: BeverageStorage
var locked: BeverageStorage
var stock: StockStorage
var distillery: SupplierDefinition
var provisioner: SupplierDefinition
var importer: SupplierDefinition


func _ready() -> void:
	registry = load("res://Data/beverage/beverage_registry.tres")
	registry.rebuild()

	await _build_world()

	_test_supplier_catalogue()
	_test_bulk_order_reaches_cellar()
	_test_routing_to_locked_storage()
	_test_ingredient_order_reaches_item_storage()
	_test_order_display_names()

	_report()


func _build_world() -> void:
	economy = EconomyManager.new()
	add_child(economy)
	economy.initialise(100000)

	cellar = BeverageStorage.new()
	cellar.location_id = &"cellar"
	cellar.display_name = "Cellar"
	cellar.storage_tags = [BeverageTags.CELLAR_STORAGE] as Array[StringName]
	cellar.registry = registry
	add_child(cellar)

	locked = BeverageStorage.new()
	locked.location_id = &"locked_cabinet"
	locked.display_name = "Locked Cabinet"
	locked.storage_tags = [BeverageTags.LOCKED_STORAGE] as Array[StringName]
	locked.registry = registry
	add_child(locked)

	stock = StockStorage.new()
	add_child(stock)

	order_manager = OrderManager.new()
	order_manager.economy_manager = economy
	add_child(order_manager)

	distillery = load("res://Data/beverage/suppliers/harbour_distillery.tres")
	provisioner = load("res://Data/beverage/suppliers/port_provisioner.tres")
	importer = load("res://Data/beverage/suppliers/island_importer.tres")

	await get_tree().process_frame


func _test_supplier_catalogue() -> void:
	_check(
		distillery != null and distillery.entries.size() == 4,
		"CATALOGUE: the distillery offers 4 Kill-Devil containers",
		"CATALOGUE: distillery catalogue is wrong"
	)

	var all_valid: bool = true

	for supplier: SupplierDefinition in [distillery, provisioner, importer]:
		for entry: OrderCatalogueEntry in supplier.entries:
			if entry == null or not entry.is_valid():
				all_valid = false

	_check(
		all_valid,
		"CATALOGUE: every supplier offer validates",
		"CATALOGUE: at least one offer is invalid"
	)


func _test_bulk_order_reaches_cellar() -> void:
	var hogshead_offer: OrderCatalogueEntry = _find_offer(
		distillery, &"hogshead__kill_devil"
	)

	_check(
		hogshead_offer != null,
		"ORDER: a Hogshead of Kill-Devil offer exists",
		"ORDER: no hogshead offer found"
	)

	var before: int = cellar.get_batch_count()

	var result: Dictionary = order_manager.submit_order(
		distillery, {&"hogshead__kill_devil": 2}
	)

	_check(
		bool(result.get("success", false)),
		"ORDER: order submitted (%s)" % String(result.get("message", "")),
		"ORDER: %s" % String(result.get("message", "rejected"))
	)

	order_manager.complete_all_deliveries()

	_check(
		cellar.get_batch_count() == before + 2,
		"DELIVERY: 2 hogsheads arrived in the cellar",
		"DELIVERY: cellar went from %d to %d batches" % [
			before, cellar.get_batch_count(),
		]
	)

	var batches: Array[FilledContainer] = cellar.get_batches_with_content(
		&"kill_devil"
	)

	_check(
		batches.size() == 2 and batches[0].quantity == 432,
		"DELIVERY: each hogshead arrived full (432 measures)",
		"DELIVERY: got %d batches, first holds %d" % [
			batches.size(),
			batches[0].quantity if not batches.is_empty() else -1,
		]
	)

	_check(
		batches[0].sealed,
		"DELIVERY: bulk stock arrived sealed, so it is not ageing yet",
		"DELIVERY: stock arrived unsealed"
	)

	# The point of the whole exercise: bulk into service, then serve.
	var service := FilledContainer.create_empty(
		registry.get_container(&"service_cask")
	)

	var transfer: BeverageTransferResult = BeverageTransferService.fill(
		batches[0], service, 0, registry
	)

	_check(
		transfer.is_success() and service.quantity == 96,
		"TRANSFER: cellar hogshead filled a 96-measure service cask",
		"TRANSFER: %s (cask holds %d)" % [
			transfer.get_message(), service.quantity,
		]
	)

	_check(
		batches[0].quantity == 432 - 96,
		"TRANSFER: the hogshead is down to %d measures" % batches[0].quantity,
		"TRANSFER: hogshead holds %d, expected 336" % batches[0].quantity
	)


func _test_routing_to_locked_storage() -> void:
	var cellar_before: int = cellar.get_batch_count()
	var locked_before: int = locked.get_batch_count()

	var result: Dictionary = order_manager.submit_order(
		importer, {&"crate__brandy": 1}
	)

	_check(
		bool(result.get("success", false)),
		"ROUTING: brandy crate ordered",
		"ROUTING: %s" % String(result.get("message", "rejected"))
	)

	order_manager.complete_all_deliveries()

	_check(
		locked.get_batch_count() == locked_before + 1
			and cellar.get_batch_count() == cellar_before,
		"ROUTING: the brandy went to locked storage, not the cellar",
		"ROUTING: cellar %d->%d, locked %d->%d" % [
			cellar_before, cellar.get_batch_count(),
			locked_before, locked.get_batch_count(),
		]
	)


func _test_ingredient_order_reaches_item_storage() -> void:
	var before: int = stock.count_item(&"sugar_loaf")

	var result: Dictionary = order_manager.submit_order(
		provisioner, {&"sugar_loaf": 5, &"nutmeg": 10}
	)

	_check(
		bool(result.get("success", false)),
		"INGREDIENTS: sugar and nutmeg ordered",
		"INGREDIENTS: %s" % String(result.get("message", "rejected"))
	)

	order_manager.complete_all_deliveries()

	_check(
		stock.count_item(&"sugar_loaf") == before + 5,
		"INGREDIENTS: 5 sugar loaves reached the item storage",
		"INGREDIENTS: sugar went %d -> %d" % [
			before, stock.count_item(&"sugar_loaf"),
		]
	)

	_check(
		stock.count_item(&"nutmeg") == 10,
		"INGREDIENTS: 10 nutmeg reached the item storage",
		"INGREDIENTS: nutmeg count is %d" % stock.count_item(&"nutmeg")
	)


func _test_order_display_names() -> void:
	var hogshead: OrderCatalogueEntry = _find_offer(
		distillery, &"hogshead__kill_devil"
	)
	var crate: OrderCatalogueEntry = _find_offer(importer, &"crate__brandy")
	var sugar: OrderCatalogueEntry = _find_offer(provisioner, &"sugar_loaf")

	_check(
		hogshead.get_display_name(registry)
			== "Hogshead (very large cask) of Kill-Devil",
		"UI: order reads 'Hogshead (very large cask) of Kill-Devil'",
		"UI: got '%s'" % hogshead.get_display_name(registry)
	)

	_check(
		crate.get_display_name(registry)
			== "Crate (case of bottles) of French Brandy",
		"UI: order reads 'Crate (case of bottles) of French Brandy'",
		"UI: got '%s'" % crate.get_display_name(registry)
	)

	_check(
		sugar.get_display_name(registry) == "Sugar Loaf",
		"UI: a plain ingredient still reads as its own name",
		"UI: got '%s'" % sugar.get_display_name(registry)
	)

	_check(
		hogshead.get_detail_text(registry) == "432 measures per container",
		"UI: the detail line explains what one container holds",
		"UI: got '%s'" % hogshead.get_detail_text(registry)
	)


# --- Harness -----------------------------------------------------------------

func _find_offer(
	supplier: SupplierDefinition,
	offer_id: StringName
) -> OrderCatalogueEntry:
	for entry: OrderCatalogueEntry in supplier.entries:
		if entry != null and entry.get_offer_id() == offer_id:
			return entry

	return null


func _check(condition: bool, pass_text: String, fail_text: String) -> void:
	if condition:
		passed += 1
		print("  [PASS] " + pass_text)
	else:
		failed += 1
		print("  [FAIL] " + fail_text)


func _report() -> void:
	print("")
	print("==================================================")
	print("BEVERAGE ORDERING TEST")
	print("  passed: %d" % passed)
	print("  failed: %d" % failed)
	print("==================================================")

	get_tree().quit(1 if failed > 0 else 0)
