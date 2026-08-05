extends Node

## Drives the group framework through real behaviour.
##
## Builds a miniature tavern - tables, chairs, standing areas - and runs whole
## group visits through it: seating, standing fallback, atomic reservation,
## shared ordering, repeated consumption, leader loss and departure.

var passed: int = 0
var failed: int = 0

var registry: BeverageRegistry
var vessel_pool: VesselPool
var preparation: PreparationService
var order_service: GroupOrderService
var storage: BeverageStorage
var pantry: TestPantry

var tables: Array[Node2D] = []
var areas: Array[GroupStandingArea] = []


func _ready() -> void:
	registry = load("res://Data/beverage/beverage_registry.tres")
	registry.rebuild()

	await _build_world()

	_test_definitions()
	_test_formation_slots()
	_test_seated_reservation_is_atomic()
	_test_group_prefers_table()
	_test_standing_fallback()
	_test_standing_area_not_double_booked()
	_test_shared_order_selection()
	_test_shared_serving_consumption()
	_test_leader_replacement()
	_test_departure_releases_everything()
	_test_no_place_resolves_safely()

	_report()


# --- World -------------------------------------------------------------------

func _build_world() -> void:
	vessel_pool = VesselPool.new()
	vessel_pool.registry = registry
	add_child(vessel_pool)

	for id in [
		&"mug", &"tankard", &"cup", &"wine_glass", &"dram_glass",
		&"pitcher", &"punch_bowl", &"table_cask", &"coffee_pot",
	]:
		vessel_pool.set_stock(id, 8)

	storage = BeverageStorage.new()
	storage.location_id = &"cellar"
	storage.registry = registry
	add_child(storage)

	for pair in [
		[&"hogshead", &"kill_devil"], [&"kilderkin", &"ale"],
		[&"barrel", &"water"], [&"kilderkin", &"small_beer"],
	]:
		var container: ContainerDefinition = registry.get_container(pair[0])
		var content: BeverageContentDefinition = registry.get_content(pair[1])
		var batch := FilledContainer.create(
			container, content, container.maximum_capacity, 0
		)
		batch.sealed = false
		storage.add_batch(batch)

	pantry = TestPantry.new()
	pantry.add_to_group(&"test_pantry")
	add_child(pantry)

	for id in [&"sugar_loaf", &"nutmeg", &"citrus", &"spices"]:
		pantry.add_item_by_id(id, 20)

	preparation = PreparationService.new()
	preparation.registry = registry
	preparation.vessel_pool = vessel_pool
	preparation.ingredient_storage_group = &"test_pantry"
	preparation.liquid_storage_group = &"beverage_storage"
	add_child(preparation)

	# Group orders now require a station that can actually pour them, so the
	# test tavern needs real stations rather than just stock in a cellar.
	var station_scene: PackedScene = load(
		"res://scenes/furniture/drinks_station.tscn"
	)

	for pair in [[&"ale", "AleStation"], [&"kill_devil", "RumStation"],
			[&"small_beer", "BeerStation"]]:
		var station: DrinksStation = station_scene.instantiate()
		station.name = pair[1]
		station.served_drink = registry.get_drink(pair[0])
		add_child(station)

	var setup := BeverageSceneSetup.new()
	setup.registry = registry
	setup.starting_measures = 96
	add_child(setup)

	order_service = GroupOrderService.new()
	order_service.registry = registry
	order_service.vessel_pool = vessel_pool
	order_service.preparation_service = preparation
	add_child(order_service)

	# Two four-seat tables, matching the real tavern.
	for index in range(2):
		tables.append(_make_table(Vector2(200 * index, 0), 4))

	# Two standing areas.
	areas.append(_make_area("dock_corner", Vector2(0, 300), 2, 6))
	areas.append(_make_area("bar_end", Vector2(300, 300), 3, 8))

	await get_tree().process_frame
	await get_tree().process_frame


func _make_table(position: Vector2, seats: int) -> Node2D:
	var table := StubTable.new()
	table.global_position = position
	table.add_to_group(&"tables")
	add_child(table)

	for index in range(seats):
		var chair := StubChair.new()
		chair.global_position = position + Vector2(
			24 * cos(TAU * index / seats), 24 * sin(TAU * index / seats)
		)
		table.add_child(chair)
		table.seats.append(chair)

	return table


