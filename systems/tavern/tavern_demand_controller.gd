class_name TavernDemandController
extends Node

## Keeps the time-of-day and capacity contributions to demand up to date.
##
## This node is the only thing that reads the clock in order to influence
## customer arrivals, and it does not touch the spawner. It maintains two
## modifiers on [constant ModifierTargets.CUSTOMER_ARRIVAL_RATE]:
##
## [codeblock]
## time_of_day        the demand profile's multiplier for the current minute
## capacity_pressure  a damper that slows arrivals as the tavern fills
## [/codeblock]
##
## Everything else - the spawner, events, weather, future reputation - meets
## through that one target. The spawner asks for the final number, the profile
## contributes one term, a festival contributes another, and none of them knows
## about the others.
##
## [b]Why capacity is a modifier rather than a check[/b]
##
## A hard "stop spawning when full" produces a tavern that slams shut and then
## bursts. Expressing capacity as a curve means arrivals taper as the room
## fills and recover naturally as seats free up, and - because it is an
## ordinary modifier - it shows up in the breakdown alongside everything else
## instead of being an invisible special case in the spawner.


const SOURCE_TIME_OF_DAY: StringName = &"time_of_day"
const SOURCE_CAPACITY: StringName = &"capacity_pressure"

const DEFAULT_PROFILE_PATH: String = (
	"res://Data/tavern/default_demand_profile.tres"
)


@export var demand_profile: DemandProfile = null

## How full the tavern must be before arrivals start tapering.
@export_range(0.0, 1.0, 0.05)
var capacity_pressure_threshold: float = 0.6

## Multiplier applied when the tavern is completely full.
##
## Not zero: a full tavern should become unattractive, not sealed. Customers
## leave constantly, and a hard zero produces a visible stop-start rhythm.
@export_range(0.0, 1.0, 0.05)
var full_capacity_multiplier: float = 0.15

## How often the contributions are recalculated, in world minutes.
##
## Demand curves are smooth; recomputing every frame would be waste. Five
## minutes of world time is far finer than the profile's own resolution.
@export_range(1, 120, 1)
var refresh_interval_minutes: int = 5

## Samples kept for the diagnostic export.
@export_range(0, 5000, 50)
var maximum_samples: int = 600


var _time_modifier: Modifier = null
var _capacity_modifier: Modifier = null

var _samples: Array[Dictionary] = []
var _game_manager: Node = null


func _ready() -> void:
	_resolve_profile()

	_game_manager = get_parent().get_node_or_null("GameManager")

	if _game_manager == null:
		_game_manager = get_tree().get_first_node_in_group(&"game_manager")

	# Driven by the world clock rather than a private timer, so it stays
	# correct through pauses, speed changes and large skips for free.
	WorldTime.minute_passed.connect(_on_minute_passed)

	_refresh.call_deferred()


func _resolve_profile() -> void:
	if demand_profile == null and ResourceLoader.exists(
		DEFAULT_PROFILE_PATH
	):
		demand_profile = load(DEFAULT_PROFILE_PATH) as DemandProfile

	if demand_profile == null:
		push_warning(
			"TavernDemandController has no DemandProfile; demand will stay "
			+ "flat at 1.0."
		)

		return

	demand_profile.validate_or_warn()


func _on_minute_passed(
	_stamp: GameTimeStamp
) -> void:
	if WorldTime.get_total_minutes() % refresh_interval_minutes != 0:
		return

	_refresh()


func _refresh() -> void:
	_refresh_time_of_day()
	_refresh_capacity_pressure()
	_sample()


func _refresh_time_of_day() -> void:
	if demand_profile == null:
		return

	var minutes: int = WorldTime.get_hour() * 60 + WorldTime.get_minute()

	var multiplier: float = demand_profile.get_multiplier_at(minutes)

	_time_modifier = _set_multiplier(
		_time_modifier,
		SOURCE_TIME_OF_DAY,
		multiplier,
		"Time profile: %s" % demand_profile.describe_level(multiplier).to_lower()
	)


func _refresh_capacity_pressure() -> void:
	var occupancy: float = _get_occupancy()

	var multiplier: float = 1.0

	if occupancy > capacity_pressure_threshold:
		var span: float = maxf(1.0 - capacity_pressure_threshold, 0.01)

		var t: float = clampf(
			(occupancy - capacity_pressure_threshold) / span,
			0.0,
			1.0
		)

		multiplier = lerpf(1.0, full_capacity_multiplier, t)

	_capacity_modifier = _set_multiplier(
		_capacity_modifier,
		SOURCE_CAPACITY,
		multiplier,
		"Capacity pressure (%.0f%% full)" % (occupancy * 100.0)
	)


## Replaces a controller-owned modifier with a new value.
##
## These two are continuous rather than event-driven, so they are replaced
## outright each refresh instead of stacking. REPLACE stacking makes that the
## service's job rather than something this node has to police.
func _set_multiplier(
	existing: Modifier,
	source_id: StringName,
	value: float,
	label: String
) -> Modifier:
	if existing != null:
		Modifiers.remove(existing, ModifierService.REASON_REPLACED)

	var modifier: Modifier = Modifier.create(
		source_id,
		ModifierTargets.CUSTOMER_ARRIVAL_RATE,
		Modifier.Operation.MULTIPLY,
		value,
		label
	)

	modifier.stacking = Modifier.Stacking.REPLACE

	return Modifiers.add(modifier)


func _get_occupancy() -> float:
	if _game_manager == null:
		return 0.0

	if not _game_manager.has_method(&"get_occupancy_ratio"):
		return 0.0

	return float(_game_manager.call(&"get_occupancy_ratio"))


## Records a demand sample.
##
## Sampled on the refresh interval rather than per frame, and bounded, so a
## long session produces a usable curve instead of an unreadable log.
func _sample() -> void:
	if maximum_samples <= 0:
		return

	var demand: float = Modifiers.evaluate(
		ModifierTargets.CUSTOMER_ARRIVAL_RATE,
		1.0
	)

	_samples.append({
		"world_minutes": WorldTime.get_total_minutes(),
		"clock": WorldTime.get_clock_text(),
		"state": Tavern.get_state_name(),
		"demand": demand,
		"occupancy": _get_occupancy(),
	})

	while _samples.size() > maximum_samples:
		_samples.pop_front()


func get_current_demand() -> float:
	return Modifiers.evaluate(
		ModifierTargets.CUSTOMER_ARRIVAL_RATE,
		1.0
	)


## Desired number of customers right now, for the debug panel.
func get_desired_occupancy() -> int:
	if _game_manager == null:
		return 0

	if not _game_manager.has_method(&"get_seating_capacity"):
		return 0

	var capacity: int = int(_game_manager.call(&"get_seating_capacity"))

	var target: float = Modifiers.evaluate(
		ModifierTargets.CUSTOMER_TARGET_OCCUPANCY,
		0.75
	)

	return int(round(float(capacity) * target * get_current_demand()))


func build_report_section() -> Dictionary:
	return {
		"profile": (
			{} if demand_profile == null
			else demand_profile.to_dictionary()
		),
		"current_demand": get_current_demand(),
		"desired_occupancy": get_desired_occupancy(),
		"capacity_pressure_threshold": capacity_pressure_threshold,
		"samples": _samples.duplicate(true),
		"breakdown": Modifiers.explain(
			ModifierTargets.CUSTOMER_ARRIVAL_RATE,
			1.0
		),
	}
