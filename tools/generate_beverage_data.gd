extends SceneTree

## Authoring tool: writes the initial Beverage Framework resources.
##
## Run once with:
##   godot --headless --script tools/generate_beverage_data.gd
##
## Everything it writes is a normal .tres afterwards and is edited in the
## inspector like any other resource. This exists because hand-writing sixty
## interlinked .tres files is where typos in stable ids come from.

const OUT := "res://Data/beverage/"


func _init() -> void:
	_ensure_dirs()

	var spoilage := _make_spoilage_profiles()
	var storage := _make_storage_profiles()
	var containers := _make_containers()
	var contents := _make_contents(spoilage)
	var formats := _make_serving_formats()
	var ingredients := _make_ingredients(spoilage, storage)
	var drinks := _make_drinks(spoilage)
	var recipes := _make_recipes(spoilage)

	_build_registry(
		contents, containers, formats, recipes, storage, spoilage
	)
	_report(spoilage, storage, containers, contents, formats, ingredients, drinks, recipes)

	quit()


func _ensure_dirs() -> void:
	for sub in [
		"spoilage", "storage_profiles", "containers", "contents",
		"serving_formats", "ingredients", "drinks", "recipes",
	]:
		DirAccess.make_dir_recursive_absolute(OUT + sub)


func _save(resource: Resource, sub: String, file_name: String) -> Resource:
	var path := "%s%s/%s.tres" % [OUT, sub, file_name]
	var err := ResourceSaver.save(resource, path)

	if err != OK:
		push_error("Failed to save %s (error %d)" % [path, err])
	else:
		resource.take_over_path(path)

	return resource


# --- Spoilage ----------------------------------------------------------------

func _make_spoilage_profiles() -> Dictionary:
	var made := {}

	# Balance placeholders. One game day is config-driven; these are minutes.
	var rows := [
		# id, name, expiry_minutes, grace, spoiled_below, sealed_pauses
		["never", "Does Not Spoil", 0, 0, 0.0, true],
		["prepared_drink_fast", "Prepared Drink (fast)", 240, 0, 0.05, false],
		["prepared_punch", "Prepared Punch", 480, 0, 0.05, false],
		["poured_drink", "Poured Drink", 120, 0, 0.05, false],
		["cask_ale", "Cask Ale (stales once tapped)", 4320, 240, 0.1, true],
		["cask_cider", "Cask Cider", 3600, 240, 0.1, true],
		["fresh_produce", "Fresh Produce", 4320, 0, 0.05, false],
		["ground_provisions", "Ground Provisions", 20160, 0, 0.05, false],
	]

	for row in rows:
		var profile := SpoilageProfileDefinition.new()
		profile.profile_id = StringName(row[0])
		profile.display_name = row[1]
		profile.expiry_minutes = row[2]
		profile.grace_minutes = row[3]
		profile.spoiled_below_freshness = row[4]
		profile.sealed_state_pauses_spoilage = row[5]
		profile.expiry_result = SpoilageProfileDefinition.ExpiryResult.SPOILED
		profile.description = (
			"Placeholder balance values, not historical measurements."
		)

		made[row[0]] = _save(profile, "spoilage", row[0])

	return made


# --- Storage profiles --------------------------------------------------------

