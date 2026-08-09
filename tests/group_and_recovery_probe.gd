extends Node2D

## Covers the two blockers: group shared service, and the bartender getting
## permanently stuck holding a bottle.
##
## Both are reproduced against the live main.tscn rather than against helper
## methods, because both were configuration faults that every unit-level test
## in the project happily passed through.

var passed: int = 0
var failed: int = 0
var main: Node = null


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout

	_check_no_active_ale()
	_check_group_order_selection()
	_check_order_catalogue()
	await _check_bounded_recovery()

	print("RESULT %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("[PASS] %s" % label)
	else:
		failed += 1
		print("[FAIL] %s %s" % [label, detail])


# --- Groups ------------------------------------------------------------------

func _get_order_service() -> Node:
	var nodes: Array = get_tree().get_nodes_in_group(&"group_order_service")

	return null if nodes.is_empty() else nodes[0]


func _check_no_active_ale() -> void:
	var service: Node = _get_order_service()

	_ok("group order service exists", service != null)

	if service == null:
		return

	_ok("forced group drink is no longer ale",
		service.forced_drink_id != &"ale",
		"forced_drink_id = %s" % String(service.forced_drink_id))

	_ok("forced group drink is small beer",
		service.forced_drink_id == &"small_beer",
		"got %s" % String(service.forced_drink_id))

	var keg_nodes: Array = get_tree().get_nodes_in_group(&"group_keg_stock_service")
	_ok("group keg stock service exists", not keg_nodes.is_empty())

	if keg_nodes.is_empty():
		return

	var keg_item: ItemDefinition = keg_nodes[0].get_keg_item()

	_ok("group keg item is the small beer keg",
		keg_item != null and keg_item.item_id == &"small_beer_table_keg",
		"got %s" % ("<null>" if keg_item == null else String(keg_item.item_id)))

	_ok("group keg carries the small beer drink id",
		keg_item != null
		and keg_item.default_metadata.get("drink_id", &"") == &"small_beer",
		"metadata %s" % ("{}" if keg_item == null else str(keg_item.default_metadata)))


func _check_group_order_selection() -> void:
	var service: Node = _get_order_service()
	var registry: BeverageRegistry = service.registry

	# The exact pairing the forced path asks for must be servable, which is
	# what stopped working: small_beer had no table_cask format at all.
	var small_beer: DrinkDefinition = registry.get_drink(&"small_beer")

	_ok("small beer supports the shared table cask",
		small_beer != null and small_beer.allows_serving_format(&"table_cask"),
		"formats %s" % ("[]" if small_beer == null else str(small_beer.serving_format_ids)))

	var format: ServingFormatDefinition = registry.get_serving_format(&"table_cask")
	var station: DrinksStation = service.find_capable_station(small_beer, format, false)

	_ok("a station can fill a small beer table cask",
		station != null,
		"no capable station" if station == null else "")

	# And the whole selection path, which is what the group actually calls.
	for size: int in [2, 4, 6]:
		var group := _make_probe_group(size)
		var order = service.choose_shared_order(group)

		_ok("group of %d gets a shared order" % size, order != null,
			"failure: %s" % service.last_selection_failure)

		if order != null:
			_ok("group of %d orders small beer" % size,
				order.drink_id == &"small_beer",
				"got %s" % String(order.drink_id))
			_ok("group of %d orders a table cask" % size,
				order.serving_format_id == &"table_cask",
				"got %s" % String(order.serving_format_id))

		group.free()


func _make_probe_group(size: int) -> CustomerGroup:
	var group := CustomerGroup.new()
	add_child(group)
	group.definition = load("res://Data/groups/dock_workers.tres")

	var members: Array[Node] = []

	for i: int in range(size):
		var customer: Customer = (
			load("res://scenes/customers/customer.tscn").instantiate()
		)
		group.add_child(customer)
		customer.customer_type = load("res://resources/CustomerTypes/sailor.tres")
		members.append(customer)

	group.members = members

	return group


# --- Order ledger ------------------------------------------------------------

func _check_order_catalogue() -> void:
	var supplier: SupplierDefinition = load(
		"res://Data/suppliers/harbour_supplies.tres"
	)

	_ok("supplier catalogue loads", supplier != null and not supplier.entries.is_empty())

	if supplier == null:
		return

	var contents: Array[String] = []
	var item_ids: Array[String] = []

	for entry: OrderCatalogueEntry in supplier.entries:
		if entry.is_filled_container():
			contents.append(String(entry.content_id))
		elif entry.item != null:
			item_ids.append(String(entry.item.item_id))

	print("  orderable contents: %s" % str(contents))
	print("  orderable items:    %s" % str(item_ids))

	for wanted: String in [
		"kill_devil", "cider", "small_beer",
		"port_wine", "canary_wine", "madeira", "brandy",
	]:
		_ok("%s is orderable" % wanted, contents.has(wanted))

	_ok("ale stock is no longer orderable", not item_ids.has("ale_keg"),
		"items %s" % str(item_ids))

	_ok("the group keg is orderable",
		item_ids.has("small_beer_table_keg"), "items %s" % str(item_ids))

	# Filled-container entries are what route a delivery to the storeroom
	# props; plain items land in the legacy singleton and stay invisible.
	var container_entries: int = 0

	for entry: OrderCatalogueEntry in supplier.entries:
		if entry.is_filled_container():
			container_entries += 1

	_ok("drink stock is ordered as filled containers", container_entries >= 7,
		"only %d" % container_entries)


# --- Bartender recovery ------------------------------------------------------

func _find_bartender() -> StaffMember:
	# Roles live on StaffDefinition capabilities, not on the member.
	for node in get_tree().get_nodes_in_group(&"tavern_staff"):
		var staff := node as StaffMember

		if (
			staff != null
			and staff.definition != null
			and staff.definition.capabilities.has(&"prepare_drinks")
		):
			return staff

	for node in get_tree().get_nodes_in_group(&"tavern_staff"):
		return node as StaffMember

	return null


func _check_bounded_recovery() -> void:
	var bartender: StaffMember = _find_bartender()

	if bartender == null:
		_ok("a bartender exists", false)
		return

	var policy: CarriedItemPolicy = bartender._get_carried_item_policy()

	_ok("policy bounds recovery attempts",
		policy.maximum_recovery_attempts > 0,
		"got %d" % policy.maximum_recovery_attempts)

	# Reproduce the reported failure: holding a bottle with every shelf full
	# and every bar slot occupied, so nothing will take it.
	for node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station := node as DrinksStation

		if station != null:
			station.set_servings(station.maximum_servings)

	for node in get_tree().get_nodes_in_group(&"bar_counters"):
		var counter := node as BarCounter

		if counter != null and counter.has_method("fill_all_slots_for_test"):
			counter.fill_all_slots_for_test()

	var port_wine: ItemDefinition = load("res://Data/beverage/drinks/port_wine.tres")
	bartender.item_carrier.clear_carried_item()
	bartender.reset_carried_recovery()
	bartender.item_carrier.give(ItemStack.create(port_wine, 1))

	_ok("bartender is holding port wine",
		bartender.item_carrier.is_carrying_item(&"port_wine"))

	# Run long enough that an unbounded loop would show itself many times over.
	var recovering_samples: int = 0

	for i: int in range(120):
		await get_tree().create_timer(0.1).timeout

		if bartender.current_state == StaffMember.State.RECOVERING_ITEM:
			recovering_samples += 1

	_ok("bartender is not stuck in RECOVERING_ITEM",
		bartender.current_state != StaffMember.State.RECOVERING_ITEM,
		"state = %s" % StaffMember.State.keys()[bartender.current_state])

	_ok("recovery did not churn for the whole window",
		recovering_samples < 60,
		"%d of 120 samples in RECOVERING_ITEM" % recovering_samples)

	_ok("recovery was bounded, not retried forever",
		bartender._carried_recovery_attempts <= policy.maximum_recovery_attempts,
		"%d attempts" % bartender._carried_recovery_attempts)

	# The bottle must still exist somewhere - carried or put down, never gone.
	var still_held: bool = bartender.item_carrier.is_carrying_item(&"port_wine")
	_ok("the bottle was not silently destroyed",
		still_held or bartender._carried_item_recoveries > 0,
		"held=%s recoveries=%d" % [still_held, bartender._carried_item_recoveries])