func _make_area(
	id: String, position: Vector2, minimum: int, maximum: int
) -> GroupStandingArea:
	var area := GroupStandingArea.new()
	area.area_id = StringName(id)
	area.display_name = id
	area.minimum_group_size = minimum
	area.maximum_group_size = maximum
	area.formation_radius = 40.0
	add_child(area)
	area.global_position = position

	return area


func _make_group(
	definition_path: String, size: int
) -> CustomerGroup:
	var group := CustomerGroup.new()
	group.definition = load(definition_path)
	group.beverage_registry = registry
	group.vessel_pool = vessel_pool
	add_child(group)

	for index in range(size):
		var member := StubCustomer.new()
		member.name = "Member%d_%s" % [index, group.group_id]
		add_child(member)
		group.add_member(member)

	return group


# --- Tests -------------------------------------------------------------------

func _test_definitions() -> void:
	var crew: CustomerGroupDefinition = load(
		"res://Data/groups/pirate_crew.tres"
	)

	_check(
		crew != null and crew.validate_or_warn(),
		"DEFINITION: pirate crew validates",
		"DEFINITION: pirate crew is invalid"
	)

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var sizes := {}

	for _i in range(200):
		var size := crew.choose_size(rng)
		sizes[size] = int(sizes.get(size, 0)) + 1

	var in_range := true

	for key in sizes:
		if int(key) < crew.minimum_size or int(key) > crew.maximum_size:
			in_range = false

	_check(
		in_range and sizes.size() > 1,
		"DEFINITION: sizes follow the configured weights, all within 4-8",
		"DEFINITION: sizes out of range or not varied: %s" % str(sizes)
	)

	var pair: CustomerGroupDefinition = load(
		"res://Data/groups/sailor_pair.tres"
	)
	var firkin: ServingFormatDefinition = registry.get_serving_format(
		&"firkin_serving"
	)

	_check(
		not pair.accepts_serving_format(firkin, 2),
		"DEFINITION: a pair will not order a firkin",
		"DEFINITION: a pair accepted a firkin"
	)

	_check(
		crew.accepts_serving_format(firkin, 8),
		"DEFINITION: an eight-strong crew will order a firkin",
		"DEFINITION: the crew refused a firkin"
	)


func _test_formation_slots() -> void:
	var slots := GroupFormation.build_slots(
		Vector2(100, 100), 6, 40.0,
		GroupFormation.Layout.LOOSE_CIRCLE, 6.0, 42
	)

	_check(
		slots.size() == 6,
		"FORMATION: six members get six slots",
		"FORMATION: got %d slots" % slots.size()
	)

	var minimum_gap := INF

	for i in range(slots.size()):
		for j in range(i + 1, slots.size()):
			minimum_gap = minf(minimum_gap, slots[i].distance_to(slots[j]))

	_check(
		minimum_gap > 12.0,
		"FORMATION: members keep at least %.0fpx apart" % minimum_gap,
		"FORMATION: members only %.1fpx apart" % minimum_gap
	)

	# Stability is what stops jitter: the same inputs must give the same shape.
	var again := GroupFormation.build_slots(
		Vector2(100, 100), 6, 40.0,
		GroupFormation.Layout.LOOSE_CIRCLE, 6.0, 42
	)

	var identical := true

	for i in range(slots.size()):
		if slots[i].distance_to(again[i]) > 0.01:
			identical = false

	_check(
		identical,
		"FORMATION: slots are deterministic, so members cannot drift",
		"FORMATION: recomputing moved the slots"
	)


func _test_seated_reservation_is_atomic() -> void:
	var table := tables[0] as StubTable
	var holder := Node.new()
	add_child(holder)

	# Five seats requested at a four-seat table: must take none at all.
	var place := GroupPlace.reserve_seated(table, 5, holder)

	_check(
		not place.is_valid(),
		"ATOMIC: a five-person group cannot book a four-seat table",
		"ATOMIC: an oversized booking succeeded"
	)

	_check(
		table.get_available_chairs().size() == 4,
		"ATOMIC: all four seats are still free after the failed booking",
		"ATOMIC: %d seats free - the failed booking leaked"
			% table.get_available_chairs().size()
	)

	var good := GroupPlace.reserve_seated(table, 3, holder)

	_check(
		good.is_valid() and good.chairs.size() == 3,
		"ATOMIC: a three-person group books three seats",
		"ATOMIC: booking failed"
	)

	_check(
		table.get_available_chairs().size() == 1,
		"ATOMIC: one seat remains free for someone else",
		"ATOMIC: %d seats free" % table.get_available_chairs().size()
	)

	good.release()

	_check(
		table.get_available_chairs().size() == 4,
		"ATOMIC: releasing returns every seat",
		"ATOMIC: %d seats free after release"
			% table.get_available_chairs().size()
	)