func _make_storage_profiles() -> Dictionary:
	var made := {}

	var CAT := ContainerDefinition.Category

	# id, name, content_tags, cellar, bar, dry, locked, spoil_mod, theft,
	# bulk, shelf, container_categories
	var rows := [
		["bulk_cellar_cask", "Bulk Cellar Cask",
			[BeverageTags.LIQUID, BeverageTags.SPIRIT],
			true, false, false, false, 0.8, 30, 4.0, 0.0, [CAT.CASK]],
		["beer_cask", "Beer or Ale Cask",
			[BeverageTags.BEER, BeverageTags.ALE, BeverageTags.CIDER],
			true, true, false, false, 0.8, 10, 3.0, 0.0, [CAT.CASK]],
		["luxury_bottled", "Luxury Bottled Alcohol",
			[BeverageTags.LUXURY, BeverageTags.PREMIUM],
			false, false, false, true, 0.9, 90, 0.5, 1.0,
			[CAT.CRATE, CAT.BOTTLE]],
		["ordinary_bottled", "Ordinary Bottled Alcohol",
			[BeverageTags.WINE],
			true, true, false, true, 0.9, 25, 0.5, 1.0,
			[CAT.CRATE, CAT.BOTTLE]],
		["dry_ingredient", "Dry Ingredient",
			[BeverageTags.DRY_GOOD],
			false, true, true, false, 1.0, 15, 0.2, 0.5, []],
		["perishable_ingredient", "Perishable Ingredient",
			[BeverageTags.PERISHABLE],
			true, true, false, false, 1.0, 5, 0.2, 0.5, []],
		["prepared_drink", "Prepared Drink",
			[BeverageTags.MIXED_DRINK, BeverageTags.HOT_DRINK],
			false, true, false, false, 1.2, 0, 0.1, 0.3, []],
		["serving_vessel", "Serving Vessel",
			[BeverageTags.SERVING_VESSEL],
			false, true, true, false, 1.0, 5, 0.1, 0.3, []],
	]

	for row in rows:
		var profile := StorageProfileDefinition.new()
		profile.profile_id = StringName(row[0])
		profile.display_name = row[1]
		var tags: Array[StringName] = []
		for t in row[2]:
			tags.append(t)
		profile.content_tags = tags
		profile.cellar_compatible = row[3]
		profile.behind_bar_compatible = row[4]
		profile.dry_storage_compatible = row[5]
		profile.locked_storage_compatible = row[6]
		profile.spoilage_modifier = row[7]
		profile.theft_value = row[8]
		profile.bulk_space_requirement = row[9]
		profile.shelf_space_requirement = row[10]

		var categories: Array[ContainerDefinition.Category] = []
		for c in row[11]:
			categories.append(c)
		profile.container_categories = categories

		made[row[0]] = _save(profile, "storage_profiles", row[0])

	return made


# --- Containers --------------------------------------------------------------

func _make_containers() -> Dictionary:
	var made := {}
	var C := ContainerDefinition.Category

	# Capacities are configurable GAME values, historically inspired only.
	# Real cask sizes varied by period, place and contents.
	# id, historical, gloss, category, capacity, bulk, serving, portable
	var rows := [
		["firkin", "Firkin", "small cask", C.CASK, 72, true, false, true],
		["kilderkin", "Kilderkin", "medium cask", C.CASK, 144, true, false, false],
		["barrel", "Barrel", "large cask", C.CASK, 288, true, false, false],
		["hogshead", "Hogshead", "very large cask", C.CASK, 432, true, false, false],
		["puncheon", "Puncheon", "bulk rum cask", C.CASK, 600, true, false, false],
		["pipe", "Pipe", "large wine cask", C.CASK, 800, true, false, false],
		["service_cask", "Service Cask", "tapped bar cask", C.CASK, 96, false, false, true],
		["bottle", "Bottle", "", C.BOTTLE, 8, false, true, true],
		["crate", "Crate", "case of bottles", C.CRATE, 96, true, false, true],
		["dram_glass", "Dram Glass", "small measure", C.DRINKING_VESSEL, 1, false, true, true],
		["cup", "Cup", "", C.DRINKING_VESSEL, 3, false, true, true],
		["mug", "Mug", "", C.DRINKING_VESSEL, 4, false, true, true],
		["tankard", "Tankard", "large mug", C.DRINKING_VESSEL, 6, false, true, true],
		["wine_glass", "Glass", "", C.DRINKING_VESSEL, 3, false, true, true],
		["pitcher", "Pitcher", "shared jug", C.PITCHER, 24, false, true, true],
		["punch_bowl", "Punch Bowl", "shared bowl", C.BOWL, 36, false, true, true],
		["table_cask", "Table Cask", "shared small keg", C.TABLE_CASK, 48, false, true, true],
		["coffee_pot", "Coffee Pot", "", C.PITCHER, 12, false, true, true],
		["sack", "Sack", "dry goods sack", C.DRY_CONTAINER, 50, true, false, true],
	]

	for row in rows:
		var container := ContainerDefinition.new()
		container.container_id = StringName(row[0])
		container.historical_name = row[1]
		container.simplified_explanation = row[2]
		container.category = row[3]
		container.maximum_capacity = row[4]
		container.bulk_storage = row[5]
		container.customer_serving = row[6]
		container.portable = row[7]
		container.unit_name = "measures"
		container.description = (
			"Capacity is a configurable game value, historically inspired "
			+ "rather than an exact period measure."
		)

		if row[3] == C.DRY_CONTAINER:
			container.supported_content_tags = [BeverageTags.DRY_GOOD]
		else:
			container.supported_content_tags = [BeverageTags.LIQUID]

		# A crate holds sealed bottles, so it is a source but not a
		# destination: you take bottles out, you do not decant into it.
		if row[0] == "crate":
			container.can_be_transfer_destination = false

		if row[3] == C.DRINKING_VESSEL:
			container.storage_space_usage = 0.05
		elif row[5]:
			container.storage_space_usage = float(row[4]) / 100.0

		made[row[0]] = _save(container, "containers", row[0])

	return made


