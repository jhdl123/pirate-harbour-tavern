class_name Table
extends StaticBody2D


var chairs: Array[Chair] = []


func _ready() -> void:
	refresh_chairs()

	print(
		name,
		" has ",
		chairs.size(),
		" seats"
	)


func refresh_chairs() -> void:
	chairs.clear()

	var chairs_container: Node = get_node_or_null("Chairs")

	if chairs_container == null:
		push_error(
			name + " does not have a Chairs node."
		)
		return

	for child: Node in chairs_container.get_children():
		if child is Chair:
			chairs.append(child)


func get_chairs() -> Array[Chair]:
	if chairs.is_empty():
		refresh_chairs()

	return chairs


func get_available_chairs() -> Array[Chair]:
	if chairs.is_empty():
		refresh_chairs()

	var available_chairs: Array[Chair] = []

	for chair: Chair in chairs:
		if chair.is_available():
			available_chairs.append(chair)

	return available_chairs


func get_available_seat_count() -> int:
	return get_available_chairs().size()


func get_occupied_seat_count() -> int:
	if chairs.is_empty():
		refresh_chairs()

	var occupied_count: int = 0

	for chair: Chair in chairs:
		if !chair.is_available():
			occupied_count += 1

	return occupied_count


func has_available_seat() -> bool:
	return !get_available_chairs().is_empty()


func reserve_chair(
	chair: Chair,
	new_customer: Node
) -> bool:
	if chair == null:
		return false

	if !chairs.has(chair):
		push_error(
			chair.name
			+ " does not belong to "
			+ name
		)

		return false

	return chair.assign_customer(new_customer)


func assign_customer(new_customer: Node) -> Chair:
	for chair: Chair in get_available_chairs():
		if chair.assign_customer(new_customer):
			return chair

	return null


func contains_customer(target_customer: Node) -> bool:
	if chairs.is_empty():
		refresh_chairs()

	for chair: Chair in chairs:
		if chair.contains_customer(target_customer):
			return true

	return false


func get_customer_chair(
	target_customer: Node
) -> Chair:
	if chairs.is_empty():
		refresh_chairs()

	for chair: Chair in chairs:
		if chair.contains_customer(target_customer):
			return chair

	return null


func clear_customer(target_customer: Node) -> void:
	var customer_chair: Chair = get_customer_chair(
		target_customer
	)

	if customer_chair != null:
		customer_chair.clear_customer()
