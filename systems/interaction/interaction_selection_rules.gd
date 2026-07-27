class_name InteractionSelectionRules
extends Resource

## Tuning data for how [InteractionSelector] chooses a target.
##
## Kept as a resource so selection feel can be tuned in the inspector, saved as
## a preset, and eventually varied per actor - the player, a bartender and a
## cleaner can all use different weights without any code change.
##
## Scoring is deliberately simple and additive:
##
## [codeblock]
## score = distance_weight * (1 - distance / distance_falloff)
##       + priority_weight * interaction_priority
##       + sticky_bonus    (current selection only)
## [/codeblock]
##
## Facing direction is intentionally absent. When it is added it becomes one
## more weighted term here and nothing else in the framework changes.


@export_category("Scoring")

## How much closeness matters. Raise to make distance dominate.
@export_range(0.0, 10.0, 0.05)
var distance_weight: float = 1.0

## Distance at which the closeness term reaches zero, in pixels.
##
## This only normalises the score. It is not a reachability limit - the
## detector's own collision shape decides what is in range at all.
@export_range(16.0, 512.0, 1.0)
var distance_falloff: float = 160.0

## How much [member Interactable.interaction_priority] matters.
##
## At the default, one point of priority is worth roughly 24 pixels of
## closeness against the default falloff.
@export_range(0.0, 5.0, 0.01)
var priority_weight: float = 0.15


@export_category("Stickiness")

## Score bonus given to the object that is already selected.
##
## This is what stops two nearby objects flickering as the player shuffles
## between them: a rival has to be clearly better, not marginally better.
@export_range(0.0, 2.0, 0.01)
var sticky_bonus: float = 0.12

## Seconds between selection re-evaluations.
##
## Small enough to feel immediate, large enough that selection is not decided
## by sub-pixel movement noise. Highlights and prompts refresh on the same tick.
@export_range(0.0, 0.5, 0.01)
var selection_interval: float = 0.05


@export_category("Manual Cycling")

## How long a target chosen with the cycle key survives automatic re-scoring.
##
## Without this, cycling would immediately snap back to the nearest object.
## Set to 0 to rely on [member manual_release_distance] alone.
@export_range(0.0, 30.0, 0.5)
var manual_hold_seconds: float = 5.0

## How far the actor may move before a manually cycled target is released.
##
## Walking away is a clear signal that the player has moved on, and releasing
## restores automatic selection without needing another key press.
@export_range(0.0, 512.0, 1.0)
var manual_release_distance: float = 80.0


## Turns a distance in pixels into a 0..1 closeness value.
func get_closeness(
	distance: float
) -> float:
	if distance_falloff <= 0.0:
		return 0.0

	return clampf(
		1.0 - distance / distance_falloff,
		0.0,
		1.0
	)
