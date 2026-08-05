extends Node

## Drives the Beverage Framework through real gameplay paths.
##
## Deliberately NOT a check that classes exist. Every case here moves real
## stock, reserves real ingredients and reads the result back, because the
## repeated lesson on this project is that a method existing is not
## integration.

var passed: int = 0
var failed: int = 0

var registry: BeverageRegistry
var vessel_pool: VesselPool
var preparation: PreparationService
var spoilage: SpoilageService
var cellar: BeverageStorage
var bar: BeverageStorage


func _ready() -> void:
	registry = load("res://Data/beverage/beverage_registry.tres")
	registry.rebuild()

	_build_world()

	_test_validation()
	_test_container_content_separation()
	_test_bulk_to_service_transfer()
	_test_invalid_transfers()
	_test_quantity_conservation()
	_test_serving_formats()
	_test_vessels()
	_test_bumbo_preparation()
	_test_bumbo_missing_ingredient()
	_test_rum_punch_batch()
	_test_missing_station()
	_test_shared_serving()
	_test_spoilage()
	_test_save_round_trip()

	_report()


func _build_world() -> void:
	cellar = BeverageStorage.new()
	cellar.location_id = &"cellar"
	cellar.display_name = "Cellar"
	cellar.storage_tags = [BeverageTags.CELLAR_STORAGE] as Array[StringName]
	cellar.registry = registry
	cellar.spoilage_modifier = 0.8
	add_child(cellar)

	bar = BeverageStorage.new()
	bar.location_id = &"behind_bar"
	bar.display_name = "Behind the Bar"
	bar.storage_tags = (
		[BeverageTags.BAR_STORAGE, BeverageTags.CELLAR_STORAGE]
		as Array[StringName]
	)
	bar.registry = registry
	add_child(bar)

	vessel_pool = VesselPool.new()
	vessel_pool.registry = registry
	add_child(vessel_pool)

	for container_id in [
		&"mug", &"tankard", &"cup", &"wine_glass", &"dram_glass",
		&"pitcher", &"punch_bowl", &"table_cask", &"coffee_pot",
	]:
		vessel_pool.set_stock(container_id, 6)

	spoilage = SpoilageService.new()
	spoilage.registry = registry
	add_child(spoilage)

	preparation = PreparationService.new()
	preparation.registry = registry
	preparation.vessel_pool = vessel_pool
	preparation.ingredient_storage_group = &"test_ingredient_storage"
	preparation.liquid_storage_group = &"beverage_storage"
	add_child(preparation)

	var pantry := TestPantry.new()
	pantry.add_to_group(&"test_ingredient_storage")
	add_child(pantry)
	_pantry = pantry


var _pantry: TestPantry


## Minimal item store standing in for the tavern's ingredient inventory.
##
## Exposes exactly the two methods PreparationService asks for, which is the
## point: the service never knows what kind of storage it is talking to.
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


# --- Tests -------------------------------------------------------------------

## Total available measures of a content across every storage location.
##
## Preparation draws from anywhere in the beverage_storage group, so a test
## that measures only one location will see stock "vanish" when it was simply
## taken from the cellar instead of the bar.
func _total_available(content_id: StringName) -> int:
	return cellar.count_available_content(content_id) \
		+ bar.count_available_content(content_id)



func _test_validation() -> void:
	var report := BeverageValidator.validate(registry)

	_check(
		not report.has_errors(),
		"VALIDATION: all resources resolve (%s)" % report.get_summary(),
		"VALIDATION: %s -> %s" % [
			report.get_summary(),
			", ".join(report.get_lines()),
		]
	)


func _test_container_content_separation() -> void:
	var hogshead := registry.get_container(&"hogshead")
	var rum := registry.get_content(&"kill_devil")
	var madeira := registry.get_content(&"madeira")

	var rum_cask := FilledContainer.create(hogshead, rum, 400, 0)
	var wine_cask := FilledContainer.create(hogshead, madeira, 400, 0)

	_check(
		rum_cask.content_id == &"kill_devil"
			and wine_cask.content_id == &"madeira"
			and rum_cask.container == wine_cask.container,
		"SEPARATION: one hogshead definition holds two different contents",
		"SEPARATION: containers did not share a definition"
	)

	_check(
		rum_cask.get_display_name(registry) == "Hogshead (very large cask) of Kill-Devil",
		"NAMING: historical name shows its explanation in brackets",
		"NAMING: got '%s'" % rum_cask.get_display_name(registry)
	)


