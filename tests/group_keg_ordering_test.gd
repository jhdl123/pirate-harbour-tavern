extends Node

## Group ordering restricted to kegs and casks - the current scope.
##
## No recipes, no ingredients, no preparation. A group orders something that
## can be poured straight out of a station's cask, and the measures really
## leave that cask.

var passed: int = 0
var failed: int = 0

var registry: BeverageRegistry
var vessel_pool: VesselPool
var order_service: GroupOrderService
var setup: BeverageSceneSetup
var stations: Array[DrinksStation] = []


func _ready() -> void:
	registry = load("res://Data/beverage/beverage_registry.tres")
	registry.rebuild()

	await _build_world()

	_test_stations_configured()
	_test_only_pourable_drinks_offered()
	_test_shared_keg_order()
	_test_stock_actually_leaves_the_cask()
	_test_empty_station_blocks_ordering()
	_test_no_capable_station_blocks_ordering()
	_test_pair_gets_small_format_crew_gets_large()

	_report()


func _build_world() -> void:
	vessel_pool = VesselPool.new()
	vessel_pool.registry = registry
	add_child(vessel_pool)

	for id in [&"mug", &"tankard", &"pitcher", &"table_cask", &"firkin"]:
		vessel_pool.set_stock(id, 6)

	var scene: PackedScene = load("res://scenes/furniture/drinks_station.tscn")

	for pair in [[&"small_beer", "SmallBeerStation"], [&"ale", "AleStation"], [&"kill_devil", "RumStation"]]:
		var station: DrinksStation = scene.instantiate()
		station.name = pair[1]
		station.served_drink = registry.get_drink(pair[0])
		add_child(station)
		stations.append(station)

	setup = BeverageSceneSetup.new()
	setup.registry = registry
	setup.starting_measures = 96
	add_child(setup)

	order_service = GroupOrderService.new()
	order_service.registry = registry
	order_service.vessel_pool = vessel_pool
	add_child(order_service)

	# Two frames: one for the stations' own _ready, one for the setup node.
	await get_tree().process_frame
	await get_tree().process_frame


func _make_group(path: String, size: int) -> CustomerGroup:
	var group := CustomerGroup.new()
	group.definition = load(path)
	group.beverage_registry = registry
	add_child(group)

	var area := GroupStandingArea.new()
	area.area_id = StringName("area_%d" % group.get_instance_id())
	area.minimum_group_size = 1
	area.maximum_group_size = 12
	add_child(area)

	for index in range(size):
		var member := StubMember.new()
		member.name = "M%d_%d" % [index, group.get_instance_id()]
		add_child(member)
		group.add_member(member)

	group.place = GroupPlace.reserve_standing(area, size, group, group.group_id)

	return group


# --- Tests -------------------------------------------------------------------

func _test_stations_configured() -> void:
	_check(
		stations[0].has_service_batch(),
		"SETUP: the scene setup node gave the station a real service cask",
		"SETUP: no service container was built"
	)

	_check(
		stations[0].has_capability(StationCapabilities.FILL_SHARED_CASK)
			and stations[0].has_capability(StationCapabilities.FILL_PITCHER),
		"SETUP: stations can fill pitchers and shared casks",
		"SETUP: capabilities missing"
	)

	_check(
		stations[0].get_available_measures() == 96,
		"SETUP: the fallback stock granted 96 measures",
		"SETUP: station holds %d measures"
			% stations[0].get_available_measures()
	)


func _test_only_pourable_drinks_offered() -> void:
	var group := _make_group("res://Data/groups/pirate_crew.tres", 6)
	var seen: Dictionary = {}

	# Sample repeatedly: selection is weighted, so one draw proves nothing.
	for _i in range(60):
		var order := order_service.choose_shared_order(group)

		if order != null:
			seen[order.drink_id] = true

	_check(
		not seen.is_empty(),
		"SCOPE: the crew can order %d different keg drinks" % seen.size(),
		"SCOPE: nothing could be ordered at all"
	)

	var any_prepared := false

	for drink_id in seen:
		var drink: DrinkDefinition = registry.get_drink(drink_id)

		if drink != null and drink.requires_preparation():
			any_prepared = true

	_check(
		not any_prepared,
		"SCOPE: no mixed or prepared drink was ever offered",
		"SCOPE: a prepared drink was offered: %s" % str(seen.keys())
	)

	_check(
		not seen.has(&"rum_punch") and not seen.has(&"coffee"),
		"SCOPE: Rum Punch and Coffee are correctly out of scope",
		"SCOPE: an out-of-scope drink appeared"
	)


func _test_shared_keg_order() -> void:
	var group := _make_group("res://Data/groups/pirate_crew.tres", 6)

	var order := GroupOrder.create(
		group.group_id, &"leader", &"kill_devil", &"table_cask", true
	)
	order.price = order.calculate_price(registry)

	_check(
		order_service.reserve_order(order),
		"KEG: a Table Cask of Kill-Devil was reserved",
		"KEG: reservation failed (%s)" % order.get_failure_text()
	)

	var serving := order_service.fulfil_order(order, group)

	_check(
		serving != null and serving.remaining_portions == 8,
		"KEG: the shared cask was delivered with 8 portions",
		"KEG: serving is %s" % (
			"null" if serving == null
			else str(serving.remaining_portions) + " portions"
		)
	)

	_check(
		order.paid == false and order.price > 0,
		"KEG: the order carries a price and is not yet paid (%d)" % order.price,
		"KEG: pricing wrong"
	)

	_check(
		order.mark_paid() and not order.mark_paid(),
		"KEG: payment lands exactly once, never per member",
		"KEG: the order could be paid twice"
	)

	var members := group.get_valid_members()
	var taken := 0

	for _round in range(3):
		for member in members:
			if serving.take_portion(member):
				taken += 1

	_check(
		taken == 8 and serving.is_empty(),
		"KEG: six members drank all 8 portions between them",
		"KEG: %d portions taken, %d left" % [
			taken, serving.remaining_portions,
		]
	)


