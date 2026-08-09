extends Node2D

## Verifies the storeroom/back-bar refactor against the live main.tscn.
##
## Checks the three things a static read cannot: that the converted props sit
## at the same world positions the loose sprites did, that the three stations
## resolve their drinks, and that the new colliders have not cut the storeroom
## off the navmesh.

const EXPECTED_UNITS: Dictionary = {
	"Environment/BackBar/BrandyShelf": [
		Vector2(550, 31), Vector2(557, 31), Vector2(565, 31),
		Vector2(572, 31), Vector2(579, 31), Vector2(586, 31),
	],
	"Environment/BackBar/MadeiraShelf": [
		Vector2(550, 53), Vector2(559, 53), Vector2(568, 52),
		Vector2(577, 53), Vector2(586, 53),
	],
	"Environment/BackBar/PortWineShelf": [
		Vector2(607, 31), Vector2(616, 31), Vector2(626, 31),
		Vector2(635, 31), Vector2(644, 31),
	],
	"Environment/BackBar/CanaryWineShelf": [
		Vector2(607, 53), Vector2(615, 53), Vector2(624, 53),
		Vector2(633, 53), Vector2(643, 53),
	],
	"Environment/Storeroom/GrogCaskStack": [
		Vector2(867, 65), Vector2(898, 66), Vector2(883, 43), Vector2(929, 65),
		Vector2(913, 41), Vector2(869, 82), Vector2(900, 83), Vector2(885, 60),
		Vector2(931, 82), Vector2(915, 58),
	],
	"Environment/Storeroom/SmallBeerCaskStack": [
		Vector2(976, 62), Vector2(1007, 63), Vector2(992, 40), Vector2(1038, 62),
		Vector2(1022, 38), Vector2(994, 75), Vector2(1025, 76),
	],
	"Environment/Storeroom/CiderCaskStack": [
		Vector2(1027, 132), Vector2(1054, 128), Vector2(1085, 127),
		Vector2(1071, 104), Vector2(1055, 139), Vector2(1086, 140),
		Vector2(1071, 117),
	],
}

const EXPECTED_CRATES: Dictionary = {
	"Environment/Storeroom/WineCrate1": Vector2(868, 163),
	"Environment/Storeroom/WineCrate2": Vector2(900, 164),
	"Environment/Storeroom/WineCrate3": Vector2(868, 192),
	"Environment/Storeroom/WineCrate4": Vector2(900, 193),
}

## Ale is retired from normal service; Small Beer took its stand.
## refill_item is DERIVED from the poured content now, so these also assert
## that no station inherited the base scene's grog barrel.
const EXPECTED_STATIONS: Dictionary = {
	"Environment/SmallBeer_station": ["small_beer", Vector2(403, 49), "small_beer_cask"],
	"Environment/Grog_station": ["grog", Vector2(356, 80), "grog_barrel"],
	"Environment/Cider_station": ["cider", Vector2(461, 49), "cider_cask"],
}

