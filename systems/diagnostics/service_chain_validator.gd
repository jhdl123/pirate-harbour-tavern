class_name ServiceChainValidator
extends RefCounted

## Walks the full drink service chain against the LIVE tavern and reports where
## it breaks.
##
## This is the diagnostic that answers "which system is at fault" instead of
## "something is wrong". Every previous fault on this project - the grog barrel
## on the Port Wine station, the wine crates refusing their own stock, the
## refill tasks nothing could claim - was invisible because each individual
## system reported success. The chain only breaks BETWEEN systems, so only a
## check that crosses every boundary can see it.
##
## ARCHITECTURE RULE: this observes, it never re-implements. Every value comes
## from the authoritative system - the ItemRegistry, the BeverageRegistry, the
## live station nodes, the live storage nodes. There are no diagnostic-only
## quantities and no diagnostic-only mappings, so adding a drink makes it
## appear here automatically.


## One step in the chain, in the order a drink actually travels.
enum Step {
	DRINK_DEFINITION,
	CUSTOMER_ORDER,
	SERVICE_STATION,
	STATION_CONTENT,
	RESTOCK_ITEM,
	ORDER_CATALOGUE,
	AUTHORITATIVE_STORAGE,
	PHYSICAL_DISPLAY,
	STAFF_REPLENISHMENT,
	BAR_COUNTER,
	CUSTOMER_CONSUMPTION,
}

const STEP_NAMES: Dictionary = {
	Step.DRINK_DEFINITION: "Drink definition",
	Step.CUSTOMER_ORDER: "Customer order",
	Step.SERVICE_STATION: "Service station",
	Step.STATION_CONTENT: "Station content",
	Step.RESTOCK_ITEM: "Restock item",
	Step.ORDER_CATALOGUE: "Order catalogue",
	Step.AUTHORITATIVE_STORAGE: "Authoritative storage",
	Step.PHYSICAL_DISPLAY: "Physical display",
	Step.STAFF_REPLENISHMENT: "Staff replenishment",
	Step.BAR_COUNTER: "BarCounter",
	Step.CUSTOMER_CONSUMPTION: "Customer consumption",
}


## Every drink any customer type can order, with its chain result.
##
## Keyed by drink item id. Each value is a Dictionary with `steps` (a
## per-step PASS/FAIL/N/A dictionary), `result`, `first_failure` and the
## resolved identities the report prints.
static func validate_all(tree: SceneTree) -> Dictionary:
	var results: Dictionary = {}
	var item_registry: ItemRegistry = load("res://Data/items/item_registry.tres")
	var beverage_registry: BeverageRegistry = _find_beverage_registry(tree)

	for drink: DrinkDefinition in _get_orderable_drinks(tree):
		results[String(drink.item_id)] = _validate_drink(
			tree, drink, item_registry, beverage_registry
		)

	return results


## Drinks reachable through customer demand, not every drink authored.
##
## A drink nobody can order is not a broken chain, it is unused content, and
## reporting it as FAIL would bury the real failures.
static func _get_orderable_drinks(tree: SceneTree) -> Array[DrinkDefinition]:
	var drinks: Array[DrinkDefinition] = []

	# GameManager is in no group, so find it by type. Depending on a group
	# nobody registers is how this silently returned zero drinks and reported
	# a clean bill of health for a tavern that served nothing.
	for node: Node in _find_customer_type_sources(tree):
		for customer_type: CustomerType in node.customer_types:
			if customer_type == null:
				continue

			for drink: DrinkDefinition in customer_type.get_orderable_drinks():
				if drink != null and not drinks.has(drink):
					drinks.append(drink)

	return drinks


## Nodes that own the customer roster.
##
## GameManager holds it, but a test harness may substitute its own spawner, so
## this matches on the property rather than the class.
static func _find_customer_type_sources(tree: SceneTree) -> Array[Node]:
	var sources: Array[Node] = []
	var root: Node = tree.current_scene if tree.current_scene != null else tree.root

	_collect_customer_type_sources(root, sources)

	return sources


static func _collect_customer_type_sources(
	node: Node,
	sources: Array[Node]
) -> void:
	if "customer_types" in node and node.customer_types is Array:
		sources.append(node)

	for child: Node in node.get_children():
		_collect_customer_type_sources(child, sources)


