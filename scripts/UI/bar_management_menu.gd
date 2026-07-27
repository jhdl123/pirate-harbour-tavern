class_name BarManagementMenu
extends CanvasLayer


enum Page {
	OVERVIEW,
	PROGRESSION,
}


@export_category("System References")
@export var game_manager: Node
@export var economy_manager: EconomyManager
@export var statistics_tracker: StatisticsTracker

@export_category("Input")
@export var menu_action: StringName = &"bar_management_menu"


@onready var screen: Control = $Screen

@onready var close_button: Button = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Header/CloseButton
)

@onready var overview_button: Button = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/PageButtons/
	OverviewButton
)

@onready var progression_button: Button = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/PageButtons/
	ProgressionButton
)

@onready var overview_page: Control = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/
	OverviewPage
)

@onready var progression_page: Control = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/
	ProgressionPage
)


# Header

@onready var time_label: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Header/
	TimeLabel
)


# Overview page

@onready var money_value: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/
	OverviewPage/OverviewMargin/OverviewRows/SummaryGrid/MoneyValue
)

@onready var customers_value: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/
	OverviewPage/OverviewMargin/OverviewRows/SummaryGrid/
	CustomersValue
)

@onready var served_today_value: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/
	OverviewPage/OverviewMargin/OverviewRows/SummaryGrid/
	ServedTodayValue
)

@onready var seats_value: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/
	OverviewPage/OverviewMargin/OverviewRows/SummaryGrid/SeatsValue
)


# Progression page

@onready var total_served_label: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/
	ProgressionPage/ProgressionMargin/ProgressionRows/
	TotalServedLabel
)

@onready var days_operated_label: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/
	ProgressionPage/ProgressionMargin/ProgressionRows/
	DaysOperatedLabel
)

@onready var total_earned_label: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/
	ProgressionPage/ProgressionMargin/ProgressionRows/
	TotalEarnedLabel
)

@onready var peak_customers_label: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/
	ProgressionPage/ProgressionMargin/ProgressionRows/
	PeakCustomersLabel
)

@onready var customer_milestone_label: Label = (
	$Screen/CentreContainer/MenuPanel/OuterMargin/MainRows/Pages/
	ProgressionPage/ProgressionMargin/ProgressionRows/
	CustomerMilestoneLabel
)


var current_page: Page = Page.OVERVIEW
var _paused_by_this_menu: bool = false


func _ready() -> void:
	screen.visible = false

	close_button.pressed.connect(close_menu)
	overview_button.pressed.connect(show_overview)
	progression_button.pressed.connect(show_progression)

	show_overview()


func _unhandled_input(
	event: InputEvent
) -> void:
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

	if not _validate_references():
		return

	screen.visible = true

	refresh_all_pages()

	if not Simulation.is_paused():
		Simulation.push_state(
			SimulationState.State.PAUSED
		)

		_paused_by_this_menu = true
	else:
		_paused_by_this_menu = false

	close_button.grab_focus()


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

	overview_button.disabled = true
	progression_button.disabled = false

	if screen.visible:
		refresh_overview()


func show_progression() -> void:
	current_page = Page.PROGRESSION

	overview_page.visible = false
	progression_page.visible = true

	overview_button.disabled = false
	progression_button.disabled = true

	if screen.visible:
		refresh_progression()


func refresh_all_pages() -> void:
	refresh_header()
	refresh_overview()
	refresh_progression()


func refresh_header() -> void:
	time_label.text = "Day %d — %s" % [
		WorldTime.get_day(),
		WorldTime.get_clock_text()
	]


func refresh_overview() -> void:
	if not _validate_references():
		return

	var active_customer_count: int = (
		game_manager.active_customers.size()
	)

	var seating: Dictionary = _get_seating_summary()

	money_value.text = "£%d" % (
		economy_manager.get_money()
	)

	customers_value.text = str(
		active_customer_count
	)

	served_today_value.text = str(
		statistics_tracker.get_customers_served_today()
	)

	seats_value.text = (
		"%d occupied / %d available / %d total"
		% [
			seating.occupied,
			seating.available,
			seating.total
		]
	)


func refresh_progression() -> void:
	if statistics_tracker == null:
		return

	var customers_served: int = (
		statistics_tracker.get_customers_served_total()
	)

	var milestone_target: int = 25
	var milestone_progress: int = mini(
		customers_served,
		milestone_target
	)

	total_served_label.text = (
		"Customers served: %d"
		% customers_served
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

	if customers_served >= milestone_target:
		customer_milestone_label.text = (
			"Serve 25 customers — Complete"
		)
	else:
		customer_milestone_label.text = (
			"Serve 25 customers — %d / %d"
			% [
				milestone_progress,
				milestone_target
			]
		)


func _get_seating_summary() -> Dictionary:
	var occupied_seats: int = 0
	var available_seats: int = 0

	for current_table: Table in game_manager.tables:
		if current_table == null:
			continue

		occupied_seats += (
			current_table.get_occupied_seat_count()
		)

		available_seats += (
			current_table.get_available_seat_count()
		)

	return {
		"occupied": occupied_seats,
		"available": available_seats,
		"total": occupied_seats + available_seats
	}


func _validate_references() -> bool:
	var references_are_valid: bool = true

	if game_manager == null:
		push_error(
			"BarManagementMenu requires GameManager."
		)

		references_are_valid = false

	if economy_manager == null:
		push_error(
			"BarManagementMenu requires EconomyManager."
		)

		references_are_valid = false

	if statistics_tracker == null:
		push_error(
			"BarManagementMenu requires StatisticsTracker."
		)

		references_are_valid = false

	return references_are_valid
