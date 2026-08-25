class_name CustomerGroup
extends Node

## One group visit, from arrival to departure.
##
## Makes group-level decisions - where to settle, what to order, when to go -
## and assigns each member a destination. It deliberately does NOT drive
## members frame by frame: a member's walking, avoidance, animation and local
## states stay in [Customer], exactly as they are for a solo visitor. The group
## sets intent; the customer carries it out.
##
## That division is what keeps this from becoming a second customer AI, and it
## is why adding groups needs no change to navigation.
##
## Every failure path leads to [constant State.LEAVING]. A group that cannot
## find a place, cannot order, or loses its leader still resolves and still
## releases its reservations - a stuck group holding the only free table would
## be far worse than a group that simply gives up and goes.


signal state_changed(previous: State, current: State)
signal member_left(member: Node)
signal leader_changed(leader: Node)
signal order_placed(order: GroupOrder)
signal visit_completed
signal visit_failed(reason: String)


enum State {
	SPAWNING,
	ENTERING,
	FORMING_UP,
	FINDING_PLACE,
	MOVING_TO_PLACE,
	SETTLING,
	WAITING_TO_ORDER,
	ORDERING,
	WAITING_FOR_SERVICE,
	SOCIALISING,
	CONSUMING,
	CONSIDERING_REORDER,
	PREPARING_TO_LEAVE,
	LEAVING,
	COMPLETE,
	FAILED,
	## Appended rather than inserted so every existing State integer keeps
	## its value - saved games, debug panels and tests all read these.
	##
	## Waiting for a filled keg to be found and claimed in real storage.
	WAITING_FOR_STOCK,
	## Keg claimed; waiting for a member of staff to carry it over.
	WAITING_FOR_DELIVERY,
	## Keg finished; members may relax, socialise or play darts nearby.
	LEISURE,
	## Leaving has been decided; members away from the group are called back.
	RECALLING,
	## Members are stepping outward so staff can reach the delivery point.
	CLEARING_DELIVERY_SPACE,
	## Enough room exists; the tavern hand is on its way in with the keg.
	DELIVERY_IN_PROGRESS,
	## Keg placed; members are walking back to their drinking slots.
	REFORMING,
}


@export_category("Identity")

## Stable runtime id. Written onto every member as group_id.
@export var group_id: StringName = &""

@export var definition: CustomerGroupDefinition

## Forces this group's shared order to one exact drink.
##
## Empty for a normal visit, which keeps the weighted, data-driven selection
## intact. Set by the developer test-group action so the milestone loop always
## orders the same thing and a failure is never just an unlucky roll.
@export var required_drink_id: StringName = &""

## Forces this group's shared serving format. See [member required_drink_id].
@export var required_serving_format_id: StringName = &""


## Whether [param drink] and [param format] satisfy any forced order.
func accepts_pairing(
	drink_id_value: StringName,
	format_id_value: StringName
) -> bool:
	if not required_drink_id.is_empty() and drink_id_value != required_drink_id:
		return false

	if (
		not required_serving_format_id.is_empty()
		and format_id_value != required_serving_format_id
	):
		return false

	return true


@export_category("Behaviour")

## World minutes the group will wait for service before giving up.
@export_range(1, 600, 1)
var base_patience_minutes: int = 45

## World minutes between one member's drinks.
@export_range(1, 120, 1)
var minutes_between_drinks: int = 4

## Seconds a member spends on one social action.
@export_range(0.5, 60.0, 0.5)
var social_action_seconds: float = 4.0

## Real seconds between releasing members into the doorway.
@export_range(0.0, 5.0, 0.05)
var member_entry_delay: float = 0.5

## Real seconds one member may take to cross before the next is released.
@export_range(1.0, 20.0, 0.5)
var member_entry_timeout: float = 8.0

## Real seconds between members beginning to leave. This avoids the entire
## group collapsing into one doorway movement while keeping one group visit.
@export_range(0.0, 5.0, 0.05)
var member_departure_delay: float = 0.6


@export_category("Assembly")

## World minutes a member may take to reach its slot before recovery starts.
##
## Assembly used to have no bound at all: one member that could not finish its
## approach left the whole group in MOVING_TO_PLACE until patience ran out,
## and the other members stood in IN_GROUP doing nothing the entire time.
@export_range(1, 120, 1)
var slot_arrival_timeout_minutes: int = 5

## Distance from its slot at which a member counts as assembled, in pixels.
@export_range(4.0, 256.0, 1.0)
var slot_arrival_tolerance: float = 32.0

## Times a member's slot navigation is refreshed before it is placed.
@export_range(0, 10, 1)
var maximum_slot_retries: int = 2


## Restricts this visit to a standing area.
##
## The seated group path is not reliable yet: a second member sent to a chair
## at an occupied table stalls in MOVING_TO_SEAT a few pixels short of its
## seat, so the group never reports itself in position and the visit times out.
## Standing areas have no such handover and are the reliable destination for
## the basic group milestone. Set by [GroupSpawner] from [GroupManager].
@export var standing_places_only: bool = true


@export_category("Delivery clearance")

## How much farther out from the centre a member stands during a delivery.
##
## The ring itself is not the problem - the middle is empty - but the members'
## avoidance radii close the gaps between them, so a worker carrying a keg has
## no path in. Widening the ring for the length of the delivery opens one.
@export_range(0.0, 200.0, 1.0)
var delivery_step_back_distance: float = 34.0

## How close to its temporary position a member must be to count as clear.
@export_range(1.0, 200.0, 1.0)
var delivery_position_tolerance: float = 26.0

## Share of members that must be clear before the keg may be placed.
##
## Not everybody: insisting on the whole party would let one member wedged
## behind a bench block every delivery the group ever receives.
@export_range(0.1, 1.0, 0.05)
var minimum_cleared_fraction: float = 0.7

## World minutes spent clearing before the delivery proceeds regardless.
@export_range(1, 60, 1)
var delivery_clearance_timeout: int = 4

## World minutes spent reforming before drinking starts regardless.
@export_range(1, 60, 1)
var delivery_reform_timeout: int = 4

## Times a member's step-back navigation is refreshed before it is placed.
@export_range(0, 10, 1)
var maximum_clearance_retries: int = 1


@export_category("Order icon")

## Icon shown above the leader while the group's keg order is outstanding.
##
## A texture, not a scene: the leader already owns an OrderIcon sprite for
## solo ordering, and this simply swaps what it shows. One icon system.
@export var group_order_icon_texture: Texture2D


@export_category("Leisure")

## Whether members may take a break once the keg is finished.
@export var leisure_enabled: bool = true

## Shortest and longest the leisure phase may last, in world minutes.
@export_range(0, 240, 1)
var minimum_leisure_minutes: int = 8

@export_range(0, 240, 1)
var maximum_leisure_minutes: int = 20

## World minutes between one leisure decision and the next.
@export_range(1, 60, 1)
var leisure_decision_interval_minutes: int = 2

## Which leisure activities this group may choose from.
##
## Data rather than a hard-coded list, so a definition can give a rowdy crew
## darts and a quiet one conversation without touching a script.
@export var leisure_activities: Array[StringName] = [
	&"darts", &"socialise", &"relax",
]

## Chance an idle member starts something when a decision is made.
@export_range(0.0, 1.0, 0.05)
var leisure_activity_chance: float = 0.6

## Share of the group that may be away from its slot at once.
##
## Half by default: a group that all wandered off at once would stop looking
## like a group at all, and the formation point would sit empty.
@export_range(0.0, 1.0, 0.05)
var maximum_away_fraction: float = 0.5

## Whether members may start activities while the keg still has portions.
##
## ON as of Phase A. It was off for the group-loop pass, on the reasoning that
## drinking is the point of the visit and a member at the darts board is a
## member not taking its turn at the cask. That reasoning is what produced
## "group activity participation 0.0%" in every run since: a keg holds eight
## servings and a crew drinks it slowly, so shared_serving is non-empty for
## almost the whole of a group's life and the guard in
## GroupManager._offer_leisure_activity() returned before any member was ever
## considered. Making optional activities reachable by group members
## (is_settled) did nothing while this stayed false - they became eligible and
## were still never offered.
##
## Cohesion is still bounded, by maximum_away_fraction rather than by a blanket
## ban: at most half a crew can be away at once, and the leisure roll still has
## to pass. A crew that never sends anyone to the darts board is the thing
## Phase A is trying to stop.
@export var allow_activities_while_drinking: bool = true

## World minutes members are given to come back before departure starts.
@export_range(1, 120, 1)
var recall_timeout_minutes: int = 6

