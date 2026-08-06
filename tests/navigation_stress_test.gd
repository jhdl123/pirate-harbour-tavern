extends Node

## Navigation and collision avoidance verification.
##
## Runs against main.tscn with real actors, because the whole point of this
## pass is behaviour under crowding - a unit test on the steering maths would
## pass while actors still ground against each other in a doorway.

var passed: int = 0
var failed: int = 0

var main: Node
var game_manager: Node
var customer_nav: ActorNavigationProfile
var staff_nav: ActorNavigationProfile


func _ready() -> void:
	customer_nav = load("res://Data/navigation/customer_navigation.tres")
	staff_nav = load("res://Data/navigation/staff_navigation.tres")

	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)

	for _i: int in range(10):
		await get_tree().process_frame

	game_manager = main.get_node_or_null(^"Managers/GameManager")

	_quieten()

	_test_profiles_authored()
	_test_profiles_differentiated()
	_test_parked_yields()
	_test_personal_variation()
	_test_passing_bias()
	await _test_level_geometry()
	await _test_crowd_movement()

	print("\n=== RESULT: %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _check(label: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("  [PASS] " + label)
	else:
		failed += 1
		print("  [FAIL] " + label)


func _quieten() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"navigation_debugger"):
		node.set(&"enabled", false)

	var debugger: Node = main.get_node_or_null(^"NavigationDebugger")

	if debugger != null:
		debugger.set(&"enabled", false)


# --- Profiles ----------------------------------------------------------------

func _test_profiles_authored() -> void:
	print("\n--- profiles are authored, not defaults ---")

	_check("customer profile loads", customer_nav != null)
	_check("staff profile loads", staff_nav != null)

	# Both files were previously empty, so every value was a code default.
	_check(
		"customer profile has organic movement values",
		customer_nav.lateral_path_offset > 0.0
		and customer_nav.passing_side_bias > 0.0
		and customer_nav.speed_variation > 0.0
	)
	_check(
		"staff profile has organic movement values",
		staff_nav.passing_side_bias > 0.0
	)


func _test_profiles_differentiated() -> void:
	print("\n--- staff and customers steer differently ---")

	_check(
		"staff outrank customers in avoidance",
		staff_nav.avoidance_priority > customer_nav.avoidance_priority
	)
	_check(
		"working staff outrank everything else",
		staff_nav.working_priority > staff_nav.avoidance_priority
		and staff_nav.working_priority > customer_nav.working_priority
	)
	_check(
		"staff hold a tighter line than customers",
		staff_nav.lateral_path_offset < customer_nav.lateral_path_offset
	)
	_check(
		"staff walk at more uniform speeds than customers",
		staff_nav.speed_variation < customer_nav.speed_variation
	)
	_check(
		"staff repath more readily",
		staff_nav.minimum_repath_interval < customer_nav.minimum_repath_interval
	)


func _test_parked_yields() -> void:
	print("\n--- parked actors yield rather than shove ---")

	# The 4 August keg-delivery failures were seated customers at maximum
	# avoidance priority pushing staff off their approach.
	_check(
		"a parked customer yields to a traveller",
		customer_nav.parked_yield_priority < customer_nav.avoidance_priority
	)
	_check(
		"a parked customer yields to working staff",
		customer_nav.parked_yield_priority < staff_nav.working_priority
	)
	_check(
		"a parked staff member still yields",
		staff_nav.parked_yield_priority < staff_nav.working_priority
	)


# --- Per-actor variation -----------------------------------------------------

func _test_personal_variation() -> void:
	print("\n--- actors are individually varied ---")

	var sides: Dictionary = {}
	var speeds: Dictionary = {}

	for index: int in 40:
		var nav: ActorNavigation = ActorNavigation.new()

		nav.profile = customer_nav
		nav.seed_personal_movement(0, 0.5)

		sides[nav.get_passing_side()] = true
		speeds[snappedf(nav.get_speed_multiplier(), 0.001)] = true

		nav.free()

	_check(
		"actors take both passing sides (%d distinct)" % sides.size(),
		sides.size() == 2
	)
	_check(
		"actors walk at varied speeds (%d distinct of 40)" % speeds.size(),
		speeds.size() > 20
	)

	# Determinism, so a reproducible run reproduces movement too.
	var first: ActorNavigation = ActorNavigation.new()
	var second: ActorNavigation = ActorNavigation.new()

	first.profile = customer_nav
	second.profile = customer_nav
	first.seed_personal_movement(9876, 0.5)
	second.seed_personal_movement(9876, 0.5)

	_check(
		"the same seed reproduces passing side",
		first.get_passing_side() == second.get_passing_side()
	)
	_check(
		"the same seed reproduces speed",
		is_equal_approx(
			first.get_speed_multiplier(), second.get_speed_multiplier()
		)
	)

	# Restlessness should shift the speed distribution.
	var placid_total: float = 0.0
	var restless_total: float = 0.0

	for index: int in 60:
		var placid: ActorNavigation = ActorNavigation.new()
		var restless: ActorNavigation = ActorNavigation.new()

		placid.profile = customer_nav
		restless.profile = customer_nav
		placid.seed_personal_movement(0, 0.1)
		restless.seed_personal_movement(0, 0.9)

		placid_total += placid.get_speed_multiplier()
		restless_total += restless.get_speed_multiplier()

		placid.free()
		restless.free()

	print(
		"    placid mean %.3f  restless mean %.3f"
		% [placid_total / 60.0, restless_total / 60.0]
	)

	_check(
		"restless actors walk faster than placid ones",
		restless_total > placid_total
	)

	first.free()
	second.free()


