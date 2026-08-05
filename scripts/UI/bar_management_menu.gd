class_name BarManagementMenu
extends CanvasLayer


enum Page {
	OVERVIEW,
	PROGRESSION,
}

@export var game_manager: GameManager
@export var economy_manager: EconomyManager
@export var statistics_tracker: StatisticsTracker


@export var menu_action: StringName = &"bar_management_menu"



@onready var screen: Control = $Screen

@onready var close_button: Button = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Header/CloseButton
)

@onready var overview_button: Button = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/PageButtons/OverviewButton
)

@onready var progression_button: Button = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/PageButtons/ProgressionButton
)

@onready var overview_page: Control = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/OverviewPage
)

@onready var progression_page: Control = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/ProgressionPage
)

@onready var time_label: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Header/TimeLabel
)

@onready var money_value: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/OverviewPage/
	OverviewMargin/OverviewRows/SummaryGrid/MoneyValue
)

@onready var customers_value: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/OverviewPage/
	OverviewMargin/OverviewRows/SummaryGrid/CustomersValue
)

@onready var seats_value: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/OverviewPage/
	OverviewMargin/OverviewRows/SummaryGrid/SeatsValue
)

@onready var served_today_value: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/OverviewPage/
	OverviewMargin/OverviewRows/SummaryGrid/ServedTodayValue
)

@onready var total_served_label: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/ProgressionPage/
	ProgressionMargin/ProgressionRows/TotalServedLabel
)

@onready var days_operated_label: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/ProgressionPage/
	ProgressionMargin/ProgressionRows/DaysOperatedLabel
)

@onready var total_earned_label: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/ProgressionPage/
	ProgressionMargin/ProgressionRows/TotalEarnedLabel
)

@onready var peak_customers_label: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/ProgressionPage/
	ProgressionMargin/ProgressionRows/PeakCustomersLabel
)

@onready var customer_milestone_label: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/ProgressionPage/
	ProgressionMargin/ProgressionRows/CustomerMilestoneLabel
)

## Milestones shown one at a time on the progression page. Purely
## informational - it reads statistics_tracker, it never writes to it.
const CUSTOMER_MILESTONES: Array[int] = [25, 50, 100, 200, 500, 1000]

var current_page: Page = Page.OVERVIEW
var _paused_by_this_menu: bool = false


func _ready() -> void:
	screen.visible = false

	close_button.pressed.connect(close_menu)
	overview_button.pressed.connect(show_overview)
	progression_button.pressed.connect(show_progression)

	show_overview()
	_install_stock_page()
	_connect_refresh_sources()


var _refresh_queued: bool = false


func _connect_refresh_sources() -> void:
	if economy_manager != null:
		economy_manager.money_changed.connect(_on_relevant_change)

	if statistics_tracker != null:
		statistics_tracker.statistic_changed.connect(_on_relevant_change)

	WorldTime.time_changed.connect(_on_relevant_change)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(menu_action):
		toggle_menu()
		get_viewport().set_input_as_handled()
		return

	if (
		screen.visible
		and event.is_action_pressed(&"ui_cancel")
	):
		close_menu()
		get_viewport().set_input_as_handled()


func toggle_menu() -> void:
	if screen.visible:
		close_menu()
	else:
		open_menu()


func open_menu() -> void:
	if screen.visible:
		return

	screen.visible = true

	# A full refresh on every open, so reopening can never show a value that
	# was true the last time the menu happened to be looked at.
	_connect_stock_sources()
	refresh_all()

	if not Simulation.is_paused():
		Simulation.push_state(
			SimulationState.State.PAUSED
		)
		_paused_by_this_menu = true
	else:
		_paused_by_this_menu = false

	close_button.grab_focus()

## Overview and progression are read-only, so they only need to be accurate
## while the menu is visible; refresh_overview()/refresh_progression() are
## called on open and whenever a source signal fires, matching the "M menu
## updates after state changes" requirement without a per-frame poll.

func refresh_overview() -> void:
	time_label.text = (
		WorldTime.get_full_text() if WorldTime != null else "—"
	)

	money_value.text = (
		"£%d" % economy_manager.get_money()
		if economy_manager != null else "£—"
	)

	customers_value.text = (
		str(game_manager.get_active_customer_count())
		if game_manager != null else "—"
	)

	served_today_value.text = (
		str(statistics_tracker.get_customers_served_today())
		if statistics_tracker != null else "—"
	)

	if game_manager != null:
		seats_value.text = "%d occupied / %d available / %d total" % [
			game_manager.get_occupied_seat_count(),
			game_manager.get_available_seat_count(),
			game_manager.get_total_seat_count(),
		]
	else:
		seats_value.text = "— occupied / — available / — total"


