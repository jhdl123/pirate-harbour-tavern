extends Node2D

## Verifies the drinks-system pass against the live main.tscn.
##
## Three things a static read cannot confirm: that the weighted draw actually
## produces the authored distribution, that serving formats resolve (and that
## solo customers never resolve a shared one), and that a delivery routed into
## a storeroom prop changes what the player sees on the shelf.

const CASK_MEASURES: Dictionary = {
	"firkin": 72, "kilderkin": 144, "barrel": 288,
	"hogshead": 432, "puncheon": 600, "pipe": 864,
}

## Drinks each type must be capable of ordering, from Joe's table.
## Drinks each type must be capable of ordering.
##
## Coffee and the mixed drinks were cut because nothing can make them; the
## grog station dispenses the `grog` item, so `kill_devil` (a second
## DrinkDefinition sharing the same content) is not what gets ordered.
const EXPECTED_MENU: Dictionary = {
	"local_worker":     ["small_beer", "grog"],
	"sailor":           ["small_beer", "cider", "grog"],
	"pirate":           ["grog", "cider", "small_beer"],
	"captain":          ["madeira", "brandy"],
	"merchant":         ["madeira", "port_wine"],
	"naval_officer":    ["madeira", "port_wine", "brandy"],
	"plantation_owner": ["madeira", "brandy", "canary_wine"],
}