static func _validate_drink(
	tree: SceneTree,
	drink: DrinkDefinition,
	item_registry: ItemRegistry,
	beverage_registry: BeverageRegistry
) -> Dictionary:
	var steps: Dictionary = {}
	var detail: Dictionary = {}
	var identities: Dictionary = {
		"drink_id": String(drink.item_id),
		"display_name": drink.display_name,
		"customer_price": drink.base_sell_price,
		"serving_format": String(drink.get_default_serving_format_id()),
	}

	steps[Step.DRINK_DEFINITION] = true
	steps[Step.CUSTOMER_ORDER] = true

	# --- Service station -----------------------------------------------------
	var station: DrinksStation = _find_station_for(tree, drink)

	steps[Step.SERVICE_STATION] = station != null
	identities["service_station"] = "none" if station == null else String(station.name)

	if station == null:
		detail[Step.SERVICE_STATION] = "no live station serves this drink"

		return _finish(steps, detail, identities)

	var plan: StationStockPlan = StationStockPlan.for_station(
		station, beverage_registry, item_registry
	)

	steps[Step.STATION_CONTENT] = not plan.content_id.is_empty()
	identities["content_id"] = String(plan.content_id)

	if plan.content_id.is_empty():
		detail[Step.STATION_CONTENT] = plan.detail

		return _finish(steps, detail, identities)

	# --- Restock item --------------------------------------------------------
	steps[Step.RESTOCK_ITEM] = plan.restock_item != null
	identities["restock_item"] = (
		"none" if plan.restock_item == null else String(plan.restock_item.item_id)
	)

	if plan.restock_item == null:
		detail[Step.RESTOCK_ITEM] = plan.detail

		return _finish(steps, detail, identities)

	# The exact failure that produced "Port Wine Station requires Grog Barrel".
	if station.refill_item != null and not plan.accepts_stock(station.refill_item):
		steps[Step.RESTOCK_ITEM] = false
		detail[Step.RESTOCK_ITEM] = (
			"station asks for '%s' but pours '%s'"
			% [String(station.refill_item.item_id), String(plan.content_id)]
		)

	# --- Order catalogue -----------------------------------------------------
	var entry: OrderCatalogueEntry = _find_catalogue_entry(plan)

	steps[Step.ORDER_CATALOGUE] = entry != null
	identities["orderable"] = "YES" if entry != null else "NO"
	identities["purchase_price"] = 0 if entry == null else entry.get_unit_price()

	if entry == null:
		detail[Step.ORDER_CATALOGUE] = (
			"no supplier entry delivers content '%s'" % String(plan.content_id)
		)

	# --- Storage and its physical display ------------------------------------
	var display: StockedDisplay = _find_display_for(tree, plan.content_id)
	var storage: BeverageStorage = _find_storage_for(tree, plan.content_id)

	steps[Step.AUTHORITATIVE_STORAGE] = storage != null
	identities["storage"] = "none" if storage == null else String(storage.location_id)

	if storage == null:
		detail[Step.AUTHORITATIVE_STORAGE] = (
			"no BeverageStorage accepts content '%s'" % String(plan.content_id)
		)

	steps[Step.PHYSICAL_DISPLAY] = display != null
	identities["physical_display"] = (
		"none" if display == null else String(display.name)
	)

	if display == null:
		detail[Step.PHYSICAL_DISPLAY] = "no matching storeroom display found"

	var shelf: StockedDisplay = _find_shelf_for(tree, plan.content_id)
	identities["bar_shelf"] = "none" if shelf == null else String(shelf.name)

	# A live mismatch between what is stored and what the player can see is
	# the difference between "stock never arrived" and "stock arrived and the
	# prop did not update" - two completely different bugs.
	if display != null:
		var held: int = display.count_item(plan.restock_item.item_id)
		var shown: int = display.get_visible_units()
		identities["storeroom_units_held"] = held
		identities["storeroom_units_shown"] = shown

		if held != shown and held <= display.get_unit_capacity():
			steps[Step.PHYSICAL_DISPLAY] = false
			detail[Step.PHYSICAL_DISPLAY] = (
				"authoritative %d units but %d shown" % [held, shown]
			)

	# --- Staff replenishment -------------------------------------------------
	# The question is whether a refill task could be CLAIMED, which is where
	# restocking silently died: the executor asked the legacy StockStorage
	# while deliveries were landing in the props.
	var source: Node = _find_stock_source(tree, plan.restock_item)

	steps[Step.STAFF_REPLENISHMENT] = source != null
	identities["restock_source"] = "none" if source == null else String(source.name)

	if source == null:
		detail[Step.STAFF_REPLENISHMENT] = (
			"nothing in the world can supply '%s' to staff"
			% String(plan.restock_item.item_id)
		)

	# --- Bar counter and consumption -----------------------------------------
	var counter: BarCounter = _find_bar_counter(tree)

	steps[Step.BAR_COUNTER] = (
		counter != null and counter.get_service_container() != null
	)
	identities["bar_slots"] = (
		0 if counter == null or counter.get_service_container() == null
		else counter.get_service_container().get_slot_count()
	)

	if not bool(steps[Step.BAR_COUNTER]):
		detail[Step.BAR_COUNTER] = "no bar counter with service slots"

	steps[Step.CUSTOMER_CONSUMPTION] = drink.base_sell_price > 0
	identities["customer_price"] = drink.base_sell_price

	if drink.base_sell_price <= 0:
		detail[Step.CUSTOMER_CONSUMPTION] = "drink has no sale price"

	return _finish(steps, detail, identities)


