class_name GroupDiagnosticsPanel
extends CanvasLayer

## Every active group visit, with actions to drive one by hand.
##
## Built programmatically in the same style as the beverage panel, so it needs
## no scene file and can be dropped anywhere. Toggled with F8.


@export_category("References")

@export var group_manager: GroupManager
@export var group_spawner: GroupSpawner
@export var order_service: GroupOrderService

@export_category("Input")

@export var toggle_key: Key = KEY_F8

## Spawns the milestone test group of four through the production path.
@export var spawn_test_group_key: Key = KEY_F10

## Size used by the "spawn test group" buttons.
@export_range(2, 12, 1)
var test_group_size: int = 4


var _panel: PanelContainer
var _content: VBoxContainer
var _showing_actions: bool = false


func _ready() -> void:
	layer = 128

	_build_ui()
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey

	if key_event == null or not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == toggle_key:
		_panel.visible = not _panel.visible

		if _panel.visible:
			refresh()

		get_viewport().set_input_as_handled()
		return

	if key_event.keycode == spawn_test_group_key:
		_action_spawn_test_group()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	for child: Node in _content.get_children():
		child.queue_free()

	if _showing_actions:
		_show_actions()
	else:
		_show_groups()


func _show_groups() -> void:
	if group_manager == null:
		_line("No GroupManager is assigned.")
		return

	var rows: Array[Dictionary] = group_manager.get_summary()

	_heading("Active groups: %d (%d members)" % [
		group_manager.get_active_group_count(),
		group_manager.get_active_member_count(),
	])

	if rows.is_empty():
		_line("  No groups are currently visiting.")

	for row: Dictionary in rows:
		_line("  %s - %s" % [
			String(row["group_id"]), String(row["definition"]),
		])
		_detail("    state: %s | size: %d (%d valid) | leader: %s" % [
			String(row["state"]), int(row["size"]),
			int(row["valid_members"]), String(row["leader"]),
		])
		_detail("    place: %s %s" % [
			String(row["place_type"]), String(row["place_id"]),
		])
		_detail("    order: %s (%s)" % [
			String(row["order"]), String(row["order_status"]),
		])

		if int(row["serving_portions"]) >= 0:
			_detail("    serving: %d / %d portions" % [
				int(row["serving_portions"]), int(row["serving_maximum"]),
			])

		_detail("    patience: %d min | visiting: %d min | orders: %d" % [
			int(row["patience"]), int(row["duration"]),
			int(row["orders_placed"]),
		])

		if int(row.get("keg_starting", 0)) > 0:
			_detail("    keg: %s %d/%d from %s (stock %d -> %d)" % [
				String(row["keg_drink"]), int(row["keg_remaining"]),
				int(row["keg_starting"]), String(row["source_station"]),
				int(row["stock_before"]), int(row["stock_after"]),
			])
			_detail("    portions per member: %s" % str(row["portions"]))

		if not String(row.get("departure_reason", "")).is_empty():
			_detail("    departure: %s | cleaned up: %s" % [
				String(row["departure_reason"]), str(row["cleanup"]),
			])

		var group: CustomerGroup = group_manager.get_group(
			StringName(String(row["group_id"]))
		)

		if group != null:
			var diagnostics: Dictionary = group.get_diagnostics()

			_detail("    leader: %s | members: %s" % [
				String(diagnostics["leader_id"]),
				", ".join(diagnostics["member_ids"]),
			])
			_detail("    keg: %s %s | %d / %d portions | source: %s (%d -> %d)" % [
				String(diagnostics["keg_drink_id"]),
				String(diagnostics["keg_format_id"]),
				int(diagnostics["keg_remaining_portions"]),
				int(diagnostics["keg_starting_portions"]),
				String(diagnostics["source_station"]),
				int(diagnostics["stock_before_measures"]),
				int(diagnostics["stock_after_measures"]),
			])
			_detail("    portions per member: %s" % str(
				diagnostics["portions_per_member"]
			))

			if not String(diagnostics["order_failure_reason"]).is_empty():
				_line("    order failure: %s"
					% String(diagnostics["order_failure_reason"]),
					Color(1.0, 0.6, 0.4))

			if not String(diagnostics["departure_reason"]).is_empty():
				_detail("    departure: %s | cleaned up: %s" % [
					String(diagnostics["departure_reason"]),
					str(diagnostics["cleanup_completed"]),
				])

		if not String(row["problem"]).is_empty():
			_line("    problem: %s" % String(row["problem"]),
				Color(1.0, 0.5, 0.4))

	_heading("Standing areas")

	for node: Node in get_tree().get_nodes_in_group(&"group_standing_areas"):
		var area: GroupStandingArea = node as GroupStandingArea

		if area == null:
			continue

		var summary: Dictionary = area.get_summary()

		_detail("  %s - %s (%d-%d)" % [
			String(summary["area_id"]),
			"free" if bool(summary["free"])
				else "held by " + String(summary["holder_group_id"]),
			int(summary["minimum_size"]), int(summary["maximum_size"]),
		])

	_heading("Tables")

	for node: Node in get_tree().get_nodes_in_group(&"tables"):
		if not node.has_method(&"get_available_seat_count"):
			continue

		_detail("  %s - %d seats free" % [
			node.name, int(node.call(&"get_available_seat_count")),
		])


