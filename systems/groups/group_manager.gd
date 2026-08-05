class_name GroupManager
extends Node

## Runs every active group visit.
##
## Ticks each group's state machine on a world-time signal rather than in
## [method Node._process]: a group visit is measured in tavern minutes, not
## frames, so nothing here needs to run sixty times a second. Members still
## move every frame - that is their own navigation, untouched.
##
## The manager also owns the safety net. Any group that fails, empties, runs
## out of patience or loses every member is resolved and swept, so a stuck
## visit can never hold the tavern's only table forever.


signal group_created(group: CustomerGroup)
signal group_completed(group: CustomerGroup)
signal group_failed(group: CustomerGroup, reason: String)


@export_category("References")

@export var registry: BeverageRegistry
@export var order_service: GroupOrderService
@export var vessel_pool: VesselPool

## Where group nodes and their members are parented.
@export var entities_path: NodePath

## Scene used for each member.
@export var customer_scene: PackedScene


@export_category("Limits")

## Most groups active at once.
@export_range(1, 20, 1)
var maximum_active_groups: int = 3

## Most members across all groups. Counted against the tavern's own cap too.
@export_range(2, 100, 1)
var maximum_group_members: int = 16


@export_category("Timing")

## World minutes a group waits after settling before it orders.
@export_range(0, 60, 1)
var minutes_before_ordering: int = 2

## World minutes between one member's drinks from a shared serving.
@export_range(1, 60, 1)
var minutes_between_drinks: int = 3

## World minutes a group lingers after its drink is finished.
@export_range(0, 120, 1)
var minutes_socialising_after_empty: int = 10

## World minutes after closing before groups are made to leave.
@export_range(0, 240, 1)
var closing_grace_minutes: int = 20

## Times a shared-serving request is retried before the group gives up.
##
## A serving request can fail transiently - the vessel pool is momentarily
## empty because another group has not finished tearing down yet. Sending the
## party home on the first refusal is what produced groups that assembled and
## then left three minutes later without ever drinking.
@export_range(0, 10, 1)
var maximum_serving_attempts: int = 3

## World minutes between shared-serving retries.
@export_range(1, 30, 1)
var minutes_between_serving_attempts: int = 2

## World minutes before a member's first pull from a new keg.
@export_range(0, 30, 1)
var first_drink_delay_minutes: int = 1

## Ticks a group may spend in one state before it is forced onward.
##
## A clock-independent backstop. Patience alone is not enough: it is measured
## in tavern minutes, so a stopped or oddly-scaled clock would let a group sit
## in MOVING_TO_PLACE forever holding a table. This guarantees every state
## ends. Set generously - it should only ever fire on a genuine stall.
@export_range(10, 2000, 10)
var maximum_ticks_per_state: int = 240


@export_category("Stock and delivery")

## Whether a group keg must come out of real storage and be carried over.
##
## Off restores the instant-keg behaviour the basic loop milestone used. On is
## the real flow: reserve, task, collect, carry, place.
@export var use_real_keg_stock: bool = true

## Stock service. Found in the tree when not wired in the inspector.
@export var keg_stock_service: GroupKegStockService

## World minutes a group waits for its keg before giving up on the order.
@export_range(1, 240, 1)
var delivery_patience_minutes: int = 30

## World minutes between attempts to claim a keg when none was free.
@export_range(1, 60, 1)
var minutes_between_stock_attempts: int = 3

## Attempts to claim a keg before the group gives up and leaves.
@export_range(1, 20, 1)
var maximum_stock_attempts: int = 5


@export_category("Leisure")

## Whether the leisure phase runs at all. Off leaves the previous behaviour:
## a fixed wait after the keg empties, then departure.
@export var leisure_enabled: bool = true


@export_category("Ordering")

## The implemented group experience is a shared keg/cask/pitcher order.
## Individual fallback orders were only a placeholder: they paid immediately
## without creating normal customer service tasks. Keep this enabled until a
## proper per-member group ordering bridge is built.
@export var shared_orders_only: bool = true

## Whether a group may order again once its keg is empty.
##
## OFF for the basic group milestone: one group, one keg, one visit. Multiple
## group orders are explicitly out of scope for this pass.
@export var allow_reorders: bool = false

## Whether groups settle in standing areas only.
##
## See [member CustomerGroup.standing_places_only]. Applied to every group this
## manager registers, so the setting lives in one place.
@export var standing_places_only: bool = true

## Whether a group may order a second shared serving after the first empties.
##
## OFF for this milestone. The basic group keg loop is one keg, then leave, so
## reordering is left switched off until the multi-order pass. Turning it on
## restores the existing reorder behaviour without any other change.
@export var allow_reorder: bool = false


@export_category("Debug")

@export var log_state_changes: bool = false


var active_groups: Array[CustomerGroup] = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _entities: Node = null
var _next_group_number: int = 1
var _group_registered_msec: Dictionary = {}
var _group_closing_observed_minutes: Dictionary = {}

## Last world minute processed by the group state machine. The normal driver is
## WorldTime.minute_passed; _process uses this as a recovery path if that signal
## is missed or connected too late. Both paths share this guard, so a minute is
## never applied twice.
var _last_group_tick_minute: int = -1

## Real-time backstop for groups parked outside. This cannot depend on world
## time because the clock may pause or stop at closing.
@export_range(2.0, 60.0, 0.5)
var outside_entry_watchdog_seconds: float = 30.0


func _ready() -> void:
	add_to_group(&"group_manager")

	_rng.randomize()

	if not entities_path.is_empty():
		_entities = get_node_or_null(entities_path)

	if _entities == null:
		_entities = get_parent()

	if registry == null:
		registry = load("res://Data/beverage/beverage_registry.tres")

	_connect_world_clock()


## Subscribes the group tick to the world clock.
##
## WorldTime emits [signal WorldTime.minute_passed]. An earlier name is tried
## as well so an older clock still drives groups, and a missing connection is
## reported rather than silently leaving every group frozen after entry - which
## is exactly what happened before: nothing past MOVING_TO_PLACE ever ran.
func _connect_world_clock() -> void:
	var world_time: Node = get_node_or_null(^"/root/WorldTime")

	if world_time == null:
		push_warning(
			"GroupManager found no WorldTime autoload. Group visits will "
			+ "never advance past entry."
		)
		return

	for signal_name: StringName in [&"minute_passed", &"minute_changed"]:
		if not world_time.has_signal(signal_name):
			continue

		if world_time.is_connected(signal_name, _on_minute_changed):
			return

		world_time.connect(signal_name, _on_minute_changed)

		return

	push_warning(
		"GroupManager could not find a per-minute signal on WorldTime. "
		+ "Group visits will never advance past entry."
	)


