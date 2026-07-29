class_name TavernActivityPoint
extends Node2D

## A place in the tavern a customer can temporarily visit to do something.
##
## Deliberately not built for darts specifically - a card table, a musician's
## corner, a gambling table or a notice board are all just another instance
## of this same class with different [member activity_id]/config values and
## a different child scene for visuals. Nothing here knows what a customer
## is; [VisitTavernActivityBehaviour] is the only thing that reads this
## class, and it reads it entirely through this exported data plus the
## [Reservable] child every other reservable thing in the project already
## uses (chairs, stations) - no new reservation system, per the brief.
##
## [b]Capacity.[/b] This phase's darts instance proves the pattern with a
## single [Reservable] (capacity effectively 1). [member capacity] is
## exposed now so a future multi-slot point (e.g. a four-seat card table)
## has a place to record its intent, but actually supporting more than one
## simultaneous user needs more than one [Reservable]/use position child and
## is not implemented this phase - see docs/CUSTOMER_AI_SYSTEM.md's Phase 2C
## "Known limitations".


@export_category("Identity")

## Matches a [Reservable] tag on this node's [member reservable] child, and
## the [code]destination_tag[/code] on whichever [ActivityDefinition] visits
## this point - e.g. [code]&"darts"[/code].
@export var activity_id: StringName = &""

@export var display_name: String = "Tavern Activity"

## Disabled points are simply never returned by [DestinationBroker]'s
## availability check - a disabled point's [Reservable] never reports free
## if this is false (see [method is_available]).
@export var enabled: bool = true


@export_category("Capacity")

## See the class doc comment - not yet functionally more than 1.
@export_range(1, 4, 1)
var capacity: int = 1


@export_category("Use")

## World minutes spent using this point once reserved and reached.
@export_range(0.5, 60.0, 0.5)
var activity_duration_minutes: float = 6.0

## Added to [member CustomerNeeds.mood] on completion.
@export_range(-1.0, 1.0, 0.01)
var satisfaction_effect: float = 0.15

## Added to [member CustomerNeeds.intoxication] on completion - 0.0 for
## anything that is not itself a drink (darts, cards, a notice board).
@export_range(0.0, 1.0, 0.01)
var intoxication_effect: float = 0.0

## Added to [member CustomerNeeds.engagement] on completion - see
## docs/CUSTOMER_AI_SYSTEM.md's Phase 2C "reasons to stay" section.
@export_range(0.0, 1.0, 0.01)
var engagement_effect: float = 0.3

## Deducted from [member CustomerNeeds.wealth] on completion, if any -
## e.g. a future gambling table. 0 for darts.
@export_range(0, 100, 1)
var money_cost: int = 0

## World minutes this point refuses a new reservation after releasing the
## previous one - 0 disables the cooldown. Not yet enforced by
## [VisitTavernActivityBehaviour]; recorded for a future phase - see known
## limitations.
@export_range(0.0, 30.0, 0.5)
var cooldown_minutes: float = 0.0

## Empty means any [CustomerType] may use this point.
@export var allowed_customer_types: Array[CustomerType] = []

## A customer below this satisfaction, or above this intoxication, is not
## offered this point - read by [method is_available_for].
@export_range(0.0, 1.0, 0.01)
var minimum_satisfaction: float = 0.0
@export_range(0.0, 1.0, 0.01)
var maximum_intoxication: float = 1.0

## Whether [VisitTavernActivityBehaviour] sends the customer back to their
## chair once this completes. Every Phase 2C activity uses this - exposed
## per the brief's suggested property list for a future point that might
## not (e.g. a point that hands off to another point directly).
@export var return_to_seat_after_use: bool = true

## Purely informational for now - see docs/CUSTOMER_AI_SYSTEM.md's Phase 2C
## debug-visualisation note.
@export var show_debug_visual: bool = false


@onready var reservable: Reservable = $Reservable
@onready var use_position: Marker2D = $UsePosition


func _ready() -> void:
	_apply_enabled_state()
	set_process(show_debug_visual)


func _process(_delta: float) -> void:
	# Only running at all when show_debug_visual is true (see _ready()) -
	# disabled by default per docs/CUSTOMER_AI_SYSTEM.md's Phase 2C debug
	# visualisation note, so this costs nothing in normal play.
	queue_redraw()


func _draw() -> void:
	if not show_debug_visual:
		return

	var state_colour: Color = Color.DIM_GRAY

	if not enabled:
		state_colour = Color.DIM_GRAY
	elif reservable != null and reservable.is_free():
		state_colour = Color.GREEN
	else:
		state_colour = Color.RED

	draw_circle(Vector2.ZERO, 14.0, state_colour)

	if use_position != null:
		draw_line(
			Vector2.ZERO,
			to_local(use_position.global_position),
			Color.YELLOW,
			2.0
		)


## Runtime on/off switch (the F10 "Enable/Disable Tavern Activities"
## developer action uses this). Implemented by having this point reserve
## itself when disabled, rather than teaching [Reservable]/[DestinationBroker]
## a second "is this actually available" concept - a disabled point is
## simply never free, which is a state those classes already handle
## correctly with no changes to either of them.
func set_enabled(value: bool) -> void:
	enabled = value
	_apply_enabled_state()


func _apply_enabled_state() -> void:
	if reservable == null:
		return

	if enabled:
		if reservable.get_holder() == self:
			reservable.release(self)
	else:
		reservable.reserve(self)


func get_use_position() -> Vector2:
	if use_position != null:
		return use_position.global_position

	return global_position


func is_available_for(customer_type: CustomerType) -> bool:
	if not enabled:
		return false

	if allowed_customer_types.is_empty():
		return true

	return allowed_customer_types.has(customer_type)
