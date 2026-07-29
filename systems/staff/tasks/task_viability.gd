class_name TaskViability
extends RefCounted

## Estimates whether a worker can finish a task before it stops mattering.
##
## The estimate is assembled from parts the executor understands and the
## evaluator does not:
##
## [codeblock]
## travel to the source     only when the worker is not already carrying it
## collecting                one interaction overhead
## travel to the target      source -> customer, or worker -> customer
## performing                one interaction overhead, plus any action time
## [/codeblock]
##
## The executor supplies the legs, because only it knows that serving needs a
## trip to the bar first and cleaning does not. This class turns those legs
## into minutes, compares them against the deadline, and hands back a verdict
## with every intermediate number attached so a report can explain the
## decision rather than just state it.
##
## Cached per task: pathfinding for every candidate on every evaluation is the
## one thing here that could get expensive, so a computed path length is
## reused for [member TaskViabilityConfig.maximum_path_estimate_age_seconds].


## Result keys, documented here rather than in a second class:
##
## [codeblock]
## has_estimate       bool     false when nothing could be worked out
## estimated_minutes  float    predicted time to finish
## deadline_minutes   float    time until the task stops being achievable
## margin_minutes     float    deadline - estimate - safety buffer
## verdict            TaskViabilityConfig.Verdict
## score              float    contribution to the task's total score
## permits_claim      bool
## travel_pixels      float    distance the estimate was built from
## detail             String   human-readable summary
## [/codeblock]
const HAS_ESTIMATE: StringName = &"has_estimate"


## Works out how viable [param task] is for [param worker].
static func evaluate(
	worker: Node,
	task: TavernTask,
	executor: StaffTaskExecutor,
	config: TaskViabilityConfig
) -> Dictionary:
	if config == null or not config.enabled:
		return _unknown(config, "viability checking is disabled")

	if executor == null:
		return _unknown(config, "no executor")

	var deadline: float = executor.get_deadline_minutes(worker, task)

	if deadline < 0.0:
		# No deadline means nothing can expire, so nothing can be non-viable.
		# Cleaning tasks live here.
		return _unknown(config, "task has no deadline")

	var travel_pixels: float = executor.estimate_travel_pixels(worker, task)

	if travel_pixels < 0.0:
		return _unknown(config, "no travel estimate available")

	var speed: float = _get_speed(worker, config)

	if speed <= 0.0:
		return _unknown(config, "worker speed is unknown")

	# Travel time in real seconds, converted to world minutes. The world clock
	# is the only shared unit patience and estimates can both be expressed in.
	var travel_seconds: float = travel_pixels / speed

	var travel_minutes: float = _seconds_to_world_minutes(travel_seconds)

	var overhead: float = (
		config.interaction_overhead_minutes
		* float(executor.get_interaction_count(worker, task))
	)

	var action_minutes: float = _seconds_to_world_minutes(
		executor.estimate_action_seconds(worker, task)
	)

	var estimated: float = travel_minutes + overhead + action_minutes

	var margin: float = deadline - estimated - config.safety_buffer_minutes

	var verdict: TaskViabilityConfig.Verdict = config.classify(margin, true)

	return {
		HAS_ESTIMATE: true,
		"estimated_minutes": estimated,
		"deadline_minutes": deadline,
		"margin_minutes": margin,
		"verdict": verdict,
		"verdict_name": TaskViabilityConfig.get_verdict_name(verdict),
		"score": config.get_score_contribution(verdict, margin),
		"permits_claim": config.permits_claim(verdict),
		"travel_pixels": travel_pixels,
		"detail": (
			"travel %.0fpx (%.1fm) + overhead %.1fm + action %.1fm "
			% [travel_pixels, travel_minutes, overhead, action_minutes]
			+ "vs %.1fm remaining" % deadline
		),
	}


static func _unknown(
	config: TaskViabilityConfig,
	detail: String
) -> Dictionary:
	var permits: bool = (
		true if config == null else config.accept_unknown_viability
	)

	return {
		HAS_ESTIMATE: false,
		"estimated_minutes": -1.0,
		"deadline_minutes": -1.0,
		"margin_minutes": 0.0,
		"verdict": TaskViabilityConfig.Verdict.UNKNOWN,
		"verdict_name": "UNKNOWN",
		"score": 0.0,
		"permits_claim": permits,
		"travel_pixels": -1.0,
		"detail": detail,
	}


## Straight-line or navigated distance between two points.
##
## Caches on the task so a candidate considered several times in quick
## succession is only pathfound once.
static func measure_distance(
	worker: Node,
	task: TavernTask,
	cache_key: String,
	from_position: Vector2,
	to_position: Vector2,
	config: TaskViabilityConfig
) -> float:
	var straight: float = from_position.distance_to(to_position)

	if config == null or not config.use_navigation_path_length:
		return straight * _get_detour_factor(config)

	var cached: Dictionary = task.path_estimate_cache.get(cache_key, {})

	if not cached.is_empty():
		var age_ms: int = Time.get_ticks_msec() - int(cached.get("ticks", 0))

		var maximum_age_ms: int = int(
			config.maximum_path_estimate_age_seconds * 1000.0
		)

		if age_ms <= maximum_age_ms:
			return float(cached.get("length", straight))

	var worker_2d: Node2D = worker as Node2D

	if worker_2d == null:
		return straight * _get_detour_factor(config)

	var map: RID = worker_2d.get_world_2d().navigation_map

	var length: float = NavigationService.get_path_length(
		map,
		from_position,
		to_position
	)

	if length == INF or length <= 0.0:
		# Unreachable, or the map is not ready. Fall back rather than treating
		# an unavailable measurement as an infinite journey, which would make
		# every task look impossible on the first frame.
		length = straight * _get_detour_factor(config)

	task.path_estimate_cache[cache_key] = {
		"length": length,
		"ticks": Time.get_ticks_msec(),
	}

	return length


static func _get_detour_factor(
	config: TaskViabilityConfig
) -> float:
	return 1.35 if config == null else config.straight_line_detour_factor


static func _get_speed(
	worker: Node,
	config: TaskViabilityConfig
) -> float:
	if worker != null and worker.has_method(&"get_movement_speed"):
		var speed: float = float(worker.call(&"get_movement_speed"))

		if speed > 0.0:
			return speed

	return config.fallback_speed


## Real seconds into world minutes, using the project's own clock rate.
##
## Going through [WorldTime] rather than assuming a conversion means changing
## how fast a day runs does not silently invalidate every estimate.
static func _seconds_to_world_minutes(
	seconds: float
) -> float:
	if seconds <= 0.0:
		return 0.0

	var config: GameTimeConfig = WorldTime.get_config()

	if config == null or config.game_minutes_per_real_second <= 0.0:
		return seconds / 60.0

	# Deliberately at speed 1.0 rather than the current speed: the worker walks
	# at a constant real pace while the world may be fast-forwarded, so a
	# fast-forwarded tavern genuinely does give a worker less time per
	# customer, and the estimate should say so.
	return seconds * config.game_minutes_per_real_second
