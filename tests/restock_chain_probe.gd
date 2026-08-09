extends Node2D

## Proves two things the 9 Aug session showed were broken.
##
## 1. refill_station was 2 created / 0 claimed. can_claim() asked the legacy
##    singleton StockStorage for the station's stock item, but deliveries move
##    into the storeroom props, so no refill task was ever claimable.
## 2. Only ale and grog had any world/carried/inventory texture, so every other
##    drink was invisible on the bar, on a table and in a staff member's hands.

var passed: int = 0
var failed: int = 0
var main: Node = null


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout

	_check_drink_textures()
	_check_stock_source_interface()
	_check_restock_chain()

	print("RESULT %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("[PASS] %s" % label)
	else:
		failed += 1
		print("[FAIL] %s %s" % [label, detail])


func _check_drink_textures() -> void:
	print("--- drink sprites ---")
	# Drinks live in the ItemRegistry; the beverage registry holds contents,
	# containers and formats.
	var items: ItemRegistry = load("res://Data/items/item_registry.tres")

	for definition: ItemDefinition in items.definitions:
		var drink := definition as DrinkDefinition

		if drink == null:
			continue

		var missing: Array[String] = []

		if drink.world_texture == null:
			missing.append("world")
		if drink.carried_texture == null:
			missing.append("carried")
		if drink.inventory_icon == null:
			missing.append("icon")
		if drink.order_icon_texture == null:
			missing.append("order_icon")

		print("  %-20s %s" % [
			String(drink.item_id),
			"ok" if missing.is_empty() else "MISSING " + str(missing),
		])
		_ok("%s has every sprite" % drink.item_id, missing.is_empty(),
			str(missing))


func _props() -> Array[StockedDisplay]:
	var found: Array[StockedDisplay] = []

	for node in get_tree().get_nodes_in_group(&"stocked_display"):
		var prop := node as StockedDisplay

		if prop != null and prop.storage_backed:
			found.append(prop)

	return found


func _check_stock_source_interface() -> void:
	print("--- storeroom props as stock sources ---")

	for prop: StockedDisplay in _props():
		_ok("%s offers the stock-source interface" % prop.name,
			prop.has_method(&"count_item") and prop.has_method(&"take_one"))


func _check_restock_chain() -> void:
	print("--- restock chain ---")

	var registry: BeverageRegistry = main.get_node(^"Managers/Cellar").registry
	var items: ItemRegistry = load("res://Data/items/item_registry.tres")
	var carrier: ItemCarrier = null

	for node in get_tree().get_nodes_in_group(&"tavern_staff"):
		var staff := node as StaffMember

		if staff != null and staff.item_carrier != null:
			carrier = staff.item_carrier
			break

	for node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation
		var plan: StationStockPlan = StationStockPlan.for_station(
			station, registry, items
		)

		if not plan.is_valid():
			_ok("%s resolves a stock plan" % station.name, false, plan.detail)
			continue

		# Stock the matching prop, then check the station could be restocked
		# from it - the exact question can_claim() asks.
		var prop: StockedDisplay = null

		for candidate: StockedDisplay in _props():
			if candidate.content_id == plan.content_id:
				prop = candidate

		_ok("%s has a storeroom source for %s" % [
			station.name, String(plan.content_id)
		], prop != null, "no prop holds this content")

		if prop == null:
			continue

		var container: ContainerDefinition = registry.get_container(
			plan.restock_item.provides_container_id
		)
		var batch := FilledContainer.new()
		batch.container = container
		batch.content_id = plan.content_id
		batch.quantity = container.maximum_capacity
		prop.get_storage().add_batch(batch)

		_ok("%s reports the delivered %s" % [
			prop.name, plan.restock_item.display_name
		], prop.count_item(plan.restock_item.item_id) > 0,
			"count_item returned %d" % prop.count_item(plan.restock_item.item_id))

		# And the carrier can actually take it out.
		if carrier != null:
			carrier.clear_carried_item()
			var before: int = prop.count_item(plan.restock_item.item_id)
			var result: ItemTransferResult = prop.take_one(
				plan.restock_item.item_id, carrier
			)

			_ok("a staff member can collect %s from %s" % [
				plan.restock_item.display_name, prop.name
			], result.is_success(), str(result.status))

			_ok("collecting removes one from %s" % prop.name,
				prop.count_item(plan.restock_item.item_id) == before - 1,
				"%d -> %d" % [before, prop.count_item(plan.restock_item.item_id)])

			# And it goes into the station.
			station.set_servings(0)
			_ok("%s accepts the collected stock" % station.name,
				station.staff_refill_from(carrier)
				and station.current_servings > 0,
				"servings %d" % station.current_servings)

			carrier.clear_carried_item()