func _show_actions() -> void:
	_heading("Spawn")
	_button("Spawn Test Group of 4 (F10)", _action_spawn_test_group)
	_button("Spawn test group (%d)" % test_group_size, _action_spawn)
	_button("Spawn pair (2)", _action_spawn_pair)
	_button("Spawn crew (6)", _action_spawn_crew)
	_button("Force seated group", _action_force_seated)
	_button("Force standing group", _action_force_standing)

	_heading("Active group")
	_button("Force shared order", _action_force_order)
	_button("Fill shared serving", _action_fill_serving)
	_button("Empty shared serving", _action_empty_serving)
	_button("Force reorder", _action_force_reorder)
	_button("Remove leader (test replacement)", _action_remove_leader)
	_button("Force departure", _action_force_departure)

	_heading("Maintenance")
	_button("Tick groups once", _action_tick)
	_button("Clear orphaned reservations", _action_clear_orphans)


# --- Actions -----------------------------------------------------------------

func _spawn(definition_path: String, size: int) -> void:
	if group_spawner == null:
		_toast("No GroupSpawner assigned.")
		return

	var definition: CustomerGroupDefinition = null

	if not definition_path.is_empty():
		definition = load(definition_path)

	var door: Node2D = _find_door()
	var position: Vector2 = (
		door.global_position if door != null else Vector2.ZERO
	)

	var group: CustomerGroup = group_spawner.spawn_group(
		position, definition, size
	)

	if group != null:
		# Panel spawns must join the normal roster, exactly as an automatic
		# group arrival does.
		group_spawner.register_members_with_game_manager(group)

	_toast(
		"Spawned %s" % String(group.group_id) if group != null
		else "Group could not spawn (limit or no definition)."
	)

	_showing_actions = false
	refresh()


## F10: Spawn Test Group of 4.
func _action_spawn_test_group() -> void:
	if group_spawner == null:
		_toast("No GroupSpawner assigned.")
		return

	var group: CustomerGroup = group_spawner.spawn_test_group(
		group_spawner.test_group_size
	)

	if group == null:
		_toast("Test group could not spawn (limit, population or definition).")
		return

	_toast(
		"Spawned test group %s with %d members (leader %s)." % [
			String(group.group_id),
			group.get_valid_members().size(),
			String(group.leader.name) if group.leader != null else "-",
		]
	)

	if _panel.visible:
		refresh()


func _action_spawn() -> void:
	_spawn("", test_group_size)


func _action_spawn_pair() -> void:
	_spawn("res://Data/groups/sailor_pair.tres", 2)


func _action_spawn_crew() -> void:
	_spawn("res://Data/groups/pirate_crew.tres", 6)