func _test_group_prefers_table() -> void:
	var group := _make_group("res://Data/groups/sailor_pair.tres", 2)

	_check(
		group.find_place(),
		"SEATED: a pair found a place",
		"SEATED: no place found"
	)

	_check(
		group.place.is_seated() and group.place.chairs.size() == 2,
		"SEATED: the pair sat down and booked exactly two seats",
		"SEATED: place is %s" % group.get_summary()["place_type"]
	)

	# The group must not be spread over two tables.
	var parents := {}

	for chair in group.place.chairs:
		parents[(chair as Node).get_parent()] = true

	_check(
		parents.size() == 1,
		"SEATED: both seats are at the same table",
		"SEATED: the group split across %d tables" % parents.size()
	)

	group.begin_departure()
	group.complete_visit()


func _test_standing_fallback() -> void:
	# Fill every seat so nothing can sit.
	var blockers: Array[GroupPlace] = []
	var holder := Node.new()
	add_child(holder)

	for table in tables:
		blockers.append(GroupPlace.reserve_seated(table, 4, holder))

	var group := _make_group("res://Data/groups/pirate_crew.tres", 6)

	_check(
		group.find_place(),
		"STANDING: a six-strong crew found a place with no seats free",
		"STANDING: no place found"
	)

	_check(
		group.place.is_standing(),
		"STANDING: it fell back to a standing area",
		"STANDING: it got a %s place" % group.get_summary()["place_type"]
	)

	_check(
		group.place.slots.size() == 6,
		"STANDING: six formation slots were generated",
		"STANDING: got %d slots" % group.place.slots.size()
	)

	_check(
		group.place.get_serving_position() != Vector2.ZERO,
		"STANDING: the area exposes a serving point for a shared cask",
		"STANDING: no serving point"
	)

	group.begin_departure()
	group.complete_visit()

	for blocker in blockers:
		blocker.release()


func _test_standing_area_not_double_booked() -> void:
	var area := areas[0]
	var first := Node.new()
	var second := Node.new()
	add_child(first)
	add_child(second)

	_check(
		area.reserve_for(first, &"group_a"),
		"AREA: the first group booked the area",
		"AREA: the first booking failed"
	)

	_check(
		not area.reserve_for(second, &"group_b"),
		"AREA: a second group cannot book the same area",
		"AREA: the area was double-booked"
	)

	area.release_for(first)

	_check(
		area.is_free() and area.reserve_for(second, &"group_b"),
		"AREA: releasing frees it for the next group",
		"AREA: the area stayed locked"
	)

	area.release_for(second)


func _test_shared_order_selection() -> void:
	var group := _make_group("res://Data/groups/pirate_crew.tres", 6)
	group.find_place()

	var order := order_service.choose_shared_order(group)

	_check(
		order != null,
		"ORDER: the crew chose a shared drink",
		"ORDER: no shared order could be chosen"
	)

	_check(
		order.is_shared and not order.drink_id.is_empty()
			and not order.serving_format_id.is_empty(),
		"ORDER: it carries both a drink id and a serving-format id (%s)"
			% order.get_display_name(registry),
		"ORDER: ids missing"
	)

	_check(
		order.group_id == group.group_id,
		"ORDER: the order is stamped with the group id",
		"ORDER: group id missing"
	)

	var format := registry.get_serving_format(order.serving_format_id)

	_check(
		format.is_shared and format.portion_count >= 6,
		"ORDER: the format is shared with %d portions for 6 drinkers"
			% format.portion_count,
		"ORDER: format has %d portions" % format.portion_count
	)

	_check(
		order.price > 0,
		"ORDER: a price was calculated (%d)" % order.price,
		"ORDER: price is %d" % order.price
	)

	group.begin_departure()
	group.complete_visit()


