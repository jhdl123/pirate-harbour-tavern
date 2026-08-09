extends Node2D

## Proves the delivery loop reaches the physical storeroom.
##
## The fault this covers: the order catalogue used plain ITEM entries, which
## OrderManager routes into the legacy singleton StockStorage, while the
## storeroom props read BeverageStorage. Stock existed and was completely
## invisible. FILLED_CONTAINER entries route to the props instead, so the
## question this probe answers is "did the delivery change what the player can
## see", not "did a number go up somewhere".

var passed: int = 0
var failed: int = 0
var main: Node = null
var registry: BeverageRegistry = null


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout

	registry = main.get_node(^"Managers/Cellar").registry

	_check_prop_mapping()
	_check_order_menu_builds()
	await _check_cask_delivery()
	await _check_withdrawal()

	print("RESULT %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("[PASS] %s" % label)
	else:
		failed += 1
		print("[FAIL] %s %s" % [label, detail])


func _props() -> Array[StockedDisplay]:
	var found: Array[StockedDisplay] = []

	for node in get_tree().get_nodes_in_group(&"stocked_display"):
		var prop := node as StockedDisplay

		if prop != null:
			found.append(prop)

	return found


func _find_prop(content_id: StringName) -> StockedDisplay:
	for prop: StockedDisplay in _props():
		if prop.storage_backed and prop.content_id == content_id:
			return prop

	return null


# --- Mapping -----------------------------------------------------------------

func _check_prop_mapping() -> void:
	print("--- storeroom props ---")

	var seen: Dictionary = {}

	for prop: StockedDisplay in _props():
		print("  %-22s content=%-12s backed=%s capacity=%d" % [
			prop.name, String(prop.content_id), prop.storage_backed,
			prop.get_unit_capacity(),
		])

		if not prop.storage_backed:
			continue

		# Cross-contamination is the failure mode here: two props claiming the
		# same content would both move when either is delivered to.
		_ok("%s claims a content" % prop.name, not prop.content_id.is_empty())
		_ok("%s is the only prop for %s" % [prop.name, String(prop.content_id)],
			not seen.has(prop.content_id),
			"also claimed by %s" % String(seen.get(prop.content_id, "")))

		seen[prop.content_id] = prop.name

		var storage: BeverageStorage = prop.get_storage()
		_ok("%s only accepts its own content" % prop.name,
			storage != null and storage.accepted_content_ids == [prop.content_id],
			"accepts %s" % str(storage.accepted_content_ids if storage else []))


# --- Order ledger UI ---------------------------------------------------------

## Builds the real catalogue rows, not just the data behind them.
##
## The menu read entry.item.item_id directly, which is null for a filled
## container - so the moment drink stock became orderable, opening the ledger
## threw and the player saw an empty panel. Checking the supplier resource
## alone would never have caught it.
func _check_order_menu_builds() -> void:
	var supplier: SupplierDefinition = load(
		"res://Data/suppliers/harbour_supplies.tres"
	)
	var scene: PackedScene = load("res://scenes/ui/stock_order_menu.tscn")

	if scene == null:
		_ok("the stock order menu scene loads", false)
		return

	var menu: Node = scene.instantiate()
	add_child(menu)
	menu.setup({ "supplier": supplier, "order_manager": _find_order_manager() })

	var rows: Node = menu.row_list

	_ok("the order menu built a row per catalogue entry",
		rows != null and rows.get_child_count() == supplier.entries.size(),
		"%d rows for %d entries" % [
			0 if rows == null else rows.get_child_count(),
			supplier.entries.size(),
		])

	if rows == null:
		return

	var unnamed: Array[String] = []

	for row: Node in rows.get_children():
		var label: Label = row.get_child(0) as Label

		if label == null or label.text.strip_edges().is_empty():
			unnamed.append(String(row.name))

	_ok("every catalogue row is named", unnamed.is_empty(),
		"blank rows: %s" % str(unnamed))

	for row: Node in rows.get_children():
		print("  row: %s" % (row.get_child(0) as Label).text)

	menu.queue_free()


func _find_order_manager() -> Node:
	var manager: Node = main.get_node_or_null(^"Managers/OrderManager")

	if manager != null:
		return manager

	for node in main.get_node(^"Managers").get_children():
		if node.has_method("submit_order"):
			return node

	return null


# --- Delivery ----------------------------------------------------------------

func _check_cask_delivery() -> void:
	var supplier: SupplierDefinition = load(
		"res://Data/suppliers/harbour_supplies.tres"
	)
	var manager: Node = main.get_node_or_null(^"Managers/OrderManager")

	if manager == null:
		for node in main.get_node(^"Managers").get_children():
			if node.has_method("submit_order"):
				manager = node
				break

	if manager == null:
		_ok("an order manager exists", false)
		return

	var beer: StockedDisplay = _find_prop(&"small_beer")

	if beer == null:
		_ok("a small beer storeroom prop exists", false)
		return

	# The scene starts broke; ordering is what is under test, not affording it.
	if manager.economy_manager != null:
		manager.economy_manager.set_money(5000)

	var before: int = beer.get_visible_units()
	var entry: OrderCatalogueEntry = null

	for candidate: OrderCatalogueEntry in supplier.entries:
		if candidate.is_filled_container() and candidate.content_id == &"small_beer":
			entry = candidate

	_ok("small beer is in the catalogue as a filled container", entry != null)

	if entry == null:
		return

	var result: Dictionary = manager.submit_order(
		supplier, { entry.get_offer_id(): 3 }
	)

	print("  order result: %s" % str(result.get("message", result)))
	_ok("the order was accepted",
		bool(result.get("success", false)),
		str(result.get("message", result)))

	var delivered: int = manager.complete_all_deliveries()
	print("  deliveries completed: %d" % delivered)
	await get_tree().process_frame

	# Three ordered casks must read as exactly three casks - the display unit
	# and the order unit have to be the same container.
	_ok("three delivered casks show as three casks",
		beer.get_visible_units() == before + 3,
		"%d -> %d" % [before, beer.get_visible_units()])

	# And nothing else moved.
	for prop: StockedDisplay in _props():
		if prop == beer or not prop.storage_backed:
			continue

		_ok("%s was unaffected by the small beer delivery" % prop.name,
			prop.get_visible_units() == 0,
			"showing %d" % prop.get_visible_units())


func _check_withdrawal() -> void:
	var beer: StockedDisplay = _find_prop(&"small_beer")

	if beer == null or beer.get_visible_units() <= 0:
		_ok("there is small beer stock to withdraw", false)
		return

	var before: int = beer.get_visible_units()
	var storage: BeverageStorage = beer.get_storage()
	var batches: Array[FilledContainer] = storage.get_batches()

	storage.remove_batch(batches[0])
	await get_tree().process_frame

	_ok("withdrawing one cask removes one from the storeroom display",
		beer.get_visible_units() == before - 1,
		"%d -> %d" % [before, beer.get_visible_units()])
