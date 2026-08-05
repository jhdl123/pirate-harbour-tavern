extends SceneTree

## Writes the initial customer group archetypes.
##
## Placeholder balance values throughout. The framework does not depend on any
## of these existing - delete them all and groups still work, they just have
## nothing to choose from.

const OUT := "res://Data/groups/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)

	var T := BeverageTags
	var P := CustomerGroupDefinition.PlacePreference
	var L := CustomerGroupDefinition.LeaderRule

	# id, name, min, max, weight, size_weights, place_pref, standing,
	# shared_chance, preferred_tags, min_portions, max_portions,
	# max_orders, reorder, patience, spending, leader_rule, social_tags
	var rows := [
		["sailor_pair", "Sailor Pair", 2, 2, 4.0, {2: 1.0},
			P.PREFER_SEATED, true, 0.45,
			[T.ALE, T.BEER, T.RUM], 3, 6, 3, 0.6, 1.0, 0.9,
			L.FIRST_MEMBER, [&"sailor"]],

		["dock_workers", "Dock Workers", 3, 5, 3.0, {3: 3.0, 4: 2.0, 5: 1.0},
			P.PREFER_STANDING, true, 0.8,
			[T.ALE, T.BEER, T.CHEAP], 4, 12, 3, 0.65, 1.1, 0.8,
			L.FIRST_MEMBER, [&"labourer"]],

		["merchant_party", "Merchant Party", 2, 4, 2.0, {2: 2.0, 3: 2.0, 4: 1.0},
			P.PREFER_SEATED, false, 0.25,
			[T.WINE, T.PREMIUM, T.IMPORTED], 3, 8, 2, 0.4, 0.8, 2.0,
			L.WEALTHIEST, [&"merchant"]],

		["pirate_crew", "Pirate Crew", 4, 8, 2.5, {4: 2.0, 5: 2.0, 6: 2.0, 7: 1.0, 8: 1.0},
			P.PREFER_STANDING, true, 0.9,
			[T.RUM, T.SHARED, T.MIXED_DRINK], 6, 24, 4, 0.75, 1.3, 1.1,
			L.RANDOM, [&"pirate"]],

		["captain_and_companions", "Captain and Companions", 2, 4, 1.0,
			{2: 1.0, 3: 2.0, 4: 1.0},
			P.PREFER_SEATED, false, 0.5,
			[T.PREMIUM, T.LUXURY, T.MIXED_DRINK], 3, 12, 3, 0.55, 0.9, 3.0,
			L.WEALTHIEST, [&"captain", &"high_value"]],
	]

	for row in rows:
		var definition := CustomerGroupDefinition.new()
		definition.group_id = StringName(row[0])
		definition.display_name = row[1]
		definition.minimum_size = row[2]
		definition.maximum_size = row[3]
		definition.spawn_weight = row[4]
		definition.size_weights = row[5]
		definition.place_preference = row[6]
		definition.standing_allowed = row[7]
		definition.shared_order_chance = row[8]

		var tags: Array[StringName] = []
		for t in row[9]:
			tags.append(t)
		definition.preferred_serving_tags = tags

		definition.minimum_shared_portions = row[10]
		definition.maximum_shared_portions = row[11]
		definition.maximum_orders_per_visit = row[12]
		definition.reorder_chance = row[13]
		definition.patience_modifier = row[14]
		definition.spending_modifier = row[15]
		definition.leader_rule = row[16]

		var social: Array[StringName] = []
		for t in row[17]:
			social.append(t)
		definition.social_tags = social

		definition.description = (
			"Placeholder balance values, not final tuning."
		)

		var path: String = OUT + String(row[0]) + ".tres"
		var err := ResourceSaver.save(definition, path)

		if err != OK:
			push_error("Failed to save %s (%d)" % [path, err])
		else:
			print("Wrote %s (%d-%d members)" % [
				path.get_file(), row[2], row[3],
			])

	quit()