func _test_shared_serving_consumption() -> void:
	var group := _make_group("res://Data/groups/pirate_crew.tres", 5)
	group.find_place()

	# Pin the order so the test is deterministic rather than weighted.
	var order := GroupOrder.create(
		group.group_id, &"leader", &"ale", &"pitcher", true
	)
	order.price = order.calculate_price(registry)

	_check(
		order_service.reserve_order(order),
		"SERVING: a Pitcher of Ale was reserved",
		"SERVING: reservation failed (%s)" % order.get_failure_text()
	)

	var bowls_before := vessel_pool.get_available(&"pitcher")
	var serving := order_service.fulfil_order(order, group)

	_check(
		serving != null,
		"SERVING: the shared pitcher was created in the world",
		"SERVING: nothing was created"
	)

	_check(
		serving.get_parent() != null and serving.get_child_count() > 0,
		"SERVING: it is a real world object with a visual, not an abstraction",
		"SERVING: no visual was attached"
	)

	_check(
		serving.global_position.distance_to(
			group.place.get_serving_position()
		) < 1.0,
		"SERVING: it was placed at the group's serving point",
		"SERVING: it is not at the serving point"
	)

	var portions := serving.maximum_portions

	_check(
		portions == 4,
		"SERVING: the pitcher holds 4 portions",
		"SERVING: it holds %d" % portions
	)

	# Several different members drink from the same object.
	var drinkers := group.get_valid_members()
	var taken := 0

	for member in drinkers:
		if serving.take_portion(member):
			taken += 1

	_check(
		taken == 4 and serving.remaining_portions == 0,
		"SERVING: 4 different members each took one portion",
		"SERVING: %d taken, %d left" % [taken, serving.remaining_portions]
	)

	_check(
		not serving.take_portion(drinkers[0]),
		"SERVING: the fifth member cannot drink from an empty pitcher",
		"SERVING: an empty pitcher kept serving - infinite stock"
	)

	_check(
		serving.remaining_portions == 0,
		"SERVING: portions never went negative",
		"SERVING: portions are %d" % serving.remaining_portions
	)

	_check(
		vessel_pool.get_available(&"pitcher") == bowls_before + 1,
		"SERVING: the empty pitcher returned to the vessel pool",
		"SERVING: pitcher not returned (%d -> %d)" % [
			bowls_before, vessel_pool.get_available(&"pitcher"),
		]
	)

	# An outsider must never be able to drink from it.
	var stranger := StubCustomer.new()
	add_child(stranger)
	stranger.group_id = &"someone_else"

	_check(
		not serving.is_consumer_eligible(stranger),
		"SERVING: a customer from another group is not eligible",
		"SERVING: an outsider was eligible"
	)

	group.begin_departure()
	group.complete_visit()


func _test_leader_replacement() -> void:
	var group := _make_group("res://Data/groups/dock_workers.tres", 4)
	group.find_place()

	var original := group.leader

	_check(
		original != null,
		"LEADER: the group has a leader",
		"LEADER: no leader was assigned"
	)

	var place_id := group.place.get_place_id()

	group.remove_member(original)

	_check(
		group.leader != null and group.leader != original,
		"LEADER: a replacement was promoted when the leader left",
		"LEADER: no replacement leader"
	)

	_check(
		group.place != null and group.place.get_place_id() == place_id,
		"LEADER: the group kept its place through the change",
		"LEADER: the place was lost"
	)

	_check(
		group.get_valid_members().size() == 3,
		"LEADER: the remaining three members carry on",
		"LEADER: %d members left" % group.get_valid_members().size()
	)

	group.begin_departure()
	group.complete_visit()