# --- Roster ------------------------------------------------------------------

func abort_all_groups(reason: String = "group system reset") -> void:
	for group: CustomerGroup in active_groups.duplicate():
		if group == null or not is_instance_valid(group):
			continue

		if group.is_finished():
			group.cleanup()
			continue

		group.fail_visit(reason)

	_sweep_finished()


func get_active_group_count() -> int:
	return active_groups.size()


func get_active_member_count() -> int:
	var total: int = 0

	for group: CustomerGroup in active_groups:
		total += group.get_valid_members().size()

	return total


func can_spawn_group(size: int) -> bool:
	if active_groups.size() >= maximum_active_groups:
		return false

	return get_active_member_count() + size <= maximum_group_members


## Whether a group currently owns the narrow arrival corridor.
##
## Automatic arrivals use this to fall back to a solo customer instead of
## creating another group queue behind one that is still entering.
func has_group_using_entrance() -> bool:
	for group: CustomerGroup in active_groups:
		if group == null or not is_instance_valid(group) or group.is_finished():
			continue

		if group.state in [
			CustomerGroup.State.SPAWNING,
			CustomerGroup.State.FINDING_PLACE,
			CustomerGroup.State.ENTERING,
		]:
			return true

	return false


func register_group(group: CustomerGroup) -> void:
	if group == null or active_groups.has(group):
		return

	group.standing_places_only = standing_places_only

	active_groups.append(group)
	_group_registered_msec[group] = Time.get_ticks_msec()

	group.state_changed.connect(_on_group_state_changed.bind(group))

	group.log_created()

	group_created.emit(group)

	# Start the visit immediately. Waiting for the next world-minute signal can
	# strand a freshly spawned group outside when time is paused, closing has
	# begun, or the lifecycle freezes the clock between days.
	call_deferred(&"_start_registered_group", group)


func get_group(group_id: StringName) -> CustomerGroup:
	for group: CustomerGroup in active_groups:
		if group.group_id == group_id:
			return group

	return null


func _process(_delta: float) -> void:
	# Group visits must keep advancing even if the minute signal was missed.
	# This was the failure mode where members reached IN_GROUP but never reached
	# WAITING_TO_ORDER, so they eventually left without ordering a keg.
	var current_world_minute: int = _world_minutes()

	if current_world_minute != _last_group_tick_minute:
		_last_group_tick_minute = current_world_minute
		tick()

	# Entry cleanup must use real time, not tavern time. Parked members count
	# toward GameManager.active_customers and otherwise block all later spawns.
	var now: int = Time.get_ticks_msec()

	for group: CustomerGroup in active_groups.duplicate():
		if not is_instance_valid(group) or group.is_finished():
			continue

		if group.state not in [
			CustomerGroup.State.SPAWNING,
			CustomerGroup.State.ENTERING,
			CustomerGroup.State.FINDING_PLACE,
		]:
			continue

		var registered: int = int(_group_registered_msec.get(group, now))
		if float(now - registered) / 1000.0 < outside_entry_watchdog_seconds:
			continue

		group.fail_visit("entry watchdog expired while members were outside")

	_sweep_finished()


func _start_registered_group(group: CustomerGroup) -> void:
	if not is_instance_valid(group) or group.is_finished():
		return

	_tick_group(group)


# --- Tick --------------------------------------------------------------------

func _on_minute_changed(_stamp: Variant = null) -> void:
	var current_world_minute: int = _world_minutes()

	if current_world_minute == _last_group_tick_minute:
		return

	_last_group_tick_minute = current_world_minute
	tick()


## Advances every group by one world minute.
func tick() -> void:
	for group: CustomerGroup in active_groups.duplicate():
		if not is_instance_valid(group):
			active_groups.erase(group)
			continue

		_tick_group(group)

	_sweep_finished()


func _tick_group(group: CustomerGroup) -> void:
	# Anything with nobody left in it goes, whatever state it claims to be in.
	if group.get_valid_members().is_empty() and not group.is_finished():
		# A group whose members have all walked out finished its visit; only
		# one that emptied unexpectedly failed it. Without this split every
		# successful group was recorded as a failure.
		if group.state in [
			CustomerGroup.State.PREPARING_TO_LEAVE,
			CustomerGroup.State.LEAVING,
		]:
			group.complete_visit()
		else:
			group.fail_visit("all members gone")

		return

	group.ticks_in_state += 1

	_update_order_icon(group)

	if _is_stalled(group):
		_break_stall(group)
		return

	match group.state:
		CustomerGroup.State.SPAWNING, CustomerGroup.State.ENTERING:
			_advance_to_place(group)

		CustomerGroup.State.MOVING_TO_PLACE:
			_run_assembly(group)

		CustomerGroup.State.SETTLING:
			_transition(
				group,
				CustomerGroup.State.SETTLING,
				CustomerGroup.State.WAITING_TO_ORDER
			)

		CustomerGroup.State.WAITING_TO_ORDER:
			var wait_minutes: int = (
				minutes_between_serving_attempts
				if group.serving_attempts > 0
				else minutes_before_ordering
			)

			if group.get_state_duration() >= wait_minutes:
				_place_order(group)

		CustomerGroup.State.WAITING_FOR_SERVICE:
			_serve_order(group)

		CustomerGroup.State.CONSUMING:
			_run_consumption(group)

		CustomerGroup.State.SOCIALISING:
			_run_leisure(group)

		CustomerGroup.State.CONSIDERING_REORDER:
			_consider_reorder(group)

		CustomerGroup.State.WAITING_FOR_STOCK:
			_run_stock_wait(group)

		CustomerGroup.State.WAITING_FOR_DELIVERY:
			_run_delivery_wait(group)

		CustomerGroup.State.RECALLING:
			_run_recall(group)

		CustomerGroup.State.CLEARING_DELIVERY_SPACE:
			_run_delivery_clearance(group)

		CustomerGroup.State.DELIVERY_IN_PROGRESS:
			_run_delivery_in_progress(group)

		CustomerGroup.State.REFORMING:
			_run_reform(group)

		CustomerGroup.State.LEAVING:
			_check_departure_complete(group)

	if _should_force_closing_departure(group):
		group.begin_departure("tavern closed")


## True when a group has sat in one state longer than it ever should.
func _is_stalled(group: CustomerGroup) -> bool:
	if group.is_finished():
		return false

	# Waiting states are allowed to wait; only states that should progress on
	# their own are policed.
	match group.state:
		CustomerGroup.State.COMPLETE, CustomerGroup.State.FAILED:
			return false

	return group.ticks_in_state > maximum_ticks_per_state


