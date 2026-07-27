extends Label

## The HUD clock.
##
## A one-screen example of the intended pattern: subscribe to a framework
## signal, render through [TimeFormatter], own no time state and poll nothing.


func _ready() -> void:
	WorldTime.time_changed.connect(_on_time_changed)

	_on_time_changed(WorldTime.get_timestamp())


func _on_time_changed(
	stamp: GameTimeStamp
) -> void:
	text = TimeFormatter.format_day_and_clock(stamp)
