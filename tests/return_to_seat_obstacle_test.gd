extends Node

## Regression test for the return-to-seat stall traced in
## docs/history/2026-08-25_FINAL_DIAGNOSTIC.md: Chair.occupied_obstacle
## (a NavigationObstacle2D, radius 22 + 4px offset) stayed avoidance_enabled
## the whole time a customer was away visiting an activity, while
## seat_arrival_distance (2px) is far inside that obstacle's own radius -
## so a customer returning to a chair it never released was avoidance-
## blocked by its own obstacle before it could ever get close enough to
## arrive. Fix: Customer.begin_visiting_activity()/
## begin_visiting_activity_as_partner() now disable the chair's occupied
## zone for the trip; _on_returned_to_seat() already re-enables it.
##
## Uses the real chair.tscn/customer.tscn/darts_point.tscn scenes - no
## mocks - and drives the actual public methods rather than reaching into
## Chair/Customer internals beyond the one field (occupied_obstacle) this
## bug is about.


var passed: int = 0
var failed: int = 0


func _ready() -> void:
	_run()

	print("\n=== RESULT: %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _check(label: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("  [PASS] " + label)
	else:
		failed += 1
		print("  [FAIL] " + label)


func _run() -> void:
	var chair: Chair = load("res://scenes/furniture/chair.tscn").instantiate()
	chair.global_position = Vector2(500, 500)
	add_child(chair)

	var registry: ActivityRegistry = load(
		"res://Data/customer_ai/activity_registry.tres"
	)

	var customer: Customer = load("res://scenes/customers/customer.tscn").instantiate()
	customer.global_position = Vector2(500, 500)
	add_child(customer)

	# _on_returned_to_seat() calls _brain.think() when a brain is configured,
	# begin_leaving() (which releases the chair, re-disabling the zone as
	# part of normal departure cleanup) otherwise - a real brain is needed
	# here so the re-enable this test checks for is not immediately undone
	# by an unrelated, correct fallback path.
	customer.needs = CustomerNeeds.new()
	# think()'s very first check forces a leave (force_activity(&"leave",
	# &"out_of_money")) whenever wealth <= 0 - CustomerNeeds.new() defaults
	# to 0, which would otherwise make _on_returned_to_seat() -> think()
	# immediately leave (releasing the chair, re-disabling the zone as
	# part of that unrelated, correct path) before this test's assertion
	# ever runs.
	customer.needs.set_context_value(&"wealth", 30.0)
	# think() -> order_drink -> choose_order() needs a real CustomerType to
	# pick an affordable drink from - without one it errors and gives up by
	# calling begin_leaving() itself, an unrelated failure mode that would
	# also re-disable the zone and mask this test's actual assertion.
	customer.customer_type = load("res://resources/CustomerTypes/pirate.tres")
	customer._brain = CustomerBrain.new()
	customer._brain.configure(customer, customer.needs, registry)
	customer.reserved_chair = chair
	chair.reservable.reserve(customer)
	chair.reservable.occupy(customer)
	chair.set_occupied_zone_enabled(true)

	_check(
		"setup: chair's occupied zone is enabled once the customer is seated",
		chair.occupied_obstacle.avoidance_enabled
	)

	var darts_point: TavernActivityPoint = load(
		"res://scenes/furniture/darts_point.tscn"
	).instantiate()
	darts_point.global_position = Vector2(800, 800)
	add_child(darts_point)

	customer.begin_visiting_activity(darts_point, darts_point.slots[0])

	_check(
		"begin_visiting_activity() disables the chair's occupied zone" +
		" (this customer must be able to walk back through it later)",
		not chair.occupied_obstacle.avoidance_enabled
	)
	_check(
		"begin_visiting_activity() does not release the chair reservation" +
		" (reserved_chair is left completely untouched, by design)",
		customer.reserved_chair == chair and chair.reservable.is_held_by(customer)
	)

	customer._on_returned_to_seat()

	_check(
		"_on_returned_to_seat() re-enables the chair's occupied zone",
		chair.occupied_obstacle.avoidance_enabled
	)

	# The partner path (begin_visiting_activity_as_partner) needs the same
	# fix - a second customer, its own chair, co-opted into the same darts
	# point's second slot.
	var chair_b: Chair = load("res://scenes/furniture/chair.tscn").instantiate()
	chair_b.global_position = Vector2(520, 500)
	add_child(chair_b)

	var partner: Customer = load("res://scenes/customers/customer.tscn").instantiate()
	partner.global_position = Vector2(520, 500)
	add_child(partner)

	partner.reserved_chair = chair_b
	chair_b.reservable.reserve(partner)
	chair_b.reservable.occupy(partner)
	chair_b.set_occupied_zone_enabled(true)

	var darts_definition: ActivityDefinition = registry.get_definition(
		&"visit_tavern_activity"
	)

	partner.begin_visiting_activity_as_partner(
		darts_point, darts_point.slots[1], darts_definition, customer
	)

	_check(
		"begin_visiting_activity_as_partner() disables the partner's own" +
		" chair's occupied zone",
		not chair_b.occupied_obstacle.avoidance_enabled
	)