func refresh_progression() -> void:
	if statistics_tracker == null:
		return

	total_served_label.text = (
		"Customers served: %d"
		% statistics_tracker.get_customers_served_total()
	)

	days_operated_label.text = (
		"Days operated: %d"
		% statistics_tracker.get_days_operated()
	)

	total_earned_label.text = (
		"Total money earned: £%d"
		% statistics_tracker.get_money_earned_total()
	)

	peak_customers_label.text = (
		"Highest customers at once: %d"
		% statistics_tracker.get_highest_active_customers()
	)

	customer_milestone_label.text = _get_milestone_text(
		statistics_tracker.get_customers_served_total()
	)


func _get_milestone_text(served_total: int) -> String:
	for milestone: int in CUSTOMER_MILESTONES:
		if served_total < milestone:
			return "Serve %d customers — %d / %d" % [
				milestone, served_total, milestone
			]

	var last_milestone: int = CUSTOMER_MILESTONES.back()

	return "All milestones reached (%d+ customers served)" % last_milestone


func _on_relevant_change(_a = null, _b = null, _c = null) -> void:
	if screen.visible:
		request_refresh()


## Queues a refresh for the end of the frame.
##
## A delivery, a refill and a preparation can all land in the same frame, and
## rebuilding the row list three times would be wasted work and a visible
## flicker. Coalescing also means the menu never polls: it sits idle until
## something authoritative actually changes.
func request_refresh() -> void:
	if _refresh_queued or not screen.visible:
		return

	_refresh_queued = true

	_flush_refresh.call_deferred()


func _flush_refresh() -> void:
	_refresh_queued = false

	if screen.visible:
		refresh_all()


## Refreshes every page, not only the visible one.
##
## Cheap enough at this scale, and it removes a whole class of bug where
## switching pages shows values from whenever that page was last built.
func refresh_all() -> void:
	refresh_overview()
	refresh_progression()
	_refresh_stock_page()


## Subscribes to the authoritative sources of stock truth.
##
## The menu previously listened only to money, statistics and the world clock -
## none of which fire when a barrel is delivered, a station is refilled or a
## drink is poured, which is exactly why its stock figures went stale.
##
## Connections are made through a guarded helper so reopening the menu, or a
## station being added at runtime, cannot produce duplicates.
func _connect_stock_sources() -> void:
	var tree: SceneTree = get_tree()

	if tree == null:
		return

	for node: Node in tree.get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station == null:
			continue

		_connect_once(station.stock_changed, _on_relevant_change)
		_connect_once(station.stock_state_changed, _on_relevant_change)

	for node: Node in tree.get_nodes_in_group(&"stock_storage"):
		var storage: StockStorage = node as StockStorage

		if storage == null:
			continue

		_connect_once(storage.contents_changed, _on_relevant_change)

	for node: Node in tree.get_nodes_in_group(&"order_manager"):
		var manager: OrderManager = node as OrderManager

		if manager == null:
			continue

		_connect_once(manager.order_submitted, _on_relevant_change)
		_connect_once(manager.order_delivered, _on_relevant_change)
		_connect_once(
			manager.delivery_partially_received,
			_on_relevant_change
		)


## Connects [param handler] to [param source] unless it already is.
##
## Godot allows the same connection twice and then calls it twice, which would
## double every refresh each time the menu was reopened.
func _connect_once(
	source: Signal,
	handler: Callable
) -> void:
	if not source.is_connected(handler):
		source.connect(handler)


## The raw values behind the display, for the debug integrity check.
##
## Returned in the same shape the report expects, so a tester can compare what
## the menu shows against what the world actually holds without reading the UI
## node tree.
func get_stock_snapshot() -> Dictionary:
	var stations: Array = []
	var storage_entries: Array = []
	var pending: Array = []

	var tree: SceneTree = get_tree()

	if tree == null:
		return {}

	for node: Node in tree.get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station == null:
			continue

		var info: Dictionary = station.get_stock_summary()

		stations.append({
			"station": String(station.name),
			"name": info.get("name", ""),
			"current_servings": info.get("current", 0),
			"maximum_servings": info.get("maximum", 0),
		})

	for node: Node in tree.get_nodes_in_group(&"stock_storage"):
		var storage: StockStorage = node as StockStorage

		if storage == null:
			continue

		for entry: Dictionary in storage.get_summary():
			storage_entries.append({
				"display_name": entry.get("display_name", ""),
				"quantity": entry.get("quantity", 0),
			})

	for node: Node in tree.get_nodes_in_group(&"order_manager"):
		var manager: OrderManager = node as OrderManager

		if manager == null:
			continue

		for order: Variant in manager.get_pending_orders():
			pending.append({
				"order_number": order.order_number,
				"expected_at": order.expected_at_text,
			})

	return {
		"captured_world_minutes": WorldTime.get_total_minutes_precise(),
		"stations": stations,
		"storage": storage_entries,
		"pending_deliveries": pending,
	}