## Relax duration bounds for a member relaxing at its group slot.
@export_range(1.0, 60.0, 0.5)
var leisure_relax_minimum_minutes: float = 3.0

@export_range(1.0, 60.0, 0.5)
var leisure_relax_maximum_minutes: float = 6.0

## Added to CustomerNeeds.relaxation on completion - matches
## relax_at_seat.tres's declared [member ActivityDefinition.satisfies]
## value; see item 3 of
## docs/history/2026-08-25_CUSTOMER_ARCHITECTURE_AUDIT.md's plan.
@export_range(0.0, 1.0, 0.01)
var leisure_relax_relaxation_gain: float = 0.3

## Socialise duration bounds and effects, matching the seated activity.
@export_range(1.0, 60.0, 0.5)
var leisure_socialise_minimum_minutes: float = 3.0

@export_range(1.0, 60.0, 0.5)
var leisure_socialise_maximum_minutes: float = 6.0

@export_range(0.0, 1.0, 0.01)
var leisure_socialise_satisfaction_gain: float = 0.12

@export_range(0.0, 1.0, 0.01)
var leisure_socialise_partner_gain: float = 0.08

## Renamed from `leisure_socialise_engagement_gain` when
## CustomerNeeds.engagement was split into social/entertainment/relaxation
## - see docs/history/2026-08-25_CUSTOMER_ARCHITECTURE_AUDIT.md.
@export_range(0.0, 1.0, 0.01)
var leisure_socialise_social_gain: float = 0.2


@export_category("References")

@export var beverage_registry: BeverageRegistry
@export var vessel_pool: VesselPool


var state: State = State.SPAWNING
var members: Array[Node] = []
var leader: Node = null
var place: GroupPlace = null
var current_order: GroupOrder = null
var completed_orders: Array[GroupOrder] = []
var shared_serving: SharedServing = null

## Rotation cursor so members take turns rather than racing each other.
var next_drinker_index: int = 0

var visit_started_minutes: int = -1
var last_state_change_minutes: int = -1
var orders_placed: int = 0
var failure_reason: String = ""

## Ticks spent in the current state.
##
## A backstop that does not depend on the world clock. Patience is measured in
## tavern minutes, which is right for balance but useless if the clock is
## stopped, paused or fast-forwarded oddly - and a group whose members cannot
## reach their slots would then hold its table forever. Counting ticks means
## every state has an escape regardless of what time is doing.
var ticks_in_state: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _member_next_drink: Dictionary = {}
var _debug_log: Array[String] = []
var _entry_sequence_started: bool = false
var _departure_sequence_started: bool = false

## Slot index assigned to each member, keyed by member.
##
## Held explicitly rather than derived from the member's position in the array.
## get_valid_members() re-indexes the moment anybody is removed, so a member
## could be sent to slot 2 and then checked against slot 1 forever.
var _slot_index_by_member: Dictionary = {}

## World minute each member was last sent to its slot.
var _slot_started_minutes: Dictionary = {}

## Navigation refreshes spent on each member's slot approach.
var _slot_retries: Dictionary = {}

## Members still waiting for their staggered departure command.
var _departure_queue: Array[Node] = []
var _departure_stagger_remaining: float = 0.0

## One-shot guards. Every group transition passes through exactly one of
## these, so no callback can run the same step twice.
var _assembled_handled: bool = false
var _post_drink_handled: bool = false
var _cleanup_done: bool = false

## Times a member had to be recovered onto its slot this visit.
var group_slot_recoveries: int = 0

## World minute the keg ran out. Minus one until it does.
##
## The post-keg wait is measured from here, never from the visit duration -
## using the visit duration made the wait already expired the instant the
## group entered the state.
var keg_emptied_at_minutes: int = -1

## World minute the post-drink phase began. Minus one until it does.
var post_drink_started_at_minutes: int = -1

## How long this group's leisure phase will last, rolled once on entry.
var leisure_duration_minutes: int = 0

## World minute the next leisure decision is due.
var next_leisure_decision_minutes: int = -1

## World minute recall began. Minus one until it does.
var recall_started_at_minutes: int = -1

## Leisure activities members completed this visit, by kind.
var group_activity_count: int = 0
var group_relax_count: int = 0
var group_socialise_count: int = 0
var group_darts_count: int = 0

## Payment. The leader pays once, for a keg that actually exists.
var payment_made: bool = false
var paying_member_name: String = ""

## Real-stock delivery.
var keg_item_id: StringName = &""
var stock_reservation_id: StringName = &""
var delivery_task_id: StringName = &""
var delivery_status: StringName = &"none"
var keg_collected: bool = false

## True when the keg was created without touching real stock.
var bypassed_stock: bool = false

## Temporary step-back position for each member, keyed by member.
##
## Separate from the slot map so the normal drinking formation is never
## overwritten - members go back to exactly where they were standing.
var _delivery_slot_by_member: Dictionary = {}
var _clearance_retries: Dictionary = {}

var clearance_started_at_minutes: int = -1
var clearance_completed_at_minutes: int = -1
var reform_started_at_minutes: int = -1
var reform_completed_at_minutes: int = -1
var delivery_clearance_recoveries: int = 0
var members_required_to_clear: int = 0
var members_cleared: int = 0

## Where staff stand to put the keg down. Zero until one is chosen.
var delivery_approach_position: Vector2 = Vector2.ZERO
var delivery_approach_retries: int = 0

## Order icon bookkeeping.
var order_icon_shown: bool = false
var order_icon_shown_at_minutes: int = -1
var order_icon_duration_minutes: int = 0
var order_icon_hidden_reason: StringName = &""

## True once a real keg has been set down for this group.
var delivery_completed: bool = false

## Latched Captain and leader details, so the end-of-visit report still has
## them after cleanup has emptied the member list.
var _leader_is_captain: bool = false
var _leader_type_name: String = ""
var _leader_customer_id: int = -1

## One-shot guards for the delivery phases.
var _clearance_handled: bool = false
var _reform_handled: bool = false
var _drinking_started: bool = false


# --- Milestone diagnostics ---------------------------------------------------
#
# Recorded as the visit runs rather than reconstructed afterwards, because the
# interesting facts (which station poured, what the stock was before) are gone
# by the time the group has left.

## Why no shared keg could be ordered. Empty when the order succeeded.
var order_failure_reason: StringName = &""

## Shared-serving requests made for this group's keg, including retries.
var serving_attempts: int = 0

## Why the group left. Set on every departure path.
var departure_reason: StringName = &""

## Whether release_place() and the serving teardown both ran.
var cleanup_completed: bool = false

## Node name of the station the keg was drawn from.
var source_station_name: String = ""

## Station measures either side of the draw.
var stock_before_measures: int = -1
var stock_after_measures: int = -1

var keg_starting_portions: int = 0
var keg_remaining_portions: int = 0
var keg_drink_id: StringName = &""
var keg_format_id: StringName = &""

## Portions taken, keyed by member name.
var portions_per_member: Dictionary = {}

## The place this group reserved. Kept after release so a finished visit can
## still report where it sat or stood.
var destination_id: StringName = &""

## Whether that destination was a table or a standing area. Kept after the
## reservation is released so a finished visit can still report it.
var destination_kind: StringName = &""

## What the tavern was actually paid for this visit.
var amount_paid: int = 0


func _ready() -> void:
	add_to_group(&"customer_groups")

	_rng.randomize()

	if group_id.is_empty():
		group_id = StringName(
			"group_%d" % Time.get_ticks_usec()
		)

	visit_started_minutes = _world_minutes()


## Announces the group once its membership is known.
##
## Not in _ready(): members are added after the node enters the tree, so a
## line printed there would always say the group had nobody in it.
func log_created() -> void:
	print(
		"[Group %s] created with %d members: %s"
		% [String(group_id), members.size(), _describe_member_ids()]
	)


func _describe_member_ids() -> String:
	var ids: Array[String] = []

	for member: Node in members:
		if is_instance_valid(member):
			ids.append(String(member.name))

	return ", ".join(ids)


# --- Membership --------------------------------------------------------------

## Adds [param member] and stamps it with this group's id.
##
## The stamp is what [method SharedServing.is_consumer_eligible] reads, so a
## member is tied to the group's drink from the moment it joins.
func add_member(member: Node) -> void:
	if member == null or members.has(member):
		return

	members.append(member)

	# The stamp is what makes a member eligible for the group's shared drink.
	# set() on a node without the property fails silently, which would leave
	# the member unable to drink from its own group's cask - so verify it took
	# rather than discovering it at the punch bowl.
	if member.has_method(&"join_group"):
		member.call(&"join_group", group_id, self)
	else:
		member.set(&"group_id", group_id)
		member.set(&"group_controller", self)

	if StringName(String(member.get(&"group_id"))) != group_id:
		push_warning(
			"%s has no group_id property, so it cannot be recognised as part "
			% member.name
			+ "of group %s. Shared servings will refuse it."
				% String(group_id)
		)

	if member.has_signal(&"tree_exiting"):
		if not member.tree_exiting.is_connected(_on_member_exiting):
			member.tree_exiting.connect(_on_member_exiting.bind(member))

	portions_per_member[String(member.name)] = 0

	if leader == null:
		set_leader(member)