# --- Contents ----------------------------------------------------------------

func _make_contents(spoilage: Dictionary) -> Dictionary:
	var made := {}
	var T := BeverageTags

	# id, name, tags, value_per_measure, can_spoil, profile
	var rows := [
		["kill_devil", "Kill-Devil",
			[T.LIQUID, T.RUM, T.SPIRIT, T.STRONG_ALCOHOL, T.CHEAP], 2, false, ""],
		["arrack", "Arrack",
			[T.LIQUID, T.SPIRIT, T.STRONG_ALCOHOL, T.PREMIUM, T.IMPORTED, T.LUXURY], 8, false, ""],
		["brandy", "French Brandy",
			[T.LIQUID, T.SPIRIT, T.STRONG_ALCOHOL, T.PREMIUM, T.IMPORTED, T.LUXURY], 10, false, ""],
		["small_beer", "Small Beer",
			[T.LIQUID, T.BEER, T.WEAK_ALCOHOL, T.CHEAP], 1, true, "cask_ale"],
		["ale", "Ale",
			[T.LIQUID, T.ALE, T.BEER, T.WEAK_ALCOHOL, T.CHEAP], 1, true, "cask_ale"],
		["cider", "Cider",
			[T.LIQUID, T.CIDER, T.WEAK_ALCOHOL], 2, true, "cask_cider"],
		["madeira", "Madeira",
			[T.LIQUID, T.WINE, T.PREMIUM, T.IMPORTED], 6, false, ""],
		["port_wine", "Port Wine",
			[T.LIQUID, T.WINE, T.PREMIUM, T.IMPORTED], 6, false, ""],
		["canary_wine", "Canary Wine",
			[T.LIQUID, T.WINE, T.PREMIUM, T.IMPORTED], 7, false, ""],
		["water", "Water",
			[T.LIQUID, T.NON_ALCOHOLIC], 0, false, ""],
		["prepared_bumbo", "Bumbo",
			[T.LIQUID, T.MIXED_DRINK, T.RUM], 4, true, "prepared_drink_fast"],
		["prepared_rum_punch", "Rum Punch",
			[T.LIQUID, T.MIXED_DRINK, T.RUM, T.SHARED], 4, true, "prepared_punch"],
		["brewed_coffee", "Coffee",
			[T.LIQUID, T.HOT_DRINK, T.NON_ALCOHOLIC, T.IMPORTED], 5, true, "prepared_drink_fast"],
		["drinking_chocolate", "Drinking Chocolate",
			[T.LIQUID, T.HOT_DRINK, T.NON_ALCOHOLIC, T.LUXURY, T.IMPORTED], 9, true, "prepared_drink_fast"],
	]

	for row in rows:
		var content := BeverageContentDefinition.new()
		content.content_id = StringName(row[0])
		content.display_name = row[1]
		var tags: Array[StringName] = []
		for t in row[2]:
			tags.append(t)
		content.tags = tags
		content.base_value_per_measure = row[3]
		content.can_spoil = row[4]

		if row[5] != "":
			content.spoilage_profile = spoilage[row[5]]

		made[row[0]] = _save(content, "contents", row[0])

	return made


# --- Serving formats ---------------------------------------------------------