## Moves a stalled group onward rather than leaving it stuck.
##
## Leaving is always available and always safe: it releases the place, resolves
## the serving and ends the visit. A group that has stalled has already had its
## chance, so it goes rather than holding a table nobody else can use.
func _break_stall(group: CustomerGroup) -> void:
	if group.state == CustomerGroup.State.LEAVING:
		group.complete_visit()
		return

	group.failure_reason = "stalled in %s" % group.get_state_label()

	group.begin_departure(group.failure_reason)


func _advance_to_place(group: CustomerGroup) -> void:
	if group.place != null and group.place.is_valid():
		group.begin_entry_sequence()
		return

	if group.find_place():
		group.begin_entry_sequence()
		return

	# Nowhere to go. A group that cannot be seated or stood is turned away
	# rather than left milling about the door indefinitely.
	group.fail_visit("no table or standing area available")


## Moves a group from one exact state to another, once.
##
## Every group transition goes through here rather than through a scattered
## set_state() call, so a second callback arriving in the same minute - the
## minute signal and the _process recovery path both exist - cannot run the
## same step twice.
func _transition(
	group: CustomerGroup,
	expected: CustomerGroup.State,
	next: CustomerGroup.State
) -> bool:
	if group.state != expected:
		return false

	group.set_state(next)

	return true


## Assembles a group, recovering any member that cannot reach its slot.
##
## The group progresses exactly once, through mark_assembled(), however many
## times this is reached in the same minute.
func _run_assembly(group: CustomerGroup) -> void:
	var assembled: bool = group.update_assembly()

	if not assembled:
		if not group.has_run_out_of_patience():
			return

		# Patience is the last line, and by now every member has had its
		# retries and its placement. Anybody still not in position is left
		# behind rather than holding the place - but the group still goes on
		# to order, so a single wedged member no longer wastes the visit.
		push_warning(
			"[Group %s] assembling on patience with %d members not in position."
			% [String(group.group_id), group.get_valid_members().size()]
		)

	if not group.mark_assembled():
		return

	_transition(
		group,
		CustomerGroup.State.MOVING_TO_PLACE,
		CustomerGroup.State.SETTLING
	)


func _place_order(group: CustomerGroup) -> void:
	if order_service == null:
		group.fail_visit("no order service")
		return

	if not _transition(
		group,
		CustomerGroup.State.WAITING_TO_ORDER,
		CustomerGroup.State.ORDERING
	):
		return

	var definition: CustomerGroupDefinition = group.definition
	var wants_shared: bool = (
		shared_orders_only
		or definition == null
		or definition.wants_shared_order(_rng)
	)

	var order: GroupOrder = null

	if wants_shared:
		order = order_service.choose_shared_order(group)

	if order == null and not shared_orders_only:
		order = order_service.choose_individual_order(
			group, group.leader
		)

	if order == null:
		# Record WHY rather than "nothing available". Insufficient stock, no
		# capable station and no shared format at all are three different
		# faults and were previously indistinguishable.
		_handle_serving_setback(
			group, order_service.explain_shared_failure(group), null
		)
		return

	group.record_order_source(
		order_service.find_source_station_for_order(order)
	)

	if not order_service.reserve_order(order):
		_handle_serving_setback(
			group, order_service.describe_order_failure(order), order
		)
		return

	group.current_order = order
	group.orders_placed += 1

	group.set_state(CustomerGroup.State.WAITING_FOR_SERVICE)

	group.order_placed.emit(order)


## Handles one failed shared-serving attempt.
##
## Retries a small number of times before giving up, because the usual cause
## is transient: the vessel this group needs is still held by a group that has
## only just finished. Whatever is being held by the failed attempt is handed
## back first, so a retry is not competing with its own leftovers.
func _handle_serving_setback(
	group: CustomerGroup,
	reason: StringName,
	order: GroupOrder
) -> void:
	group.serving_attempts += 1

	if order != null and order_service != null:
		# Without this the vessel reserved by reserve_order() was never
		# returned on any failure path, so every failed group permanently
		# removed one shared vessel from circulation.
		order_service.cancel_order(order)

	group.current_order = null

	push_warning(
		"[Group %s] shared-serving attempt %d of %d failed (%s)."
		% [
			String(group.group_id), group.serving_attempts,
			maximum_serving_attempts, String(reason),
		]
	)

	if group.serving_attempts >= maximum_serving_attempts:
		group.record_order_failure(reason)
		group.begin_departure()
		return

	# Back to waiting. The state clock restarts here, so
	# minutes_between_serving_attempts is what paces the next try.
	group.set_state(CustomerGroup.State.WAITING_TO_ORDER)


func _serve_order(group: CustomerGroup) -> void:
	var order: GroupOrder = group.current_order

	if order == null or order.has_failed():
		group.begin_departure()
		return

	if not order.is_shared:
		# The individual fallback used to pay here and move straight to
		# socialising, so the group was charged for a drink that was never
		# made and the reserved vessel was never handed back. Until a real
		# per-member group ordering bridge exists, that path is refused.
		order_service.cancel_order(order)
		group.record_order_failure(&"individual_orders_unsupported")
		group.begin_departure()
		return

	group.record_stock_before(order_service.get_stock_for_order(order))

	if use_real_keg_stock:
		# The keg is a real object on a real shelf, and somebody has to carry
		# it. Everything past here is the instant-keg development path.
		_begin_stock_reservation(group)

		return

	group.bypassed_stock = true

	print(
		"[Group %s] creating keg without real stock (use_real_keg_stock off)."
		% String(group.group_id)
	)

	# Only a genuinely dead reference is cleared here. A valid serving owned
	# by this group is reused; a serving owned by another active group is
	# never touched.
	if group.shared_serving != null and not is_instance_valid(group.shared_serving):
		group.shared_serving = null

	var serving: SharedServing = order_service.fulfil_order(order, group)

	if serving == null:
		_handle_serving_setback(
			group, order_service.describe_order_failure(order), order
		)
		return

	group.serving_attempts += 1

	group.record_keg_created(
		serving, order_service.get_stock_for_order(order)
	)

	# Payment happens only once a real keg exists in the world.
	_pay_for_order(group, order)

	# The first pull is delayed from here rather than from arrival, so a
	# group does not appear to drink from a keg the instant it lands.
	_set_first_drink_delay(group)

	_transition(
		group,
		CustomerGroup.State.WAITING_FOR_SERVICE,
		CustomerGroup.State.CONSUMING
	)


# --- Real stock and staff delivery -------------------------------------------
#
# A keg is a stock item, a claim on it is a promise, and carrying it is a
# staff task. None of those three is invented here: the item is an
# ItemDefinition, the claim lives in GroupKegStockService, and the carry is an
# ordinary TavernTask executed by DeliverGroupKegExecutor.