func _test_bulk_to_service_transfer() -> void:
	var hogshead := registry.get_container(&"hogshead")
	var service := registry.get_container(&"service_cask")
	var rum := registry.get_content(&"kill_devil")

	var bulk := FilledContainer.create(hogshead, rum, 400, 0)
	var tapped := FilledContainer.create_empty(service)

	cellar.add_batch(bulk)
	bar.add_batch(tapped)

	var result := BeverageTransferService.fill(bulk, tapped, 10, registry)

	_check(
		result.is_success() and tapped.quantity == 96 and bulk.quantity == 304,
		"TRANSFER: hogshead -> service cask moved 96, source now 304",
		"TRANSFER: %s (dest %d, source %d)" % [
			result.get_message(), tapped.quantity, bulk.quantity,
		]
	)

	_check(
		tapped.content_id == &"kill_devil",
		"TRANSFER: contents id preserved through the transfer",
		"TRANSFER: destination content became '%s'" % String(tapped.content_id)
	)


func _test_invalid_transfers() -> void:
	var service := registry.get_container(&"service_cask")
	var ale := registry.get_content(&"ale")
	var sack := registry.get_container(&"sack")

	var ale_cask := FilledContainer.create(service, ale, 90, 0)
	var rum_cask := bar.get_batches_with_content(&"kill_devil")[0]

	var mixing := BeverageTransferService.can_transfer(
		ale_cask, rum_cask, 10, registry
	)

	_check(
		not mixing.is_success()
			and mixing.refusal == FilledContainer.Refusal.CONTENT_MISMATCH,
		"TRANSFER: ale into a rum cask is refused as a content mismatch",
		"TRANSFER: mixing was allowed (%s)" % mixing.get_message()
	)

	var dry := FilledContainer.create_empty(sack)
	var wrong_kind := BeverageTransferService.can_transfer(
		ale_cask, dry, 10, registry
	)

	_check(
		not wrong_kind.is_success(),
		"TRANSFER: liquid into a dry-goods sack is refused",
		"TRANSFER: liquid was allowed into a sack"
	)

	var empty := FilledContainer.create_empty(service)
	var from_empty := BeverageTransferService.transfer(
		empty, ale_cask, 5, 0, registry
	)

	_check(
		not from_empty.is_success()
			and from_empty.refusal == FilledContainer.Refusal.SOURCE_EMPTY,
		"TRANSFER: drawing from an empty cask fails safely",
		"TRANSFER: empty source did not refuse"
	)

	var full := FilledContainer.create(service, ale, 96, 0)
	var into_full := BeverageTransferService.transfer(
		ale_cask, full, 5, 0, registry
	)

	_check(
		not into_full.is_success()
			and into_full.refusal == FilledContainer.Refusal.DESTINATION_FULL,
		"TRANSFER: filling a full cask fails safely",
		"TRANSFER: full destination accepted stock"
	)


func _test_quantity_conservation() -> void:
	var barrel := registry.get_container(&"barrel")
	var service := registry.get_container(&"service_cask")
	var cider := registry.get_content(&"cider")

	var source := FilledContainer.create(barrel, cider, 200, 0)
	var destination := FilledContainer.create_empty(service)
	var total_before := source.quantity + destination.quantity

	for _i in range(5):
		BeverageTransferService.transfer(source, destination, 17, 0, registry)
		BeverageTransferService.transfer(destination, source, 5, 0, registry)

	var total_after := source.quantity + destination.quantity

	_check(
		total_before == total_after,
		"CONSERVATION: 10 transfers preserved %d measures exactly" % total_after,
		"CONSERVATION: %d before, %d after" % [total_before, total_after]
	)


