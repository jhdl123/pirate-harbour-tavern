extends Node2D


@export_category("Drink")
@export var served_drink: DrinkDefinition


func _ready() -> void:
	if served_drink == null:
		push_warning(
			name
			+ " has no DrinkDefinition assigned."
		)


func interact(player: Node) -> void:
	if served_drink == null:
		push_warning(
			name
			+ " cannot serve a drink because no "
			+ "DrinkDefinition is assigned."
		)
		return

	if not player.has_method("get_carried_drink"):
		push_warning(
			name
			+ " was interacted with by an object "
			+ "that cannot carry drinks."
		)
		return

	var current_drink: DrinkDefinition = (
		player.get_carried_drink()
	)

	if current_drink == served_drink:
		player.clear_carried_drink()
		return

	player.set_carried_drink(served_drink)