func remove_member(member: Node) -> void:
	if not members.has(member):
		return

	members.erase(member)
	_member_next_drink.erase(member)
	_slot_index_by_member.erase(member)
	_slot_started_minutes.erase(member)
	_slot_retries.erase(member)
	_departure_queue.erase(member)

	# The member no longer belongs to this group, whatever happens next.
	_clear_member_group_reference(member)

	member_left.emit(member)

	if member == leader:
		_promote_new_leader()

	# An empty group must not linger holding a table.
	if get_valid_members().is_empty():
		_log("last member gone")

		if state in [State.PREPARING_TO_LEAVE, State.LEAVING] or is_finished():
			cleanup()
		else:
			record_departure_reason(&"members_lost")
			begin_departure()


func get_size() -> int:
	return members.size()


## Members that still exist and are still in the tree.
func get_valid_members() -> Array[Node]:
	var valid: Array[Node] = []

	for member: Node in members:
		if is_instance_valid(member) and member.is_inside_tree():
			valid.append(member)

	return valid


func set_leader(new_leader: Node) -> void:
	if new_leader == null or not members.has(new_leader):
		return

	leader = new_leader

	_latch_leader_details()

	leader_changed.emit(leader)


## Picks a replacement leader from the surviving members.
##
## The leader is never a single point of failure: losing one promotes another
## and the visit carries on with its place, its order and its reservations
## untouched.
func _promote_new_leader() -> void:
	var valid: Array[Node] = get_valid_members()

	if valid.is_empty():
		leader = null
		return

	set_leader(valid[0])
	_log("leader replaced")


func _on_member_exiting(member: Node) -> void:
	remove_member(member)


# --- State -------------------------------------------------------------------

func set_state(next: State) -> void:
	if state == next:
		return

	var previous: State = state
	state = next
	last_state_change_minutes = _world_minutes()
	ticks_in_state = 0

	_log("%s -> %s" % [State.keys()[previous], State.keys()[next]])

	state_changed.emit(previous, next)


func get_state_name() -> String:
	return State.keys()[state]


## The milestone's own name for this state.
##
## The enum keeps its existing names so nothing that reads State.keys() moves,
## but the keg loop is easier to follow when WAITING_FOR_SERVICE reads as
## WAITING_FOR_KEG and CONSUMING reads as DRINKING_FROM_KEG.
func get_state_label() -> String:
	match state:
		State.WAITING_FOR_SERVICE:
			return "WAITING_FOR_KEG"
		State.CONSUMING:
			return "DRINKING_FROM_KEG"
		State.MOVING_TO_PLACE:
			return "ASSEMBLING"
		State.SOCIALISING:
			# The post-keg state has always been the leisure phase; it is
			# only now that members do anything during it.
			return "LEISURE"
		State.WAITING_TO_ORDER:
			return "READY_TO_ORDER"
		_:
			return get_state_name()


func is_finished() -> bool:
	return state == State.COMPLETE or state == State.FAILED


## World minutes this visit has been running.
func get_visit_duration() -> int:
	if visit_started_minutes < 0:
		return 0

	return maxi(_world_minutes() - visit_started_minutes, 0)


## World minutes spent in the current group state.
func get_state_duration() -> int:
	if last_state_change_minutes < 0:
		return 0

	return maxi(_world_minutes() - last_state_change_minutes, 0)


## Patience left, in world minutes. Zero means out of patience.
func get_remaining_patience() -> int:
	var total: int = base_patience_minutes

	if definition != null:
		total = int(round(
			float(base_patience_minutes) * definition.patience_modifier
		))

	return maxi(total - get_visit_duration(), 0)


func has_run_out_of_patience() -> bool:
	return get_remaining_patience() <= 0


# --- Place selection ---------------------------------------------------------

## Finds and books somewhere for the group to settle.
##
## Tries seating first unless the definition says otherwise, then standing.
## Returns false when neither is possible, which the caller resolves by
## leaving rather than by waiting indefinitely.
func find_place() -> bool:
	set_state(State.FINDING_PLACE)

	var size: int = get_valid_members().size()

	if size <= 0:
		return false

	if standing_places_only:
		if _try_standing_ignoring_preference(size):
			return true

		_log("no standing area available for %d" % size)

		return false

	var prefers_standing: bool = (
		definition != null
		and definition.place_preference
			== CustomerGroupDefinition.PlacePreference.PREFER_STANDING
	)

	if not prefers_standing:
		if _try_seated(size):
			return true

	if _try_standing(size):
		return true

	# Preferred standing but none free - fall back to sitting rather than
	# turning the group away over a preference.
	if prefers_standing and _try_seated(size):
		return true

	_log("no place available for %d" % size)

	return false


## Books a standing area even for a group whose definition prefers a table.
##
## Used only while [member standing_places_only] is on. The whole party takes
## one area or the visit does not start, so a group can never split.
func _try_standing_ignoring_preference(size: int) -> bool:
	var tags: Array[StringName] = (
		definition.social_tags if definition != null else []
	)

	var area: GroupStandingArea = GroupStandingArea.find_best_free(
		get_tree(), size, tags
	)

	if area == null:
		return false

	var found: GroupPlace = GroupPlace.reserve_standing(
		area, size, self, group_id
	)

	if not found.is_valid():
		# A failed booking gives nothing back: reserve_standing either takes
		# the whole area or takes nothing at all.
		return false

	place = found
	destination_id = place.get_place_id()
	destination_kind = &"standing"
	_log("standing at %s" % String(destination_id))

	return true


func _try_seated(size: int) -> bool:
	var found: GroupPlace = GroupPlace.find_and_reserve_table(
		get_tree(), size, self
	)

	if not found.is_valid():
		return false

	place = found
	destination_id = place.get_place_id()
	destination_kind = &"seated"
	_log("seated at %s" % String(destination_id))

	return true


func _try_standing(size: int) -> bool:
	if definition != null and not definition.standing_allowed:
		return false

	var tags: Array[StringName] = (
		definition.social_tags if definition != null else []
	)

	var area: GroupStandingArea = GroupStandingArea.find_best_free(
		get_tree(), size, tags
	)

	if area == null:
		return false

	var found: GroupPlace = GroupPlace.reserve_standing(
		area, size, self, group_id
	)

	if not found.is_valid():
		return false

	place = found
	destination_id = place.get_place_id()
	destination_kind = &"standing"
	_log("standing at %s" % String(destination_id))

	return true


## Starts a controlled one-at-a-time doorway sequence. The final table or
## standing destination is assigned only after each member crosses inside.
func begin_entry_sequence() -> void:
	if _entry_sequence_started or place == null or not place.is_valid():
		return

	_entry_sequence_started = true
	set_state(State.ENTERING)
	_run_entry_sequence()


func _run_entry_sequence() -> void:
	var valid: Array[Node] = get_valid_members()

	for index: int in range(valid.size()):
		if is_finished():
			return

		var member: Node = valid[index]

		if not is_instance_valid(member):
			continue

		if not member.has_method(&"begin_group_entry"):
			_assign_member_to_place(member, index)
			continue

		member.call(&"begin_group_entry")

		var elapsed: float = 0.0
		while (
			is_instance_valid(member)
			and int(member.get(&"current_state"))
				== int(Customer.State.GROUP_ENTERING)
			and elapsed < member_entry_timeout
		):
			await get_tree().create_timer(0.1).timeout
			elapsed += 0.1

		if not is_instance_valid(member):
			continue

		if int(member.get(&"current_state")) == int(Customer.State.GROUP_ENTERING):
			fail_visit("member %d could not cross the doorway" % index)
			return

		_assign_member_to_place(member, index)

		if member_entry_delay > 0.0:
			await get_tree().create_timer(member_entry_delay).timeout

	if not is_finished():
		set_state(State.MOVING_TO_PLACE)