func _test_serving_formats() -> void:
	var ale := registry.get_drink(&"ale")
	var formats := registry.get_serving_formats_for_drink(ale)

	_check(
		formats.size() >= 4,
		"FORMATS: ale offers %d valid serving formats" % formats.size(),
		"FORMATS: ale offered only %d" % formats.size()
	)

	var tankard := registry.get_serving_format(&"tankard")
	var punch_bowl := registry.get_serving_format(&"punch_bowl")

	_check(
		tankard.get_order_display_name("Ale") == "Tankard of Ale",
		"FORMATS: order text reads 'Tankard of Ale'",
		"FORMATS: got '%s'" % tankard.get_order_display_name("Ale")
	)

	_check(
		punch_bowl.get_order_display_name_with_explanation("Rum Punch")
			== "Punch Bowl (shared bowl) of Rum Punch",
		"FORMATS: shared format shows its explanation in brackets",
		"FORMATS: got '%s'"
			% punch_bowl.get_order_display_name_with_explanation("Rum Punch")
	)

	_check(
		tankard.is_individual() and punch_bowl.is_shared,
		"FORMATS: individual and shared servings are distinguished",
		"FORMATS: sharing flags are wrong"
	)

	_check(
		not punch_bowl.accepts_drink(ale),
		"FORMATS: a punch bowl refuses ale (wrong drink tags)",
		"FORMATS: punch bowl accepted ale"
	)


func _test_vessels() -> void:
	var mug_before := vessel_pool.get_available(&"mug")

	_check(
		vessel_pool.reserve(&"mug"),
		"VESSELS: a mug was reserved for a serving",
		"VESSELS: could not reserve a mug"
	)

	_check(
		vessel_pool.get_available(&"mug") == mug_before - 1
			and vessel_pool.get_count(&"mug", VesselPool.State.IN_USE) == 1,
		"VESSELS: reserving moved one mug from available to in-use",
		"VESSELS: counts wrong (%d available, %d in use)" % [
			vessel_pool.get_available(&"mug"),
			vessel_pool.get_count(&"mug", VesselPool.State.IN_USE),
		]
	)

	vessel_pool.release(&"mug")

	_check(
		vessel_pool.get_available(&"mug") == mug_before,
		"VESSELS: a finished serving returned its mug",
		"VESSELS: mug was not returned"
	)

	vessel_pool.set_stock(&"coffee_pot", 0)

	_check(
		not vessel_pool.reserve(&"coffee_pot"),
		"VESSELS: reserving a vessel the tavern has none of fails gracefully",
		"VESSELS: reserved a vessel that does not exist"
	)

	vessel_pool.set_stock(&"coffee_pot", 6)


func _test_bumbo_preparation() -> void:
	_pantry.add_item_by_id(&"sugar_loaf", 5)
	_pantry.add_item_by_id(&"nutmeg", 5)

	var water_cask := FilledContainer.create(
		registry.get_container(&"barrel"),
		registry.get_content(&"water"),
		200, 0
	)
	bar.add_batch(water_cask)

	var recipe := registry.get_recipe(&"bumbo_recipe")
	var capabilities: Array[StringName] = [
		StationCapabilities.MIX_SINGLE,
		StationCapabilities.DRAW_FROM_CASK,
		StationCapabilities.ACCESS_WATER,
		StationCapabilities.ACCESS_DRY_INGREDIENTS,
	]

	var rum_before := _total_available(&"kill_devil")
	var sugar_before := _pantry.count_item(&"sugar_loaf")
	var nutmeg_before := _pantry.count_item(&"nutmeg")
	var water_before := _total_available(&"water")

	var request := preparation.reserve(
		recipe, registry.get_serving_format(&"mug"), capabilities
	)

	_check(
		request.is_ready(),
		"BUMBO: preparation reserved successfully",
		"BUMBO: blocked - %s" % request.get_message()
	)

	_check(
		preparation.complete(request),
		"BUMBO: preparation completed",
		"BUMBO: completion failed"
	)

	var rum_used := rum_before - _total_available(&"kill_devil")
	var water_used := water_before - _total_available(&"water")
	var sugar_used := sugar_before - _pantry.count_item(&"sugar_loaf")
	var nutmeg_used := nutmeg_before - _pantry.count_item(&"nutmeg")

	_check(
		rum_used == 2 and water_used == 2
			and sugar_used == 1 and nutmeg_used == 1,
		"BUMBO: consumed all four ingredients exactly once "
			+ "(rum %d, water %d, sugar %d, nutmeg %d)"
			% [rum_used, water_used, sugar_used, nutmeg_used],
		"BUMBO: wrong consumption (rum %d, water %d, sugar %d, nutmeg %d)"
			% [rum_used, water_used, sugar_used, nutmeg_used]
	)

	_check(
		not preparation.complete(request),
		"BUMBO: completing the same request twice is refused",
		"BUMBO: double completion was allowed - stock would duplicate"
	)


