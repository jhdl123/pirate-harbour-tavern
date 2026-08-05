class_name BeverageDiagnosticsPanel
extends CanvasLayer

## Everything the Beverage Framework knows, in one place, with actions.
##
## Built programmatically in the same style as [StockDevPanel] so it needs no
## scene file and can be dropped into any scene as a single node. Toggled with
## F7 by default.
##
## The point of this panel is that the framework can be tested without
## guessing: every question the brief asks - which drinks loaded, which
## references are broken, what is in the cellar, which vessels are free, what
## is spoiling - is a tab here, and the destructive answers are buttons.


@export_category("Registry")
@export var registry: BeverageRegistry

@export_category("Runtime")
@export var vessel_pool: VesselPool
@export var spoilage_service: SpoilageService
@export var preparation_service: PreparationService

@export_category("Input")
@export var toggle_key: Key = KEY_F7


enum Tab {
	DEFINITIONS,
	VALIDATION,
	STOCK,
	STATIONS,
	VESSELS,
	SPOILAGE,
	ACTIONS,
}


var _panel: PanelContainer
var _content: VBoxContainer
var _current_tab: Tab = Tab.VALIDATION


func _ready() -> void:
	layer = 128

	if registry == null:
		registry = load("res://Data/beverage/beverage_registry.tres")

	_build_ui()
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey

	if key_event == null or not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == toggle_key:
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	_panel.visible = not _panel.visible

	if _panel.visible:
		refresh()


func refresh() -> void:
	for child: Node in _content.get_children():
		child.queue_free()

	match _current_tab:
		Tab.DEFINITIONS: _show_definitions()
		Tab.VALIDATION: _show_validation()
		Tab.STOCK: _show_stock()
		Tab.STATIONS: _show_stations()
		Tab.VESSELS: _show_vessels()
		Tab.SPOILAGE: _show_spoilage()
		Tab.ACTIONS: _show_actions()


# --- Tabs --------------------------------------------------------------------

func _show_definitions() -> void:
	if registry == null:
		_line("No BeverageRegistry is assigned.")
		return

	registry.rebuild()

	var drinks: Array[DrinkDefinition] = registry.get_all_drinks()
	_heading("Drinks (%d)" % drinks.size())

	for drink: DrinkDefinition in drinks:
		var names: PackedStringArray = PackedStringArray()

		for format: ServingFormatDefinition in registry.get_serving_formats_for_drink(drink):
			names.append(format.historical_name)

		_line("  %s [%s]" % [drink.display_name, String(drink.item_id)])
		_detail("    content: %s | recipe: %s" % [
			_or_dash(drink.content_id), _or_dash(drink.recipe_id),
		])
		_detail("    formats: %s" % (
			", ".join(names) if not names.is_empty() else "NONE"
		))
		_detail("    needs: %s" % _join(drink.required_station_capabilities))

	_heading("Recipes (%d)" % registry.recipes.size())

	for recipe: DrinkRecipeDefinition in registry.recipes:
		if recipe == null:
			continue

		_line("  %s -> %s" % [recipe.display_name, String(recipe.output_drink_id)])

		for ingredient: RecipeIngredient in recipe.ingredients:
			if ingredient != null:
				_detail("    %s" % ingredient.get_display_text(registry))

		_detail("    station: %s" % _join(recipe.get_all_required_capabilities()))
		_detail("    %d minutes | batch: %s | vessel: %s" % [
			recipe.preparation_minutes,
			"yes" if recipe.is_batch_preparation else "no",
			_or_dash(recipe.required_vessel_container_id),
		])

	_heading("Containers (%d)" % registry.containers.size())

	for container: ContainerDefinition in registry.containers:
		if container != null:
			_line("  %s - %d %s%s" % [
				container.get_display_name_with_explanation(),
				container.maximum_capacity,
				container.unit_name,
				" [bulk]" if container.bulk_storage else "",
			])

	_heading("Serving formats (%d)" % registry.serving_formats.size())

	for format: ServingFormatDefinition in registry.serving_formats:
		if format != null:
			_line("  %s - %d measures, %d portion(s)%s" % [
				format.get_display_name_with_explanation(),
				format.measures_per_serving,
				format.portion_count,
				" [shared]" if format.is_shared else "",
			])


func _show_validation() -> void:
	var report: BeverageValidator.Report = BeverageValidator.validate(registry)

	_heading("Validation: %s" % report.get_summary())

	if report.is_clean():
		_line("  Every beverage resource resolves cleanly.")
		return

	for issue: BeverageValidator.Issue in report.issues:
		_line(
			"  " + issue.get_text(),
			Color(1.0, 0.45, 0.4)
				if issue.severity == BeverageValidator.Issue.Severity.ERROR
				else Color(1.0, 0.85, 0.4)
		)