var passed: int = 0
var failed: int = 0
var main: Node = null
var registry: BeverageRegistry = null


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout

	registry = main.get_node(^"Managers/Cellar").registry

	_check_cask_capacities()
	_check_container_locations()
	_check_customer_roster()
	_check_menus()
	_check_weighted_distribution()
	_check_serving_formats()
	_check_storage_props()
	_check_delivery_routing()

	print("RESULT %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("[PASS] %s" % label)
	else:
		failed += 1
		print("[FAIL] %s %s" % [label, detail])


# --- Containers --------------------------------------------------------------

func _check_cask_capacities() -> void:
	for container_id: String in CASK_MEASURES:
		var container: ContainerDefinition = registry.get_container(
			StringName(container_id)
		)

		if container == null:
			_ok("%s exists" % container_id, false)
			continue

		_ok("%s holds %d measures" % [container_id, CASK_MEASURES[container_id]],
			container.maximum_capacity == CASK_MEASURES[container_id],
			"got %d" % container.maximum_capacity)


func _check_container_locations() -> void:
	var expected: Dictionary = {
		"kilderkin": "bar_storage",
		"hogshead": "cellar_storage",
		"puncheon": "cellar_storage",
		"pipe": "cellar_storage",
	}

	for container_id: String in expected:
		var container: ContainerDefinition = registry.get_container(
			StringName(container_id)
		)
		_ok("%s is tagged %s" % [container_id, expected[container_id]],
			container != null
			and container.typical_storage_tags.has(StringName(expected[container_id])),
			"tags %s" % str(container.typical_storage_tags if container else []))


# --- Customer types ----------------------------------------------------------

func _get_types() -> Array:
	return main.get_node(^"Managers/GameManager").customer_types


func _find_type(type_id: String) -> CustomerType:
	for customer_type: CustomerType in _get_types():
		if customer_type != null and customer_type.type_id == StringName(type_id):
			return customer_type

	return null


func _check_customer_roster() -> void:
	_ok("eight customer types are registered", _get_types().size() == 8,
		"found %d" % _get_types().size())

	for type_id: String in ["naval_officer", "plantation_owner"]:
		_ok("%s is in the roster" % type_id, _find_type(type_id) != null)

	var officer: CustomerType = _find_type("naval_officer")
	_ok("naval officer carries the 'official' tag merchants react to",
		officer != null and officer.tags.has(&"official"))

	var merchant: CustomerType = _find_type("merchant")
	_ok("merchant's 'official' affinity now resolves to a real type",
		merchant != null and merchant.compatible_tags.has(&"official")
		and officer != null and officer.tags.has(&"official"))


func _check_menus() -> void:
	for type_id: String in EXPECTED_MENU:
		var customer_type: CustomerType = _find_type(type_id)

		if customer_type == null:
			_ok("%s exists" % type_id, false)
			continue

		_ok("%s uses the weighted model" % type_id,
			customer_type.uses_weighted_preferences())

		var ids: Array[String] = []

		for drink: DrinkDefinition in customer_type.get_orderable_drinks():
			ids.append(String(drink.item_id))

		var missing: Array = []

		for wanted: String in EXPECTED_MENU[type_id]:
			if not ids.has(wanted):
				missing.append(wanted)

		_ok("%s can order %s" % [type_id, str(EXPECTED_MENU[type_id])],
			missing.is_empty(), "missing %s (has %s)" % [str(missing), str(ids)])


func _check_weighted_distribution() -> void:
	# The pirate's entries are 5.0 / 3.0 / 1.5, so grog must dominate.
	# Sampling the real customer method, not re-implementing the maths here.
	var customer: Customer = _spawn_probe_customer("pirate")

	if customer == null:
		_ok("pirate probe customer spawned", false)
		return

	var counts: Dictionary = {}

	for i: int in range(600):
		var drink: DrinkDefinition = customer.choose_drink_from_customer_type()

		if drink == null:
			continue

		var key: String = String(drink.item_id)
		counts[key] = int(counts.get(key, 0)) + 1

	_ok("pirate draws all three of its drinks", counts.size() >= 3,
		"got %s" % str(counts))

	var grog: int = int(counts.get("grog", 0))
	var cider: int = int(counts.get("cider", 0))

	_ok("grog is the pirate's most common order",
		grog > cider, "grog %d vs cider %d" % [grog, cider])

	# Weight 5.0 of 9.5 total is ~53%; allow a wide band for sampling noise.
	var share: float = float(grog) / 600.0
	_ok("grog share is near its authored weight",
		share > 0.35 and share < 0.70, "share %.2f" % share)

	customer.queue_free()


func _check_serving_formats() -> void:
	var captain: Customer = _spawn_probe_customer("captain")
	var labourer: Customer = _spawn_probe_customer("local_worker")

	if captain == null or labourer == null:
		_ok("format probe customers spawned", false)
		return

	var madeira: DrinkDefinition = registry.get_drink(&"madeira")
	var small_beer: DrinkDefinition = registry.get_drink(&"small_beer")

	_ok("captain takes madeira by the bottle",
		captain.choose_serving_format_for(madeira) == &"bottle_serving",
		"got %s" % captain.choose_serving_format_for(madeira))

	_ok("dock labourer takes small beer in a tankard",
		labourer.choose_serving_format_for(small_beer) == &"tankard",
		"got %s" % labourer.choose_serving_format_for(small_beer))

	# A bottle costs more than a tankard - the whole point of the format.
	captain.ordered_serving_format_id = &"bottle_serving"
	_ok("bottle serving raises the price",
		captain.get_serving_format_price_modifier() > 1.0,
		"modifier %.2f" % captain.get_serving_format_price_modifier())

	# Solo customers must never resolve a shared format.
	var punch: DrinkDefinition = registry.get_drink(&"rum_punch")
	var pirate: Customer = _spawn_probe_customer("pirate")
	_ok("a lone pirate does not resolve a punch bowl",
		pirate != null and pirate.choose_serving_format_for(punch).is_empty(),
		"got %s" % (pirate.choose_serving_format_for(punch) if pirate else "<null>"))

	captain.queue_free()
	labourer.queue_free()

	if pirate != null:
		pirate.queue_free()


func _spawn_probe_customer(type_id: String) -> Customer:
	var customer_type: CustomerType = _find_type(type_id)

	if customer_type == null:
		return null

	var customer: Customer = (
		load("res://scenes/customers/customer.tscn").instantiate()
	)
	add_child(customer)
	customer.customer_type = customer_type
	customer.payment_multiplier = customer_type.payment_multiplier

	return customer


# --- Storage -----------------------------------------------------------------

func _get_props() -> Array[StockedDisplay]:
	var props: Array[StockedDisplay] = []

	for node in get_tree().get_nodes_in_group(&"stocked_display"):
		var prop := node as StockedDisplay

		if prop != null:
			props.append(prop)

	return props


func _check_storage_props() -> void:
	var backed: int = 0

	for prop: StockedDisplay in _get_props():
		if prop.storage_backed:
			backed += 1
			_ok("%s owns a storage location" % prop.name,
				prop.get_storage() != null)
			_ok("%s only accepts its own content" % prop.name,
				prop.get_storage() != null
				and prop.get_storage().accepted_content_ids == [prop.content_id],
				"accepts %s" % str(prop.get_storage().accepted_content_ids if prop.get_storage() else []))

	# Only the bulk cask stacks own storage now. The back-bar shelves display
	# their service station's bottles instead, so there is one source of truth
	# for what is on the shelf.
	# Three cask stacks plus four drink-specific wine crates now hold real
	# stock; the back-bar shelves mirror their service station instead.
	_ok("seven storeroom props are storage-backed", backed == 7, "found %d" % backed)

	for shelf_name: String in ["MadeiraShelf", "BrandyShelf"]:
		var shelf: StockedDisplay = main.get_node_or_null(
			NodePath("Environment/BackBar/%s" % shelf_name)
		)
		_ok("%s mirrors a service station" % shelf_name,
			shelf != null and not shelf.mirror_station.is_empty() and not shelf.storage_backed)

	# Empty stores show nothing - that is the visible signal the player reads.
	var beer: StockedDisplay = main.get_node_or_null(
		^"Environment/Storeroom/SmallBeerCaskStack"
	)
	_ok("an empty small beer stack shows no casks",
		beer != null and beer.get_visible_units() == 0,
		"showing %d" % (beer.get_visible_units() if beer else -1))


func _check_delivery_routing() -> void:
	var beer: StockedDisplay = main.get_node_or_null(
		^"Environment/Storeroom/SmallBeerCaskStack"
	)
	var cellar: BeverageStorage = main.get_node_or_null(^"Managers/Cellar")

	if beer == null or cellar == null:
		_ok("routing fixtures present", false)
		return

	var kilderkin: ContainerDefinition = registry.get_container(&"kilderkin")

	# Two casks of small beer land in the small beer stack, not the Cellar.
	for i: int in range(2):
		var batch := FilledContainer.new()
		batch.container = kilderkin
		batch.content_id = &"small_beer"
		batch.quantity = kilderkin.maximum_capacity

		_ok("small beer stack accepts small beer cask %d" % (i + 1),
			beer.get_storage().add_batch(batch))

	_ok("the small beer stack outranks the Cellar for small beer",
		beer.get_storage().storage_priority > cellar.storage_priority,
		"%d vs %d" % [beer.get_storage().storage_priority, cellar.storage_priority])

	_ok("two delivered casks show as two casks",
		beer.get_visible_units() == 2, "showing %d" % beer.get_visible_units())

	# And the wrong liquid is refused rather than silently stored.
	var wrong := FilledContainer.new()
	wrong.container = kilderkin
	wrong.content_id = &"madeira"
	wrong.quantity = kilderkin.maximum_capacity

	_ok("the small beer stack refuses madeira",
		not beer.get_storage().accepts(wrong))
	_ok("the Cellar still takes what the specific stores refuse",
		cellar.accepts(wrong))

	# Drawing stock back down must shrink the visible pile again.
	var batches: Array[FilledContainer] = beer.get_storage().get_batches()
	beer.get_storage().remove_batch(batches[0])
	_ok("taking a cask removes one from the pile",
		beer.get_visible_units() == 1, "showing %d" % beer.get_visible_units())