func _test_bumbo_missing_ingredient() -> void:
	var nutmeg_held := _pantry.count_item(&"nutmeg")
	_pantry.remove_item(&"nutmeg", nutmeg_held)

	var sugar_before := _pantry.count_item(&"sugar_loaf")
	var rum_before := _total_available(&"kill_devil")

	var request := preparation.reserve(
		registry.get_recipe(&"bumbo_recipe"),
		registry.get_serving_format(&"mug"),
		[
			StationCapabilities.MIX_SINGLE,
			StationCapabilities.DRAW_FROM_CASK,
			StationCapabilities.ACCESS_WATER,
			StationCapabilities.ACCESS_DRY_INGREDIENTS,
		] as Array[StringName]
	)

	_check(
		not request.is_ready()
			and request.failure_reason
				== PreparationRequest.Failure.MISSING_INGREDIENTS,
		"BUMBO FAIL: missing nutmeg blocks preparation cleanly (%s)"
			% request.get_message(),
		"BUMBO FAIL: preparation was allowed without nutmeg"
	)

	_check(
		_pantry.count_item(&"sugar_loaf") == sugar_before
			and _total_available(&"kill_devil") == rum_before,
		"BUMBO FAIL: no stock was consumed or left reserved by the failure",
		"BUMBO FAIL: stock leaked (sugar %d -> %d, rum %d -> %d)" % [
			sugar_before, _pantry.count_item(&"sugar_loaf"),
			rum_before, _total_available(&"kill_devil"),
		]
	)

	_pantry.add_item_by_id(&"nutmeg", 5)


func _test_rum_punch_batch() -> void:
	_pantry.add_item_by_id(&"citrus", 6)
	_pantry.add_item_by_id(&"sugar_loaf", 6)

	var recipe := registry.get_recipe(&"rum_punch_recipe")
	var capabilities: Array[StringName] = [
		StationCapabilities.PREPARE_BATCH,
		StationCapabilities.FILL_SHARED_BOWL,
		StationCapabilities.DRAW_FROM_CASK,
		StationCapabilities.ACCESS_WATER,
		StationCapabilities.ACCESS_FRESH_INGREDIENTS,
		StationCapabilities.ACCESS_DRY_INGREDIENTS,
	]

	var citrus_before := _pantry.count_item(&"citrus")
	var bowls_before := vessel_pool.get_available(&"punch_bowl")

	var request := preparation.reserve(
		recipe, registry.get_serving_format(&"punch_bowl"), capabilities
	)

	_check(
		request.is_ready(),
		"PUNCH: batch preparation reserved (bowl and all ingredients)",
		"PUNCH: blocked - %s" % request.get_message()
	)

	_check(
		vessel_pool.get_available(&"punch_bowl") == bowls_before - 1,
		"PUNCH: a punch bowl was taken out of the pool for the batch",
		"PUNCH: no bowl was reserved"
	)

	preparation.complete(request)

	_check(
		_pantry.count_item(&"citrus") == citrus_before - 3,
		"PUNCH: batch consumed 3 citrus",
		"PUNCH: citrus went %d -> %d" % [
			citrus_before, _pantry.count_item(&"citrus"),
		]
	)

	# The optional spices line is absent from the pantry, and that is fine.
	_check(
		request.status == PreparationRequest.Status.COMPLETED,
		"PUNCH: optional spices being absent did not block the batch",
		"PUNCH: optional ingredient blocked preparation"
	)