func _show_stock() -> void:
	var storages: Array[Node] = get_tree().get_nodes_in_group(&"beverage_storage")

	if storages.is_empty():
		_line("No BeverageStorage locations are in the scene.")
		return

	for node: Node in storages:
		var storage: BeverageStorage = node as BeverageStorage

		if storage == null:
			continue

		var rows: Array[Dictionary] = storage.get_summary()
		_heading("%s (%d batches)" % [storage.display_name, rows.size()])

		if rows.is_empty():
			_line("  empty")
			continue

		for row: Dictionary in rows:
			_line("  %s" % String(row["display_name"]))
			_detail("    %d / %d measures%s%s" % [
				int(row["quantity"]), int(row["maximum"]),
				" | %d reserved" % int(row["reserved"])
					if int(row["reserved"]) > 0 else "",
				" | sealed" if bool(row["sealed"]) else "",
			])


func _show_stations() -> void:
	var stations: Array[Node] = get_tree().get_nodes_in_group(&"drink_stations")
	_heading("Stations (%d)" % stations.size())

	for node: Node in stations:
		var station: DrinksStation = node as DrinksStation

		if station == null:
			continue

		var summary: Dictionary = station.get_beverage_summary()

		_line("  %s" % String(summary["station"]))
		_detail("    %s | %d / %d servings | %s" % [
			String(summary["drink_name"]),
			int(summary["servings"]),
			int(summary["maximum_servings"]),
			String(summary["stock_state"]),
		])

		if not bool(summary["migrated"]):
			_detail("    legacy counter (no service container configured)")
			continue

		_detail("    %s | %d / %d measures" % [
			String(summary.get("container_name", "?")),
			int(summary.get("measures", 0)),
			int(summary.get("measures_maximum", 0)),
		])
		_detail("    can: %s" % _join(summary["capabilities"]))

		# Why a drink will not appear here - the question worth answering.
		if registry == null:
			continue

		var blocked: PackedStringArray = PackedStringArray()

		for drink: DrinkDefinition in registry.get_all_drinks():
			if station.can_serve_drink(drink):
				continue

			var missing: Array[StringName] = station.get_missing_capabilities(drink)

			if not missing.is_empty():
				blocked.append("%s (needs %s)" % [
					drink.display_name, _join(missing),
				])

		if not blocked.is_empty():
			_detail("    cannot serve: %s" % ", ".join(blocked))


func _show_vessels() -> void:
	if vessel_pool == null:
		_line("No VesselPool is assigned.")
		return

	var rows: Array[Dictionary] = vessel_pool.get_summary()
	_heading("Vessels (%d types)" % rows.size())

	for row: Dictionary in rows:
		_line("  %s" % String(row["display_name"]))
		_detail("    %d available | %d in use | %d dirty | %d total" % [
			int(row["available"]), int(row["in_use"]),
			int(row["dirty"]), int(row["total"]),
		])


func _show_spoilage() -> void:
	if spoilage_service != null:
		var rows: Array[Dictionary] = spoilage_service.get_summary()
		_heading("Tracked perishables (%d)" % rows.size())

		if rows.is_empty():
			_line("  Nothing spoilable is currently tracked.")

		for row: Dictionary in rows:
			_line("  [%s] %s - freshness %.0f%%%s" % [
				String(row["kind"]), String(row["name"]),
				float(row["freshness"]) * 100.0,
				" SPOILED" if bool(row["spoiled"]) else "",
			], Color(1.0, 0.45, 0.4) if bool(row["spoiled"])
				else Color(0.9, 0.9, 0.9))
	else:
		_line("No SpoilageService is assigned.")

	_heading("Active shared servings")

	var servings: Array[Node] = get_tree().get_nodes_in_group(&"shared_servings")

	if servings.is_empty():
		_line("  none")

	for node: Node in servings:
		var serving: SharedServing = node as SharedServing

		if serving != null:
			_line("  %s - %d / %d portions%s" % [
				serving.get_display_name(),
				serving.remaining_portions,
				serving.maximum_portions,
				" SPOILED" if serving.is_spoiled() else "",
			])


func _show_actions() -> void:
	_heading("Stock")
	_button("Add sample bulk stock to first cellar", _action_add_sample_stock)
	_button("Fill every service container from bulk", _action_fill_stations)
	_button("Empty every service container", _action_empty_stations)

	_heading("Vessels")
	_button("Restock all vessels to 12", _action_restock_vessels)
	_button("Mark one of each vessel dirty", _action_dirty_vessels)

	_heading("Shared servings")
	_button("Empty every shared serving", _action_empty_shared)

	_heading("Spoilage")
	_button("Re-evaluate spoilage now", _action_evaluate_spoilage)

	_heading("Validation")
	_button("Validate all beverage resources", _action_validate)


# --- Actions -----------------------------------------------------------------

func _action_add_sample_stock() -> void:
	var storage: BeverageStorage = _get_first_storage()

	if storage == null or registry == null:
		_toast("No BeverageStorage in the scene.")
		return

	var added: int = 0

	for pair: Array in [
		[&"hogshead", &"kill_devil"], [&"kilderkin", &"ale"],
		[&"pipe", &"madeira"], [&"barrel", &"water"],
	]:
		var container: ContainerDefinition = registry.get_container(pair[0])
		var content: BeverageContentDefinition = registry.get_content(pair[1])

		if container == null or content == null:
			continue

		var batch: FilledContainer = FilledContainer.create(
			container, content, container.maximum_capacity, _world_minutes()
		)

		if storage.add_batch(batch):
			added += 1

			if spoilage_service != null:
				spoilage_service.track_batch(batch, storage.spoilage_modifier)

	_toast("Added %d bulk containers to %s." % [added, storage.display_name])
	refresh()


