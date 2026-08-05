class_name DemandProfile
extends Resource

## How busy the tavern should be at each time of day.
##
## Stored as keyframes rather than bands, and interpolated between them. Bands
## produce a visible step - the tavern lurches from moderate to busy on a
## single minute - whereas a curve builds and fades the way real trade does.
## Setting [member use_interpolation] to false gives the band behaviour if that
## is ever wanted, using the same data.
##
## The profile produces a plain multiplier. It has no idea what it is
## multiplying, and does not touch the spawner: [TavernDemandController] feeds
## it into the modifier framework as the time-of-day contribution to
## [constant ModifierTargets.CUSTOMER_ARRIVAL_RATE], which is what keeps
## clock-reading out of the customer scripts entirely.


@export_category("Identity")

@export var profile_id: StringName = &"default_demand"

@export var display_name: String = "Standard Evening Trade"


@export_category("Keyframes")

## Hour-of-day keyframes, as minutes past midnight mapped to a multiplier.
##
## Keys are ints (minutes past midnight), values are floats. Order does not
## matter; the profile sorts them.
@export var keyframes: Dictionary = {
	600: 0.30,
	720: 0.60,
	900: 0.90,
	1080: 1.40,
	1260: 1.80,
	1440: 1.20,
	1470: 0.50,
}

## Whether to blend between keyframes or hold each value until the next.
@export var use_interpolation: bool = true


@export_category("Limits")

@export_range(0.0, 10.0, 0.05)
var minimum_multiplier: float = 0.0

@export_range(0.1, 10.0, 0.05)
var maximum_multiplier: float = 4.0


const MINUTES_PER_DAY: int = 1440


## Keyframe times in ascending order. Cached on first use.
var _sorted_times: Array[int] = []


func _get_sorted_times() -> Array[int]:
	if not _sorted_times.is_empty():
		return _sorted_times

	for key: Variant in keyframes.keys():
		_sorted_times.append(int(key))

	_sorted_times.sort()

	return _sorted_times


## The demand multiplier at [param minutes_past_midnight].
##
## Wraps at midnight in both directions, so a profile whose last keyframe is
## before the first still blends across the boundary rather than falling off a
## cliff at 00:00.
func get_multiplier_at(
	minutes_past_midnight: int
) -> float:
	var times: Array[int] = _get_sorted_times()

	if times.is_empty():
		return 1.0

	var minutes: int = minutes_past_midnight % MINUTES_PER_DAY

	var previous_time: int = times[times.size() - 1]
	var next_time: int = times[0]

	for time: int in times:
		if time <= minutes:
			previous_time = time
		else:
			next_time = time
			break

	var previous_value: float = float(keyframes[previous_time])

	if not use_interpolation:
		return clampf(
			previous_value,
			minimum_multiplier,
			maximum_multiplier
		)

	var next_value: float = float(keyframes[next_time])

	var span: int = next_time - previous_time

	if span <= 0:
		span += MINUTES_PER_DAY

	var elapsed: int = minutes - previous_time

	if elapsed < 0:
		elapsed += MINUTES_PER_DAY

	var t: float = 0.0 if span == 0 else float(elapsed) / float(span)

	return clampf(
		lerpf(previous_value, next_value, t),
		minimum_multiplier,
		maximum_multiplier
	)


## A readable label for the current period, for UI and diagnostics.
func describe_level(
	multiplier: float
) -> String:
	if multiplier <= 0.01:
		return "Closed"

	if multiplier < 0.5:
		return "Quiet"

	if multiplier < 1.0:
		return "Steady"

	if multiplier < 1.5:
		return "Busy"

	return "Peak"


func validate_or_warn() -> bool:
	if keyframes.is_empty():
		push_warning(
			"DemandProfile '%s' has no keyframes; demand will always be 1.0."
			% String(profile_id)
		)

		return false

	return true


func to_dictionary() -> Dictionary:
	return {
		"profile_id": String(profile_id),
		"display_name": display_name,
		"keyframes": keyframes.duplicate(),
		"use_interpolation": use_interpolation,
		"minimum_multiplier": minimum_multiplier,
		"maximum_multiplier": maximum_multiplier,
	}
