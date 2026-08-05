extends SceneTree

## Writes the beverage supplier catalogue.
##
## Bulk casks, bottled crates and dry ingredients, each routed to the storage
## that suits it. Prices are configurable placeholder balance values.

const OUT := "res://Data/beverage/suppliers/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)

	var registry: BeverageRegistry = load(
		"res://Data/beverage/beverage_registry.tres"
	)

	_make_distiller(registry)
	_make_brewer(registry)
	_make_importer(registry)
	_make_provisioner(registry)

	quit()


func _filled(
	container: String, content: String, price: int, maximum: int,
	tags: Array, rarity: int, delivery: int
) -> OrderCatalogueEntry:
	var entry := OrderCatalogueEntry.new()
	entry.shape = OrderCatalogueEntry.Shape.FILLED_CONTAINER
	entry.container_id = StringName(container)
	entry.content_id = StringName(content)
	entry.unit_price_override = price
	entry.maximum_order_quantity = maximum
	entry.rarity = rarity
	entry.delivery_minutes = delivery
	entry.arrives_sealed = true

	var destination: Array[StringName] = []
	for t in tags:
		destination.append(t)
	entry.destination_storage_tags = destination

	return entry


func _item(item_path: String, price: int, maximum: int) -> OrderCatalogueEntry:
	var entry := OrderCatalogueEntry.new()
	entry.shape = OrderCatalogueEntry.Shape.ITEM
	entry.item = load(item_path)
	entry.unit_price_override = price
	entry.maximum_order_quantity = maximum

	return entry


func _save(
	supplier_id: String, display: String, entries: Array, file: String
) -> void:
	var supplier := SupplierDefinition.new()
	supplier.supplier_id = StringName(supplier_id)
	supplier.display_name = display

	var typed: Array[OrderCatalogueEntry] = []
	for e in entries:
		typed.append(e)
	supplier.entries = typed

	var path := OUT + file + ".tres"
	var err := ResourceSaver.save(supplier, path)

	if err != OK:
		push_error("Failed to save %s (%d)" % [path, err])
	else:
		print("Wrote %s with %d offers." % [path.get_file(), typed.size()])


func _make_distiller(_registry: BeverageRegistry) -> void:
	var C := BeverageTags.CELLAR_STORAGE
	var A := DrinkDefinition.Availability

	_save("harbour_distillery", "Harbour Distillery", [
		_filled("barrel", "kill_devil", 220, 10, [C], A.VERY_COMMON, 120),
		_filled("hogshead", "kill_devil", 300, 6, [C], A.VERY_COMMON, 180),
		_filled("puncheon", "kill_devil", 400, 4, [C], A.COMMON, 240),
		_filled("firkin", "kill_devil", 70, 12, [C], A.VERY_COMMON, 90),
	], "harbour_distillery")


func _make_brewer(_registry: BeverageRegistry) -> void:
	var C := BeverageTags.CELLAR_STORAGE
	var B := BeverageTags.BAR_STORAGE
	var A := DrinkDefinition.Availability

	_save("town_brewer", "Town Brewer", [
		_filled("kilderkin", "ale", 90, 10, [C, B], A.VERY_COMMON, 120),
		_filled("barrel", "ale", 160, 8, [C], A.VERY_COMMON, 150),
		_filled("kilderkin", "small_beer", 60, 12, [C, B], A.VERY_COMMON, 120),
		_filled("barrel", "cider", 140, 6, [C], A.UNCOMMON, 180),
	], "town_brewer")


func _make_importer(_registry: BeverageRegistry) -> void:
	var C := BeverageTags.CELLAR_STORAGE
	var L := BeverageTags.LOCKED_STORAGE
	var A := DrinkDefinition.Availability

	var entries := [
		_filled("pipe", "madeira", 700, 2, [C], A.COMMON, 480),
		_filled("hogshead", "madeira", 420, 4, [C], A.COMMON, 420),
		_filled("crate", "port_wine", 260, 4, [C, L], A.UNCOMMON, 480),
		_filled("crate", "canary_wine", 280, 3, [C, L], A.UNCOMMON, 480),
		_filled("crate", "brandy", 520, 2, [L], A.RARE, 600),
		_filled("crate", "arrack", 480, 1, [L], A.RARE, 720),
	]

	# Rare imports are not always in stock, which is what makes a run of
	# arrack worth waiting for rather than a permanent menu item.
	entries[4].availability = 0.5
	entries[5].availability = 0.3
	entries[5].reputation_requirement = 25

	for e in entries:
		var region: Array[StringName] = [&"imported"]
		e.region_tags = region

	_save("island_importer", "Island Importer", entries, "island_importer")


func _make_provisioner(_registry: BeverageRegistry) -> void:
	_save("port_provisioner", "Port Provisioner", [
		_item("res://Data/beverage/ingredients/sugar_loaf.tres", 12, 40),
		_item("res://Data/beverage/ingredients/nutmeg.tres", 6, 60),
		_item("res://Data/beverage/ingredients/citrus.tres", 3, 60),
		_item("res://Data/beverage/ingredients/coffee_beans.tres", 15, 30),
		_item("res://Data/beverage/ingredients/chocolate.tres", 25, 20),
		_item("res://Data/beverage/ingredients/spices.tres", 8, 40),
	], "port_provisioner")