func _assign_member_to_place(member: Node, index: int) -> void:
	if place == null or not place.is_valid() or not is_instance_valid(member):
		return

	# Remember which slot this member owns. Everything after this - arrival
	# checks, retries, the final placement - reads the slot from here rather
	# than from the member's current position in the array.
	_slot_index_by_member[member] = index
	_slot_started_minutes[member] = _world_minutes()

	if not _slot_retries.has(member):
		_slot_retries[member] = 0

	if place.is_seated():
		var chair: Node = place.get_chair_for(index)

		if chair != null and member.has_method(&"assign_group_chair"):
			member.call(&"assign_group_chair", chair)
			return

	if member.has_method(&"assign_group_position"):
		member.call(
			&"assign_group_position",
			place.get_slot_for(index),
			place.get_centre()
		)


## The slot index this member was actually assigned.
func get_slot_index_for(member: Node) -> int:
	if _slot_index_by_member.has(member):
		return int(_slot_index_by_member[member])

	return maxi(members.find(member), 0)


## This member's Customer state, or minus one when it has none.
##
## Group members are normally [Customer] nodes, but the framework tests build
## plain stand-ins. get() returns null for a property that does not exist, and
## int(null) is a hard error rather than a zero.
func _get_member_state(member: Node) -> int:
	if not is_instance_valid(member):
		return -1

	var raw: Variant = member.get(&"current_state")

	if raw == null:
		return -1

	return int(raw)


## Whether this member has stopped taking part in assembly.
##
## A member already walking out is not blocking anybody, so it must not hold
## the group in MOVING_TO_PLACE.
func _is_member_departing(member: Node) -> bool:
	var member_state: int = _get_member_state(member)

	return member_state in [
		int(Customer.State.LEAVING_TO_DOOR),
		int(Customer.State.EXITING),
	]


## Advances assembly by one tick, recovering members that cannot arrive.
##
## Returns true once every member that is still taking part is standing at its
## slot. No member is ever removed or abandoned: it is retried, then accepted
## within tolerance, then placed - in that order, and only that many times.
func update_assembly() -> bool:
	if place == null or not place.is_valid():
		return false

	var valid: Array[Node] = get_valid_members()

	if valid.is_empty():
		return false

	var everybody_ready: bool = true

	for member: Node in valid:
		if _is_member_departing(member):
			continue

		if not _update_member_assembly(member):
			everybody_ready = false

	return everybody_ready


## One member's assembly step. Returns true when it is in position.
func _update_member_assembly(member: Node) -> bool:
	var member_2d: Node2D = member as Node2D

	if member_2d == null:
		return true

	var index: int = get_slot_index_for(member)
	var target: Vector2 = place.get_slot_for(index)
	var member_state: int = _get_member_state(member)
	var distance: float = member_2d.global_position.distance_to(target)

	if member_state == int(Customer.State.IN_GROUP):
		# Already arrived. Tolerance is not re-checked here: a member that has
		# joined the group must not be sent away again because somebody nudged
		# it a few pixels.
		return true

	# Close enough counts. The precise formation point is a presentation
	# detail, not a gameplay requirement, and insisting on it is what left
	# members oscillating a handful of pixels short forever.
	if distance <= slot_arrival_tolerance:
		_accept_member_at_slot(member, false)

		return true

	if not _slot_started_minutes.has(member):
		_slot_started_minutes[member] = _world_minutes()

		return false

	var waiting: int = _world_minutes() - int(_slot_started_minutes[member])

	if waiting < slot_arrival_timeout_minutes:
		return false

	var retries: int = int(_slot_retries.get(member, 0))

	if retries < maximum_slot_retries:
		_slot_retries[member] = retries + 1
		_slot_started_minutes[member] = _world_minutes()
		group_slot_recoveries += 1

		push_warning(
			"[Group %s] refreshing slot navigation for %s (attempt %d)."
			% [String(group_id), member.name, retries + 1]
		)

		_log("slot retry %d for %s" % [retries + 1, member.name])

		if member.has_method(&"refresh_group_slot"):
			member.call(&"refresh_group_slot")
		else:
			_assign_member_to_place(member, index)

		return false

	# Every retry used. Place the member rather than losing it - a group that
	# cannot assemble must still be able to drink and leave.
	push_warning(
		"[Group %s] placing %s at its slot after %d failed attempts."
		% [String(group_id), member.name, retries]
	)

	_accept_member_at_slot(member, true)

	return true


func _accept_member_at_slot(member: Node, snap: bool) -> void:
	group_slot_recoveries += 1

	_log(
		"%s %s at slot" % [member.name, "placed" if snap else "accepted"]
	)

	if member.has_method(&"accept_group_slot_arrival"):
		member.call(&"accept_group_slot_arrival", snap)


## Marks the group assembled exactly once. Returns true the first time only.
func mark_assembled() -> bool:
	if _assembled_handled:
		return false

	_assembled_handled = true

	_log("assembled with %d members" % get_valid_members().size())

	print(
		"[Group %s] assembled: %d members, %d slot recoveries."
		% [String(group_id), get_valid_members().size(), group_slot_recoveries]
	)

	return true


## Marks the post-keg phase started exactly once. Returns true the first time.
func mark_post_drink_started() -> bool:
	if _post_drink_handled:
		return false

	_post_drink_handled = true

	if keg_emptied_at_minutes < 0:
		keg_emptied_at_minutes = _world_minutes()

	post_drink_started_at_minutes = _world_minutes()

	print(
		"[Group %s] keg empty; post-drink phase started at minute %d."
		% [String(group_id), post_drink_started_at_minutes]
	)

	return true


## World minutes since the post-keg phase began.
func get_post_drink_duration() -> int:
	if post_drink_started_at_minutes < 0:
		return 0

	return maxi(_world_minutes() - post_drink_started_at_minutes, 0)


## Sends each member to its assigned position.
func move_members_to_place() -> void:
	if place == null or not place.is_valid():
		return

	set_state(State.MOVING_TO_PLACE)

	var valid: Array[Node] = get_valid_members()

	for index: int in range(valid.size()):
		_assign_member_to_place(valid[index], index)


## True once enough members have reached their positions to begin the visit.
##
## Deliberately a threshold rather than everyone: one member stuck behind a
## chair should not hold up the other seven indefinitely.
func are_members_in_position(tolerance: float = -1.0) -> bool:
	var valid: Array[Node] = get_valid_members()

	if valid.is_empty() or place == null or not place.is_valid():
		return false

	var limit: float = (
		slot_arrival_tolerance if tolerance < 0.0 else tolerance
	)

	for member: Node in valid:
		if _is_member_departing(member):
			continue

		var member_2d: Node2D = member as Node2D

		if member_2d == null:
			return false

		# Both seated and standing group members finish their move in
		# IN_GROUP. Do not begin ordering while some are still walking.
		if _get_member_state(member) != int(Customer.State.IN_GROUP):
			return false

		# The slot comes from the assignment map, not from this member's
		# current position in the array - those two diverge as soon as
		# anybody is removed.
		var target: Vector2 = place.get_slot_for(get_slot_index_for(member))

		if member_2d.global_position.distance_to(target) > limit:
			return false

	return true


# --- Delivery clearance ------------------------------------------------------
#
# The group widens its own ring while a keg is on its way, then closes it again.
# Nothing here touches collision shapes, moves the tavern hand, or changes the
# normal drinking formation - the original slots sit untouched in the slot map
# the whole time.

## Sends every member outward and starts the clearance clock.
##
## Returns false when there is nothing to clear (no place, no members), so the
## caller can go straight on rather than waiting for a phase that cannot end.
func begin_delivery_clearance() -> bool:
	if _clearance_handled:
		return false

	if place == null or not place.is_valid():
		return false

	var valid: Array[Node] = get_valid_members()

	if valid.is_empty():
		return false

	_clearance_handled = true
	clearance_started_at_minutes = _world_minutes()

	var centre: Vector2 = place.get_centre()

	for member: Node in valid:
		var target: Vector2 = _build_delivery_slot(member, centre)

		_delivery_slot_by_member[member] = target
		_clearance_retries[member] = 0

		if member.has_method(&"begin_delivery_step_back"):
			member.call(&"begin_delivery_step_back", target)

	members_required_to_clear = maxi(
		1, int(ceil(float(valid.size()) * minimum_cleared_fraction))
	)

	# The approach is picked now, while the ring is still where it will be
	# during the delivery, so the gap chosen is the gap that will exist.
	delivery_approach_position = place.get_delivery_approach_position(
		_get_delivery_slot_positions()
	)

	print(
		"[Group %s] delivery clearance started; %d of %d members must clear."
		% [String(group_id), members_required_to_clear, valid.size()]
	)

	return true


