extends Node

## Watches customers arrive, using the new lifecycle trace.
##
## Answers the question the earlier reports could not: do customers actually
## get inside, and if not, where do they stop?

var passed: int = 0
var failed: int = 0

var main: Node
var game_manager: Node
var report_manager: Node


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	for _i in range(8):
		await get_tree().process_frame

	game_manager = main.get_node_or_null(^"Managers/GameManager")
	report_manager = main.get_node_or_null(^"Managers/CustomerAIReportManager")

	await _run_arrivals()
	_report()


func _run_arrivals() -> void:
	_check(
		report_manager != null,
		"TRACE: the report manager is present",
		"TRACE: no report manager"
	)

	# The tavern must actually be open, or spawn_customer refuses every
	# arrival - which would make this test pass for the wrong reason.
	# Hypothesis check: is the door spread scattering customers off the
	# navigation mesh so they can never path anywhere?
	if OS.get_environment("NO_DOOR_SPREAD") == "1":
		var d: CustomerDoor = main.get_node_or_null(^"Markers/CustomerDoor")
		d.spawn_spread = 0.0
		d.inside_spread = 0.0
		d.exit_spread = 0.0
		print("  (door spread disabled for this run)")

	Tavern.open_early()

	await get_tree().process_frame

	_check(
		Tavern.is_accepting_arrivals(),
		"TRACE: the tavern is open for arrivals",
		"TRACE: the tavern refused to open (state %s)" % Tavern.current_state
	)

	# Spawn a handful and let them walk.
	for _i in range(5):
		game_manager.spawn_customer()

		for _f in range(20):
			await get_tree().process_frame

	for _f in range(240):
		WorldTime.advance_minutes(1) if _f % 30 == 0 else null
		await get_tree().process_frame

	var customers: Array[Node] = get_tree().get_nodes_in_group(
		&"navigation_customers"
	)

	_check(
		customers.size() > 0,
		"TRACE: %d customers are in the tavern" % customers.size(),
		"TRACE: no customers spawned at all"
	)

	var door: Node2D = main.get_node_or_null(^"Markers/CustomerDoor")
	var inside: Vector2 = door.get_inside_position()

	var entered: int = 0
	var states: Dictionary = {}

	for customer: Node in customers:
		var state_name: String = Customer.State.keys()[
			customer.get(&"current_state")
		]
		states[state_name] = int(states.get(state_name, 0)) + 1

		var position: Vector2 = (customer as Node2D).global_position

		# Anyone past the doorway counts as having got in.
		if position.distance_to(inside) < 200.0:
			entered += 1

	print("  STATES: %s" % str(states))

	var nav: Node = main.get_node_or_null(^"NavigationRegion2D")
	print("  SIM: state=%s paused=%s nav_ready=%s" % [
		Simulation.get_state_name() if Simulation.has_method(&"get_state_name")
			else str(Simulation.current_state),
		Simulation.is_paused() if Simulation.has_method(&"is_paused") else "?",
		nav.is_navigation_ready if nav != null else "?",
	])

	var sample: Node2D = customers[0] as Node2D
	print("  SAMPLE: pos=%s target=%s door_inside=%s dist=%.1f" % [
		str(sample.global_position),
		str(sample.get(&"entrance_inside_position")),
		str(inside),
		sample.global_position.distance_to(
			sample.get(&"entrance_inside_position")
		),
	])

	_check(
		entered == customers.size(),
		"TRACE: all %d customers got inside the tavern" % entered,
		"TRACE: only %d of %d got inside - the rest are stuck outside"
			% [entered, customers.size()]
	)

	# Nobody should still be in ENTERING after four game hours.
	var still_entering: int = int(states.get("ENTERING", 0))

	_check(
		still_entering == 0,
		"TRACE: nobody is stuck in ENTERING",
		"TRACE: %d customers never finished ENTERING - they cannot get "
			% still_entering + "through the door"
	)

	# The trace itself must be populated, or the next report is useless again.
	var traced: int = 0

	for customer: Node in customers:
		if customer.has_method(&"report_position_to"):
			traced += 1

	_check(
		traced == customers.size(),
		"TRACE: every customer can report its position to the exporter",
		"TRACE: %d of %d customers cannot" % [traced, customers.size()]
	)


func _check(condition: bool, pass_text: String, fail_text: String) -> void:
	if condition:
		passed += 1
		print("  [PASS] " + pass_text)
	else:
		failed += 1
		print("  [FAIL] " + fail_text)


func _report() -> void:
	print("")
	print("  passed: %d  failed: %d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
