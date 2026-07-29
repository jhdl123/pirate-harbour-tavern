extends Node

## Focused probe: how long does one cleaning job actually take, with nothing
## else competing for the worker's attention?

const MAIN_SCENE: String = "res://scenes/main/main.tscn"

var _main: Node = null
var _worker: Node = null
var _chair: Chair = null
var _elapsed: float = 0.0
var _log_elapsed: float = 0.0
var _started_minutes: float = 0.0
var _armed: bool = false


func _ready() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)

	# Stop customer spawning so the worker has exactly one job.
	var manager: Node = _main.get_node_or_null("Managers/GameManager")
	if manager != null:
		var config: GameConfig = manager.get(&"game_config") as GameConfig
		if config != null:
			config.maximum_active_customers = 0
			config.ignore_customer_limit = false


func _process(delta: float) -> void:
	_elapsed += delta

	if not _armed and _elapsed > 1.5:
		_armed = true
		var workers: Array = get_tree().get_nodes_in_group(&"tavern_staff")
		_worker = workers[0] if not workers.is_empty() else null

		for node: Node in get_tree().get_nodes_in_group(
			Reservable.group_for_tag(&"seat")
		):
			var reservable: Reservable = node as Reservable
			if reservable == null or not reservable.is_free():
				continue
			var chair: Chair = reservable.get_parent() as Chair
			if chair == null or chair.empty_glass_task == null:
				continue
			if chair.cleanable.has_cleaning_task():
				continue
			_chair = chair
			break

		if _worker == null or _chair == null:
			print("PROBE: could not set up")
			get_tree().quit(1)
			return

		_started_minutes = WorldTime.get_total_minutes_precise()

		print("PROBE: worker at ", (_worker as Node2D).global_position)
		print("PROBE: chair ", _chair.name, " at ", _chair.global_position)
		print("PROBE: staging ", _chair.get_staging_position())

		_chair.cleanable.set_cleaning_task(_chair.empty_glass_task)
		return

	if not _armed:
		return

	_log_elapsed += delta

	if _log_elapsed >= 1.0:
		_log_elapsed = 0.0
		print(
			"PROBE t=%.1fs world=%.1fmin | %s | pos=%s | dist=%.0f"
			% [
				_elapsed,
				WorldTime.get_total_minutes_precise() - _started_minutes,
				_worker.call(&"get_debug_line"),
				str((_worker as Node2D).global_position.round()),
				(_worker as Node2D).global_position.distance_to(
					_chair.global_position
				),
			]
		)

	if not _chair.cleanable.has_cleaning_task():
		print(
			"PROBE: cleaned after %.1f real seconds / %.1f world minutes"
			% [
				_elapsed,
				WorldTime.get_total_minutes_precise() - _started_minutes,
			]
		)
		get_tree().quit(0)

	if _elapsed > 60.0:
		print("PROBE: TIMED OUT")
		get_tree().quit(1)