func _test_missing_station() -> void:
	var request := preparation.reserve(
		registry.get_recipe(&"coffee_recipe"),
		registry.get_serving_format(&"cup"),
		[StationCapabilities.MIX_SINGLE] as Array[StringName]
	)

	_check(
		not request.is_ready()
			and request.failure_reason == PreparationRequest.Failure.NO_STATION,
		"STATION: a station without BREW cannot make coffee (%s)"
			% request.get_message(),
		"STATION: coffee was allowed at a station with no brewing"
	)

	_check(
		not request.missing_capabilities.is_empty(),
		"STATION: the missing capabilities are reported, not just the failure",
		"STATION: no missing capabilities were listed"
	)


func _test_shared_serving() -> void:
	var table := Node2D.new()
	table.global_position = Vector2(100, 100)
	add_child(table)

	# Mirrors the real path: preparation reserves the bowl, the serving
	# hands it back when it is finished. Skipping the reserve here would let
	# the test "return" a bowl that was never taken.
	vessel_pool.reserve(&"punch_bowl")

	var serving := SharedServing.new()
	add_child(serving)
	serving.anchor_table = table
	serving.global_position = table.global_position
	serving.configure(
		registry,
		vessel_pool,
		registry.get_drink(&"rum_punch"),
		registry.get_serving_format(&"punch_bowl"),
		0
	)

	_check(
		serving.remaining_portions == 6 and serving.maximum_portions == 6,
		"SHARED: punch bowl created with 6 portions",
		"SHARED: got %d portions" % serving.remaining_portions
	)

	_check(
		serving.get_display_name() == "Punch Bowl of Rum Punch",
		"SHARED: serving names itself 'Punch Bowl of Rum Punch'",
		"SHARED: got '%s'" % serving.get_display_name()
	)

	# Four different customers seated around the table share one bowl.
	var drinkers: Array[Node2D] = []

	for i in range(4):
		var drinker := Node2D.new()
		add_child(drinker)
		drinker.global_position = table.global_position + Vector2(20 * i, 20)
		drinkers.append(drinker)

	var taken := 0

	for drinker in drinkers:
		if serving.take_portion(drinker):
			taken += 1

	_check(
		taken == 4 and serving.remaining_portions == 2,
		"SHARED: 4 group members each took a portion; 2 remain",
		"SHARED: %d taken, %d remaining" % [taken, serving.remaining_portions]
	)

	var outsider := Node2D.new()
	add_child(outsider)
	outsider.global_position = Vector2(2000, 2000)

	_check(
		not serving.take_portion(outsider),
		"SHARED: a customer at another table cannot drink from this bowl",
		"SHARED: an unrelated customer drank from the bowl"
	)

	var bowls_before := vessel_pool.get_available(&"punch_bowl")

	serving.take_portion(drinkers[0])
	serving.take_portion(drinkers[1])

	_check(
		serving.is_empty() and serving.remaining_portions == 0,
		"SHARED: bowl reached an empty state after 6 portions",
		"SHARED: bowl has %d left" % serving.remaining_portions
	)

	_check(
		not serving.take_portion(drinkers[0]),
		"SHARED: an empty bowl gives out no more drinks",
		"SHARED: empty bowl kept serving - infinite stock"
	)

	_check(
		vessel_pool.get_available(&"punch_bowl") == bowls_before + 1,
		"SHARED: the emptied bowl was returned to the vessel pool",
		"SHARED: bowl was not returned (%d -> %d)" % [
			bowls_before, vessel_pool.get_available(&"punch_bowl"),
		]
	)


