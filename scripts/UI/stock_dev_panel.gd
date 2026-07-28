class_name StockDevPanel
extends CanvasLayer

## Rapid system-testing panel (F10). Every button calls a real game-system
## method - see ARCHITECTURE_OVERVIEW.md. Disabled outside debug/editor
## builds so it can never accidentally ship active in an exported release;
## see KNOWN_ISSUES.md for the current, coarse nature of that check.

@export var economy_manager: EconomyManager
@export var order_manager: OrderManager
@export var item_registry: ItemRegistry
var panel: PanelContainer
var status: Label
var _enabled: bool = false

func _ready() -> void:
	_enabled = OS.is_debug_build()
	if not _enabled:
		return
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	panel.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event.is_action_pressed(&"stock_dev_panel"):
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.position = Vector2(930, 90)
	panel.custom_minimum_size = Vector2(330, 0)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	panel.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	margin.add_child(rows)
	var title := Label.new()
	title.text = "STOCK DEV TOOLS [F10]"
	title.add_theme_font_size_override("font_size", 18)
	rows.add_child(title)
	_add_button(rows, "Add £100", func(): economy_manager.add_money(100, &"developer"))
	_add_button(rows, "Advance 1 game hour", func(): WorldTime.advance_minutes(60))
	_add_button(rows, "Skip 24 game hours", func(): WorldTime.advance_minutes(1440))
	_add_button(rows, "Add 2 of each stock", _add_test_stock)
	_add_button(rows, "Empty all drink stations", func(): _each_station(func(s): s.empty_stock()))
	_add_button(rows, "Fill all drink stations", func(): _each_station(func(s): s.fill_stock()))
	_add_button(rows, "Complete next delivery", _complete_next)
	_add_button(rows, "Complete all deliveries", _complete_all)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Developer actions use the real game systems."
	rows.add_child(status)

func _add_button(parent: VBoxContainer, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)

func _get_storage() -> StockStorage:
	var nodes := get_tree().get_nodes_in_group(&"stock_storage")
	return nodes[0] as StockStorage if not nodes.is_empty() else null

func _add_test_stock() -> void:
	var storage := _get_storage()
	if storage == null:
		status.text = "No storage container found."
		return
	if item_registry == null:
		status.text = "No ItemRegistry assigned to the dev panel."
		return
	var grog := item_registry.get_definition(&"grog_barrel")
	var ale := item_registry.get_definition(&"ale_keg")
	if grog == null or ale == null:
		status.text = "ItemRegistry is missing grog_barrel or ale_keg."
		return
	var moved := storage.add_item(grog, 2) + storage.add_item(ale, 2)
	status.text = "Added %d stock items." % moved

func _each_station(callback: Callable) -> void:
	var count := 0
	for node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station := node as DrinksStation
		if station != null:
			callback.call(station)
			count += 1
	status.text = "Updated %d drink stations." % count

func _complete_next() -> void:
	status.text = "Completed next delivery." if order_manager != null and order_manager.complete_next_delivery() else "No pending delivery or no storage space."

func _complete_all() -> void:
	var count := order_manager.complete_all_deliveries() if order_manager != null else 0
	status.text = "Completed %d deliveries." % count