func get_keg_stock_service() -> GroupKegStockService:
	if keg_stock_service != null and is_instance_valid(keg_stock_service):
		return keg_stock_service

	var found: Array[Node] = get_tree().get_nodes_in_group(
		&"group_keg_stock_service"
	)

	if not found.is_empty():
		keg_stock_service = found[0] as GroupKegStockService

	return keg_stock_service


## Moves a group into WAITING_FOR_STOCK and tries to claim a keg at once.
func _begin_stock_reservation(group: CustomerGroup) -> void:
	_transition(
		group,
		CustomerGroup.State.WAITING_FOR_SERVICE,
		CustomerGroup.State.WAITING_FOR_STOCK
	)

	group.delivery_status = &"awaiting_stock"

	_run_stock_wait(group)


func _run_stock_wait(group: CustomerGroup) -> void:
	var service: GroupKegStockService = get_keg_stock_service()

	if service == null:
		_fail_group_order(group, &"no_keg_stock_service")
		return

	var keg_item: ItemDefinition = service.get_keg_item()

	if keg_item == null:
		_fail_group_order(group, &"no_keg_item_defined")
		return

	group.keg_item_id = keg_item.item_id

	# Already holding a claim - just wait for the task to run.
	if not group.stock_reservation_id.is_empty():
		return

	if group.serving_attempts >= maximum_stock_attempts:
		_fail_group_order(group, &"group_keg_out_of_stock")
		return

	if group.get_state_duration() >= delivery_patience_minutes:
		_fail_group_order(group, &"group_keg_out_of_stock")
		return

	var reservation: Dictionary = service.reserve_keg(group)

	if reservation.is_empty():
		group.serving_attempts += 1

		if group.serving_attempts >= maximum_stock_attempts:
			_fail_group_order(group, &"group_keg_out_of_stock")

		return

	group.stock_reservation_id = StringName(
		String(reservation.get("reservation_id", ""))
	)

	if not _create_delivery_task(group, keg_item):
		# Nothing can carry it. Hand the claim straight back rather than
		# sitting on a keg nobody will ever fetch.
		service.release_reservation(group.stock_reservation_id)
		group.stock_reservation_id = &""
		group.serving_attempts += 1

		return

	group.delivery_status = &"awaiting_delivery"

	_transition(
		group,
		CustomerGroup.State.WAITING_FOR_STOCK,
		CustomerGroup.State.WAITING_FOR_DELIVERY
	)


func _create_delivery_task(
	group: CustomerGroup,
	keg_item: ItemDefinition
) -> bool:
	var board: Node = get_node_or_null(^"/root/TaskBoard")

	if board == null or not board.has_method(&"create_task"):
		return false

	var service: GroupKegStockService = get_keg_stock_service()
	var storage: Node = (
		service.get_reservation_storage(group.stock_reservation_id)
		if service != null else null
	)

	var task: Variant = board.call(
		&"create_task",
		TavernTaskTypes.DELIVER_GROUP_KEG,
		"group_keg:%s" % String(group.group_id),
		{
			"source": storage,
			"required_item": keg_item,
			"required_quantity": 1,
			"urgency": 0.8,
			"metadata": {
				"group_id": String(group.group_id),
				"reservation_id": String(group.stock_reservation_id),
				"serving_format_id": String(
					group.current_order.serving_format_id
					if group.current_order != null else &""
				),
			},
		}
	)

	if task == null:
		return false

	group.delivery_task_id = StringName(String(task.get(&"task_id")))

	print(
		"[Group %s] delivery task %s created for 1 x %s."
		% [
			String(group.group_id),
			String(group.delivery_task_id),
			String(keg_item.item_id),
		]
	)

	return true


func _run_delivery_wait(group: CustomerGroup) -> void:
	var board: Node = get_node_or_null(^"/root/TaskBoard")
	var service: GroupKegStockService = get_keg_stock_service()

	# The claim can go stale under us - a player emptying the crate by hand is
	# the obvious way. Notice it here rather than when the worker arrives.
	if service != null and not group.keg_collected:
		if not service.is_reservation_valid(group.stock_reservation_id):
			service.release_reservation(group.stock_reservation_id)
			group.stock_reservation_id = &""

			if not group.delivery_task_id.is_empty() and board != null:
				var stale: Variant = board.call(&"get_task", group.delivery_task_id)

				if stale != null and not bool(stale.call(&"is_terminal")):
					board.call(&"cancel", stale, &"group_keg_reservation_lost")

			group.delivery_task_id = &""
			group.delivery_status = &"awaiting_stock"

			_transition(
				group,
				CustomerGroup.State.WAITING_FOR_DELIVERY,
				CustomerGroup.State.WAITING_FOR_STOCK
			)

			return

	if board != null and not group.delivery_task_id.is_empty():
		var task: Variant = board.call(&"get_task", group.delivery_task_id)

		if task == null or bool(task.call(&"is_terminal")):
			# The board gave up on it. Go back and try to claim again, which
			# is bounded by maximum_stock_attempts.
			group.delivery_task_id = &""
			group.serving_attempts += 1

			if service != null and not group.stock_reservation_id.is_empty():
				service.release_reservation(group.stock_reservation_id)
				group.stock_reservation_id = &""

			group.delivery_status = &"awaiting_stock"

			_transition(
				group,
				CustomerGroup.State.WAITING_FOR_DELIVERY,
				CustomerGroup.State.WAITING_FOR_STOCK
			)

			return

	if group.get_state_duration() >= delivery_patience_minutes:
		_fail_group_order(group, &"group_keg_delivery_timed_out")


# --- Delivery phases ---------------------------------------------------------

func _run_delivery_clearance(group: CustomerGroup) -> void:
	if group.update_delivery_clearance():
		group.mark_clearance_complete()

		_transition(
			group,
			CustomerGroup.State.CLEARING_DELIVERY_SPACE,
			CustomerGroup.State.DELIVERY_IN_PROGRESS
		)

		return

	if group.get_state_duration() >= delivery_patience_minutes:
		_fail_group_order(group, &"group_keg_delivery_timed_out")