## Spawns a group small enough to be seated.
func _action_force_seated() -> void:
	_spawn("res://Data/groups/merchant_party.tres", 2)


## Spawns a group too large for any table, forcing the standing path.
func _action_force_standing() -> void:
	_spawn("res://Data/groups/pirate_crew.tres", 6)


func _get_first_group() -> CustomerGroup:
	if group_manager == null or group_manager.active_groups.is_empty():
		return null

	return group_manager.active_groups[0]


func _action_force_order() -> void:
	var group: CustomerGroup = _get_first_group()

	if group == null or order_service == null:
		_toast("No active group.")
		return

	group.set_state(CustomerGroup.State.WAITING_TO_ORDER)
	_toast("%s will order on the next tick." % String(group.group_id))
	refresh()


func _action_fill_serving() -> void:
	var group: CustomerGroup = _get_first_group()

	if group == null or group.shared_serving == null:
		_toast("No shared serving to fill.")
		return

	group.shared_serving.remaining_portions = (
		group.shared_serving.maximum_portions
	)

	_toast("Refilled to %d portions."
		% group.shared_serving.remaining_portions)
	refresh()


func _action_empty_serving() -> void:
	var group: CustomerGroup = _get_first_group()

	if group == null or group.shared_serving == null:
		_toast("No shared serving to empty.")
		return

	group.shared_serving.empty_now()
	_toast("Emptied the shared serving.")
	refresh()


func _action_force_reorder() -> void:
	var group: CustomerGroup = _get_first_group()

	if group == null:
		_toast("No active group.")
		return

	group.shared_serving = null
	group.current_order = null
	group.set_state(CustomerGroup.State.WAITING_TO_ORDER)

	_toast("%s will reorder." % String(group.group_id))
	refresh()


func _action_remove_leader() -> void:
	var group: CustomerGroup = _get_first_group()

	if group == null or group.leader == null:
		_toast("No leader to remove.")
		return

	var previous: String = String(group.leader.name)
	group.remove_member(group.leader)

	_toast("Removed %s; leader is now %s." % [
		previous,
		String(group.leader.name) if group.leader != null else "nobody",
	])
	refresh()


func _action_force_departure() -> void:
	var group: CustomerGroup = _get_first_group()

	if group == null:
		_toast("No active group.")
		return

	group.begin_departure()
	_toast("%s is leaving." % String(group.group_id))
	refresh()


func _action_tick() -> void:
	if group_manager != null:
		group_manager.tick()

	refresh()


func _action_clear_orphans() -> void:
	if group_manager == null:
		return

	_toast("Cleared %d orphaned reservation(s)."
		% group_manager.clear_orphaned_reservations())
	refresh()


func _find_door() -> Node2D:
	var door: Node = get_tree().current_scene.get_node_or_null(
		^"Markers/CustomerDoor"
	)

	return door as Node2D


# --- UI plumbing -------------------------------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(10, 10)
	_panel.custom_minimum_size = Vector2(520, 620)
	add_child(_panel)

	var root: VBoxContainer = VBoxContainer.new()
	_panel.add_child(root)

	var title: Label = Label.new()
	title.text = "Group Diagnostics (F8)"
	title.add_theme_font_size_override("font_size", 16)
	root.add_child(title)

	var tabs: HBoxContainer = HBoxContainer.new()
	root.add_child(tabs)

	var groups_button: Button = Button.new()
	groups_button.text = "Groups"
	groups_button.pressed.connect(_on_tab.bind(false))
	tabs.add_child(groups_button)

	var actions_button: Button = Button.new()
	actions_button.text = "Actions"
	actions_button.pressed.connect(_on_tab.bind(true))
	tabs.add_child(actions_button)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(500, 560)
	root.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)


func _on_tab(actions: bool) -> void:
	_showing_actions = actions
	refresh()


func _heading(text: String) -> void:
	_add_label(text, 13, Color(0.6, 1.0, 0.7))


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
	print("[GroupDiagnostics] " + text)
