extends PanelContainer

## Development read-out for the world time and simulation frameworks.
##
## Deliberately ugly and deliberately shallow: it reads the two public APIs and
## nothing else, so it doubles as a worked example of how any future UI should
## subscribe. If this panel ever needs a private hook into either framework,
## that is a sign the public API is missing something.
##
## Event driven throughout. Nothing here polls, and nothing here runs on a
## frame timer - the labels update because the frameworks announced a change.


@export_category("Hotkeys")

@export var toggle_panel_action: StringName = &"debug_toggle_time_panel"
@export var toggle_pause_action: StringName = &"debug_toggle_pause"
@export var cycle_speed_action: StringName = &"debug_cycle_speed"
@export var skip_hour_action: StringName = &"debug_skip_hour"


@export_category("Behaviour")

## Whether the panel is visible when the game starts.
@export var start_visible: bool = true


@onready var day_label: Label = $Margin/Rows/DayLabel
@onready var clock_label: Label = $Margin/Rows/ClockLabel
@onready var speed_label: Label = $Margin/Rows/SpeedLabel
@onready var state_label: Label = $Margin/Rows/StateLabel
@onready var paused_label: Label = $Margin/Rows/PausedLabel
@onready var scheduled_label: Label = $Margin/Rows/ScheduledLabel
@onready var hint_label: Label = $Margin/Rows/HintLabel


func _ready() -> void:
	visible = start_visible

	mouse_filter = Control.MOUSE_FILTER_IGNORE

	WorldTime.time_changed.connect(_on_time_changed)
	WorldTime.speed_changed.connect(_on_speed_changed)
	WorldTime.time_paused_changed.connect(_on_time_paused_changed)
	WorldTime.day_changed.connect(_on_day_changed)

	Simulation.state_changed.connect(_on_simulation_state_changed)

	hint_label.text = _build_hint_text()

	_refresh_everything()


func _unhandled_input(
	event: InputEvent
) -> void:
	if event.is_action_pressed(toggle_panel_action):
		visible = not visible
		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	if event.is_action_pressed(toggle_pause_action):
		Simulation.toggle_pause()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(cycle_speed_action):
		WorldTime.cycle_speed()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(skip_hour_action):
		WorldTime.skip_to_next_hour()
		get_viewport().set_input_as_handled()


# -----------------------------------------------------------------------------
# Framework callbacks
# -----------------------------------------------------------------------------

func _on_time_changed(
	stamp: GameTimeStamp
) -> void:
	day_label.text = TimeFormatter.format_day(stamp)
	clock_label.text = TimeFormatter.format_clock(stamp)

	_refresh_scheduled_label()


func _on_day_changed(
	stamp: GameTimeStamp
) -> void:
	day_label.text = TimeFormatter.format_day(stamp)


func _on_speed_changed(
	multiplier: float
) -> void:
	speed_label.text = "Speed %s" % TimeFormatter.format_speed(multiplier)


func _on_time_paused_changed(
	_is_time_paused: bool
) -> void:
	_refresh_paused_label()


func _on_simulation_state_changed(
	_previous_state: SimulationState.State,
	_current_state: SimulationState.State
) -> void:
	_refresh_state_label()
	_refresh_paused_label()


# -----------------------------------------------------------------------------
# Rendering
# -----------------------------------------------------------------------------

func _refresh_everything() -> void:
	_on_time_changed(WorldTime.get_timestamp())
	_on_speed_changed(WorldTime.get_speed())

	_refresh_state_label()
	_refresh_paused_label()


func _refresh_state_label() -> void:
	state_label.text = "State: %s" % Simulation.get_state_name()


## Shows both pause levels, because they are genuinely different things.
##
## The simulation can be paused while time is not, and time can be frozen while
## the simulation runs. Collapsing the two into one line during development
## would hide exactly the bug this panel exists to catch.
func _refresh_paused_label() -> void:
	var simulation_text: String = "Yes" if Simulation.is_paused() else "No"
	var time_text: String = "Yes" if WorldTime.is_paused() else "No"

	paused_label.text = "Paused: %s   Time frozen: %s" % [
		simulation_text,
		time_text
	]


func _refresh_scheduled_label() -> void:
	var scheduler: TimeScheduler = WorldTime.get_scheduler()

	if scheduler == null:
		scheduled_label.text = "Scheduled: -"
		return

	var next_event: ScheduledTimeEvent = scheduler.get_next_event()

	if next_event == null:
		scheduled_label.text = "Scheduled: %d" % scheduler.get_pending_count()
		return

	var minutes_away: int = (
		next_event.trigger_minutes - WorldTime.get_total_minutes()
	)

	scheduled_label.text = "Scheduled: %d   next in %s" % [
		scheduler.get_pending_count(),
		TimeFormatter.format_duration(
			maxi(minutes_away, 0),
			WorldTime.get_config()
		)
	]


func _build_hint_text() -> String:
	return "%s panel   %s pause   %s speed   %s skip hour" % [
		InteractionInput.get_action_key_hint(toggle_panel_action),
		InteractionInput.get_action_key_hint(toggle_pause_action),
		InteractionInput.get_action_key_hint(cycle_speed_action),
		InteractionInput.get_action_key_hint(skip_hour_action)
	]