func _test_spoilage() -> void:
	var punch_profile := registry.get_spoilage_profile(&"prepared_punch")
	var never := registry.get_spoilage_profile(&"never")

	_check(
		punch_profile.is_enabled() and not never.is_enabled(),
		"SPOILAGE: profiles can be enabled and disabled per definition",
		"SPOILAGE: enable flags are wrong"
	)

	_check(
		is_equal_approx(punch_profile.calculate_freshness(0), 1.0)
			and punch_profile.calculate_freshness(240) < 1.0
			and is_equal_approx(punch_profile.calculate_freshness(480), 0.0),
		"SPOILAGE: prepared punch decays from fresh to spoiled over 480 minutes",
		"SPOILAGE: freshness curve wrong (0=%f, 240=%f, 480=%f)" % [
			punch_profile.calculate_freshness(0),
			punch_profile.calculate_freshness(240),
			punch_profile.calculate_freshness(480),
		]
	)

	var table := Node2D.new()
	add_child(table)

	var serving := SharedServing.new()
	add_child(serving)
	serving.anchor_table = table
	serving.configure(
		registry, vessel_pool,
		registry.get_drink(&"rum_punch"),
		registry.get_serving_format(&"punch_bowl"),
		0
	)

	_check(
		not serving.check_spoilage(100),
		"SPOILAGE: punch is still good after 100 minutes",
		"SPOILAGE: punch spoiled too early"
	)

	_check(
		serving.check_spoilage(600) and serving.is_spoiled(),
		"SPOILAGE: punch has spoiled after 600 minutes - it does not last forever",
		"SPOILAGE: punch never spoiled"
	)

	# Sealed spirits must be unaffected.
	var rum_cask := FilledContainer.create(
		registry.get_container(&"hogshead"),
		registry.get_content(&"kill_devil"),
		400, 0
	)

	_check(
		is_equal_approx(rum_cask.get_freshness(100000, registry), 1.0)
			and not rum_cask.is_spoiled(100000, registry),
		"SPOILAGE: sealed Kill-Devil is unaffected after 100000 minutes",
		"SPOILAGE: non-spoiling stock decayed"
	)

	# Perishable ingredients support spoilage.
	var citrus: IngredientDefinition = registry.get_ingredient(&"citrus")

	_check(
		citrus != null and citrus.is_perishable(),
		"SPOILAGE: citrus is a perishable ingredient",
		"SPOILAGE: citrus is not perishable"
	)

	var sugar: IngredientDefinition = registry.get_ingredient(&"sugar_loaf")

	_check(
		sugar != null and not sugar.is_perishable(),
		"SPOILAGE: a sugar loaf does not go off",
		"SPOILAGE: sugar was marked perishable"
	)

	# A scheduled check, not a per-frame one.
	# 456, not 480: the profile treats punch as spoiled once freshness drops
	# below 0.05, which happens slightly before it is fully decayed. One
	# scheduled event at that moment replaces any per-frame checking.
	_check(
		punch_profile.get_minutes_until_spoiled(0) == 456,
		"SPOILAGE: expiry is scheduled 456 minutes ahead, not polled",
		"SPOILAGE: got %d minutes" % punch_profile.get_minutes_until_spoiled(0)
	)


func _test_save_round_trip() -> void:
	var original := FilledContainer.create(
		registry.get_container(&"pipe"),
		registry.get_content(&"madeira"),
		640, 120
	)
	original.reserve(40)
	original.storage_location_id = &"cellar"

	var restored := FilledContainer.from_save_dict(
		original.to_save_dict(), registry
	)

	_check(
		restored != null
			and restored.content_id == original.content_id
			and restored.quantity == original.quantity
			and restored.reserved_quantity == original.reserved_quantity
			and restored.container.container_id == &"pipe",
		"SAVE: a filled container survives a save/load round trip",
		"SAVE: round trip lost data"
	)

	var storage_data := cellar.to_save_dict()
	var reloaded := BeverageStorage.new()
	reloaded.registry = registry
	reloaded.location_id = &"cellar"
	add_child(reloaded)
	reloaded.from_save_dict(storage_data)

	_check(
		reloaded.get_batch_count() == cellar.get_batch_count(),
		"SAVE: a storage location restores all %d batches"
			% cellar.get_batch_count(),
		"SAVE: restored %d of %d batches" % [
			reloaded.get_batch_count(), cellar.get_batch_count(),
		]
	)

	var broken := FilledContainer.from_save_dict(
		{"container_id": "a_cask_that_does_not_exist", "quantity": 50},
		registry
	)

	_check(
		broken == null,
		"SAVE: unknown container id in save data fails safely, not fatally",
		"SAVE: unknown container was restored anyway"
	)


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
	print("BEVERAGE FRAMEWORK TEST")
	print("  passed: %d" % passed)
	print("  failed: %d" % failed)
	print("==================================================")

	get_tree().quit(1 if failed > 0 else 0)
