extends Node

## Reproduces the seats-leak that strands customers at the door.
##
## A group reserves chairs as the GROUP, then hands one to each member. When
## that member later releases its chair it releases as ITSELF - and
## Reservable.release() silently ignores a holder mismatch, so the chair is
## never freed. Seats drain away one visit at a time until nobody can sit.

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	_test_holder_mismatch_is_silent()
	_test_group_seat_handover_leaks()
	_test_group_releases_unused_chairs()
	_report()


func _test_holder_mismatch_is_silent() -> void:
	var reservable := Reservable.new()
	add_child(reservable)

	var owner_a := Node.new()
	var owner_b := Node.new()
	add_child(owner_a)
	add_child(owner_b)

	reservable.reserve(owner_a)

	# The behaviour at the heart of the bug.
	reservable.release(owner_b)

	_check(
		not reservable.is_free(),
		"CAUSE: releasing with the wrong holder is silently ignored",
		"CAUSE: the mismatched release actually worked"
	)

	reservable.release(owner_a)

	_check(
		reservable.is_free(),
		"CAUSE: releasing with the correct holder works",
		"CAUSE: the correct release failed too"
	)


func _test_group_seat_handover_leaks() -> void:
	var chair_scene: PackedScene = load("res://scenes/furniture/chair.tscn")
	var chair: Chair = chair_scene.instantiate()
	add_child(chair)

	var group := Node.new()
	var member := Node.new()
	add_child(group)
	add_child(member)

	# Exactly what GroupPlace.reserve_seated does.
	_check(
		chair.assign_customer(group),
		"LEAK: the group reserved the chair",
		"LEAK: the group could not reserve the chair"
	)

	# What Customer.assign_group_chair() now does on handover.
	chair.transfer_reservation(member)

	# Exactly what Customer.release_reserved_chair() does when the visit ends.
	chair.release_reservation(member)

	_check(
		chair.is_available(),
		"LEAK: the chair was returned when the member left",
		"LEAK: the chair is STILL held - this is the seat leak. A group's "
			+ "chairs are never freed by their members, so seating drains "
			+ "away and later customers are stranded at the door."
	)


## A group that never seats its members must still free its own chairs.
func _test_group_releases_unused_chairs() -> void:
	var chair_scene: PackedScene = load("res://scenes/furniture/chair.tscn")
	var chair: Chair = chair_scene.instantiate()
	add_child(chair)

	var group := Node.new()
	add_child(group)

	chair.assign_customer(group)
	chair.release_reservation(group)

	_check(
		chair.is_available(),
		"ROLLBACK: a group frees chairs it booked but never handed out",
		"ROLLBACK: the group's own chairs leaked"
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
