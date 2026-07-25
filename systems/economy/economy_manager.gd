class_name EconomyManager
extends Node

signal money_changed(
	previous_amount: int,
	current_amount: int,
	change_amount: int
)

signal money_added(
	amount: int,
	reason: StringName
)

signal money_spent(
	amount: int,
	reason: StringName
)

signal transaction_failed(
	amount: int,
	reason: StringName
)


var current_money: int = 0


## Sets the economy's starting balance.
##
## This is intended for new games, loading saves and test setup.
func initialise(starting_money: int) -> void:
	set_money(maxi(starting_money, 0))


func set_money(new_amount: int) -> void:
	var safe_amount: int = maxi(new_amount, 0)

	if safe_amount == current_money:
		return

	var previous_amount: int = current_money
	current_money = safe_amount

	money_changed.emit(
		previous_amount,
		current_money,
		current_money - previous_amount
	)


func get_money() -> int:
	return current_money


func can_afford(amount: int) -> bool:
	if amount < 0:
		return false

	return current_money >= amount


## Adds money and returns the amount actually added.
func add_money(
	amount: int,
	reason: StringName = &""
) -> int:
	if amount <= 0:
		return 0

	var previous_amount: int = current_money
	current_money += amount

	money_added.emit(amount, reason)
	money_changed.emit(
		previous_amount,
		current_money,
		amount
	)

	return amount


## Attempts to spend money.
##
## Returns true only when the full transaction succeeds.
func spend_money(
	amount: int,
	reason: StringName = &""
) -> bool:
	if amount < 0:
		push_warning("EconomyManager cannot spend a negative amount.")
		return false

	if amount == 0:
		return true

	if not can_afford(amount):
		transaction_failed.emit(amount, reason)
		return false

	var previous_amount: int = current_money
	current_money -= amount

	money_spent.emit(amount, reason)
	money_changed.emit(
		previous_amount,
		current_money,
		-amount
	)

	return true
