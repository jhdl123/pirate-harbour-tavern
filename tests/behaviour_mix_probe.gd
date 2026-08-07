extends Node

## Measures how customers actually spend a visit.
##
## Samples every customer's state on a fixed tick and converts the tally into
## percentage of customer-time, which is what "does the tavern feel alive"
## actually means - counting activity starts hides the fact that drinking
## occupies most of the clock even when other activities are chosen.

const SAMPLE_SECONDS: float = 0.5

var tally: Dictionary = {}
var samples: int = 0
var darts_by_board: Dictionary = {}


func _ready() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	for _i: int in range(10):
		await get_tree().process_frame

	for node: Node in get_tree().get_nodes_in_group(&"navigation_debugger"):
		node.set(&"enabled", false)

	var debugger: Node = main.get_node_or_null(^"NavigationDebugger")

	if debugger != null:
		debugger.set(&"enabled", false)

	var game_manager: Node = main.get_node_or_null(^"Managers/GameManager")

	if not Tavern.is_accepting_arrivals():
		Tavern.open_early()

	var elapsed: float = 0.0

	while elapsed < 150.0:
		if (
			game_manager != null
			and game_manager.has_method("spawn_customer")
			and elapsed < 60.0
		):
			game_manager.call("spawn_customer")

		await get_tree().create_timer(SAMPLE_SECONDS).timeout
		elapsed += SAMPLE_SECONDS

		_sample()

	_report()

	get_tree().quit()


func _sample() -> void:
	for customer: Node in get_tree().get_nodes_in_group(
		&"navigation_customers"
	):
		var state: Variant = customer.get(&"current_state")

		if state == null:
			continue

		var label: String = _label(int(state))

		tally[label] = int(tally.get(label, 0)) + 1
		samples += 1

	# Background conversation is layered over state, so it is counted
	# separately rather than as a state bucket - a customer can be both
	# DRINKING and talking, and reporting them as one or the other would
	# hide exactly the thing this pass is about.
	for customer: Node in get_tree().get_nodes_in_group(
		&"navigation_customers"
	):
		if customer.has_method(&"is_in_conversation") and customer.call(
			&"is_in_conversation"
		):
			tally["IN CONVERSATION (overlaid)"] = int(
				tally.get("IN CONVERSATION (overlaid)", 0)
			) + 1

	for node: Node in get_tree().get_nodes_in_group(&"reservable_tag_darts"):
		if node.has_method("is_reserved") and node.call("is_reserved"):
			var board: String = String(node.get_parent().name)

			darts_by_board[board] = int(darts_by_board.get(board, 0)) + 1


func _label(state: int) -> String:
	match state:
		Customer.State.DRINKING:
			return "drinking"
		Customer.State.RELAXING:
			return "relaxing"
		Customer.State.SOCIALISING:
			return "socialising"
		Customer.State.USING_ACTIVITY:
			return "darts"
		Customer.State.MOVING_TO_ACTIVITY, Customer.State.RETURNING_TO_SEAT:
			return "travelling to/from darts"
		Customer.State.IN_GROUP:
			return "in group"
		Customer.State.WAITING_TO_ORDER, Customer.State.ORDERING:
			return "ordering"

	return "other (moving, entering, leaving)"


func _report() -> void:
	print("\n=== Customer time distribution ===")
	print("samples: %d customer-ticks" % samples)

	var rows: Array = []

	for label: String in tally:
		rows.append([label, int(tally[label])])

	rows.sort_custom(func(a, b): return a[1] > b[1])

	for row: Array in rows:
		print("  %-28s %6.1f%%  (%d)" % [
			row[0], (float(row[1]) / maxf(1.0, float(samples))) * 100.0, row[1]
		])

	var service: Node = get_tree().get_first_node_in_group(
		&"social_presence_service"
	)

	if service != null:
		print("\n=== conversation ===")

		var diagnostics: Dictionary = service.call(&"get_diagnostics")

		for key: String in diagnostics:
			print("  %-32s %s" % [key, str(diagnostics[key])])

	print("\n=== dartboard usage ===")

	if darts_by_board.is_empty():
		print("  no board was ever occupied")
	else:
		for board: String in darts_by_board:
			print("  %-14s occupied for %d ticks" % [
				board, darts_by_board[board]
			])
