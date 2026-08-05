extends Node

## Drives a real DrinksStation node through the Beverage Framework.
##
## The framework test proves the data layer. This proves the INTEGRATION: that
## a station in the scene tree actually draws real measures, refuses drinks it
## has no capability for, and can be filled from a bulk cask - and that an
## un-migrated station still behaves exactly as it did before.

var passed: int = 0
var failed: int = 0

var registry: BeverageRegistry
var legacy_station: DrinksStation
var migrated_station: DrinksStation
var cellar: BeverageStorage


func _ready() -> void:
	registry = load("res://Data/beverage/beverage_registry.tres")
	registry.rebuild()

	await _build_stations()

	_test_legacy_station_unchanged()
	_test_migrated_station_holds_measures()
	_test_serving_draws_real_measures()
	_test_capability_gating()
	_test_bulk_to_service_fill()
	_test_empty_station_refuses()
	_test_station_save_round_trip()

	_report()


func _build_stations() -> void:
	var scene: PackedScene = load("res://scenes/furniture/drinks_station.tscn")

	legacy_station = scene.instantiate()
	legacy_station.name = "LegacyStation"
	add_child(legacy_station)

	migrated_station = scene.instantiate()
	migrated_station.name = "MigratedStation"

	# Configure BEFORE _ready runs, the way an authored scene would.
	migrated_station.served_drink = registry.get_drink(&"kill_devil")
	migrated_station.beverage_registry = registry
	migrated_station.service_container = registry.get_container(&"service_cask")
	migrated_station.station_capabilities = (
		[
			StationCapabilities.DRAW_FROM_CASK,
			StationCapabilities.FILL_PITCHER,
		] as Array[StringName]
	)
	migrated_station.maximum_servings = 96
	migrated_station.starting_servings = 20

	add_child(migrated_station)

	cellar = BeverageStorage.new()
	cellar.location_id = &"cellar"
	cellar.registry = registry
	add_child(cellar)

	await get_tree().process_frame


func _test_legacy_station_unchanged() -> void:
	_check(
		not legacy_station.has_service_batch(),
		"LEGACY: an unconfigured station stays on the old integer counter",
		"LEGACY: unconfigured station built a container anyway"
	)

	var before: int = legacy_station.current_servings
	var carrier := _make_carrier()

	_check(
		legacy_station.staff_dispense_to(carrier),
		"LEGACY: still pours a drink exactly as before",
		"LEGACY: could not pour"
	)

	_check(
		legacy_station.current_servings == before - 1,
		"LEGACY: pouring decrements the counter by one",
		"LEGACY: counter went %d -> %d" % [
			before, legacy_station.current_servings,
		]
	)

	carrier.queue_free()


func _test_migrated_station_holds_measures() -> void:
	_check(
		migrated_station.has_service_batch(),
		"MIGRATED: station built a real service cask",
		"MIGRATED: no service container was built"
	)

	var batch: FilledContainer = migrated_station.get_service_batch()

	_check(
		batch.content_id == &"kill_devil",
		"MIGRATED: cask is tapped with kill_devil",
		"MIGRATED: cask holds '%s'" % String(batch.content_id)
	)

	# Kill-Devil's default format is a dram: one measure per serving.
	_check(
		migrated_station.get_measures_per_serving() == 1,
		"MIGRATED: one serving costs 1 measure (dram)",
		"MIGRATED: serving costs %d measures"
			% migrated_station.get_measures_per_serving()
	)

	_check(
		batch.quantity == 20 and migrated_station.current_servings == 20,
		"MIGRATED: starting servings seeded 20 real measures",
		"MIGRATED: %d measures, %d servings" % [
			batch.quantity, migrated_station.current_servings,
		]
	)


func _test_serving_draws_real_measures() -> void:
	var batch: FilledContainer = migrated_station.get_service_batch()
	var measures_before: int = batch.quantity
	var carrier := _make_carrier()

	_check(
		migrated_station.staff_dispense_to(carrier),
		"MIGRATED: station poured a drink",
		"MIGRATED: could not pour"
	)

	_check(
		batch.quantity == measures_before - 1,
		"MIGRATED: pouring drew 1 real measure out of the cask",
		"MIGRATED: measures went %d -> %d" % [
			measures_before, batch.quantity,
		]
	)

	_check(
		migrated_station.current_servings == batch.quantity,
		"MIGRATED: the legacy serving counter stayed in step with the cask",
		"MIGRATED: counter %d vs cask %d" % [
			migrated_station.current_servings, batch.quantity,
		]
	)

	carrier.queue_free()