func _make_serving_formats() -> Dictionary:
	var made := {}
	var T := BeverageTags

	# id, historical, gloss, vessel, measures, portions, shared,
	# min_group, max_group, table, anchor, price_mod, valid_tags
	var rows := [
		["dram", "Dram", "small measure", "dram_glass", 1, 1, false, 1, 1, false, false, 1.0,
			[T.SPIRIT, T.RUM]],
		["cup", "Cup", "", "cup", 3, 1, false, 1, 1, false, false, 1.0, []],
		["glass", "Glass", "", "wine_glass", 3, 1, false, 1, 1, false, false, 1.0,
			[T.WINE, T.SPIRIT]],
		["mug", "Mug", "", "mug", 4, 1, false, 1, 1, false, false, 1.0, []],
		# Rum is included so the migrated Grog can be served in a tankard,
		# which is what a sailor would actually be handed.
		["tankard", "Tankard", "large mug", "tankard", 6, 1, false, 1, 1, false, false, 1.0,
			[T.BEER, T.ALE, T.CIDER, T.RUM]],
		["bottle_serving", "Bottle", "", "bottle", 8, 1, false, 1, 2, false, false, 1.1,
			[T.WINE, T.SPIRIT]],
		["pitcher", "Pitcher", "shared jug", "pitcher", 24, 4, true, 2, 4, true, true, 0.9,
			[T.BEER, T.ALE, T.CIDER]],
		["punch_bowl", "Punch Bowl", "shared bowl", "punch_bowl", 36, 6, true, 3, 6, true, true, 0.85,
			[T.MIXED_DRINK]],
		["table_cask", "Table Cask", "shared small keg", "table_cask", 48, 8, true, 4, 8, false, true, 0.8,
			[T.RUM, T.SPIRIT, T.ALE, T.BEER]],
		["coffee_pot", "Pot", "shared coffee pot", "coffee_pot", 12, 3, true, 2, 3, true, true, 0.9,
			[T.HOT_DRINK]],
		["firkin_serving", "Firkin", "small cask", "firkin", 72, 12, true, 6, 12, false, true, 0.75,
			[T.ALE, T.BEER, T.RUM]],
		["kilderkin_serving", "Kilderkin", "medium cask", "kilderkin", 144, 24, true, 10, 24, false, true, 0.7,
			[T.ALE, T.BEER]],
	]

	for row in rows:
		var format := ServingFormatDefinition.new()
		format.format_id = StringName(row[0])
		format.historical_name = row[1]
		format.simplified_explanation = row[2]
		format.required_container_id = StringName(row[3])
		format.measures_per_serving = row[4]
		format.portion_count = row[5]
		format.is_shared = row[6]
		format.minimum_group_size = row[7]
		format.maximum_group_size = row[8]
		format.requires_table = row[9]
		format.creates_group_anchor = row[10]
		format.price_modifier = row[11]

		var tags: Array[StringName] = []
		for t in row[12]:
			tags.append(t)
		format.valid_drink_tags = tags

		# Shared and not needing a surface means it can stand on the floor of
		# a standing area - a cask on the boards is the whole point.
		format.allows_standing_area = bool(row[6]) and not bool(row[9])
		format.consumption_time_modifier = 1.0
		format.service_time_modifier = 1.0 + (float(row[4]) / 100.0)

		made[row[0]] = _save(format, "serving_formats", row[0])

	return made


# --- Ingredients -------------------------------------------------------------

func _make_ingredients(spoilage: Dictionary, storage: Dictionary) -> Dictionary:
	var made := {}
	var T := BeverageTags

	# id, name, unit, plural, stack, buy, can_spoil, profile, storage, extra_tags
	var rows := [
		["sugar_loaf", "Sugar Loaf", "loaf", "loaves", 20, 12, false, "",
			"dry_ingredient", [T.DRY_GOOD]],
		["nutmeg", "Nutmeg", "nutmeg", "nutmegs", 40, 6, false, "",
			"dry_ingredient", [T.DRY_GOOD, T.IMPORTED]],
		["citrus", "Citrus Fruit", "fruit", "fruits", 30, 3, true, "fresh_produce",
			"perishable_ingredient", [T.PERISHABLE]],
		["coffee_beans", "Coffee Beans", "pound", "pounds", 25, 15, true, "ground_provisions",
			"dry_ingredient", [T.DRY_GOOD, T.IMPORTED]],
		["chocolate", "Cocoa", "block", "blocks", 20, 25, true, "ground_provisions",
			"dry_ingredient", [T.DRY_GOOD, T.IMPORTED, T.LUXURY]],
		["spices", "Mixed Spices", "measure", "measures", 40, 8, false, "",
			"dry_ingredient", [T.DRY_GOOD, T.IMPORTED]],
	]

	for row in rows:
		var ingredient := IngredientDefinition.new()
		ingredient.item_id = StringName(row[0])
		ingredient.display_name = row[1]
		ingredient.unit_name = row[2]
		ingredient.unit_name_plural = row[3]
		ingredient.maximum_stack_size = row[4]
		ingredient.base_buy_price = row[5]
		ingredient.base_sell_price = int(row[5] / 2)
		ingredient.can_spoil = row[6]

		if row[7] != "":
			ingredient.spoilage_profile = spoilage[row[7]]

		ingredient.storage_profile = storage[row[8]]

		var tags: Array[StringName] = [ItemTags.INGREDIENT, ItemTags.SMALL_ITEM]
		for t in row[9]:
			tags.append(t)
		ingredient.tags = tags

		ingredient.preferred_destination = ItemDefinition.HandlingDestination.STORAGE

		made[row[0]] = _save(ingredient, "ingredients", row[0])

	return made