## Waiting for the worker to walk in and set the keg down.
##
## The clearance is already done by this point, so all this does is watch for
## the delivery going away underneath the group.
func _run_delivery_in_progress(group: CustomerGroup) -> void:
	if group.delivery_completed:
		return

	var board: Node = get_node_or_null(^"/root/TaskBoard")

	if board != null and not group.delivery_task_id.is_empty():
		var task: Variant = board.call(&"get_task", group.delivery_task_id)

		if task == null or bool(task.call(&"is_terminal")):
			# The carry failed. Close the ring back up and try again from the
			# stock wait rather than leaving the group stood open.
			group.begin_reform()
			group.clear_delivery_positions()

			group.delivery_task_id = &""
			group.serving_attempts += 1
			group.delivery_status = &"awaiting_stock"

			var service: GroupKegStockService = get_keg_stock_service()

			if service != null and not group.stock_reservation_id.is_empty():
				service.release_reservation(group.stock_reservation_id)
				group.stock_reservation_id = &""

			group.reset_delivery_phase()

			_transition(
				group,
				CustomerGroup.State.DELIVERY_IN_PROGRESS,
				CustomerGroup.State.WAITING_FOR_STOCK
			)

			return

	if group.get_state_duration() >= delivery_patience_minutes:
		_fail_group_order(group, &"group_keg_delivery_timed_out")


func _run_reform(group: CustomerGroup) -> void:
	if not group.is_reform_complete():
		return

	group.mark_reform_complete()

	_begin_drinking(group)


## Starts shared drinking exactly once.
func _begin_drinking(group: CustomerGroup) -> void:
	if not group.mark_drinking_started():
		return

	group.clear_delivery_positions()

	print("[Group %s] drinking started." % String(group.group_id))

	group.set_state(CustomerGroup.State.CONSUMING)


## Keeps the order icon above the right member, in the right states.
func _update_order_icon(group: CustomerGroup) -> void:
	if group.wants_order_icon():
		group.show_order_icon()
	elif group.order_icon_shown:
		group.hide_order_icon(
			&"order_failed" if not group.order_failure_reason.is_empty()
			else &"no_longer_ordering"
		)


## The worker has the keg in its hands. Recorded, but not yet delivered.
func notify_group_keg_collected(task: Variant) -> void:
	var group: CustomerGroup = _group_for_task(task)

	if group == null:
		return

	group.keg_collected = true
	group.delivery_status = &"collected"

	# The worker has the keg and is now walking in. This is the moment to open
	# the ring - any earlier and the group stands spread out for no reason.
	if group.state == CustomerGroup.State.WAITING_FOR_DELIVERY:
		if group.begin_delivery_clearance():
			_transition(
				group,
				CustomerGroup.State.WAITING_FOR_DELIVERY,
				CustomerGroup.State.CLEARING_DELIVERY_SPACE
			)

	var service: GroupKegStockService = get_keg_stock_service()

	if service != null:
		service.mark_collected(group.stock_reservation_id)

	print(
		"[Group %s] keg collected by staff." % String(group.group_id)
	)


## The staff task ended without delivering. Put the claim back.
func notify_group_keg_delivery_aborted(
	task: Variant,
	reason: StringName
) -> void:
	var group: CustomerGroup = _group_for_task(task)

	if group == null:
		return

	if group.delivery_status == &"delivered":
		return

	group.delivery_status = &"failed"
	group.delivery_task_id = &""

	push_warning(
		"[Group %s] keg delivery aborted (%s)."
		% [String(group.group_id), String(reason)]
	)

	# Only an uncollected keg is still on the shelf. One already in a
	# worker's hands is handled by the existing carried-item recovery policy.
	if not group.keg_collected:
		var service: GroupKegStockService = get_keg_stock_service()

		if service != null:
			service.release_reservation(group.stock_reservation_id)

		group.stock_reservation_id = &""


## Places the delivered keg and starts the group drinking. Called by staff.
##
## Reuses [method GroupOrderService.fulfil_order] rather than building a
## SharedServing here, so there is exactly one place a shared serving is ever
## created however it got to the table.
func complete_group_keg_delivery(task: Variant, _worker: Node) -> bool:
	var group: CustomerGroup = _group_for_task(task)

	if group == null:
		return false

	if not group.is_awaiting_keg_delivery():
		return false

	var order: GroupOrder = group.current_order

	if order == null or order.has_failed():
		return false

	if group.shared_serving != null and not is_instance_valid(group.shared_serving):
		group.shared_serving = null

	var serving: SharedServing = order_service.fulfil_order(order, group)

	if serving == null:
		return false

	group.serving_attempts += 1
	group.delivery_status = &"delivered"
	group.delivery_task_id = &""

	group.record_keg_created(
		serving, order_service.get_stock_for_order(order)
	)

	print(
		"[Group %s] keg delivered and placed." % String(group.group_id)
	)

	group.delivery_completed = true

	group.hide_order_icon(&"keg_delivered")

	# Payment happens here and nowhere else: after a real keg exists, once.
	_take_group_payment(group, order)

	_set_first_drink_delay(group)

	# Members close the ring again before anybody drinks. Drinking from a keg
	# while still standing in the delivery formation would undo the point of
	# the formation existing.
	if group.begin_reform():
		group.set_state(CustomerGroup.State.REFORMING)
	else:
		_begin_drinking(group)

	return true


func _group_for_task(task: Variant) -> CustomerGroup:
	if task == null:
		return null

	var metadata: Dictionary = task.get(&"metadata") as Dictionary

	if metadata == null:
		return null

	return get_group(StringName(String(metadata.get("group_id", ""))))


## Ends an order that cannot be filled, without charging anybody.
func _fail_group_order(group: CustomerGroup, reason: StringName) -> void:
	var service: GroupKegStockService = get_keg_stock_service()

	if service != null and not group.stock_reservation_id.is_empty():
		service.release_reservation(group.stock_reservation_id)

	group.stock_reservation_id = &""
	group.delivery_status = &"failed"

	if order_service != null and group.current_order != null:
		order_service.cancel_order(group.current_order)

	group.record_order_failure(reason)
	group.hide_order_icon(&"order_failed")
	group.clear_delivery_positions()

	push_warning(
		"[Group %s] order failed: %s." % [String(group.group_id), String(reason)]
	)

	group.begin_departure(String(reason))


## Staggers when each member may first reach for a brand new keg.
func _set_first_drink_delay(group: CustomerGroup) -> void:
	var earliest: int = _world_minutes() + first_drink_delay_minutes

	for member: Node in group.get_valid_members():
		var raw: Variant = member.get(&"next_group_drink_minutes")

		if raw == null:
			continue

		var current: int = int(raw)

		if current < earliest:
			member.set(&"next_group_drink_minutes", earliest)


## Takes payment once for the whole order.
##
## The guard is inside [method GroupOrder.mark_paid], so however many members
## the group has, and however many times this is reached, the tavern is paid
## exactly once for one order.
func _pay_for_order(group: CustomerGroup, order: GroupOrder) -> void:
	_take_group_payment(group, order)