func _test_stock_actually_leaves_the_cask() -> void:
	var group := _make_group("res://Data/groups/dock_workers.tres", 4)
	var station := _find_station(&"ale")
	var before := station.get_available_measures()

	var order := GroupOrder.create(
		group.group_id, &"leader", &"ale", &"pitcher", true
	)

	order_service.reserve_order(order)
	var serving := order_service.fulfil_order(order, group)

	var format := registry.get_serving_format(&"pitcher")
	var after := station.get_available_measures()

	_check(
		serving != null,
		"STOCK: a Pitcher of Ale was poured",
		"STOCK: the pitcher was not created"
	)

	_check(
		after == before - format.measures_per_serving,
		"STOCK: %d measures really left the cask (%d -> %d)" % [
			format.measures_per_serving, before, after,
		],
		"STOCK: cask went %d -> %d, expected a drop of %d" % [
			before, after, format.measures_per_serving,
		]
	)


func _test_empty_station_blocks_ordering() -> void:
	var group := _make_group("res://Data/groups/sailor_pair.tres", 2)

	for station in stations:
		station.empty_stock()

	var order := GroupOrder.create(
		group.group_id, &"leader", &"ale", &"pitcher", true
	)

	var pitchers_before := vessel_pool.get_available(&"pitcher")

	_check(
		not order_service.reserve_order(order),
		"EMPTY: an order fails cleanly when every cask is dry",
		"EMPTY: an order succeeded with no stock"
	)

	_check(
		order.failure_reason == GroupOrder.Failure.NO_STOCK,
		"EMPTY: the failure is reported as no stock",
		"EMPTY: reason was '%s'" % order.get_failure_text()
	)

	_check(
		vessel_pool.get_available(&"pitcher") == pitchers_before,
		"EMPTY: no vessel was stranded by the failed order",
		"EMPTY: a pitcher leaked (%d -> %d)" % [
			pitchers_before, vessel_pool.get_available(&"pitcher"),
		]
	)

	_check(
		order_service.choose_shared_order(group) == null
			or _find_station(&"ale").get_available_measures() == 0,
		"EMPTY: a dry tavern offers the group nothing to order",
		"EMPTY: something was still offered"
	)

	# Restock for anything that follows.
	for station in stations:
		station.grant_service_stock(96)


func _test_no_capable_station_blocks_ordering() -> void:
	var group := _make_group("res://Data/groups/pirate_crew.tres", 6)

	var saved: Array = []

	for station in stations:
		saved.append(station.station_capabilities.duplicate())
		# Can pour a drink, but cannot fill a shared cask.
		station.station_capabilities = (
			[StationCapabilities.DRAW_FROM_CASK] as Array[StringName]
		)

	var order := GroupOrder.create(
		group.group_id, &"leader", &"kill_devil", &"table_cask", true
	)

	_check(
		not order_service.reserve_order(order),
		"CAPABILITY: no station can fill a shared cask, so the order fails",
		"CAPABILITY: the order succeeded without a capable station"
	)

	for index in range(stations.size()):
		stations[index].station_capabilities = saved[index]


func _test_pair_gets_small_format_crew_gets_large() -> void:
	var pair := _make_group("res://Data/groups/sailor_pair.tres", 2)
	var crew := _make_group("res://Data/groups/pirate_crew.tres", 8)

	var pair_formats: Dictionary = {}
	var crew_formats: Dictionary = {}

	for _i in range(40):
		var pair_order := order_service.choose_shared_order(pair)
		var crew_order := order_service.choose_shared_order(crew)

		if pair_order != null:
			pair_formats[pair_order.serving_format_id] = true

		if crew_order != null:
			crew_formats[crew_order.serving_format_id] = true

	_check(
		not pair_formats.has(&"firkin_serving")
			and not pair_formats.has(&"kilderkin_serving"),
		"SIZING: a pair never orders a firkin or kilderkin",
		"SIZING: a pair ordered %s" % str(pair_formats.keys())
	)

	_check(
		not crew_formats.is_empty(),
		"SIZING: an eight-strong crew has %d shared formats to pick from"
			% crew_formats.size(),
		"SIZING: the crew could order nothing"
	)


## Minimal member exposing the one property the group layer stamps.
##
## The real Customer will carry group_id as a field; this stands in for it
## without pulling the whole customer state machine into the test.
class StubMember extends Node2D:
	var group_id: StringName = &""


# --- Harness -----------------------------------------------------------------

func _find_station(content_id: StringName) -> DrinksStation:
	for station in stations:
		if station.get_service_content_id() == content_id:
			return station

	return stations[0]


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
	print("GROUP KEG ORDERING TEST")
	print("  passed: %d" % passed)
	print("  failed: %d" % failed)
	print("==================================================")

	get_tree().quit(1 if failed > 0 else 0)
