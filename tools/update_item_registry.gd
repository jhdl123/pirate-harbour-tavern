extends SceneTree

## Adds the generated beverage drinks and ingredients to the item registry.
##
## Kept separate from the data generator so it can be re-run after hand edits
## without regenerating anything. Existing entries are preserved - grog and ale
## stay where they are, which is what keeps the current game working.

func _init() -> void:
	var registry: ItemRegistry = load("res://Data/items/item_registry.tres")

	if registry == null:
		push_error("Could not load the item registry.")
		quit(1)
		return

	var before := registry.definitions.size()
	var added := 0

	for folder in ["drinks", "ingredients"]:
		var path := "res://Data/beverage/%s/" % folder
		var dir := DirAccess.open(path)

		if dir == null:
			continue

		for file in dir.get_files():
			if not file.ends_with(".tres"):
				continue

			var definition: ItemDefinition = load(path + file)

			if definition == null:
				push_error("Could not load " + path + file)
				continue

			var existing := false

			for entry in registry.definitions:
				if entry != null and entry.item_id == definition.item_id:
					existing = true
					break

			if existing:
				continue

			registry.definitions.append(definition)
			added += 1

	registry.rebuild()

	var err := ResourceSaver.save(registry, "res://Data/items/item_registry.tres")

	if err != OK:
		push_error("Failed to save the item registry (error %d)." % err)
		quit(1)
		return

	print("Item registry: %d entries before, %d added, %d now."
		% [before, added, registry.definitions.size()])

	if registry.validate_or_warn():
		print("Item registry validated cleanly.")

	quit()
