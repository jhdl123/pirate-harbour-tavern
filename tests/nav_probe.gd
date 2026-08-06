extends Node

func _ready() -> void:
	var scene: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().create_timer(1.0).timeout

	var map: RID = get_viewport().world_2d.navigation_map
	var nav: ActorNavigationProfile = load(
		"res://Data/navigation/customer_navigation.tres"
	)

	print("customer avoidance_radius = %.1f  -> two actors cannot be closer than %.1fpx"
		% [nav.avoidance_radius, nav.avoidance_radius * 2.0])
	print("target_desired_distance = %.1f   parked_priority = %.2f"
		% [nav.target_desired_distance, nav.parked_avoidance_priority])

	var chairs: Array[Node] = []
	_collect(scene, chairs)

	print("\nchairs: %d" % chairs.size())

	var seats: Array = []
	for chair: Node in chairs:
		var point: Node2D = chair.find_child("SeatPoint", true, false) as Node2D
		if point == null:
			continue
		var pos: Vector2 = point.global_position
		var off: float = pos.distance_to(
			NavigationServer2D.map_get_closest_point(map, pos)
		)
		seats.append({"name": chair.name, "pos": pos, "off_mesh": off})

	for a: int in seats.size():
		var s: Dictionary = seats[a]
		print("  %-12s %s  %.1fpx off navmesh %s"
			% [s["name"], str(s["pos"].round()), s["off_mesh"],
			("<-- SEAT IS OFF THE MESH" if s["off_mesh"] > 2.0 else "")])

	print("\nseat-to-seat distances (blocked below %.0fpx):"
		% (nav.avoidance_radius * 2.0))

	for a: int in seats.size():
		for b: int in range(a + 1, seats.size()):
			var d: float = seats[a]["pos"].distance_to(seats[b]["pos"])
			if d < 120.0:
				print("  %-12s <-> %-12s %6.1fpx  %s"
					% [seats[a]["name"], seats[b]["name"], d,
					("*** BLOCKED BY AVOIDANCE ***"
					if d < nav.avoidance_radius * 2.0 else "ok")])

	get_tree().quit()


func _collect(node: Node, out: Array[Node]) -> void:
	if node.get_script() != null and node.has_method("get_seat_position"):
		out.append(node)
	for child: Node in node.get_children():
		_collect(child, out)
