class_name BarManagementMenu
extends CanvasLayer


enum Page {
	OVERVIEW,
	PROGRESSION,
}

@export var game_manager: Node
@export var economy_manager: Node


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

var current_page: Page = Page.OVERVIEW
var _paused_by_this_menu: bool = false


func _ready() -> void:
	screen.visible = false

	close_button.pressed.connect(close_menu)
	overview_button.pressed.connect(show_overview)
	progression_button.pressed.connect(show_progression)

	show_overview()


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
	refresh_overview()

	if not Simulation.is_paused():
		Simulation.push_state(
			SimulationState.State.PAUSED
		)
		_paused_by_this_menu = true
	else:
		_paused_by_this_menu = false

	close_button.grab_focus()

func refresh_overview() -> void:
	time_label.text = "Day 1 — 08:00"
	money_value.text = "£0"
	customers_value.text = "0"
	seats_value.text = "0 occupied / 0 available / 0 total"

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


func show_progression() -> void:
	current_page = Page.PROGRESSION

	overview_page.visible = false
	progression_page.visible = true

	overview_button.disabled = false
	progression_button.disabled = true