# --- Drinks ------------------------------------------------------------------

func _make_drinks(spoilage: Dictionary) -> Dictionary:
	var made := {}
	var T := BeverageTags
	var A := DrinkDefinition.Availability
	var Q := DrinkDefinition.QualityTier
	var M := DrinkDefinition.ServiceMethod

	# id, name, content, formats, method, recipe, availability, quality,
	# alcohol, sell, minutes, capabilities, spoil_profile, tags
	var rows := [
		["kill_devil", "Kill-Devil", "kill_devil",
			["dram", "cup", "mug", "table_cask"], M.DRAWN_FROM_CASK, "",
			A.VERY_COMMON, Q.ROUGH, 2.2, 6, 7,
			[StationCapabilities.DRAW_FROM_CASK], "poured_drink",
			[T.RUM, T.SPIRIT, T.STRONG_ALCOHOL, T.CHEAP,
				T.PIRATE_FAVOURITE, T.SAILOR_FAVOURITE]],

		["bumbo", "Bumbo", "prepared_bumbo",
			["cup", "mug"], M.MIXED_TO_ORDER, "bumbo_recipe",
			A.COMMON, Q.ORDINARY, 1.6, 12, 9,
			[], "prepared_drink_fast",
			[T.MIXED_DRINK, T.RUM, T.PIRATE_FAVOURITE, T.SAILOR_FAVOURITE]],

		["rum_punch", "Rum Punch", "prepared_rum_punch",
			["punch_bowl"], M.PREPARED_AS_BATCH, "rum_punch_recipe",
			A.COMMON, Q.GOOD, 1.4, 40, 10,
			[], "prepared_punch",
			[T.MIXED_DRINK, T.RUM, T.SHARED, T.PIRATE_FAVOURITE,
				T.CAPTAIN_FAVOURITE]],

		["small_beer", "Small Beer", "small_beer",
			["mug", "tankard", "pitcher"], M.DRAWN_FROM_CASK, "",
			A.VERY_COMMON, Q.ORDINARY, 0.3, 3, 8,
			[StationCapabilities.DRAW_FROM_CASK], "poured_drink",
			[T.BEER, T.WEAK_ALCOHOL, T.CHEAP, T.SAILOR_FAVOURITE]],

		["ale", "Ale", "ale",
			["mug", "tankard", "pitcher", "firkin_serving", "kilderkin_serving"],
			M.DRAWN_FROM_CASK, "",
			A.VERY_COMMON, Q.ORDINARY, 0.9, 5, 8,
			[StationCapabilities.DRAW_FROM_CASK], "poured_drink",
			[T.ALE, T.BEER, T.WEAK_ALCOHOL, T.CHEAP,
				T.SAILOR_FAVOURITE, T.PIRATE_FAVOURITE]],

		["cider", "Cider", "cider",
			["mug", "tankard", "pitcher"], M.DRAWN_FROM_CASK, "",
			A.UNCOMMON, Q.ORDINARY, 1.0, 6, 8,
			[StationCapabilities.DRAW_FROM_CASK], "poured_drink",
			[T.CIDER, T.WEAK_ALCOHOL, T.MERCHANT_FAVOURITE]],

		["madeira", "Madeira Wine", "madeira",
			["glass", "bottle_serving"], M.POURED_FROM_BOTTLE, "",
			A.COMMON, Q.FINE, 1.5, 18, 12,
			[StationCapabilities.POUR_FROM_BOTTLE], "",
			[T.WINE, T.PREMIUM, T.IMPORTED,
				T.MERCHANT_FAVOURITE, T.CAPTAIN_FAVOURITE, T.OFFICER_FAVOURITE]],

		["port_wine", "Port Wine", "port_wine",
			["glass", "bottle_serving"], M.POURED_FROM_BOTTLE, "",
			A.UNCOMMON, Q.FINE, 1.6, 20, 12,
			[StationCapabilities.POUR_FROM_BOTTLE], "",
			[T.WINE, T.PREMIUM, T.IMPORTED,
				T.MERCHANT_FAVOURITE, T.OFFICER_FAVOURITE]],

		["canary_wine", "Canary Wine", "canary_wine",
			["glass", "bottle_serving"], M.POURED_FROM_BOTTLE, "",
			A.UNCOMMON, Q.FINE, 1.6, 22, 12,
			[StationCapabilities.POUR_FROM_BOTTLE], "",
			[T.WINE, T.PREMIUM, T.IMPORTED, T.MERCHANT_FAVOURITE]],

		["brandy", "French Brandy", "brandy",
			["dram", "glass", "bottle_serving"], M.POURED_FROM_BOTTLE, "",
			A.RARE, Q.EXCEPTIONAL, 2.4, 35, 12,
			[StationCapabilities.POUR_FROM_BOTTLE,
				StationCapabilities.ACCESS_SECURED_BOTTLES], "",
			[T.SPIRIT, T.STRONG_ALCOHOL, T.PREMIUM, T.IMPORTED, T.LUXURY,
				T.CAPTAIN_FAVOURITE, T.OFFICER_FAVOURITE]],

		["arrack", "Arrack", "arrack",
			["dram", "glass"], M.POURED_FROM_BOTTLE, "",
			A.RARE, Q.FINE, 2.3, 28, 11,
			[StationCapabilities.POUR_FROM_BOTTLE,
				StationCapabilities.ACCESS_SECURED_BOTTLES], "",
			[T.SPIRIT, T.STRONG_ALCOHOL, T.PREMIUM, T.IMPORTED,
				T.CAPTAIN_FAVOURITE]],

		["coffee", "Coffee", "brewed_coffee",
			["cup", "coffee_pot"], M.MIXED_TO_ORDER, "coffee_recipe",
			A.UNCOMMON, Q.GOOD, 0.0, 14, 10,
			[], "prepared_drink_fast",
			[T.HOT_DRINK, T.NON_ALCOHOLIC, T.IMPORTED,
				T.MERCHANT_FAVOURITE, T.OFFICER_FAVOURITE]],

		["drinking_chocolate", "Drinking Chocolate", "drinking_chocolate",
			["cup"], M.MIXED_TO_ORDER, "chocolate_recipe",
			A.RARE, Q.EXCEPTIONAL, 0.0, 30, 12,
			[], "prepared_drink_fast",
			[T.HOT_DRINK, T.NON_ALCOHOLIC, T.LUXURY, T.IMPORTED,
				T.CAPTAIN_FAVOURITE, T.MERCHANT_FAVOURITE]],
	]

	for row in rows:
		var drink := DrinkDefinition.new()
		drink.item_id = StringName(row[0])
		drink.display_name = row[1]
		drink.content_id = StringName(row[2])

		var formats: Array[StringName] = []
		for f in row[3]:
			formats.append(StringName(f))
		drink.serving_format_ids = formats

		drink.service_method = row[4]
		drink.recipe_id = StringName(row[5])
		drink.historical_availability = row[6]
		drink.rarity = row[6]
		drink.quality_tier = row[7]
		drink.alcohol_strength = row[8]
		drink.base_sell_price = row[9]
		drink.drink_duration_minutes = row[10]

		var capabilities: Array[StringName] = []
		for c in row[11]:
			capabilities.append(c)
		drink.required_station_capabilities = capabilities

		if row[12] != "":
			drink.can_spoil_after_serving = true
			drink.spoilage_profile = spoilage[row[12]]

		var tags: Array[StringName] = [
			ItemTags.PREPARED_DRINK, ItemTags.SERVICE_ITEM,
		]
		for t in row[13]:
			tags.append(t)
		drink.tags = tags

		drink.maximum_stack_size = 1
		drink.preferred_destination = ItemDefinition.HandlingDestination.CARRIER
		drink.general_popularity = clampf(
			1.0 - (float(row[6]) * 0.2), 0.1, 1.0
		)
		drink.drink_category = StringName(String(row[2]))
		drink.description = (
			"Balance values are configurable placeholders, not historical "
			+ "measurements."
		)

		made[row[0]] = _save(drink, "drinks", row[0])

	return made


