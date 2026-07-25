extends CanvasLayer


@export var economy_manager: EconomyManager


@onready var money_label: Label = $MoneyLabel


func _ready() -> void:
	if economy_manager == null:
		push_error(
			"HUD has no EconomyManager assigned."
		)
		return

	if not economy_manager.money_changed.is_connected(
		_on_money_changed
	):
		economy_manager.money_changed.connect(
			_on_money_changed
		)

	update_money_display(
		economy_manager.get_money()
	)


func _on_money_changed(
	_previous_amount: int,
	current_amount: int,
	_change_amount: int
) -> void:
	update_money_display(
		current_amount
	)


func update_money_display(
	amount: int
) -> void:
	money_label.text = "£" + str(amount)
