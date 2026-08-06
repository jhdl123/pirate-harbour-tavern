extends Node

## Runs a busy tavern and prints the navigation report, so the telemetry is
## proved against real traffic rather than a unit test.

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

	# Fill it and let it run long enough for real traffic.
	var attempts: int = 0

	while attempts < 80:
		if game_manager != null and game_manager.has_method("spawn_customer"):
			game_manager.call("spawn_customer")

		attempts += 1

		await get_tree().create_timer(0.5).timeout

	await get_tree().create_timer(10.0).timeout

	var report: Dictionary = NavigationReport.build(get_tree())

	print("\n" + NavigationReport.format_summary(report))

	get_tree().quit()