## The group leader settles the whole bill, once.
##
## Not "everybody chips in": the report used to imply every member paid, which
## was never true of anything the code did. One member's money moves, the
## tavern's money moves by the same amount, and the record names who paid.
##
## The guard is [method GroupOrder.mark_paid], so however many callbacks reach
## this - a retried delivery is the obvious one - the tavern is paid exactly
## once for one keg.
func _take_group_payment(group: CustomerGroup, order: GroupOrder) -> bool:
	if order == null:
		return false

	if not order.mark_paid():
		return false

	var amount: int = order.price

	if group.definition != null:
		amount = int(round(
			float(amount) * group.definition.spending_modifier
		))

	var payer: Node = _choose_paying_member(group, amount)

	if payer == null:
		# Nobody in the party can cover it. The keg is already on the table by
		# the time this can happen, so the visit continues and the shortfall
		# is recorded rather than silently written off as free ale.
		push_warning(
			"[Group %s] no member could afford %d for the keg."
			% [String(group.group_id), amount]
		)

		group.record_order_failure(&"group_cannot_afford_keg")

		return false

	var needs: Variant = payer.get(&"needs")

	if needs != null:
		needs.call(&"adjust", &"wealth", -float(amount))

	group.record_group_payment(payer, amount)
	group.record_payment(0)

	_record_payment_diagnostics(group, payer, order, amount)

	_credit_economy(amount)

	return true


## Whether the leader can pay, falling back to another member who can.
##
## Combining funds properly needs a shared purse the framework does not have,
## so this does the honest simple thing: the leader pays if it can, otherwise
## the richest member who can does, and the leadership does not change.
func _choose_paying_member(group: CustomerGroup, amount: int) -> Node:
	var leader: Node = group.leader

	if _can_member_afford(leader, amount):
		return leader

	var best: Node = null
	var best_wealth: float = -1.0

	for member: Node in group.get_valid_members():
		if not _can_member_afford(member, amount):
			continue

		var wealth: float = _get_member_wealth(member)

		if wealth > best_wealth:
			best_wealth = wealth
			best = member

	return best


func _can_member_afford(member: Node, amount: int) -> bool:
	if member == null or not is_instance_valid(member):
		return false

	return _get_member_wealth(member) >= float(amount)


func _get_member_wealth(member: Node) -> float:
	if member == null or not is_instance_valid(member):
		return 0.0

	var needs: Variant = member.get(&"needs")

	if needs == null:
		return 0.0

	return float(needs.get(&"wealth"))


func _record_payment_diagnostics(
	group: CustomerGroup,
	payer: Node,
	order: GroupOrder,
	amount: int
) -> void:
	var report: Variant = payer.get(&"_report_manager")

	if report == null:
		return

	var payer_id: int = int(payer.get(&"runtime_customer_id"))

	if report.has_method(&"record_payment"):
		report.call(&"record_payment", payer_id)

	if report.has_method(&"record_group_payment"):
		report.call(
			&"record_group_payment",
			payer_id,
			String(group.group_id),
			String(order.drink_id),
			String(order.serving_format_id),
			amount
		)


func _credit_economy(amount: int) -> void:
	for node: Node in get_tree().get_nodes_in_group(&"economy"):
		if node.has_method(&"add_money"):
			node.call(&"add_money", amount, &"group_order")
			return

	var economy: Node = get_node_or_null(^"/root/EconomyManager")

	if economy != null and economy.has_method(&"add_money"):
		economy.call(&"add_money", amount, &"group_order")


## Lets members take turns at the shared serving.
##
## Each member has its own next-drink minute, jittered, so the group never
## drinks in unison. One portion leaves per member per turn, and the serving
## itself refuses anything beyond empty - so the last portion cannot be taken
## twice however many members reach for it on the same tick.
func _run_consumption(group: CustomerGroup) -> void:
	var serving: SharedServing = group.shared_serving

	if serving == null or not is_instance_valid(serving):
		# The serving node was deleted from outside - a scene reset, a debug
		# tool. Drop the dead reference and move on rather than ticking
		# against it forever.
		push_warning(
			"[Group %s] shared serving disappeared; moving to the post-drink "
			% String(group.group_id)
			+ "phase."
		)

		group.shared_serving = null

		_begin_post_drink(group)

		return

	if serving.is_spoiled():
		_begin_post_drink(group)
		return

	# Only one portion may be taken per group tick. Previously every member who
	# was ready drank during the same minute, so a four- or five-person group
	# emptied an eight-portion keg almost instantly. The rotating cursor keeps
	# turns fair while preserving each customer's own staggered cooldown.
	var members: Array[Node] = group.get_valid_members()
	var eligible_drinkers: int = 0

	if not members.is_empty() and not serving.is_empty():
		var attempts: int = members.size()

		for offset: int in range(attempts):
			var index: int = (group.next_drinker_index + offset) % members.size()
			var member: Node = members[index]

			if not member.has_method(&"is_ready_for_group_drink"):
				continue

			# Somebody who has not reached their limit still counts as an
			# eligible drinker even when their cooldown has not elapsed -
			# otherwise the group would give up on a keg mid-round.
			if not _is_eligible_drinker(member):
				continue

			eligible_drinkers += 1

			if not bool(member.call(&"is_ready_for_group_drink")):
				continue

			if serving.take_portion(member):
				member.call(
					&"on_group_drink_taken",
					minutes_between_drinks,
					_get_serving_drink(serving)
				)
				group.record_member_drink(member, serving.remaining_portions)
				group.next_drinker_index = (index + 1) % members.size()
				break

	if serving.is_empty():
		_begin_post_drink(group)
		return

	# Nobody left who could ever drink from it. Move on rather than sitting
	# in CONSUMING until the stall backstop fires.
	if eligible_drinkers <= 0:
		push_warning(
			"[Group %s] no eligible drinkers remain with %d portions left."
			% [String(group.group_id), serving.remaining_portions]
		)

		_begin_post_drink(group)


## Whether this member could still take a portion at some point.
func _is_eligible_drinker(member: Node) -> bool:
	var raw_state: Variant = member.get(&"current_state")

	if raw_state == null or int(raw_state) != int(Customer.State.IN_GROUP):
		return false

	if not member.has_method(&"get_effective_drink_limit"):
		return true

	return (
		int(member.get(&"drinks_consumed_this_visit"))
		< int(member.call(&"get_effective_drink_limit"))
	)


## The drink definition a serving holds, for intoxication.
func _get_serving_drink(serving: SharedServing) -> DrinkDefinition:
	if registry == null:
		return null

	return registry.get_drink(serving.drink_id)


## Moves the group into its post-keg wait, exactly once.
func _begin_post_drink(group: CustomerGroup) -> void:
	if not group.mark_post_drink_started():
		return

	if group.current_order != null:
		group.completed_orders.append(group.current_order)

	if leisure_enabled and group.leisure_enabled:
		group.begin_leisure()

		return

	group.set_state(CustomerGroup.State.SOCIALISING)