static func _finish(
	steps: Dictionary,
	detail: Dictionary,
	identities: Dictionary
) -> Dictionary:
	var first_failure: int = -1

	for step: int in Step.values():
		if steps.has(step) and not bool(steps[step]):
			first_failure = step
			break

	return {
		"steps": steps,
		"detail": detail,
		"identities": identities,
		"result": "PASS" if first_failure < 0 else "FAIL",
		"first_failure": first_failure,
		"first_failure_name": (
			"" if first_failure < 0 else String(STEP_NAMES[first_failure])
		),
	}


# --- Lookups -----------------------------------------------------------------
#
# Every one of these reads a live node or an authored resource. None of them
# caches, derives or second-guesses; a wrong answer here means the game itself
# is wrong, which is the whole point.

static func _find_beverage_registry(tree: SceneTree) -> BeverageRegistry:
	for node: Node in tree.get_nodes_in_group(&"beverage_storage"):
		var storage := node as BeverageStorage

		if storage != null and storage.registry != null:
			return storage.registry

	return null


static func _find_station_for(
	tree: SceneTree,
	drink: DrinkDefinition
) -> DrinksStation:
	for node: Node in tree.get_nodes_in_group(&"drink_stations"):
		var station := node as DrinksStation

		if (
			station != null
			and station.served_drink != null
			and station.served_drink.item_id == drink.item_id
		):
			return station

	return null


static func _find_catalogue_entry(
	plan: StationStockPlan
) -> OrderCatalogueEntry:
	var supplier: SupplierDefinition = load(
		"res://Data/suppliers/harbour_supplies.tres"
	)

	if supplier == null:
		return null

	for entry: OrderCatalogueEntry in supplier.entries:
		if entry == null:
			continue

		if entry.is_filled_container() and entry.content_id == plan.content_id:
			return entry

		if (
			entry.item != null
			and plan.restock_item != null
			and entry.item.item_id == plan.restock_item.item_id
		):
			return entry

	return null


## The STOREROOM display for a content, not the bar shelf.
##
## Both carry the same content_id, so taking the first match returned the
## back-bar shelf and reported PASS while the storeroom crate - the thing
## actually under investigation - went unchecked. The storeroom prop is the
## one that owns storage; a shelf mirrors its service station instead.
static func _find_display_for(
	tree: SceneTree,
	content_id: StringName
) -> StockedDisplay:
	for node: Node in tree.get_nodes_in_group(&"stocked_display"):
		var display := node as StockedDisplay

		if (
			display != null
			and display.content_id == content_id
			and display.storage_backed
		):
			return display

	return null


## The behind-bar shelf for a content, if one exists.
static func _find_shelf_for(
	tree: SceneTree,
	content_id: StringName
) -> StockedDisplay:
	for node: Node in tree.get_nodes_in_group(&"stocked_display"):
		var display := node as StockedDisplay

		if (
			display != null
			and display.content_id == content_id
			and not display.mirror_station.is_empty()
		):
			return display

	return null


static func _find_storage_for(
	tree: SceneTree,
	content_id: StringName
) -> BeverageStorage:
	for node: Node in tree.get_nodes_in_group(&"beverage_storage"):
		var storage := node as BeverageStorage

		if storage == null:
			continue

		if storage.accepted_content_ids.has(content_id):
			return storage

	return null


static func _find_stock_source(
	tree: SceneTree,
	stock_item: ItemDefinition
) -> Node:
	if stock_item == null:
		return null

	for group: StringName in [&"stocked_display", &"stock_storage"]:
		for node: Node in tree.get_nodes_in_group(group):
			if not node.has_method(&"count_item"):
				continue

			# Accepting the item matters, not holding it right now - an empty
			# store is a stock problem, not a wiring problem.
			if node is StockedDisplay:
				var display := node as StockedDisplay

				if display.content_id == stock_item.provides_content_id:
					return node
			else:
				return node

	return null


static func _find_bar_counter(tree: SceneTree) -> BarCounter:
	for node: Node in tree.get_nodes_in_group(&"bar_counters"):
		return node as BarCounter

	return null