func close_menu() -> void:
	if not screen.visible:
		return

	screen.visible = false

	if _paused_by_this_menu:
		Simulation.pop_state()
		_paused_by_this_menu = false


func show_overview() -> void:
	current_page = Page.OVERVIEW

	overview_page.visible = true
	progression_page.visible = false
	if _stock_page != null: _stock_page.visible = false
	if _stock_button != null: _stock_button.disabled = false

	overview_button.disabled = true
	progression_button.disabled = false


func show_progression() -> void:
	current_page = Page.PROGRESSION

	overview_page.visible = false
	progression_page.visible = true
	if _stock_page != null: _stock_page.visible = false
	if _stock_button != null: _stock_button.disabled = false

	overview_button.disabled = false
	progression_button.disabled = true

# --- Stock overview extension ------------------------------------------------
var _stock_button: Button
var _stock_page: ScrollContainer
var _stock_rows: VBoxContainer

func _install_stock_page() -> void:
	if _stock_button != null:
		return
	var page_buttons := overview_button.get_parent()
	var pages := overview_page.get_parent()
	_stock_button = Button.new()
	_stock_button.text = "Stock"
	_stock_button.pressed.connect(_show_stock_page)
	page_buttons.add_child(_stock_button)
	_stock_page = ScrollContainer.new()
	_stock_page.visible = false
	_stock_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stock_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.add_child(_stock_page)

	# "Pages" is a plain Control, not a Container, so it lays nothing out. The
	# pages authored in the scene get their size from their own anchors; a
	# page created in code gets anchors of 0,0 and therefore a rect of exactly
	# zero by zero. It still builds its rows perfectly happily - they are just
	# inside a box with no area, which looks precisely like "the stock menu
	# shows nothing".
	#
	# Mirroring the overview page's rect rather than assuming a full-rect
	# preset keeps this correct if the scene ever gives the pages margins.
	_match_page_rect(_stock_page, overview_page)

	_stock_rows = VBoxContainer.new()
	_stock_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stock_rows.add_theme_constant_override("separation", 8)
	_stock_page.add_child(_stock_rows)


## Gives [param page] the same anchors and offsets as [param reference].
##
## Used for pages added at runtime, so they occupy the same area as the ones
## authored in the scene.
func _match_page_rect(
	page: Control,
	reference: Control
) -> void:
	if page == null or reference == null:
		return

	page.anchor_left = reference.anchor_left
	page.anchor_top = reference.anchor_top
	page.anchor_right = reference.anchor_right
	page.anchor_bottom = reference.anchor_bottom

	page.offset_left = reference.offset_left
	page.offset_top = reference.offset_top
	page.offset_right = reference.offset_right
	page.offset_bottom = reference.offset_bottom

func _show_stock_page() -> void:
	overview_page.visible = false
	progression_page.visible = false
	_stock_page.visible = true
	overview_button.disabled = false
	progression_button.disabled = false
	_stock_button.disabled = true
	_connect_stock_sources()
	_refresh_stock_page()

func _refresh_stock_page() -> void:
	if _stock_rows == null:
		return
	# Removed from the tree before being freed. queue_free() alone is
	# deferred, so a rebuild would briefly show the old rows and the new ones
	# together - which at a one-second refresh cadence reads as flicker.
	for child in _stock_rows.get_children():
		_stock_rows.remove_child(child)
		child.queue_free()
	_add_stock_heading("STORAGE")
	var storages := get_tree().get_nodes_in_group(&"stock_storage")
	if storages.is_empty():
		_add_stock_line("No storage container found")
	else:
		var summary := (storages[0] as StockStorage).get_summary()
		if summary.is_empty():
			_add_stock_line("Storage is empty")
		for entry in summary:
			_add_stock_line("%s: %d" % [entry.display_name, entry.quantity])
	_add_stock_heading("DRINK STATIONS")
	for node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station := node as DrinksStation
		if station != null:
			var info := station.get_stock_summary()
			_add_stock_line("%s: %d / %d" % [info.name, info.current, info.maximum])
	_add_stock_heading("PENDING DELIVERIES")
	var managers := get_tree().get_nodes_in_group(&"order_manager")
	if managers.is_empty() or (managers[0] as OrderManager).pending_orders.is_empty():
		_add_stock_line("None")
	else:
		for order in (managers[0] as OrderManager).get_pending_orders():
			_add_stock_line("Order #%d — %s" % [order.order_number, order.expected_at_text])

func _add_stock_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	_stock_rows.add_child(label)

func _add_stock_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	_stock_rows.add_child(label)
