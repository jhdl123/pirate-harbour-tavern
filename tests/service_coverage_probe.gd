extends Node2D

## Every drink any customer type can order must have a station that pours it.
##
## The gap this exists to prevent: authoring demand from a design table without
## checking supply, which silently turns into customers timing out unserved.

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout

	var stations: Array = get_tree().get_nodes_in_group(&"drink_stations")
	print("--- %d stations ---" % stations.size())

	for node in stations:
		var station: DrinksStation = node as DrinksStation
		print("  %-18s %-12s %d/%d servings  %s" % [
			station.name,
			station.served_drink.item_id if station.served_drink else "?",
			station.current_servings,
			station.maximum_servings,
			str(station.station_capabilities),
		])

	var wanted: Dictionary = {}

	for customer_type: CustomerType in main.get_node(^"Managers/GameManager").customer_types:
		for drink: DrinkDefinition in customer_type.get_orderable_drinks():
			var list: Array = wanted.get(String(drink.item_id), [])
			list.append(String(customer_type.type_id))
			wanted[String(drink.item_id)] = list

	print("--- stock plans ---")

	var items: ItemRegistry = load("res://Data/items/item_registry.tres")
	var bev: BeverageRegistry = main.get_node(^"Managers/Cellar").registry

	for node in stations:
		var station: DrinksStation = node as DrinksStation
		var plan: StationStockPlan = StationStockPlan.for_station(station, bev, items)
		print("  %s" % plan.describe())
		_ok("%s resolves a stock plan" % station.name, plan.is_valid(), plan.detail)
		_ok("%s restock item matches its content" % station.name,
			plan.is_valid() and station.refill_item != null
			and plan.accepts_stock(station.refill_item),
			"refill_item=%s content=%s" % [
				station.refill_item.item_id if station.refill_item else "<null>",
				String(plan.content_id)])

	print("--- coverage ---")

	for drink_id: String in wanted:
		var drink: DrinkDefinition = null
		var server: String = ""

		for node in stations:
			var station: DrinksStation = node as DrinksStation

			if station.served_drink != null and station.served_drink.item_id == StringName(drink_id):
				drink = station.served_drink

			if drink != null and station.can_serve_drink(drink) and station.current_servings > 0:
				server = String(station.name)
				break

		_ok("%s is servable (ordered by %s)" % [drink_id, str(wanted[drink_id])],
			not server.is_empty(), "no station pours it")

	# Bottled drinks must actually come by the bottle, not the glass.
	var registry: BeverageRegistry = main.get_node(^"Managers/Cellar").registry

	for drink_id: String in ["madeira", "brandy", "port_wine", "canary_wine"]:
		var drink: DrinkDefinition = registry.get_drink(StringName(drink_id))
		_ok("%s defaults to a bottle serving" % drink_id,
			drink != null and drink.get_default_serving_format_id() == &"bottle_serving",
			"got %s" % (drink.get_default_serving_format_id() if drink else "<null>"))

	# Nothing skipped should still be ordered.
	for drink_id: String in ["coffee", "bumbo", "rum_punch"]:
		_ok("%s is no longer ordered by anyone" % drink_id, not wanted.has(drink_id),
			"still ordered by %s" % str(wanted.get(drink_id, [])))

	# The shelf must show what the station holds.
	var shelf: StockedDisplay = main.get_node_or_null(^"Environment/BackBar/BrandyShelf")
	var service: DrinksStation = main.get_node_or_null(
		^"Environment/BackBar/BrandyShelf/BrandyService"
	)

	if shelf != null and service != null:
		_ok("brandy shelf shows the station's bottles",
			shelf.get_visible_units() == service.current_servings,
			"%d shown vs %d in stock" % [shelf.get_visible_units(), service.current_servings])

		var before: int = shelf.get_visible_units()
		service.set_servings(service.current_servings - 2)
		await get_tree().process_frame

		_ok("taking two bottles removes two from the shelf",
			shelf.get_visible_units() == before - 2,
			"%d -> %d" % [before, shelf.get_visible_units()])
	else:
		_ok("brandy shelf and its service station exist", false)

	print("RESULT %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("[PASS] %s" % label)
	else:
		failed += 1
		print("[FAIL] %s %s" % [label, detail])