## This member's temporary position: farther out along its own radius.
##
## Radial rather than a separate formation, so the ring keeps its shape and
## nobody crosses anybody else's path on the way out or back.
func _build_delivery_slot(member: Node, centre: Vector2) -> Vector2:
	var slot: Vector2 = place.get_slot_for(get_slot_index_for(member))
	var outward: Vector2 = slot - centre

	if outward.length_squared() < 0.01:
		# Degenerate: a member standing on the centre has no radius to push
		# along, so push it anywhere consistent rather than nowhere.
		outward = Vector2.RIGHT

	var target: Vector2 = (
		slot + outward.normalized() * delivery_step_back_distance
	)

	return _project_to_navigation(target, slot)


## Keeps a temporary position on the navigation map.
##
## Falls back to the original slot rather than a wall: a member that cannot
## step back is a slower delivery, but a member inside a bench is a bug.
func _project_to_navigation(target: Vector2, fallback: Vector2) -> Vector2:
	if not is_inside_tree():
		return target

	var map: RID = get_tree().root.world_2d.navigation_map

	if not map.is_valid():
		return target

	var closest: Vector2 = NavigationServer2D.map_get_closest_point(
		map, target
	)

	# A map with no regions answers every query with the origin. Projecting
	# onto that would put the whole group on top of (0, 0) - so when the
	# answer is the origin and the target plainly is not, there is no usable
	# navigation map and the raw target is the better answer.
	if closest.is_zero_approx() and not target.is_zero_approx():
		return target

	# A projection that lands a long way off means the point was never really
	# reachable; the original slot is known-good.
	if closest.distance_to(target) > delivery_step_back_distance:
		return fallback

	return closest


func _get_delivery_slot_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []

	for key: Variant in _delivery_slot_by_member:
		positions.append(_delivery_slot_by_member[key])

	return positions


## Advances clearance by one tick. True once enough members are clear.
func update_delivery_clearance() -> bool:
	var valid: Array[Node] = get_valid_members()

	if valid.is_empty():
		return true

	var cleared: int = 0

	for member: Node in valid:
		if _update_member_clearance(member):
			cleared += 1

	members_cleared = cleared

	if cleared >= members_required_to_clear:
		return true

	# Bounded: a delivery that has waited long enough goes ahead with the room
	# it has. The approach point is outside the ring anyway.
	if _world_minutes() - clearance_started_at_minutes >= delivery_clearance_timeout:
		push_warning(
			"[Group %s] clearance timed out with %d of %d clear; "
			% [String(group_id), cleared, members_required_to_clear]
			+ "proceeding with the delivery anyway."
		)

		return true

	return false


func _update_member_clearance(member: Node) -> bool:
	var member_2d: Node2D = member as Node2D

	if member_2d == null:
		return true

	var target: Vector2 = _delivery_slot_by_member.get(
		member, member_2d.global_position
	)

	if member_2d.global_position.distance_to(target) <= delivery_position_tolerance:
		return true

	var retries: int = int(_clearance_retries.get(member, 0))

	if retries < maximum_clearance_retries:
		_clearance_retries[member] = retries + 1
		delivery_clearance_recoveries += 1

		if member.has_method(&"refresh_delivery_step_back"):
			member.call(&"refresh_delivery_step_back")

		return false

	# Out of retries. Place it clear rather than let one member hold up every
	# delivery this group will ever receive.
	delivery_clearance_recoveries += 1

	if member.has_method(&"accept_delivery_clearance"):
		member.call(&"accept_delivery_clearance", true)

	return true


func mark_clearance_complete() -> void:
	if clearance_completed_at_minutes >= 0:
		return

	clearance_completed_at_minutes = _world_minutes()

	print(
		"[Group %s] clearance threshold reached (%d cleared); approach at %s."
		% [
			String(group_id), members_cleared,
			str(delivery_approach_position.round()),
		]
	)


## Puts every member back on its original drinking slot.
func begin_reform() -> bool:
	if _reform_handled:
		return false

	_reform_handled = true
	reform_started_at_minutes = _world_minutes()

	for member: Node in get_valid_members():
		if member.has_method(&"end_delivery_step_back"):
			member.call(&"end_delivery_step_back")

	_delivery_slot_by_member.clear()
	_clearance_retries.clear()

	print("[Group %s] reforming after delivery." % String(group_id))

	return true


## True once enough members are back on their slots, or time is up.
func is_reform_complete() -> bool:
	if place == null or not place.is_valid():
		return true

	var valid: Array[Node] = get_valid_members()

	if valid.is_empty():
		return true

	var back: int = 0

	for member: Node in valid:
		var member_2d: Node2D = member as Node2D

		if member_2d == null:
			continue

		var slot: Vector2 = place.get_slot_for(get_slot_index_for(member))

		if member_2d.global_position.distance_to(slot) <= slot_arrival_tolerance:
			back += 1

	if back >= maxi(1, int(ceil(float(valid.size()) * minimum_cleared_fraction))):
		return true

	return (
		_world_minutes() - reform_started_at_minutes >= delivery_reform_timeout
	)


func mark_reform_complete() -> void:
	if reform_completed_at_minutes >= 0:
		return

	reform_completed_at_minutes = _world_minutes()

	print("[Group %s] reformed; drinking may begin." % String(group_id))


func get_reform_duration() -> int:
	if reform_started_at_minutes < 0:
		return 0

	var ended: int = (
		reform_completed_at_minutes
		if reform_completed_at_minutes >= 0
		else _world_minutes()
	)

	return maxi(ended - reform_started_at_minutes, 0)


func get_clearance_duration() -> int:
	if clearance_started_at_minutes < 0:
		return 0

	var ended: int = (
		clearance_completed_at_minutes
		if clearance_completed_at_minutes >= 0
		else _world_minutes()
	)

	return maxi(ended - clearance_started_at_minutes, 0)


## Clears any temporary positions without moving anybody. For teardown.
func clear_delivery_positions() -> void:
	for key: Variant in _delivery_slot_by_member:
		var member: Node = key as Node

		if is_instance_valid(member):
			member.set(&"delivery_slot_position", Vector2.ZERO)
			member.set(&"is_stepped_back_for_delivery", false)

	_delivery_slot_by_member.clear()
	_clearance_retries.clear()


# --- Order icon --------------------------------------------------------------

## Shows the order icon above the current leader. Idempotent.
func show_order_icon() -> void:
	var current: Node = get_icon_leader()

	if current == null:
		return

	if not current.has_method(&"show_group_order_icon"):
		return

	# Move it if the leader changed, rather than leaving one behind.
	for member: Node in get_valid_members():
		if member != current and member.has_method(&"hide_group_order_icon"):
			member.call(&"hide_group_order_icon")

	current.call(&"show_group_order_icon", group_order_icon_texture)

	if not order_icon_shown:
		order_icon_shown = true
		order_icon_shown_at_minutes = _world_minutes()

		print(
			"[Group %s] order icon shown above leader %s."
			% [String(group_id), current.name]
		)


## Hides the order icon wherever it is. Idempotent.
func hide_order_icon(reason: StringName) -> void:
	var was_shown: bool = order_icon_shown

	for member: Node in members:
		if is_instance_valid(member) and member.has_method(&"hide_group_order_icon"):
			member.call(&"hide_group_order_icon")

	if not was_shown:
		return

	order_icon_shown = false
	order_icon_hidden_reason = reason

	if order_icon_shown_at_minutes >= 0:
		order_icon_duration_minutes = maxi(
			_world_minutes() - order_icon_shown_at_minutes, 0
		)

	print(
		"[Group %s] order icon hidden (%s) after %d minutes."
		% [String(group_id), String(reason), order_icon_duration_minutes]
	)


## The member the icon belongs above: the leader, or a valid stand-in.
##
## A leader can be removed mid-order. Rather than losing the icon - and with
## it the only sign of who the player should serve - the group promotes and
## the icon follows.
func get_icon_leader() -> Node:
	if is_instance_valid(leader) and members.has(leader):
		return leader

	_promote_new_leader()

	if is_instance_valid(leader):
		print(
			"[Group %s] leader replaced; order icon moved to %s."
			% [String(group_id), leader.name]
		)

	return leader if is_instance_valid(leader) else null


## True while this group's keg order is outstanding and should be visible.
func wants_order_icon() -> bool:
	if delivery_completed or is_finished():
		return false

	return state in [
		State.WAITING_TO_ORDER,
		State.ORDERING,
		State.WAITING_FOR_SERVICE,
		State.WAITING_FOR_STOCK,
		State.WAITING_FOR_DELIVERY,
		State.CLEARING_DELIVERY_SPACE,
		State.DELIVERY_IN_PROGRESS,
	]


