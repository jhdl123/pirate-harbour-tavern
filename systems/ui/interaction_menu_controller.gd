extends CanvasLayer

## Autoload responsible for exactly one context-specific interaction menu.
##
## World objects ask this controller to open a PackedScene and pass context.
## The controller owns pausing, closing, cleanup and restoring the interrupted
## simulation state. Individual menus only own their content and decisions.

signal menu_opened(menu: InteractionMenuView)
signal menu_closed(result: Dictionary)

var _current_menu: InteractionMenuView = null
var _paused_by_controller: bool = false


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS


## Esc closes whatever menu this controller currently owns (DECISIONS.md §48 -
## Esc and Close navigate back the same way). Centralised here rather than in
## each [InteractionMenuView] so every menu gets it for free.
func _unhandled_input(
	event: InputEvent
) -> void:
	if not is_open():
		return

	if not event.is_action_pressed(&"ui_cancel"):
		return

	close_menu()
	get_viewport().set_input_as_handled()


func open_menu(
	menu_scene: PackedScene,
	context: Dictionary = {}
) -> bool:
	if menu_scene == null:
		push_error("InteractionMenu cannot open a null PackedScene.")
		return false

	if is_open():
		push_warning("InteractionMenu already has a menu open.")
		return false

	var instance: Node = menu_scene.instantiate()
	var menu: InteractionMenuView = instance as InteractionMenuView

	if menu == null:
		push_error(
			"Interaction menu scene root must extend InteractionMenuView."
		)
		instance.queue_free()
		return false

	_current_menu = menu
	add_child(menu)

	if not menu.close_requested.is_connected(_on_close_requested):
		menu.close_requested.connect(_on_close_requested)

	menu.setup(context)

	if not Simulation.is_paused():
		Simulation.push_state(SimulationState.State.PAUSED)
		_paused_by_controller = true
	else:
		_paused_by_controller = false

	menu_opened.emit(menu)
	return true


func close_menu(result: Dictionary = {}) -> bool:
	if not is_open():
		return false

	var closing_menu: InteractionMenuView = _current_menu
	_current_menu = null

	if is_instance_valid(closing_menu):
		closing_menu.queue_free()

	if _paused_by_controller:
		Simulation.pop_state()
		_paused_by_controller = false

	menu_closed.emit(result)
	return true


func is_open() -> bool:
	return (
		_current_menu != null
		and is_instance_valid(_current_menu)
	)


func get_current_menu() -> InteractionMenuView:
	if not is_open():
		return null

	return _current_menu


func _on_close_requested(result: Dictionary) -> void:
	close_menu(result)
