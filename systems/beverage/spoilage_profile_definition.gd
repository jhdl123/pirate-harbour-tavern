class_name SpoilageProfileDefinition
extends Resource

## How one kind of stock goes off.
##
## A profile is shared by every batch that uses it, so "citrus keeps for three
## days" is authored once. The per-batch facts - when it was made, how fresh it
## is now - live on [FilledContainer], never here.
##
## Spoilage is evaluated from elapsed world minutes when something is read or
## when a scheduled check fires. Nothing is processed per frame. See
## [SpoilageService].


## What happens when freshness reaches zero.
enum ExpiryResult {
	## Quality drops but the stock stays usable. Ale going stale.
	STALE,

	## The stock becomes unusable and should be discarded.
	SPOILED,

	## The stock turns into a different item entirely - see
	## [member spoiled_item_id].
	TRANSFORMS,
}


@export_category("Identity")

## Stable internal identifier. Referenced by drinks, ingredients and batches.
@export var profile_id: StringName = &""

@export var display_name: String = "Unnamed Spoilage Profile"

@export_multiline var description: String = ""


@export_category("Timing")

## World minutes from full freshness to fully spoiled, before modifiers.
##
## Zero disables spoilage for anything using this profile, which is a safe and
## deliberate way to author "does not go off for now".
@export_range(0, 2000000, 1)
var expiry_minutes: int = 0

## World minutes before freshness starts falling at all.
##
## A sealed cask that only starts ageing once tapped uses this.
@export_range(0, 2000000, 1)
var grace_minutes: int = 0

## Freshness at or below which the stock is treated as spoiled.
##
## Freshness runs 1.0 (fresh) to 0.0 (gone). A threshold above zero lets a
## drink become unservable slightly before it is visually ruined.
@export_range(0.0, 1.0, 0.01)
var spoiled_below_freshness: float = 0.0


@export_category("Behaviour")

@export var expiry_result: ExpiryResult = ExpiryResult.SPOILED

## Item id this becomes when [member expiry_result] is
## [constant ExpiryResult.TRANSFORMS]. Ignored otherwise.
@export var spoiled_item_id: StringName = &""

## True when sealing the container stops the clock.
##
## Bottled wine and sealed spirit casks use this: they only begin ageing once
## opened, which is why they can share a profile with something perishable
## without going off in the cellar.
@export var sealed_state_pauses_spoilage: bool = true


func is_enabled() -> bool:
	return expiry_minutes > 0


## Freshness after [param elapsed_minutes], with an optional storage modifier.
##
## [param storage_modifier] comes from [StorageProfileDefinition]: below 1.0 a
## location preserves stock (a cold cellar), above 1.0 it ruins it faster.
func calculate_freshness(
	elapsed_minutes: int,
	storage_modifier: float = 1.0
) -> float:
	if not is_enabled():
		return 1.0

	var effective_elapsed: int = elapsed_minutes - grace_minutes

	if effective_elapsed <= 0:
		return 1.0

	var rate: float = maxf(storage_modifier, 0.0)

	if is_zero_approx(rate):
		return 1.0

	var consumed: float = (
		float(effective_elapsed) * rate / float(expiry_minutes)
	)

	return clampf(1.0 - consumed, 0.0, 1.0)


func is_spoiled_at_freshness(freshness: float) -> bool:
	if not is_enabled():
		return false

	return freshness <= spoiled_below_freshness


## World minutes from now until this batch becomes spoiled.
##
## Returns -1 when it never will. Used to schedule a single check rather than
## polling - see [SpoilageService.schedule_check].
func get_minutes_until_spoiled(
	elapsed_minutes: int,
	storage_modifier: float = 1.0
) -> int:
	if not is_enabled():
		return -1

	var rate: float = maxf(storage_modifier, 0.0)

	if is_zero_approx(rate):
		return -1

	var usable_fraction: float = 1.0 - spoiled_below_freshness
	var total_minutes: float = (
		float(expiry_minutes) * usable_fraction / rate
	) + float(grace_minutes)

	var remaining: int = int(ceil(total_minutes)) - elapsed_minutes

	return maxi(remaining, 0)


func is_valid() -> bool:
	if profile_id.is_empty():
		return false

	if expiry_result == ExpiryResult.TRANSFORMS and spoiled_item_id.is_empty():
		return false

	return expiry_minutes >= 0 and grace_minutes >= 0


func validate_or_warn() -> bool:
	if profile_id.is_empty():
		push_error(
			"SpoilageProfileDefinition at "
			+ resource_path
			+ " has no profile_id."
		)
		return false

	if expiry_result == ExpiryResult.TRANSFORMS and spoiled_item_id.is_empty():
		push_error(
			"SpoilageProfileDefinition '"
			+ String(profile_id)
			+ "' transforms on expiry but names no spoiled_item_id."
		)
		return false

	return true