# --- Leisure -----------------------------------------------------------------
#
# The group owns the DECISION and the membership; the member owns the doing.
# Everything below either asks the tavern a question or calls a method the
# solo customer AI already calls, which is what keeps darts, socialising and
# relaxing single implementations rather than three plus three.


## Where the shared keg sits, and where staff bring it. Zero when unplaced.
func get_serving_position() -> Vector2:
	if place == null or not place.is_valid():
		return Vector2.ZERO

	return place.get_serving_position()


## Whether this group is still expecting a keg to be carried to it.
func is_awaiting_keg_delivery() -> bool:
	return (
		not is_finished()
		and not delivery_completed
		and state in [
			State.WAITING_FOR_DELIVERY,
			State.WAITING_FOR_STOCK,
			State.CLEARING_DELIVERY_SPACE,
			State.DELIVERY_IN_PROGRESS,
		]
	)


## True once the ring has opened and staff may walk in with the keg.
##
## The task is deliberately not placeable before this: a worker that arrives
## while the ring is still closed has nowhere to put the keg down, which is
## exactly how deliveries were timing out.
func is_ready_for_keg_placement() -> bool:
	return state == State.DELIVERY_IN_PROGRESS or delivery_completed


## Marks shared drinking as started. True the first time only.
func mark_drinking_started() -> bool:
	if _drinking_started:
		return false

	_drinking_started = true

	return true


## Puts the delivery phase back to the start so a retry can run it again.
func reset_delivery_phase() -> void:
	_clearance_handled = false
	_reform_handled = false

	clearance_started_at_minutes = -1
	clearance_completed_at_minutes = -1
	reform_started_at_minutes = -1
	reform_completed_at_minutes = -1
	members_cleared = 0
	delivery_approach_position = Vector2.ZERO
	keg_collected = false


## Starts the leisure phase, rolling how long it will run.
func begin_leisure() -> void:
	if leisure_duration_minutes > 0:
		return

	# mark_post_drink_started() has already stamped the clock by the time the
	# manager gets here; this only decides how long the phase runs.
	mark_post_drink_started()

	leisure_duration_minutes = maxi(1, randi_range(
		mini(minimum_leisure_minutes, maximum_leisure_minutes),
		maxi(minimum_leisure_minutes, maximum_leisure_minutes)
	))

	next_leisure_decision_minutes = _world_minutes()

	set_state(State.SOCIALISING)

	print(
		"[Group %s] entered leisure phase for %d minutes."
		% [String(group_id), leisure_duration_minutes]
	)


## True once the leisure phase has run its course.
func is_leisure_finished() -> bool:
	return get_post_drink_duration() >= leisure_duration_minutes


## Members currently away from their slots on a leisure activity.
func get_away_members() -> Array[Node]:
	var away: Array[Node] = []

	for member: Node in get_valid_members():
		if member.has_method(&"is_group_member_busy"):
			if bool(member.call(&"is_group_member_busy")):
				away.append(member)

	return away


## Most members allowed away at once, always at least one.
func get_maximum_away() -> int:
	return maxi(
		1,
		int(floor(float(get_valid_members().size()) * maximum_away_fraction))
	)


## Whether a leisure decision is due right now.
func is_leisure_decision_due() -> bool:
	if not leisure_enabled:
		return false

	if next_leisure_decision_minutes < 0:
		return true

	return _world_minutes() >= next_leisure_decision_minutes


func note_leisure_decision_made() -> void:
	next_leisure_decision_minutes = (
		_world_minutes() + leisure_decision_interval_minutes
	)


## Members standing at their slots with nothing to do.
func get_idle_members() -> Array[Node]:
	var idle: Array[Node] = []

	for member: Node in get_valid_members():
		if member.has_method(&"is_group_member_idle"):
			if bool(member.call(&"is_group_member_idle")):
				idle.append(member)

	return idle


## Records one finished leisure activity. Called by the member itself.
func on_member_activity_finished(
	member: Node,
	activity_id: StringName
) -> void:
	if member == null:
		return

	group_activity_count += 1

	match activity_id:
		&"relax":
			group_relax_count += 1
		&"socialise":
			group_socialise_count += 1
		&"darts":
			group_darts_count += 1

	_log("%s finished %s" % [member.name, String(activity_id)])

	print(
		"[Group %s] member %s completed activity '%s'."
		% [String(group_id), member.name, String(activity_id)]
	)


## Called by a member the moment it is standing at its slot again.
func on_member_returned_to_slot(member: Node) -> void:
	if member == null:
		return

	_log("%s back at slot" % member.name)


## Stops new activities and asks anybody away to come back.
##
## Recall is bounded on purpose. One member wedged at the darts board must not
## be able to hold the whole party in the tavern, so the timeout in
## [GroupManager] moves the group on whether everybody made it back or not.
func begin_recall() -> void:
	if state == State.RECALLING or is_finished():
		return

	if state in [State.PREPARING_TO_LEAVE, State.LEAVING]:
		return

	recall_started_at_minutes = _world_minutes()

	set_state(State.RECALLING)

	var recalled: int = 0

	for member: Node in get_valid_members():
		if not member.has_method(&"is_group_member_busy"):
			continue

		if not bool(member.call(&"is_group_member_busy")):
			continue

		# Cancelling first releases the darts board before the walk home, so
		# the point is free for somebody else immediately rather than a
		# journey later.
		if member.has_method(&"cancel_group_activity"):
			member.call(&"cancel_group_activity")

		if member.has_method(&"begin_returning_to_group_slot"):
			member.call(&"begin_returning_to_group_slot")

		recalled += 1

	print(
		"[Group %s] recall started; %d member(s) called back."
		% [String(group_id), recalled]
	)


## World minutes since recall began.
func get_recall_duration() -> int:
	if recall_started_at_minutes < 0:
		return 0

	return maxi(_world_minutes() - recall_started_at_minutes, 0)


## True when nobody is part-way through an activity any more.
func is_recall_complete() -> bool:
	return get_away_members().is_empty()


## Releases every activity booking any member still holds. Idempotent.
func release_member_activity_reservations() -> int:
	var released: int = 0

	for member: Node in get_valid_members():
		if not member.has_method(&"release_group_activity_reservation"):
			continue

		if member.get(&"group_activity_reservation") == null:
			continue

		member.call(&"release_group_activity_reservation")

		released += 1

	return released


# --- Payment -----------------------------------------------------------------

## Records that the leader paid for the keg. Returns false if already paid.
func record_group_payment(member: Node, amount: int) -> bool:
	if payment_made:
		return false

	payment_made = true
	paying_member_name = String(member.name) if member != null else ""
	amount_paid += amount

	print(
		"[Group %s] payment completed: %s paid %d for %s (%s)."
		% [
			String(group_id), paying_member_name, amount,
			String(keg_drink_id), String(keg_format_id),
		]
	)

	_log("%s paid %d" % [paying_member_name, amount])

	return true


# --- Departure ---------------------------------------------------------------

## Starts the group leaving and releases what it holds.
##
## Safe from any state, including a failed one, and safe to call twice.
func begin_departure(reason: String = "") -> void:
	if state in [State.PREPARING_TO_LEAVE, State.LEAVING] or is_finished():
		return

	if not reason.is_empty():
		departure_reason = StringName(reason)

	set_state(State.PREPARING_TO_LEAVE)

	if departure_reason.is_empty():
		departure_reason = &"group_departure"

	_resolve_shared_serving()

	hide_order_icon(&"group_departed")

	# A party that has decided to leave is not owed a keg. Releasing here
	# rather than at cleanup means the claim goes back the moment the
	# decision is made, so the next group can have it while this one is
	# still walking to the door.
	if delivery_status != &"delivered":
		_release_stock_and_delivery()

	if _departure_sequence_started:
		return

	_departure_sequence_started = true
	set_state(State.LEAVING)

	var departing: int = get_valid_members().size()

	if departing > 0:
		print(
			"[Group %s] departure started (%s) with %d members."
			% [String(group_id), String(departure_reason), departing]
		)

	_run_departure_sequence()


## Queues every member to leave, staggered.
##
## Previously this was an await loop. Any path that freed the group - the
## patience check in _check_departure_complete() was the usual one - killed
## the coroutine part-way through, leaving the members it had not reached yet
## standing in IN_GROUP forever. The queue is drained from _process() instead,
## and dispatch_all_departures() guarantees the remainder are commanded before
## the group can finish.
func _run_departure_sequence() -> void:
	_departure_queue = get_valid_members()
	_departure_stagger_remaining = 0.0

	_drain_departure_queue()


func _process(delta: float) -> void:
	if _departure_queue.is_empty():
		return

	_departure_stagger_remaining -= delta

	if _departure_stagger_remaining > 0.0:
		return

	_drain_departure_queue()