func _test_passing_bias() -> void:
	print("\n--- passing bias engages only when obstructed ---")

	var nav: ActorNavigation = ActorNavigation.new()

	nav.profile = customer_nav
	nav.seed_personal_movement(1234, 0.5)

	var desired: Vector2 = Vector2.RIGHT

	# Walking freely: the solver agrees with the desired direction, so the
	# bias must not fire or every actor would curve across open floor.
	var free_velocity: Vector2 = Vector2.RIGHT * 100.0
	var unbiased: Vector2 = nav._apply_passing_bias(free_velocity, desired)

	_check(
		"an unobstructed actor is not deflected",
		unbiased.normalized().dot(desired) > 0.99
	)

	# Heavily deflected: the solver has turned the actor well off course,
	# which is the head-on standoff case.
	var blocked: Vector2 = Vector2(0.2, 0.98).normalized() * 100.0
	var biased: Vector2 = nav._apply_passing_bias(blocked, desired)

	_check(
		"an obstructed actor is nudged to its preferred side",
		not biased.is_equal_approx(blocked)
	)
	_check(
		"the nudge preserves speed",
		is_equal_approx(biased.length(), blocked.length())
	)

	# Two actors meeting head-on with opposite sides must diverge, which is
	# the entire point - matching sides is the mirror dance.
	var left: ActorNavigation = ActorNavigation.new()
	var right: ActorNavigation = ActorNavigation.new()

	left.profile = customer_nav
	right.profile = customer_nav
	left.seed_personal_movement(1, 0.5)
	right.seed_personal_movement(1, 0.5)
	left._passing_side = 1.0
	right._passing_side = -1.0

	var left_out: Vector2 = left._apply_passing_bias(blocked, desired)
	var right_out: Vector2 = right._apply_passing_bias(blocked, desired)

	_check(
		"opposite sides produce diverging manoeuvres",
		left_out.angle_to(right_out) != 0.0
	)

	nav.free()
	left.free()
	right.free()


# --- Level geometry ----------------------------------------------------------

func _test_level_geometry() -> void:
	print("\n--- every destination is reachable ---")

	await get_tree().create_timer(1.0).timeout

	var problems: Array[Dictionary] = (
		NavigationValidator.find_unreachable_points(get_tree())
	)

	for problem: Dictionary in problems:
		print(
			"    %s '%s' is %.1fpx off"
			% [
				problem["kind"], problem["node_path"],
				problem["off_mesh_distance"],
			]
		)

	_check(
		"no seat, formation slot or service point is off the navmesh (%d found)"
		% problems.size(),
		problems.is_empty()
	)


# --- Crowd behaviour ---------------------------------------------------------

func _test_crowd_movement() -> void:
	print("\n--- crowd moves without sticking ---")

	if game_manager == null:
		_check("game manager present", false)
		return

	# Fill the tavern well past its normal population.
	#
	# spawn_customer() is gated on Tavern.is_accepting_arrivals(), and the
	# scene starts before opening - calling it in a loop at scene start
	# silently records 16 tavern_not_open rejections and spawns nothing.
	# Group arrivals are disabled so this measures solo traffic, which is
	# the crowded case that matters here.
	game_manager.set(&"enable_automatic_group_arrivals", false)

	if not Tavern.is_accepting_arrivals():
		Tavern.open_early()

	var attempts: int = 0

	while (
		get_tree().get_nodes_in_group(&"navigation_customers").size() < 12
		and attempts < 60
	):
		if game_manager.has_method("spawn_customer"):
			game_manager.call("spawn_customer")

		attempts += 1

		await get_tree().create_timer(0.25).timeout

	await get_tree().create_timer(3.0).timeout

	var customers: Array[Node] = get_tree().get_nodes_in_group(&"navigation_customers")

	print("    population: %d" % customers.size())

	_check("the tavern filled", customers.size() >= 8)

	# Sample positions, wait, sample again. An actor that is trying to move
	# but has not moved is stuck; one that is parked or idle is fine.
	var before: Dictionary = {}

	for customer: Node in customers:
		if is_instance_valid(customer):
			before[customer.get_instance_id()] = (
				customer as Node2D
			).global_position

	await get_tree().create_timer(6.0).timeout

	var travelling: int = 0
	var stuck: int = 0
	var overlapping: int = 0

	var positions: Array[Vector2] = []

	for customer: Node in customers:
		if not is_instance_valid(customer):
			continue

		var nav: Variant = customer.get(&"actor_navigation")

		if nav == null:
			continue

		var node_2d: Node2D = customer as Node2D

		positions.append(node_2d.global_position)

		if not nav.call("is_travelling"):
			continue

		travelling += 1

		var start: Vector2 = before.get(
			customer.get_instance_id(), node_2d.global_position
		)

		if start.distance_to(node_2d.global_position) < 8.0:
			stuck += 1

	# Nothing should be inside another actor's body.
	var floor_distance: float = customer_nav.avoidance_radius

	for a: int in positions.size():
		for b: int in range(a + 1, positions.size()):
			if positions[a].distance_to(positions[b]) < floor_distance:
				overlapping += 1

	print(
		"    travelling %d, stuck %d, overlapping pairs %d"
		% [travelling, stuck, overlapping]
	)

	_check(
		"actors that want to move are moving (%d stuck of %d travelling)"
		% [stuck, travelling],
		stuck == 0 or travelling == 0
	)
	_check(
		"no two actors occupy the same space (%d pairs)" % overlapping,
		overlapping == 0
	)
