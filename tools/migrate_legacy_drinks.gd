extends SceneTree

## Migrates the two pre-framework drinks into the Beverage Framework.
##
## The old resources are EDITED IN PLACE rather than replaced. That matters:
## grog.tres and ale.tres are referenced by main.tscn, by the drinks stations,
## by CustomerType.available_drinks and by the item registry. Swapping the
## files would break every one of those references; adding the new fields to
## them breaks nothing.
##
## grog is kept as a real drink rather than deleted. Historically grog is
## watered rum, so it maps onto the kill_devil content cleanly and existing
## saves, stations and customer types keep working untouched.

func _init() -> void:
	var duplicate_ale := "res://Data/beverage/drinks/ale.tres"

	# The generated ale duplicates the legacy item id. The legacy one wins,
	# because scenes already point at it.
	if FileAccess.file_exists(duplicate_ale):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(duplicate_ale))
		print("Removed duplicate generated ale (legacy ale.tres is canonical).")

	_migrate_grog()
	_migrate_ale()

	quit()


func _migrate_grog() -> void:
	var path := "res://Data/items/drinks/grog.tres"
	var drink: DrinkDefinition = load(path)

	if drink == null:
		push_error("Could not load " + path)
		return

	# Grog is watered rum, so it draws from the same cask as Kill-Devil.
	drink.content_id = &"kill_devil"
	drink.serving_format_ids = [&"mug", &"tankard"] as Array[StringName]
	drink.service_method = DrinkDefinition.ServiceMethod.DRAWN_FROM_CASK
	drink.required_station_capabilities = (
		[StationCapabilities.DRAW_FROM_CASK] as Array[StringName]
	)
	drink.historical_availability = DrinkDefinition.Availability.VERY_COMMON
	drink.rarity = DrinkDefinition.Availability.VERY_COMMON
	drink.quality_tier = DrinkDefinition.QualityTier.ROUGH
	drink.general_popularity = 0.8
	drink.drink_category = &"kill_devil"
	drink.can_spoil_after_serving = true
	drink.spoilage_profile = load(
		"res://Data/beverage/spoilage/poured_drink.tres"
	)

	_merge_tags(drink, [
		BeverageTags.RUM,
		BeverageTags.WEAK_ALCOHOL,
		BeverageTags.CHEAP,
		BeverageTags.SAILOR_FAVOURITE,
		BeverageTags.PIRATE_FAVOURITE,
	])

	_save(drink, path)


func _migrate_ale() -> void:
	var path := "res://Data/items/drinks/ale.tres"
	var drink: DrinkDefinition = load(path)

	if drink == null:
		push_error("Could not load " + path)
		return

	drink.content_id = &"ale"
	drink.serving_format_ids = (
		[&"mug", &"tankard", &"pitcher", &"firkin_serving", &"kilderkin_serving"]
		as Array[StringName]
	)
	drink.service_method = DrinkDefinition.ServiceMethod.DRAWN_FROM_CASK
	drink.required_station_capabilities = (
		[StationCapabilities.DRAW_FROM_CASK] as Array[StringName]
	)
	drink.historical_availability = DrinkDefinition.Availability.VERY_COMMON
	drink.rarity = DrinkDefinition.Availability.VERY_COMMON
	drink.quality_tier = DrinkDefinition.QualityTier.ORDINARY
	drink.general_popularity = 0.85
	drink.drink_category = &"ale"
	drink.can_spoil_after_serving = true
	drink.spoilage_profile = load(
		"res://Data/beverage/spoilage/poured_drink.tres"
	)

	_merge_tags(drink, [
		BeverageTags.ALE,
		BeverageTags.BEER,
		BeverageTags.WEAK_ALCOHOL,
		BeverageTags.CHEAP,
		BeverageTags.SAILOR_FAVOURITE,
		BeverageTags.PIRATE_FAVOURITE,
	])

	_save(drink, path)


## Adds tags without dropping the ones the drink already carries.
func _merge_tags(drink: DrinkDefinition, extra: Array) -> void:
	var tags: Array[StringName] = drink.tags.duplicate()

	for tag in extra:
		if not tags.has(tag):
			tags.append(tag)

	drink.tags = tags


## Saves without losing the resource's uid.
##
## ResourceSaver drops the uid from the header, which leaves every scene that
## referenced it falling back to the text path. Capturing it first and writing
## it back keeps scene references exact - this is the "avoid fragile scene
## edits" rule applied to the resources the scenes point at.
func _save(drink: DrinkDefinition, path: String) -> void:
	var original_uid := ResourceUID.id_to_text(
		ResourceLoader.get_resource_uid(path)
	)

	var err := ResourceSaver.save(drink, path)

	if err != OK:
		push_error("Failed to save %s (error %d)" % [path, err])
		return

	_restore_uid(path, original_uid)

	print("Migrated %s -> content '%s', %d serving formats."
		% [path.get_file(), String(drink.content_id), drink.serving_format_ids.size()])


## Puts the uid back into the .tres header after a save.
func _restore_uid(path: String, uid: String) -> void:
	if uid.is_empty() or uid == "uid://<invalid>":
		return

	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		return

	var text := file.get_as_text()
	file.close()

	var newline := text.find("\n")

	if newline < 0:
		return

	var header := text.substr(0, newline)

	if header.contains("uid="):
		return

	header = header.replace(" format=3]", ' format=3 uid="%s"]' % uid)

	var out := FileAccess.open(path, FileAccess.WRITE)

	if out == null:
		return

	out.store_string(header + text.substr(newline))
	out.close()

	print("  kept uid %s on %s" % [uid, path.get_file()])
