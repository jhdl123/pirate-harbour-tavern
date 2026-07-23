extends CanvasLayer

@export var game_manager: Node


func _ready() -> void:
	game_manager.money_changed.connect(_on_money_changed)
	_on_money_changed(game_manager.money)


func _on_money_changed(new_amount: int) -> void:
	$MoneyLabel.text = "£" + str(new_amount)
