extends Label


func _ready() -> void:
	GameTime.time_changed.connect(_on_time_changed)

	_update_label(
		GameTime.get_day(),
		GameTime.get_hour(),
		GameTime.get_minute()
	)


func _on_time_changed(day: int, hour: int, minute: int) -> void:
	_update_label(day, hour, minute)


func _update_label(day: int, hour: int, minute: int) -> void:
	text = "Day %d  %02d:%02d" % [day, hour, minute]