# --- Leisure -----------------------------------------------------------------
#
# One decision per group per interval, and every activity a member starts is
# started through the member's own methods. There is no group darts, no group
# socialising and no group relaxing - only the group deciding that now is a
# good moment for one of them.

func _run_leisure(group: CustomerGroup) -> void:
	if not leisure_enabled or not group.leisure_enabled:
		_consider_reorder(group)
		return

	if group.leisure_duration_minutes <= 0:
		group.begin_leisure()

	# The reason is deliberately NOT stamped here. Recall is part of leaving,
	# and the brief asks that a group which went through leisure still departs
	# as group_departure - record_departure_reason() only takes the first
	# value, so stamping "keg_finished" now would win over it forever.
	if group.has_run_out_of_patience() or group.is_leisure_finished():
		_begin_recall(group)
		return

	if not group.is_leisure_decision_due():
		return

	group.note_leisure_decision_made()

	_offer_leisure_activity(group)


## Gives at most one idle member something to do.
func _offer_leisure_activity(group: CustomerGroup) -> void:
	if not group.allow_activities_while_drinking:
		if is_instance_valid(group.shared_serving):
			if not group.shared_serving.is_empty():
				return

	if group.get_away_members().size() >= group.get_maximum_away():
		return

	if _rng.randf() > group.leisure_activity_chance:
		return

	var idle: Array[Node] = group.get_idle_members()

	if idle.is_empty():
		return

	var member: Node = idle[_rng.randi_range(0, idle.size() - 1)]
	var last: StringName = StringName(String(member.get(&"last_group_activity_id")))

	# Tried in an order that varies each time, so a group does not always
	# fall back to the same pastime just because it is listed first.
	var options: Array[StringName] = group.leisure_activities.duplicate()

	options.shuffle()

	for option: StringName in options:
		# No immediate repeats: doing the same thing twice running reads as
		# a stuck member rather than a choice.
		if option == last and options.size() > 1:
			continue

		if _start_leisure_activity(group, member, option):
			return

	# Nothing available. Standing with the group is a perfectly good answer.


func _start_leisure_activity(
	group: CustomerGroup,
	member: Node,
	option: StringName
) -> bool:
	match option:
		&"darts":
			return _start_leisure_activity_point(group, member, &"darts")

		&"socialise":
			return _start_leisure_socialise(group, member)

		&"relax":
			if not member.has_method(&"begin_group_relax"):
				return false

			member.call(
				&"begin_group_relax",
				group.leisure_relax_minimum_minutes,
				group.leisure_relax_maximum_minutes
			)

			_log_leisure(group, member, &"relax")

			return true

	return false


## Books a real activity point through the ordinary reservation path.
##
## Goes through [DestinationBroker] - the same broker [CustomerBrain] uses -
## so a group member and a solo customer compete for the darts board on equal
## terms and neither can book one the other already holds.
func _start_leisure_activity_point(
	group: CustomerGroup,
	member: Node,
	activity_id: StringName
) -> bool:
	if not member.has_method(&"begin_group_activity"):
		return false

	var member_2d: Node2D = member as Node2D

	if member_2d == null:
		return false

	if not DestinationBroker.has_available(activity_id, get_tree()):
		return false

	var best: TavernActivityPoint = null
	var best_distance: float = INF

	for reservable: Reservable in DestinationBroker.get_candidates(
		activity_id, get_tree()
	):
		if not reservable.is_free():
			continue

		var point: TavernActivityPoint = (
			reservable.get_parent() as TavernActivityPoint
		)

		if point == null or not point.enabled:
			continue

		var distance: float = member_2d.global_position.distance_to(
			point.get_use_position()
		)

		if distance < best_distance:
			best_distance = distance
			best = point

	if best == null:
		return false

	# The member makes the booking itself, so it is the holder and therefore
	# the only thing that can release it.
	if not bool(member.call(&"begin_group_activity", best)):
		return false

	_log_leisure(group, member, activity_id)

	return true


## Pairs two members of the same group for a conversation.
func _start_leisure_socialise(
	group: CustomerGroup,
	member: Node
) -> bool:
	if not member.has_method(&"begin_group_socialise"):
		return false

	var partner: Node = null

	for candidate: Node in group.get_idle_members():
		if candidate == member:
			continue

		# Never a member who is leaving or busy: get_idle_members() already
		# means "standing at its slot with nothing to do".
		partner = candidate

		break

	if partner == null:
		return false

	member.call(
		&"begin_group_socialise",
		partner,
		group.leisure_socialise_minimum_minutes,
		group.leisure_socialise_maximum_minutes,
		group.leisure_socialise_satisfaction_gain,
		group.leisure_socialise_partner_gain,
		group.leisure_socialise_engagement_gain
	)

	_log_leisure(group, member, &"socialise")

	return true


func _log_leisure(
	group: CustomerGroup,
	member: Node,
	activity_id: StringName
) -> void:
	print(
		"[Group %s] member %s selected activity '%s'."
		% [String(group.group_id), member.name, String(activity_id)]
	)


# --- Recall ------------------------------------------------------------------

func _begin_recall(group: CustomerGroup) -> void:
	if group.get_away_members().is_empty():
		# Nobody to wait for. Straight to the existing departure path, which
		# keeps group_departure as the reason exactly as before.
		_consider_reorder(group)
		return

	group.begin_recall()


func _run_recall(group: CustomerGroup) -> void:
	if group.is_recall_complete():
		group.release_member_activity_reservations()
		group.record_departure_reason(&"group_departure")
		group.begin_departure()

		return

	if group.get_recall_duration() < group.recall_timeout_minutes:
		return

	# One member wedged at an activity must not hold the party. Release what
	# it holds and go; the member itself is still sent to the door by the
	# ordinary departure dispatch, never abandoned.
	var released: int = group.release_member_activity_reservations()

	push_warning(
		"[Group %s] recall timed out after %d minutes; %d activity "
		% [
			String(group.group_id),
			group.recall_timeout_minutes,
			released,
		]
		+ "reservation(s) released and departure started anyway."
	)

	for member: Node in group.get_valid_members():
		if member.has_method(&"cancel_group_activity"):
			member.call(&"cancel_group_activity")

	group.record_departure_reason(&"group_departure")
	group.begin_departure()