var passed: int = 0
var failed: int = 0
var main: Node = null


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main/main.tscn")
	main = packed.instantiate()
	add_child(main)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout

	_check_unit_positions()
	_check_crates()
	_check_stations()
	_check_no_leftovers()
	_check_collision()
	_check_navmesh()
	_check_stock_display_api()

	print("RESULT %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("[PASS] %s" % label)
	else:
		failed += 1
		print("[FAIL] %s %s" % [label, detail])


func _check_unit_positions() -> void:
	for path: String in EXPECTED_UNITS:
		var node: Node2D = main.get_node_or_null(NodePath(path))

		if node == null:
			_ok("%s exists" % path, false)
			continue

		var units: Node = node.get_node_or_null(^"Units")
		var expected: Array = EXPECTED_UNITS[path]

		if units == null or units.get_child_count() != expected.size():
			_ok("%s unit count" % path, false, "got %d want %d" % [
				0 if units == null else units.get_child_count(), expected.size()
			])
			continue

		var worst: float = 0.0

		for i: int in range(expected.size()):
			var sprite: Sprite2D = units.get_child(i) as Sprite2D
			worst = maxf(worst, sprite.global_position.distance_to(expected[i]))

		_ok("%s units at original positions" % path, worst < 0.01,
			"worst drift %.3fpx" % worst)


func _check_crates() -> void:
	for path: String in EXPECTED_CRATES:
		var node: Node2D = main.get_node_or_null(NodePath(path))

		if node == null:
			_ok("%s exists" % path, false)
			continue

		_ok("%s at original position" % path,
			node.global_position.distance_to(EXPECTED_CRATES[path]) < 0.01,
			"at %s" % node.global_position)


func _check_stations() -> void:
	for path: String in EXPECTED_STATIONS:
		var station: DrinksStation = main.get_node_or_null(NodePath(path)) as DrinksStation
		var want: Array = EXPECTED_STATIONS[path]

		if station == null:
			_ok("%s exists" % path, false)
			continue

		_ok("%s serves %s" % [path, want[0]],
			station.served_drink != null and station.served_drink.item_id == StringName(want[0]),
			"got %s" % ("null" if station.served_drink == null else station.served_drink.item_id))

		_ok("%s position unchanged" % path,
			station.global_position.distance_to(want[1]) < 0.01,
			"at %s" % station.global_position)

		_ok("%s refills from %s" % [path, want[2]],
			station.refill_item != null and station.refill_item.item_id == StringName(want[2]),
			"got %s" % ("null" if station.refill_item == null else station.refill_item.item_id))

		_ok("%s has service stock" % path, station.current_servings > 0,
			"servings %d" % station.current_servings)

	# Three cask stations, a small beer tap on the ale stand, four bottle
	# services on the shelves.
	# Three poured stands (grog, cider, small beer) plus four bottle services.
	_ok("seven drink stations",
		get_tree().get_nodes_in_group(&"drink_stations").size() == 7,
		"found %d" % get_tree().get_nodes_in_group(&"drink_stations").size())

	_ok("no Ale station remains",
		main.get_node_or_null(^"Environment/Ale_station") == null)

	# Stations are free to use different sprites - the grog stand uses the
	# medium barrel art. What matters is that every one HAS a sprite.
	for node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation
		_ok("%s has a sprite" % station.name,
			station.sprite != null and station.sprite.texture != null)


func _check_no_leftovers() -> void:
	var stray: Array[String] = []

	for child: Node in main.get_children():
		if child is Sprite2D:
			stray.append(child.name)

	_ok("no loose sprites left on the scene root", stray.is_empty(),
		"found %s" % str(stray))

	var managers: Node = main.get_node_or_null(^"Managers")
	var manager_props: Array[String] = []

	if managers != null:
		for child: Node in managers.get_children():
			if child is Node2D or child.name.begins_with("Node"):
				manager_props.append(child.name)

	_ok("no props left under Managers", manager_props.is_empty(),
		"found %s" % str(manager_props))

	_ok("Grog_station3 is gone",
		main.get_node_or_null(^"Environment/Grog_station3") == null)


func _check_collision() -> void:
	for path: String in EXPECTED_UNITS:
		var body: StaticBody2D = main.get_node_or_null(NodePath(path)) as StaticBody2D

		if body == null:
			continue

		var shape_node: CollisionShape2D = body.get_node_or_null(^"CollisionShape2D")
		var rect: RectangleShape2D = null if shape_node == null else shape_node.shape as RectangleShape2D

		_ok("%s has collision" % path, rect != null and rect.size.x > 0.0,
			"shape %s" % str(rect))

	# The three stacks must not share one resized shape.
	var grog: StaticBody2D = main.get_node_or_null(^"Environment/Storeroom/GrogCaskStack")
	var ale: StaticBody2D = main.get_node_or_null(^"Environment/Storeroom/SmallBeerCaskStack")
	var g_rect: RectangleShape2D = grog.get_node(^"CollisionShape2D").shape
	var a_rect: RectangleShape2D = ale.get_node(^"CollisionShape2D").shape
	_ok("cask stacks own separate collision shapes", g_rect != a_rect and g_rect.size != a_rect.size,
		"%s vs %s" % [g_rect.size, a_rect.size])


func _check_navmesh() -> void:
	var region: NavigationRegion2D = main.get_node_or_null(^"NavigationRegion2D")
	_ok("navigation region present", region != null)

	if region == null:
		return

	var map: RID = region.get_navigation_map()

	# Points that must stay walkable: the storeroom floor, the aisle in front
	# of the cask stacks, and the bar service side.
	var must_reach: Dictionary = {
		"storeroom floor": Vector2(950, 250),
		"aisle below cask stacks": Vector2(1000, 180),
		"behind the bar": Vector2(500, 100),
		"main floor": Vector2(600, 400),
	}

	for label: String in must_reach:
		var want: Vector2 = must_reach[label]
		var got: Vector2 = NavigationServer2D.map_get_closest_point(map, want)
		_ok("%s still on the navmesh" % label,
			not got.is_zero_approx() and got.distance_to(want) < 24.0,
			"nearest mesh point %s (%.1fpx away)" % [got, got.distance_to(want)])

	# And a route across the storeroom must still exist.
	var path: PackedVector2Array = NavigationServer2D.map_get_path(
		map, Vector2(600, 400), Vector2(950, 250), true
	)
	_ok("route from the floor into the storeroom exists", path.size() >= 2,
		"%d waypoints" % path.size())


func _check_stock_display_api() -> void:
	var shelf: StockedDisplay = main.get_node_or_null(^"Environment/BackBar/BrandyShelf")

	if shelf == null:
		_ok("brandy shelf is a StockedDisplay", false)
		return

	# The shelf now mirrors its service station, which starts stocked - so a
	# full shelf at load is correct.
	_ok("a shelf starts showing its station's bottles",
		not shelf.mirror_station.is_empty()
		and shelf.get_visible_units() == shelf.get_unit_capacity(),
		"%d of %d" % [shelf.get_visible_units(), shelf.get_unit_capacity()])

	shelf.set_visible_units(2)
	var units: Node = shelf.get_node(^"Units")
	var shown: int = 0

	for child: Node in units.get_children():
		if (child as Sprite2D).visible:
			shown += 1

	_ok("taking bottles hides them from the end", shown == 2, "%d visible" % shown)

	shelf.set_visible_units(-1)
	shown = 0

	for child: Node in units.get_children():
		if (child as Sprite2D).visible:
			shown += 1

	_ok("restocking shows them again", shown == shelf.get_unit_capacity(),
		"%d visible" % shown)

	# And the station drives the same visual: pour a bottle, lose a bottle.
	var service: DrinksStation = shelf.get_node_or_null(^"BrandyService")

	if service != null:
		service.set_servings(3)
		await get_tree().process_frame
		_ok("pouring down to three leaves three on the shelf",
			shelf.get_visible_units() == 3, "showing %d" % shelf.get_visible_units())
