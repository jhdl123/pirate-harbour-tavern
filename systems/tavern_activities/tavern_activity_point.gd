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
## [TavernActivitySlot] children every other reservable thing in the project
## already uses the same [Reservable] primitive for (chairs, stations) - no
## new reservation system, per the brief.
##
## [b]Capacity.[/b] One [TavernActivitySlot] child per simultaneous user -
## Darts has two, so two customers can play at once. [member capacity] is
## just a declared expectation checked against [member slots].size() in
## [method _ready] (a mismatch is a scene-authoring mistake, not a runtime
## state); [member slots].size() is what every method here actually reads.


@export_category("Identity")

## Matches the [Reservable] tag on each [TavernActivitySlot] child, and
## the [code]destination_tag[/code] on whichever [ActivityDefinition] visits
## this point - e.g. [code]&"darts"[/code].
@export var activity_id: StringName = &""

@export var display_name: String = "Tavern Activity"

## Disabled points are simply never returned by [DestinationBroker]'s
## availability check - a disabled point's [Reservable] never reports free
## if this is false (see [method is_available]).
@export var enabled: bool = true


@export_category("Capacity")

## See the class doc comment - checked against the actual
## [TavernActivitySlot] child count in [method _ready].
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

## [CustomerNeeds] field incremented by 1 each time a customer finishes using
## this point, e.g. [code]&"darts_count"[/code] - empty means no repeat-count
## tracking for this point. Generalizes what used to be a hard-coded
## [code]if activity_id == &"darts"[/code] check in
## [code]Customer._on_activity_use_finished()[/code]; a future cards table
## just sets this to its own need id (which [CustomerNeeds] must already
## define - see its [code]adjust()[/code]/[code]get_need()[/code] match
## statements).
@export var repeat_count_need_id: StringName = &""

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


## Every [TavernActivitySlot] child, in child order. Populated once in
## [method _ready] - not expected to change at runtime.
var slots: Array[TavernActivitySlot] = []

## The first slot's [Reservable]/use position, kept as computed properties
## so every existing single-slot caller (this class's own methods,
## [VisitTavernActivityBehaviour]'s solo path) keeps working unchanged.
var reservable: Reservable:
	get: return slots[0].reservable if not slots.is_empty() else null
var use_position: Marker2D:
	get: return slots[0].use_position if not slots.is_empty() else null


func _ready() -> void:
	# Lets TavernActivityPointValidator's startup scan find every point by
	# group membership rather than a recursive tree walk, the same
	# convention Reservable's tag groups already use - see
	# NavigationValidator's doc comment on why.
	add_to_group(&"tavern_activity_points")

	for child: Node in get_children():
		var slot: TavernActivitySlot = child as TavernActivitySlot

		if slot != null:
			slot.point = self
			slots.append(slot)

	if slots.is_empty():
		_synthesize_legacy_slot()

	if slots.size() != capacity:
		push_warning(
			"TavernActivityPoint '" + String(activity_id)
			+ "' declares capacity " + str(capacity)
			+ " but has " + str(slots.size()) + " TavernActivitySlot children."
		)

	_apply_enabled_state()
	set_process(show_debug_visual)


## Compatibility path for a point built without [TavernActivitySlot]
## children - e.g. tests/group_parity_test.gd's [code]_build_activity_point()[/code],
## which predates this class and adds a bare [Reservable]/[Marker2D]
## directly under the point, the shape every darts point used to have.
## Wraps whatever it finds in one in-code [TavernActivitySlot] (never added
## to the tree - it is only ever read as plain data) so a point built either
## way ends up with exactly the same [member slots] shape.
func _synthesize_legacy_slot() -> void:
	var bare_reservable: Reservable = get_node_or_null("Reservable")

	if bare_reservable == null:
		return

	var slot := TavernActivitySlot.new()

	slot.reservable = bare_reservable
	slot.use_position = get_node_or_null("UsePosition")
	slot.point = self

	slots.append(slot)


func _process(_delta: float) -> void:
	# Only running at all when show_debug_visual is true (see _ready()) -
	# disabled by default per docs/CUSTOMER_AI_SYSTEM.md's Phase 2C debug
	# visualisation note, so this costs nothing in normal play.
	queue_redraw()


func _draw() -> void:
	if not show_debug_visual:
		return

	for slot: TavernActivitySlot in slots:
		var state_colour: Color = Color.DIM_GRAY

		if not enabled:
			state_colour = Color.DIM_GRAY
		elif slot.reservable != null and slot.reservable.is_free():
			state_colour = Color.GREEN
		else:
			state_colour = Color.RED

		var local_position: Vector2 = to_local(slot.global_position)

		draw_circle(local_position, 14.0, state_colour)

		if slot.use_position != null:
			draw_line(
				local_position,
				to_local(slot.use_position.global_position),
				Color.YELLOW,
				2.0
			)


## Runtime on/off switch (the F10 "Enable/Disable Tavern Activities"
## developer action uses this). Implemented by having every slot reserve
## itself when disabled, rather than teaching [Reservable]/[DestinationBroker]
## a second "is this actually available" concept - a disabled slot is
## simply never free, which is a state those classes already handle
## correctly with no changes to either of them.
func set_enabled(value: bool) -> void:
	enabled = value
	_apply_enabled_state()


func _apply_enabled_state() -> void:
	for slot: TavernActivitySlot in slots:
		if slot.reservable == null:
			continue

		if enabled:
			if slot.reservable.get_holder() == self:
				slot.reservable.release(self)
		else:
			slot.reservable.reserve(self)


func get_use_position() -> Vector2:
	if not slots.is_empty():
		return slots[0].get_use_position()

	return global_position


## The first slot whose [Reservable] is currently free, or null if every
## slot is taken.
func get_free_slot() -> TavernActivitySlot:
	for slot: TavernActivitySlot in slots:
		if slot.reservable != null and slot.reservable.is_free():
			return slot

	return null


## Reverse lookup: which slot owns [param slot_reservable], e.g. so a
## behaviour that already holds the [Reservable] [DestinationBroker] handed
## it (which could be any slot's) can find that slot's use position.
func get_slot_for(slot_reservable: Reservable) -> TavernActivitySlot:
	for slot: TavernActivitySlot in slots:
		if slot.reservable == slot_reservable:
			return slot

	return null


func is_available_for(customer_type: CustomerType) -> bool:
	if not enabled:
		return false

	if allowed_customer_types.is_empty():
		return true

	return allowed_customer_types.has(customer_type)
