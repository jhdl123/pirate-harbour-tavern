class_name StaffDefinition
extends Resource

## Everything that makes one kind of staff member different from another.
##
## [StaffMember] is a single script with no roles baked into it. A bartender, a
## cleaner, a stock runner and a bouncer are all that same script pointed at
## different resources of this type. Adding a role is therefore authoring one
## [code].tres[/code] and, if it needs new work, one executor - never a new
## worker script and never a branch inside an existing one.
##
## The Phase 3A Tavern Hand is deliberately the least specialised possible
## archetype: it serves prepared drinks and it cleans seats.


@export_category("Identity")

## Stable identifier for this archetype, used in save data and diagnostics.
##
## Not the id of an individual worker - see
## [member StaffMember.staff_id] for that.
@export var archetype_id: StringName = &"tavern_hand"

## Name shown in prompts, alerts and speaker messages.
@export var display_name: String = "Tavern Hand"

## Player-facing job title, shown when inspecting the worker.
@export var role_name: String = "General Hand"

## Optional description for future hiring and management screens.
@export_multiline var description: String = ""


@export_category("Capabilities")

## What this archetype is allowed to do. See [StaffCapabilities].
##
## The task board intersects this with each task's
## [member TavernTaskDefinition.required_capabilities]. An empty list here means
## the worker can only take tasks that require nothing.
@export var capabilities: Array[StringName] = []


@export_category("Work Behaviour")

## Seconds between "is there anything better to do?" evaluations while idle.
##
## Not a frame-rate. The worker also re-evaluates immediately whenever the
## board reports a new task, so this only governs how quickly it notices
## something it previously could not do.
@export_range(0.05, 10.0, 0.05)
var idle_evaluation_interval: float = 0.6

## Seconds between re-checks while a task is under way.
##
## This is the loop that notices the player took the drink, the customer left
## or the seat was cleaned by somebody else.
@export_range(0.05, 5.0, 0.05)
var working_evaluation_interval: float = 0.25

## How close the worker must be to touch something, in pixels.
##
## Kept a little under the player's own reach so a worker never appears to
## serve someone from further away than you can.
@export_range(8.0, 128.0, 1.0)
var interaction_reach: float = 40.0

## Consecutive navigation failures before the worker gives up on a task.
@export_range(1, 10, 1)
var navigation_failures_before_release: int = 2

## Seconds the worker waits at its idle point before evaluating again.
@export_range(0.1, 30.0, 0.1)
var idle_settle_seconds: float = 1.0


@export_category("Movement")

## Speed, acceleration and arrival tuning. See [ActorMovementProfile].
@export var movement_profile: ActorMovementProfile

## Pathing, avoidance and recovery tuning. See [ActorNavigationProfile].
##
## Staff are normally given a slightly higher avoidance priority than
## customers, so a busy room parts around them rather than jamming them.
@export var navigation_profile: ActorNavigationProfile


@export_category("Carried Items")

## What this role does with something left in its hands when a task ends.
##
## Null falls back to built-in defaults, which are safe but not tuned. A cook
## or a stock runner would want a different outcome order here.
@export var carried_item_policy: CarriedItemPolicy


@export_category("Task Preferences")

## Per-task-type score adjustments for this archetype.
##
## Keys are task type ids, values are floats added to the score. This is how
## two workers with identical capabilities end up naturally specialising: give
## a cleaner a positive modifier on cleaning and it will drift towards the
## mess while the other keeps serving.
##
## Empty means "no preference", which is correct for a general hand.
@export var task_priority_modifiers: Dictionary = {}


@export_category("Presentation")

## Sprite used by the worker scene. Replaceable without touching any script.
@export var sprite_texture: Texture2D

## Verb shown when the player interacts with this worker.
@export var interaction_verb: String = "Talk to"

## Whether this worker may be used as the speaker on tavern alerts.
##
## Off for a role that should never be the messenger - a future silent guard,
## or a worker the player has not met yet.
@export var can_speak_for_tavern: bool = true

## Seconds a speech bubble stays on screen above the worker.
@export_range(0.5, 30.0, 0.5)
var speech_bubble_seconds: float = 4.0


func is_valid() -> bool:
	return (
		not archetype_id.is_empty()
		and not display_name.strip_edges().is_empty()
	)


func validate_or_warn() -> bool:
	if is_valid():
		return true

	push_warning(
		"StaffDefinition is incomplete: it needs an archetype_id and a "
		+ "display_name."
	)

	return false


## The score adjustment this archetype applies to [param task_type].
func get_priority_modifier(
	task_type: StringName
) -> float:
	return float(task_priority_modifiers.get(task_type, 0.0))