# --- Recipes -----------------------------------------------------------------

func _make_recipe_ingredient(
	kind: int, id: String, quantity: int, access: StringName,
	optional: bool = false
) -> RecipeIngredient:
	var ingredient := RecipeIngredient.new()
	ingredient.source_kind = kind
	ingredient.quantity = quantity
	ingredient.required_access_capability = access
	ingredient.optional = optional

	if kind == RecipeIngredient.SourceKind.ITEM:
		ingredient.item_id = StringName(id)
	else:
		ingredient.content_id = StringName(id)

	return ingredient


func _make_recipes(spoilage: Dictionary) -> Dictionary:
	var made := {}
	var ITEM := RecipeIngredient.SourceKind.ITEM
	var CONTENT := RecipeIngredient.SourceKind.CONTENT
	var S := StationCapabilities

	# Bumbo - mixed to order, single serving.
	var bumbo := DrinkRecipeDefinition.new()
	bumbo.recipe_id = &"bumbo_recipe"
	bumbo.display_name = "Bumbo"
	bumbo.output_drink_id = &"bumbo"
	bumbo.output_content_id = &"prepared_bumbo"
	bumbo.output_serving_format_id = &"mug"
	bumbo.output_measures = 4
	bumbo.preparation_minutes = 2
	bumbo.is_batch_preparation = false
	bumbo.required_station_capabilities = [S.MIX_SINGLE]
	bumbo.required_vessel_container_id = &"mug"
	bumbo.result_can_spoil = true
	bumbo.result_spoilage_profile = spoilage["prepared_drink_fast"]
	bumbo.ingredients = [
		_make_recipe_ingredient(CONTENT, "kill_devil", 2, S.DRAW_FROM_CASK),
		_make_recipe_ingredient(CONTENT, "water", 2, S.ACCESS_WATER),
		_make_recipe_ingredient(ITEM, "sugar_loaf", 1, S.ACCESS_DRY_INGREDIENTS),
		_make_recipe_ingredient(ITEM, "nutmeg", 1, S.ACCESS_DRY_INGREDIENTS),
	]
	made["bumbo_recipe"] = _save(bumbo, "recipes", "bumbo_recipe")

	# Rum Punch - batch, shared, spoils.
	var punch := DrinkRecipeDefinition.new()
	punch.recipe_id = &"rum_punch_recipe"
	punch.display_name = "Rum Punch"
	punch.output_drink_id = &"rum_punch"
	punch.output_content_id = &"prepared_rum_punch"
	punch.output_serving_format_id = &"punch_bowl"
	punch.output_measures = 36
	punch.preparation_minutes = 8
	punch.is_batch_preparation = true
	punch.required_station_capabilities = [S.PREPARE_BATCH, S.FILL_SHARED_BOWL]
	punch.required_vessel_container_id = &"punch_bowl"
	punch.result_may_be_stored = true
	punch.result_can_spoil = true
	punch.result_spoilage_profile = spoilage["prepared_punch"]
	punch.ingredients = [
		_make_recipe_ingredient(CONTENT, "kill_devil", 12, S.DRAW_FROM_CASK),
		_make_recipe_ingredient(CONTENT, "water", 16, S.ACCESS_WATER),
		_make_recipe_ingredient(ITEM, "citrus", 3, S.ACCESS_FRESH_INGREDIENTS),
		_make_recipe_ingredient(ITEM, "sugar_loaf", 2, S.ACCESS_DRY_INGREDIENTS),
		_make_recipe_ingredient(ITEM, "spices", 1, S.ACCESS_DRY_INGREDIENTS, true),
	]
	made["rum_punch_recipe"] = _save(punch, "recipes", "rum_punch_recipe")

	# Coffee - brewed.
	var coffee := DrinkRecipeDefinition.new()
	coffee.recipe_id = &"coffee_recipe"
	coffee.display_name = "Coffee"
	coffee.output_drink_id = &"coffee"
	coffee.output_content_id = &"brewed_coffee"
	coffee.output_serving_format_id = &"cup"
	coffee.output_measures = 3
	coffee.preparation_minutes = 4
	coffee.required_station_capabilities = [S.BREW, S.HEAT_LIQUID]
	coffee.required_vessel_container_id = &"cup"
	coffee.result_can_spoil = true
	coffee.result_spoilage_profile = spoilage["prepared_drink_fast"]
	coffee.ingredients = [
		_make_recipe_ingredient(ITEM, "coffee_beans", 1, S.ACCESS_DRY_INGREDIENTS),
		_make_recipe_ingredient(CONTENT, "water", 3, S.ACCESS_WATER),
	]
	made["coffee_recipe"] = _save(coffee, "recipes", "coffee_recipe")

	# Drinking Chocolate - heated and mixed.
	var chocolate := DrinkRecipeDefinition.new()
	chocolate.recipe_id = &"chocolate_recipe"
	chocolate.display_name = "Drinking Chocolate"
	chocolate.output_drink_id = &"drinking_chocolate"
	chocolate.output_content_id = &"drinking_chocolate"
	chocolate.output_serving_format_id = &"cup"
	chocolate.output_measures = 3
	chocolate.preparation_minutes = 5
	chocolate.required_station_capabilities = [S.HEAT_LIQUID, S.MIX_SINGLE]
	chocolate.required_vessel_container_id = &"cup"
	chocolate.result_can_spoil = true
	chocolate.result_spoilage_profile = spoilage["prepared_drink_fast"]
	chocolate.ingredients = [
		_make_recipe_ingredient(ITEM, "chocolate", 1, S.ACCESS_DRY_INGREDIENTS),
		_make_recipe_ingredient(CONTENT, "water", 3, S.ACCESS_WATER),
		_make_recipe_ingredient(ITEM, "spices", 1, S.ACCESS_DRY_INGREDIENTS, true),
	]
	made["chocolate_recipe"] = _save(chocolate, "recipes", "chocolate_recipe")

	return made