func _test_capability_gating() -> void:
	var kill_devil := registry.get_drink(&"kill_devil")
	var brandy := registry.get_drink(&"brandy")
	var coffee := registry.get_drink(&"coffee")

	_check(
		migrated_station.can_serve_drink(kill_devil),
		"CAPABILITY: a cask station can serve Kill-Devil (draw_from_cask)",
		"CAPABILITY: cask station refused Kill-Devil"
	)

	_check(
		not migrated_station.can_serve_drink(brandy),
		"CAPABILITY: it refuses brandy - no pour_from_bottle or secured access",
		"CAPABILITY: cask station served brandy"
	)

	var missing: Array[StringName] = migrated_station.get_missing_capabilities(
		brandy
	)

	_check(
		missing.has(StationCapabilities.POUR_FROM_BOTTLE)
			and missing.has(StationCapabilities.ACCESS_SECURED_BOTTLES),
		"CAPABILITY: the exact missing capabilities are reported (%d)"
			% missing.size(),
		"CAPABILITY: missing list was %s" % str(missing)
	)

	_check(
		not migrated_station.can_serve_drink(coffee),
		"CAPABILITY: it refuses coffee, which needs brewing",
		"CAPABILITY: cask station brewed coffee"
	)

	# The drink's own format list is the other half of the join.
	var dram := registry.get_serving_format(&"dram")
	var tankard := registry.get_serving_format(&"tankard")

	_check(
		migrated_station.can_serve_drink(kill_devil, dram),
		"CAPABILITY: Kill-Devil in a dram is accepted",
		"CAPABILITY: dram of Kill-Devil refused"
	)

	_check(
		not migrated_station.can_serve_drink(kill_devil, tankard),
		"CAPABILITY: Kill-Devil in a tankard is refused - not a listed format",
		"CAPABILITY: an unlisted format was accepted"
	)


func _test_bulk_to_service_fill() -> void:
	var hogshead := FilledContainer.create(
		registry.get_container(&"hogshead"),
		registry.get_content(&"kill_devil"),
		400,
		0
	)
	cellar.add_batch(hogshead)

	var batch: FilledContainer = migrated_station.get_service_batch()
	var station_before: int = batch.quantity
	var cellar_before: int = hogshead.quantity

	var result: BeverageTransferResult = migrated_station.receive_transfer(
		hogshead
	)

	_check(
		result.is_success(),
		"FILL: hogshead -> service cask succeeded (%s)" % result.get_message(),
		"FILL: %s" % result.get_message()
	)

	_check(
		batch.quantity == batch.get_maximum_quantity(),
		"FILL: the service cask is now full (%d measures)" % batch.quantity,
		"FILL: cask holds %d of %d" % [
			batch.quantity, batch.get_maximum_quantity(),
		]
	)

	var moved: int = batch.quantity - station_before

	_check(
		hogshead.quantity == cellar_before - moved,
		"FILL: the hogshead lost exactly the %d measures the cask gained"
			% moved,
		"FILL: conservation broken (%d -> %d, cask gained %d)" % [
			cellar_before, hogshead.quantity, moved,
		]
	)

	_check(
		migrated_station.current_servings == batch.quantity,
		"FILL: the station's serving count updated after the transfer",
		"FILL: counter %d vs cask %d" % [
			migrated_station.current_servings, batch.quantity,
		]
	)

	# A cask of the wrong liquid must be refused.
	var ale_cask := FilledContainer.create(
		registry.get_container(&"barrel"),
		registry.get_content(&"ale"),
		200,
		0
	)

	var wrong: BeverageTransferResult = migrated_station.receive_transfer(
		ale_cask, 10
	)

	_check(
		not wrong.is_success(),
		"FILL: filling a rum cask from an ale barrel is refused",
		"FILL: ale went into the rum cask"
	)


func _test_empty_station_refuses() -> void:
	migrated_station.empty_stock()

	var batch: FilledContainer = migrated_station.get_service_batch()

	_check(
		batch.quantity == 0 and migrated_station.current_servings == 0,
		"EMPTY: emptying the station emptied the real cask too",
		"EMPTY: %d measures, %d servings left" % [
			batch.quantity, migrated_station.current_servings,
		]
	)

	var carrier := _make_carrier()

	_check(
		not migrated_station.staff_dispense_to(carrier),
		"EMPTY: an empty station pours nothing",
		"EMPTY: empty station served a drink from nowhere"
	)

	_check(
		migrated_station.get_stock_state() == DrinksStation.StockState.EMPTY,
		"EMPTY: station reports its stock state as EMPTY",
		"EMPTY: state is %s" % migrated_station.get_stock_state_name()
	)

	carrier.queue_free()


func _test_station_save_round_trip() -> void:
	migrated_station.set_servings(40)

	var data: Dictionary = migrated_station.to_save_dict()

	_check(
		data.has("batch"),
		"SAVE: a migrated station serialises its cask",
		"SAVE: no batch in the save data"
	)

	migrated_station.empty_stock()
	migrated_station.from_save_dict(data)

	_check(
		migrated_station.current_servings == 40
			and migrated_station.get_service_batch().quantity == 40,
		"SAVE: station restored 40 servings and 40 measures",
		"SAVE: restored %d servings, %d measures" % [
			migrated_station.current_servings,
			migrated_station.get_service_batch().quantity,
		]
	)

	var legacy_data: Dictionary = legacy_station.to_save_dict()

	_check(
		not legacy_data.has("batch") and legacy_data.has("current_servings"),
		"SAVE: a legacy station serialises without inventing a container",
		"SAVE: legacy save data was wrong"
	)


# --- Harness -----------------------------------------------------------------

func _make_carrier() -> ItemCarrier:
	var carrier := ItemCarrier.new()
	add_child(carrier)
	return carrier


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
	print("BEVERAGE STATION INTEGRATION TEST")
	print("  passed: %d" % passed)
	print("  failed: %d" % failed)
	print("==================================================")

	get_tree().quit(1 if failed > 0 else 0)
