extends Node

## A/B benchmark for the Phase 3A.1 selection changes.
##
## Runs the tavern under sustained overload with an attentive simulated player
## keeping the bar stocked, then reports the churn figures. Pass
## [code]--legacy[/code] to disable the Phase 3A.1 additions and reproduce the
## Phase 3A selection behaviour for comparison:
##
## [codeblock]
## godot --headless --fixed-fps 60 res://tests/phase_3a1_benchmark.tscn
## godot --headless --fixed-fps 60 res://tests/phase_3a1_benchmark.tscn -- --legacy
## [/codeblock]
##
## The point is not to make the completion rate high. Demand deliberately
## exceeds one worker's capacity, so customers will leave unserved either way.
## The question is how much time the worker wastes on jobs it was never going
## to finish.

const MAIN_SCENE_PATH: String = "res://scenes/main/main.tscn"
const RUN_FRAMES: int = 9000

var _main: Node = null
var _legacy: bool = false


func _ready() -> void:
	_legacy = OS.get_cmdline_user_args().has("--legacy")

	_main = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()

	add_child(_main)

	await get_tree().process_frame

	if _legacy:
		# Reproduce Phase 3A: no viability term, no commitment hysteresis.
		var viability: TaskViabilityConfig = TaskBoard.get_viability_config()

		if viability != null:
			viability.enabled = false

		TaskBoard.config.same_worker_reclaim_cooldown_seconds = 0.0
		TaskBoard.config.task_switch_score_margin = 0.0
		TaskBoard.config.minimum_commitment_minutes = 0.0

	await _wait_frames(60)

	for frame: int in range(RUN_FRAMES):
		if frame % 30 == 0:
			_restock_bar()

		await get_tree().process_frame

	_report()


## Stands in for an attentive player pouring what customers have ordered.
func _restock_bar() -> void:
	var game_manager: GameManager = _main.get_node_or_null(
		"Managers/GameManager"
	) as GameManager

	if game_manager == null:
		return

	var wanted: Array[DrinkDefinition] = []

	for customer: Node in game_manager.active_customers:
		if customer == null or not is_instance_valid(customer):
			continue

		if not customer.has_method(&"is_awaiting_service"):
			continue

		if not bool(customer.call(&"is_awaiting_service")):
			continue

		var drink: DrinkDefinition = customer.call(&"get_requested_drink")

		if drink != null:
			wanted.append(drink)

	if wanted.is_empty():
		return

	for node: Node in get_tree().get_nodes_in_group(&"bar_counters"):
		var container: ItemContainer = node.call(
			&"get_service_container"
		) as ItemContainer

		if container == null:
			continue

		for index: int in range(container.get_slot_count()):
			if wanted.is_empty():
				return

			var slot: ItemSlot = container.get_slot(index)

			if slot == null or not slot.is_empty():
				continue

			ItemTransferService.give_to_slot(
				slot,
				ItemStack.create(wanted.pop_front(), 1)
			)


func _wait_frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame


func _report() -> void:
	var summary: Dictionary = TaskBoard.get_summary()
	var breakdown: Dictionary = TaskBoard.build_task_type_breakdown()

	var serve: Dictionary = breakdown.get("serve_drink", {})

	var worker_switches: int = 0
	var recoveries: int = 0

	for node: Node in get_tree().get_nodes_in_group(&"tavern_staff"):
		var snapshot: Dictionary = node.call(&"get_diagnostics_snapshot")

		worker_switches += int(snapshot.get("task_switches", 0))
		recoveries += int(snapshot.get("carried_item_recoveries", 0))

	print("")
	print("=== PHASE 3A.1 BENCHMARK (%s) ===" % (
		"LEGACY 3A behaviour" if _legacy else "3A.1 refinements ON"
	))
	print("  tasks created            : %d" % summary["tasks_created"])
	print("  tasks completed          : %d" % summary["tasks_completed"])
	print("  tasks cancelled          : %d" % summary["tasks_cancelled"])
	print("  tasks failed             : %d" % summary["tasks_failed"])
	print("  non-viable rejections    : %d" % int(
		summary.get("non_viable_rejections", 0)
	))
	print("  serve completion rate    : %.3f" % float(
		serve.get("completion_rate", 0.0)
	))
	print("  serve cancellation rate  : %.3f" % float(
		serve.get("cancellation_rate", 0.0)
	))
	print("  avg minutes wasted before cancelling a serve : %.2f" % float(
		serve.get("average_invested_before_cancel_minutes", 0.0)
	))
	print("  carried-item recoveries  : %d" % recoveries)
	print("  cancellation reasons     : %s" % JSON.stringify(
		TaskBoard.get_cancellation_reason_counts()
	))
	print("==============================================")

	get_tree().quit(0)