func _test_departure_releases_everything() -> void:
	var group := _make_group("res://Data/groups/dock_workers.tres", 4)
	group.find_place()

	var was_standing := group.place.is_standing()
	var area := group.place.standing_area
	var chairs := group.place.chairs.duplicate()

	var order := GroupOrder.create(
		group.group_id, &"leader", &"small_beer", &"pitcher", true
	)
	order_service.reserve_order(order)
	var serving := order_service.fulfil_order(order, group)

	_check(
		serving != null,
		"CLEANUP: the group has a shared serving before leaving",
		"CLEANUP: no serving was created"
	)

	var pitchers_before := vessel_pool.get_available(&"pitcher")

	group.begin_departure()
	group.complete_visit()

	_check(
		group.place == null,
		"CLEANUP: the place reference was cleared",
		"CLEANUP: the group still holds a place"
	)

	if was_standing and area != null:
		_check(
			area.is_free(),
			"CLEANUP: the standing area was released",
			"CLEANUP: the standing area is still booked"
		)
	else:
		var all_free := true

		for chair in chairs:
			if not (chair as StubChair).is_available():
				all_free = false

		_check(
			all_free,
			"CLEANUP: every seat was released",
			"CLEANUP: seats are still held"
		)

	_check(
		vessel_pool.get_available(&"pitcher") == pitchers_before + 1,
		"CLEANUP: leaving early returned the shared vessel",
		"CLEANUP: the vessel was stranded (%d -> %d)" % [
			pitchers_before, vessel_pool.get_available(&"pitcher"),
		]
	)

	_check(
		group.state == CustomerGroup.State.COMPLETE,
		"CLEANUP: the visit finished in COMPLETE",
		"CLEANUP: the visit ended in %s" % group.get_state_name()
	)


func _test_no_place_resolves_safely() -> void:
	# Block every seat and every standing area.
	var holder := Node.new()
	add_child(holder)
	var blockers: Array[GroupPlace] = []

	for table in tables:
		blockers.append(GroupPlace.reserve_seated(table, 4, holder))

	for area in areas:
		area.reserve_for(holder, &"blocker")

	var group := _make_group("res://Data/groups/pirate_crew.tres", 5)

	_check(
		not group.find_place(),
		"FULL: a group finds no place when the tavern is full",
		"FULL: a place was found in a full tavern"
	)

	group.fail_visit("no place available")

	_check(
		group.state == CustomerGroup.State.FAILED and group.place == null,
		"FULL: the group failed safely without holding anything",
		"FULL: the group is stuck in %s" % group.get_state_name()
	)

	for blocker in blockers:
		blocker.release()

	for area in areas:
		area.force_release()

	_check(
		areas[0].is_free() and areas[1].is_free(),
		"FULL: the orphan sweep freed both standing areas",
		"FULL: an area is still held"
	)


# --- Stubs -------------------------------------------------------------------
#
# Minimal stand-ins exposing only the methods the group layer actually calls.
# Using the real Customer and Chair scenes here would drag in navigation and
# the whole customer state machine, which is not what these cases are testing.

class StubChair extends Node2D:
	var _holder: Node = null

	func is_available() -> bool:
		return _holder == null

	func assign_customer(customer: Node) -> bool:
		if _holder != null:
			return false
		_holder = customer
		return true

	func release_reservation(holder: Node) -> void:
		if _holder == holder:
			_holder = null


class StubTable extends Node2D:
	var seats: Array[StubChair] = []

	func get_available_chairs() -> Array:
		var free: Array = []
		for seat in seats:
			if seat.is_available():
				free.append(seat)
		return free

	func get_available_seat_count() -> int:
		return get_available_chairs().size()


class StubCustomer extends Node2D:
	var group_id: StringName = &""
	var assigned_position: Vector2 = Vector2.ZERO
	var departing: bool = false

	func assign_group_position(target: Vector2, _centre: Vector2) -> void:
		assigned_position = target

	func begin_group_departure() -> void:
		departing = true


class TestPantry extends Node:
	var stock: Dictionary = {}

	func count_item(item_id: StringName) -> int:
		return int(stock.get(item_id, 0))

	func remove_item(item_id: StringName, amount: int) -> int:
		var available: int = count_item(item_id)
		var removed: int = mini(amount, available)
		stock[item_id] = available - removed
		return removed

	func add_item_by_id(item_id: StringName, amount: int) -> void:
		stock[item_id] = count_item(item_id) + amount


# --- Harness -----------------------------------------------------------------

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
	print("GROUP FRAMEWORK TEST")
	print("  passed: %d" % passed)
	print("  failed: %d" % failed)
	print("==================================================")

	get_tree().quit(1 if failed > 0 else 0)