func _action_fill_stations() -> void:
	var storage: BeverageStorage = _get_first_storage()

	if storage == null:
		_toast("No bulk storage to fill from.")
		return

	var filled: int = 0

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station == null or not station.has_service_batch():
			continue

		var sources: Array[FilledContainer] = storage.get_batches_with_content(
			station.get_service_content_id()
		)

		if not sources.is_empty() and station.receive_transfer(sources[0]).is_success():
			filled += 1

	_toast("Filled %d service containers." % filled)
	refresh()


func _action_empty_stations() -> void:
	var emptied: int = 0

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station != null:
			station.empty_stock()
			emptied += 1

	_toast("Emptied %d stations." % emptied)
	refresh()


func _action_restock_vessels() -> void:
	if vessel_pool == null or registry == null:
		_toast("No VesselPool assigned.")
		return

	var restocked: int = 0

	for container: ContainerDefinition in registry.containers:
		if container != null and container.is_serving_vessel():
			vessel_pool.set_stock(container.container_id, 12)
			restocked += 1

	_toast("Restocked %d vessel types to 12." % restocked)
	refresh()


func _action_dirty_vessels() -> void:
	if vessel_pool == null:
		return

	for row: Dictionary in vessel_pool.get_summary():
		vessel_pool.mark_dirty(row["container_id"], 1)

	_toast("Marked one of each vessel dirty.")
	refresh()


func _action_empty_shared() -> void:
	var emptied: int = 0

	for node: Node in get_tree().get_nodes_in_group(&"shared_servings"):
		var serving: SharedServing = node as SharedServing

		if serving == null or serving.is_empty():
			continue

		serving.empty_now()
		emptied += 1

	_toast("Emptied %d shared servings." % emptied)
	refresh()


func _action_evaluate_spoilage() -> void:
	if spoilage_service == null:
		_toast("No SpoilageService assigned.")
		return

	_toast("Found %d newly spoiled item(s)." % spoilage_service.evaluate_all())
	refresh()


func _action_validate() -> void:
	var report: BeverageValidator.Report = BeverageValidator.validate(registry)

	print("=== BEVERAGE VALIDATION: %s ===" % report.get_summary())

	for line: String in report.get_lines():
		print("  " + line)

	_current_tab = Tab.VALIDATION
	refresh()


# --- UI plumbing -------------------------------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-620, 10)
	_panel.custom_minimum_size = Vector2(600, 700)
	add_child(_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	_panel.add_child(root)

	var title: Label = Label.new()
	title.text = "Beverage Diagnostics (F7)"
	title.add_theme_font_size_override("font_size", 16)
	root.add_child(title)

	var tab_bar: HBoxContainer = HBoxContainer.new()
	root.add_child(tab_bar)

	for tab_name: String in [
		"Definitions", "Validation", "Stock", "Stations",
		"Vessels", "Spoilage", "Actions",
	]:
		var index: int = tab_bar.get_child_count()
		var button: Button = Button.new()
		button.text = tab_name
		button.pressed.connect(_on_tab_pressed.bind(index))
		tab_bar.add_child(button)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(580, 640)
	root.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)


func _on_tab_pressed(index: int) -> void:
	_current_tab = index as Tab
	refresh()


func _heading(text: String) -> void:
	_add_label(text, 13, Color(0.6, 0.85, 1.0))


func _line(text: String, colour: Color = Color(0.9, 0.9, 0.9)) -> void:
	_add_label(text, 11, colour)


func _detail(text: String) -> void:
	_add_label(text, 11, Color(0.65, 0.65, 0.65))


func _add_label(text: String, size: int, colour: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	_content.add_child(label)


func _button(text: String, callback: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(callback)
	_content.add_child(button)


func _toast(text: String) -> void:
	print("[BeverageDiagnostics] " + text)


func _get_first_storage() -> BeverageStorage:
	for node: Node in get_tree().get_nodes_in_group(&"beverage_storage"):
		var storage: BeverageStorage = node as BeverageStorage

		if storage != null:
			return storage

	return null


func _join(names: Array) -> String:
	var out: PackedStringArray = PackedStringArray()

	for entry: Variant in names:
		out.append(String(entry))

	return ", ".join(out) if not out.is_empty() else "-"


func _or_dash(id: StringName) -> String:
	return String(id) if not id.is_empty() else "-"


func _world_minutes() -> int:
	var world_time: Node = get_node_or_null(^"/root/WorldTime")

	if world_time == null or not world_time.has_method(&"get_timestamp"):
		return 0

	var stamp: Variant = world_time.call(&"get_timestamp")

	return int(stamp.total_minutes) if stamp != null else 0