func _consider_reorder(group: CustomerGroup) -> void:
	# This must measure time since the keg emptied, not the whole visit. Using
	# get_visit_duration() made the social period already expired as soon as
	# the group entered this state, so the keg vanished and everybody left.
	# post_drink_started_at_minutes is stamped once, when the keg ran out, and
	# survives any further state change.
	var since_change: int = (
		group.get_post_drink_duration()
		if group.post_drink_started_at_minutes >= 0
		else group.get_state_duration()
	)

	if since_change < minutes_socialising_after_empty:
		return

	var definition: CustomerGroupDefinition = group.definition

	if definition == null:
		group.record_departure_reason(&"keg_finished")
		group.begin_departure()
		return

	if group.has_run_out_of_patience():
		group.record_departure_reason(&"out_of_patience")
		group.begin_departure()
		return

	if not allow_reorder:
		group.record_departure_reason(&"keg_finished")
		group.begin_departure()
		return

	if not definition.wants_to_reorder(group.orders_placed, _rng):
		group.begin_departure()
		return

	# Bounded by maximum_orders_per_visit inside wants_to_reorder, so this can
	# never loop forever.
	group.shared_serving = null
	group.current_order = null

	group.set_state(CustomerGroup.State.WAITING_TO_ORDER)


func _check_departure_complete(group: CustomerGroup) -> void:
	var remaining: Array[Node] = group.get_valid_members()

	if remaining.is_empty():
		group.complete_visit()
		return

	# Nobody may still be standing in the group while it is departing. The
	# staggered queue normally handles this within a second or two; this is
	# what makes it true even if the queue was interrupted.
	var dispatched: int = group.dispatch_all_departures()

	if dispatched > 0:
		push_warning(
			"[Group %s] %d member(s) were still in the group after departure "
			% [String(group.group_id), dispatched]
			+ "began and have been sent to the door."
		)

	# A member wedged behind furniture must not hold the table. Once patience
	# is gone the visit completes and the reservations go back regardless -
	# but the members have already been commanded to leave above, so they
	# still walk out under their own navigation rather than being stranded.
	if group.has_run_out_of_patience():
		group.complete_visit()


func _should_force_closing_departure(group: CustomerGroup) -> bool:
	if group.is_finished() or group.state == CustomerGroup.State.LEAVING:
		return false

	var tavern: Node = get_node_or_null(^"/root/Tavern")

	if tavern == null:
		return false

	# Only a tavern that is actually shutting down moves a group on.
	#
	# This used to ask is_accepting_arrivals(), which is ALSO false during the
	# preparation hour before opening - so a group that arrived before the
	# doors opened was thrown out the moment it had existed for the grace
	# period, before it ever got as far as ordering.
	var winding_down: bool = false

	if tavern.has_method(&"is_winding_down"):
		winding_down = bool(tavern.call(&"is_winding_down"))
	elif tavern.has_method(&"is_accepting_arrivals"):
		winding_down = not bool(tavern.call(&"is_accepting_arrivals"))

	if not winding_down:
		_group_closing_observed_minutes.erase(group)
		return false

	# The grace window runs from when the tavern started closing, not from
	# when this group arrived.
	if not _group_closing_observed_minutes.has(group):
		_group_closing_observed_minutes[group] = _world_minutes()
		return false

	var since: int = _world_minutes() - int(
		_group_closing_observed_minutes[group]
	)

	if since < closing_grace_minutes:
		return false

	group.record_departure_reason(&"tavern_closing")

	return true


func _world_minutes() -> int:
	var world_time: Node = get_node_or_null(^"/root/WorldTime")

	if world_time == null or not world_time.has_method(&"get_timestamp"):
		return 0

	var stamp: Variant = world_time.call(&"get_timestamp")

	return int(stamp.total_minutes) if stamp != null else 0


func _sweep_finished() -> void:
	for group: CustomerGroup in active_groups.duplicate():
		if not is_instance_valid(group):
			active_groups.erase(group)
			continue

		if not group.is_finished():
			continue

		if group.state == CustomerGroup.State.FAILED:
			group_failed.emit(group, group.failure_reason)
		else:
			group_completed.emit(group)

		active_groups.erase(group)
		_group_registered_msec.erase(group)
		_group_closing_observed_minutes.erase(group)

		# Idempotent: complete_visit() and fail_visit() have both already run
		# it. Calling it again here is what covers a group freed by any other
		# route - a scene reset, a debug tool, an externally deleted serving.
		group.cleanup()

		group.queue_free()


## Releases any reservation whose group no longer exists.
##
## A safety net rather than a normal path: every release should already have
## happened through the group. Exposed for the debug panel.
func clear_orphaned_reservations() -> int:
	var cleared: int = 0

	for node: Node in get_tree().get_nodes_in_group(&"group_standing_areas"):
		var area: GroupStandingArea = node as GroupStandingArea

		if area == null or area.is_free():
			continue

		if get_group(area.get_holder_group_id()) == null:
			area.force_release()
			cleared += 1

	# Chairs whose holder no longer exists. A group freed mid-visit, or a
	# member removed before it sat down, would otherwise leave a seat booked
	# to a dead node - and with eight chairs in the tavern, a handful of those
	# strands every later customer at the door.
	for node: Node in get_tree().get_nodes_in_group(&"chairs"):
		var chair: Chair = node as Chair

		if chair == null or chair.is_available():
			continue

		var holder: Node = chair.get_reservation_holder()

		if holder == null or not is_instance_valid(holder):
			push_warning(
				"Orphan sweep freed %s: its holder no longer exists."
				% chair.name
			)
			chair.force_release_reservation()
			cleared += 1
			continue

		# Held by a group that has already finished.
		var holding_group: CustomerGroup = holder as CustomerGroup

		if holding_group != null and not active_groups.has(holding_group):
			push_warning(
				"Orphan sweep freed %s: held by finished group %s."
				% [chair.name, String(holding_group.group_id)]
			)
			chair.force_release_reservation()
			cleared += 1

	for node: Node in get_tree().get_nodes_in_group(&"shared_servings"):
		var serving: SharedServing = node as SharedServing

		if serving == null:
			continue

		if get_group(serving.group_id) == null:
			# Always resolve the vessel before deleting an orphan. queue_free() on
			# its own removes the visual node but can leave the shared-cask vessel
			# reserved, preventing later groups from ordering.
			if not serving.is_empty():
				serving.empty_now()
			serving.queue_free()
			cleared += 1

	return cleared


func _on_group_state_changed(
	_previous: CustomerGroup.State,
	current: CustomerGroup.State,
	group: CustomerGroup
) -> void:
	if not log_state_changes:
		return

	print(
		"[Group %s] %s -> %s | place=%s | keg=%s | reason=%s" % [
			String(group.group_id),
			CustomerGroup.State.keys()[_previous],
			CustomerGroup.State.keys()[current],
			String(group.get_destination_id()),
			group.describe_keg(),
			group.describe_problem(),
		]
	)


func get_summary() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	for group: CustomerGroup in active_groups:
		if is_instance_valid(group):
			rows.append(group.get_summary())

	return rows