# --- Registry ----------------------------------------------------------------

func _build_registry(
	contents: Dictionary, containers: Dictionary, formats: Dictionary,
	recipes: Dictionary, storage: Dictionary, spoilage: Dictionary
) -> void:
	var registry := BeverageRegistry.new()

	var content_list: Array[BeverageContentDefinition] = []
	for key in contents:
		content_list.append(contents[key])
	registry.contents = content_list

	var container_list: Array[ContainerDefinition] = []
	for key in containers:
		container_list.append(containers[key])
	registry.containers = container_list

	var format_list: Array[ServingFormatDefinition] = []
	for key in formats:
		format_list.append(formats[key])
	registry.serving_formats = format_list

	var recipe_list: Array[DrinkRecipeDefinition] = []
	for key in recipes:
		recipe_list.append(recipes[key])
	registry.recipes = recipe_list

	var storage_list: Array[StorageProfileDefinition] = []
	for key in storage:
		storage_list.append(storage[key])
	registry.storage_profiles = storage_list

	var spoilage_list: Array[SpoilageProfileDefinition] = []
	for key in spoilage:
		spoilage_list.append(spoilage[key])
	registry.spoilage_profiles = spoilage_list

	registry.item_registry = load("res://Data/items/item_registry.tres")

	ResourceSaver.save(registry, OUT + "beverage_registry.tres")


func _report(
	spoilage: Dictionary, storage: Dictionary, containers: Dictionary,
	contents: Dictionary, formats: Dictionary, ingredients: Dictionary,
	drinks: Dictionary, recipes: Dictionary
) -> void:
	print("=== Beverage data generated ===")
	print("  spoilage profiles : %d" % spoilage.size())
	print("  storage profiles  : %d" % storage.size())
	print("  containers        : %d" % containers.size())
	print("  contents          : %d" % contents.size())
	print("  serving formats   : %d" % formats.size())
	print("  ingredients       : %d" % ingredients.size())
	print("  drinks            : %d" % drinks.size())
	print("  recipes           : %d" % recipes.size())