func _drain_departure_queue() -> void:
	while not _departure_queue.is_empty():
		var member: Node = _departure_queue.pop_front()

		if not is_instance_valid(member) or not members.has(member):
			continue

		_send_member_home(member)

		_departure_stagger_remaining = member_departure_delay

		if member_departure_delay > 0.0:
			return


## Commands one member to leave with the group.
func _send_member_home(member: Node) -> void:
	if not is_instance_valid(member):
		return

	if member.has_method(&"begin_group_departure"):
		member.call(&"begin_group_departure")

		_log("%s departing" % member.name)


## Commands every remaining member to leave, immediately and without stagger.
##
## The backstop that makes "a member must not remain in IN_GROUP after the
## group has started departing" true regardless of which path ended the visit.
func dispatch_all_departures() -> int:
	var dispatched: int = 0

	_departure_queue.clear()

	for member: Node in get_valid_members():
		if _is_member_departing(member):
			continue

		_send_member_home(member)

		dispatched += 1

	return dispatched


## Releases every reservation and finishes the visit.
func complete_visit() -> void:
	if is_finished():
		return

	# Nobody may be left standing in the group when it finishes. This is the
	# guarantee that used to be missing: the visit could complete on patience
	# while half the party was still in IN_GROUP.
	dispatch_all_departures()

	if departure_reason.is_empty():
		departure_reason = &"visit_complete"

	cleanup()

	set_state(State.COMPLETE)

	visit_completed.emit()


func fail_visit(reason: String) -> void:
	if is_finished():
		return

	failure_reason = reason

	if departure_reason.is_empty():
		departure_reason = StringName(reason)

	# A member that is inside the tavern walks out; only one that never got
	# in is removed outright. Finishing an IN_GROUP member here was what
	# produced completed visits with departure_reason "unknown" and a state
	# trail that stopped at IN_GROUP or MOVING_TO_GROUP_SLOT.
	for member: Node in get_valid_members():
		if _is_member_inside(member):
			if member.has_method(&"begin_group_departure"):
				member.call(&"begin_group_departure")
				continue

		member.set(&"departure_reason", StringName(reason))

		if member.has_method(&"finish_customer"):
			member.call(&"finish_customer")
		else:
			member.queue_free()

	cleanup()

	set_state(State.FAILED)

	visit_failed.emit(reason)

	_log("failed: %s" % reason)


## Whether this member has actually got inside and can walk out on its own.
func _is_member_inside(member: Node) -> bool:
	var member_state: int = _get_member_state(member)

	return member_state in [
		int(Customer.State.GROUP_INSIDE_STAGING),
		int(Customer.State.MOVING_TO_GROUP_SLOT),
		int(Customer.State.IN_GROUP),
		int(Customer.State.MOVING_TO_SEAT),
		int(Customer.State.LEAVING_TO_DOOR),
		int(Customer.State.EXITING),
	]


## The one safe teardown for a group visit. Safe to call any number of times.
##
## Everything a group holds is released here and nowhere else: the formation
## point, the shared serving and its vessel, the order, the members' group
## references, the pending departure queue. Each release is guarded, so a
## second call cannot return the same vessel twice or double-decrement a
## capacity counter.
func cleanup() -> void:
	if _cleanup_done:
		return

	_cleanup_done = true

	_departure_queue.clear()

	# Any darts board or activity point a member still holds goes back before
	# anything else: those are the reservations another customer is waiting on.
	release_member_activity_reservations()

	hide_order_icon(&"cleanup")
	clear_delivery_positions()

	_release_stock_and_delivery()

	# Drop the serving before the place: the serving's position and anchor
	# come from the place, and releasing the place first would leave the
	# teardown reading a reservation that is already gone.
	_resolve_shared_serving()
	_release_current_order()
	release_place()

	for member: Node in members:
		if is_instance_valid(member):
			_clear_member_group_reference(member)

			if member.has_signal(&"tree_exiting"):
				if member.tree_exiting.is_connected(_on_member_exiting):
					member.tree_exiting.disconnect(_on_member_exiting)

	members.clear()
	leader = null
	_slot_index_by_member.clear()
	_slot_started_minutes.clear()
	_slot_retries.clear()
	_member_next_drink.clear()

	cleanup_completed = true

	_log("cleanup completed")

	print("[Group %s] cleanup completed." % String(group_id))


## Clears one member's back-reference to this group. Idempotent.
func _clear_member_group_reference(member: Node) -> void:
	if not is_instance_valid(member):
		return

	if member.get(&"group_controller") != self:
		return

	if member.has_method(&"leave_group"):
		member.call(&"leave_group")
	else:
		member.set(&"group_id", &"")
		member.set(&"group_controller", null)


## Hands back any stock claim and cancels any delivery task. Idempotent.
##
## Goes through the services that own them rather than doing the accounting
## here, so a second cleanup finds nothing to release rather than releasing a
## second time.
func _release_stock_and_delivery() -> void:
	if not delivery_task_id.is_empty():
		var board: Node = get_node_or_null(^"/root/TaskBoard")

		if board != null and board.has_method(&"cancel"):
			var task: Variant = board.call(&"get_task", delivery_task_id)

			if task != null and not bool(task.call(&"is_terminal")):
				board.call(&"cancel", task, &"group_left_before_delivery")

		delivery_task_id = &""

	if not stock_reservation_id.is_empty():
		var service: Node = _find_stock_service()

		if service != null and service.has_method(&"release_reservation"):
			service.call(&"release_reservation", stock_reservation_id)

		stock_reservation_id = &""

	if delivery_status not in [&"delivered", &"none"]:
		delivery_status = &"cancelled"


func _find_stock_service() -> Node:
	var found: Array[Node] = get_tree().get_nodes_in_group(
		&"group_keg_stock_service"
	)

	return found[0] if not found.is_empty() else null


## Marks the current order finished so nothing else tries to fulfil it.
func _release_current_order() -> void:
	if current_order == null:
		return

	if not completed_orders.has(current_order):
		completed_orders.append(current_order)

	current_order = null


func release_place() -> void:
	if place == null:
		return

	# Members are passed so chairs handed to them are released too - the group
	# no longer owns those reservations.
	var member_list: Array = []

	for member: Node in members:
		if is_instance_valid(member):
			member_list.append(member)

	var releasing: GroupPlace = place

	# Cleared before the release so a re-entrant call cannot release twice.
	place = null

	releasing.release(member_list)


## Hands the shared vessel back and drops the object.
##
## Called on every exit path, so a group that leaves early cannot strand a
## punch bowl in the vessel pool. The vessel itself is returned exactly once
## by SharedServing._release_vessel(), whichever route gets here.
func _resolve_shared_serving() -> void:
	if shared_serving == null:
		return

	var serving: SharedServing = shared_serving

	# Cleared first so nothing re-enters this with the same node.
	shared_serving = null

	if not is_instance_valid(serving):
		return

	if not serving.is_empty():
		serving.empty_now()

	serving.remove_from_group(&"shared_servings")
	serving.queue_free()


# --- Milestone recording -----------------------------------------------------

func record_order_failure(reason: StringName) -> void:
	order_failure_reason = reason
	failure_reason = String(reason)

	if departure_reason.is_empty():
		departure_reason = reason

	_log("order failed: %s" % String(reason))


func record_departure_reason(reason: StringName) -> void:
	if departure_reason.is_empty():
		departure_reason = reason


func record_order_source(station: Node) -> void:
	source_station_name = String(station.name) if station != null else ""


func record_stock_before(measures: int) -> void:
	stock_before_measures = measures


## Notes a keg that actually exists in the world.
func record_keg_created(serving: SharedServing, stock_after: int) -> void:
	if serving == null:
		return

	stock_after_measures = stock_after
	keg_starting_portions = serving.maximum_portions
	keg_remaining_portions = serving.remaining_portions
	keg_drink_id = serving.drink_id
	keg_format_id = serving.serving_format_id

	portions_per_member.clear()

	for member: Node in get_valid_members():
		portions_per_member[String(member.name)] = 0

	print(
		"[Group %s] shared serving created: %s (%s) x%d portions."
		% [
			String(group_id), String(keg_drink_id),
			String(keg_format_id), keg_starting_portions,
		]
	)

	_log(
		"keg %s (%s) x%d from %s, stock %d -> %d" % [
			String(keg_drink_id), String(keg_format_id),
			keg_starting_portions, source_station_name,
			stock_before_measures, stock_after_measures,
		]
	)


func record_member_drink(member: Node, remaining: int) -> void:
	if member == null:
		return

	var key: String = String(member.name)

	portions_per_member[key] = int(portions_per_member.get(key, 0)) + 1
	keg_remaining_portions = remaining

	_log(
		"%s drank; %d portions left" % [key, remaining]
	)

	print(
		"[Group %s] shared drink: %s, %d portions remaining."
		% [String(group_id), key, remaining]
	)

	if remaining <= 0 and keg_emptied_at_minutes < 0:
		keg_emptied_at_minutes = _world_minutes()


func get_destination_id() -> StringName:
	if place != null and place.is_valid():
		return place.get_place_id()

	return destination_id


func record_payment(amount: int) -> void:
	amount_paid += amount

	_log("paid %d" % amount)


func describe_keg() -> String:
	if keg_starting_portions <= 0:
		return "-"

	return "%s %d/%d" % [
		String(keg_drink_id), keg_remaining_portions, keg_starting_portions,
	]


func describe_problem() -> String:
	if not order_failure_reason.is_empty():
		return String(order_failure_reason)

	return String(departure_reason)


## Everything this milestone asked to be observable, in one place.
func get_diagnostics() -> Dictionary:
	var member_ids: Array[String] = []

	for member: Node in members:
		if is_instance_valid(member):
			member_ids.append(String(member.name))

	return {
		"group_id": String(group_id),
		"definition": (
			String(definition.group_id) if definition != null else "-"
		),
		"member_ids": member_ids,
		"leader_id": String(leader.name) if is_instance_valid(leader) else "",
		"group_size": get_size(),
		"state": get_state_label(),
		"destination_kind": String(destination_kind),
		"destination_id": String(get_destination_id()),
		"order_failure_reason": String(order_failure_reason),
		"source_station": source_station_name,
		"stock_before_measures": stock_before_measures,
		"stock_after_measures": stock_after_measures,
		"keg_drink_id": String(keg_drink_id),
		"keg_format_id": String(keg_format_id),
		"keg_starting_portions": keg_starting_portions,
		"keg_remaining_portions": keg_remaining_portions,
		"portions_per_member": portions_per_member,
		"departure_reason": String(departure_reason),
		"cleanup_completed": cleanup_completed,
		"amount_paid": amount_paid,
		"group_slot_recoveries": group_slot_recoveries,
		"keg_emptied_at_minutes": keg_emptied_at_minutes,
		"post_drink_started_at_minutes": post_drink_started_at_minutes,
		"post_drink_duration_minutes": get_post_drink_duration(),
		"serving_attempts": serving_attempts,
		"shared_drinks_consumed": get_shared_drinks_consumed(),
		"group_leader_id": String(leader.name) if is_instance_valid(leader) else "",
		"group_payment_made": payment_made,
		"group_payment_amount": amount_paid,
		"group_paid_by": paying_member_name,
		"group_activity_count": group_activity_count,
		"group_relax_count": group_relax_count,
		"group_socialise_count": group_socialise_count,
		"group_darts_count": group_darts_count,
		"group_order_status": (
			current_order.get_status_name() if current_order != null
			else ("completed" if not completed_orders.is_empty() else "none")
		),
		"group_order_failure_reason": String(order_failure_reason),
		"group_keg_item_id": String(keg_item_id),
		"group_stock_reserved": not stock_reservation_id.is_empty(),
		"group_stock_reservation_id": String(stock_reservation_id),
		"group_delivery_task_id": String(delivery_task_id),
		"group_delivery_status": String(delivery_status),
		"group_bypassed_stock": bypassed_stock,
		"group_departure": String(departure_reason),
		"leader_customer_id": (
			int(leader.get(&"runtime_customer_id"))
			if is_instance_valid(leader) else _leader_customer_id
		),
		"leader_customer_type": get_leader_type_name(),
		"has_captain": has_captain(),
		"order_icon_shown": order_icon_shown,
		"order_icon_duration_minutes": order_icon_duration_minutes,
		"order_icon_hidden_reason": String(order_icon_hidden_reason),
		"delivery_completed": delivery_completed,
		"delivery_clearance_started_at": clearance_started_at_minutes,
		"delivery_clearance_completed_at": clearance_completed_at_minutes,
		"delivery_clearance_minutes": get_clearance_duration(),
		"members_required_to_clear": members_required_to_clear,
		"members_cleared": members_cleared,
		"delivery_clearance_recoveries": delivery_clearance_recoveries,
		"delivery_approach_retries": delivery_approach_retries,
		"reform_duration_minutes": get_reform_duration(),
		"activity_count": group_activity_count,
		"slot_recoveries": group_slot_recoveries,
		"all_members_departed": _all_members_departed(),
		"leisure_duration_minutes": leisure_duration_minutes,
		"recall_duration_minutes": get_recall_duration(),
	}


## The leader's customer-type display name, for the report.
func get_leader_type_name() -> String:
	if is_instance_valid(leader):
		var customer_type: Variant = leader.get(&"customer_type")

		if customer_type != null:
			return String(customer_type.get(&"display_name"))

	return _leader_type_name


## Records who is leading, so the report survives cleanup.
func _latch_leader_details() -> void:
	if not is_instance_valid(leader):
		return

	_leader_customer_id = int(leader.get(&"runtime_customer_id"))

	var customer_type: Variant = leader.get(&"customer_type")

	if customer_type == null:
		return

	_leader_type_name = String(customer_type.get(&"display_name"))

	if StringName(customer_type.get(&"customer_category")) == &"captain":
		_leader_is_captain = true


## True when this group is led by a Captain.
##
## Reads the type's own category rather than matching on a display name, so
## renaming the resource cannot silently turn every Captain into a sailor.
func has_captain() -> bool:
	# Latched rather than read live: cleanup clears the member list, and the
	# diagnostics are captured after that, so asking the leader at the end of
	# the visit would report every Captain group as an ordinary one.
	if _leader_is_captain:
		return true

	if not is_instance_valid(leader):
		return false

	var customer_type: Variant = leader.get(&"customer_type")

	if customer_type == null:
		return false

	return StringName(customer_type.get(&"customer_category")) == &"captain"


func _all_members_departed() -> bool:
	for member: Node in members:
		if not is_instance_valid(member):
			continue

		var member_state: int = int(member.get(&"current_state"))

		if member_state not in [
			int(Customer.State.LEAVING_TO_DOOR),
			int(Customer.State.EXITING),
		]:
			return false

	return true


## Total portions taken from this group's keg.
func get_shared_drinks_consumed() -> int:
	var total: int = 0

	for key: Variant in portions_per_member:
		total += int(portions_per_member[key])

	return total


# --- Diagnostics -------------------------------------------------------------

func _log(message: String) -> void:
	_debug_log.append(
		"[%d] %s" % [_world_minutes(), message]
	)

	if _debug_log.size() > 40:
		_debug_log.pop_front()


func get_debug_log() -> Array[String]:
	return _debug_log


func get_summary() -> Dictionary:
	return {
		"group_id": group_id,
		"definition": (
			definition.display_name if definition != null else "-"
		),
		"size": get_size(),
		"valid_members": get_valid_members().size(),
		"leader": String(leader.name) if is_instance_valid(leader) else "-",
		"state": get_state_name(),
		"place_type": (
			"seated" if place != null and place.is_seated()
			else ("standing" if place != null and place.is_standing() else "-")
		),
		"place_id": String(place.get_place_id()) if place != null else "-",
		"order": (
			current_order.get_display_name(beverage_registry)
			if current_order != null else "-"
		),
		"order_status": (
			current_order.get_status_name() if current_order != null else "-"
		),
		"serving_portions": (
			shared_serving.remaining_portions
			if is_instance_valid(shared_serving) else -1
		),
		"serving_maximum": (
			shared_serving.maximum_portions
			if is_instance_valid(shared_serving) else -1
		),
		"patience": get_remaining_patience(),
		"duration": get_visit_duration(),
		"orders_placed": orders_placed,
		"problem": failure_reason,
		"keg_drink": String(keg_drink_id),
		"keg_starting": keg_starting_portions,
		"keg_remaining": keg_remaining_portions,
		"source_station": source_station_name,
		"stock_before": stock_before_measures,
		"stock_after": stock_after_measures,
		"portions": portions_per_member,
		"departure_reason": String(departure_reason),
		"cleanup": cleanup_completed,
	}


func _world_minutes() -> int:
	var world_time: Node = get_node_or_null(^"/root/WorldTime")

	if world_time == null or not world_time.has_method(&"get_timestamp"):
		return 0

	var stamp: Variant = world_time.call(&"get_timestamp")

	return int(stamp.total_minutes) if stamp != null else 0
