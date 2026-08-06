class_name Customer
extends CharacterBody2D


## Total paid, kept for compatibility with existing listeners.
signal customer_paid(amount: int)

## The same payment, with the identity of what was actually bought.
##
## The drink is known at payment time but was being discarded before the
## signal, which is why the daily sales breakdown had nothing to key on. The
## base price travels too so a tip can be separated from the sale without the
## listener needing to look the drink up again.
signal customer_paid_for_drink(
	amount: int,
	item_id: StringName,
	base_price: int,
	customer_id: StringName
)
signal customer_finished(customer: Node)

## Emitted once as a customer leaves, with why and whether they were served.
##
## The distinction matters: a customer who drank, paid and went home is not a
## lost customer, and counting every unpaid departure as a loss would make the
## service rate meaningless.
signal customer_departed(
	customer: Node,
	reason: StringName,
	was_served: bool
)
signal customer_abandoned_seat(customer: Node)

## Phase 3A: this customer started or stopped waiting to be served.
##
## Emitted on entering [constant State.ORDERING], on being served, and on
## giving up. [TavernTaskCoordinator] listens so that a serve task is created
## and cancelled by events rather than by anything scanning every customer
## several times a second. Nothing in the customer's own behaviour depends on
## it, so a scene with no coordinator behaves exactly as before.
signal service_state_changed(customer: Node)

## Group entry: emitted when this member has crossed the inside door marker.
signal group_entry_crossed(customer: Node)


enum State {
	ENTERING,
	WALKING_TO_STAGING,
	MOVING_TO_SEAT,
	WAITING_TO_ORDER,
	ORDERING,
	DRINKING,
	LEAVING_TO_DOOR,
	EXITING,
	## Phase 2A: running the Relax at Seat activity. Added at the end of the
	## enum so existing int-based state values (e.g. the nav debugger's
	## _get_state_name()) keep working unchanged.
	RELAXING,
	## Phase 2C: talking with a nearby seated customer, still in the chair.
	SOCIALISING,
	## Phase 2C: travelling to a reserved TavernActivityPoint.
	MOVING_TO_ACTIVITY,
	## Phase 2C: standing at a TavernActivityPoint, timer running.
	USING_ACTIVITY,
	## Phase 2C: travelling back to reserved_chair after USING_ACTIVITY.
	RETURNING_TO_SEAT,
	## Group visit: walking to an assigned formation slot in a standing area.
	MOVING_TO_GROUP_SLOT,
	## Group visit: standing at the slot, socialising and drinking with the
	## group. Deliberately distinct from SOCIALISING, which is seated.
	IN_GROUP,
	## Group visit: waiting outside until the group entry controller releases us.
	GROUP_WAITING_OUTSIDE,
	## Group visit: crossing the doorway before receiving the final place target.
	GROUP_ENTERING,
	## Group visit: crossed the door and waiting for the final destination.
	GROUP_INSIDE_STAGING,
}


@export_category("Movement")
@export var movement_speed: float = 120.0
@export var seat_movement_speed: float = 45.0
@export var navigation_arrival_distance: float = 6.0
@export var seat_arrival_distance: float = 2.0


@export_category("Stuck Detection")
@export_category("Departure Safety")

## How close to the exit counts as having left, in pixels.
##
## The exit marker sits OUTSIDE the navigation mesh - deliberately, so
## customers walk out of the doorway rather than vanishing inside it. But an
## agent cannot report arrival at a point it can never path onto: it stops at
## the mesh edge and waits forever. This radius is what actually ends the
## visit.
@export_range(4.0, 256.0, 1.0)
var exit_arrival_radius: float = 64.0

## World minutes in EXITING before the customer is removed regardless.
##
## Last-resort backstop. A customer that cannot reach the exit at all must
## still leave, or it holds a population slot forever and no new customer can
## arrive - which reads in game as "nobody is coming in".
@export_range(1, 240, 1)
var exit_timeout_minutes: int = 5

## World minutes in LEAVING_TO_DOOR before the route is refreshed, and then
## before the customer is pushed straight into EXITING.
##
## LEAVING_TO_DOOR had no backstop at all: an agent that neither arrived nor
## failed sat in it indefinitely. One observed group member stayed there for
## over 180 world minutes, holding a population slot the whole time.
@export_range(1, 240, 1)
var leaving_timeout_minutes: int = 6

## Times the door route is re-planned before the customer skips to EXITING.
@export_range(0, 5, 1)
var maximum_leaving_refreshes: int = 2

@export var stuck_check_interval: float = 0.5
@export var minimum_stuck_movement: float = 1.0
@export var maximum_stuck_checks: int = 3
@export var maximum_path_refreshes: int = 2


@export_category("Walking Avoidance")
@export var walking_avoidance_radius: float = 12.0
@export var walking_avoidance_priority: float = 0.5
@export var occupied_avoidance_radius: float = 17.0
@export var occupied_zone_offset: float = 2.0


@onready var navigation_agent: NavigationAgent2D = (
	$NavigationAgent2D
)

@onready var customer_sprite: Sprite2D = $Sprite2D
@onready var order_icon: Sprite2D = $OrderIcon
## Bookings with WorldTime, replacing three real-time Timer nodes.
##
## A Timer keeps counting while the game is paused, ignores time speed, cannot
## be skipped and cannot be saved. A booking does all four correctly, which is
## the whole reason the scheduler exists.
var _order_event: ScheduledTimeEvent = null
var _drink_event: ScheduledTimeEvent = null
var _patience_event: ScheduledTimeEvent = null

## Phase 2A: tracks the Relax at Seat activity's completion booking, so it
## cancels the same way the other three do if the customer leaves or is
## freed mid-relax - see _cancel_all_scheduled().
var _relax_event: ScheduledTimeEvent = null

## World minute the current patience window ends, for the bar.
var _patience_end_minutes: float = 0.0
var _patience_total_minutes: int = 0

var _order_delay_minutes: int = 2
var _patience_duration_minutes: int = 15
var _drink_duration_minutes: int = 8
@onready var patience_bar: PatienceBar = $PatienceBar

@onready var actor_movement: ActorMovement = (
	$ActorMovement
)

@onready var actor_navigation: ActorNavigation = (
	$ActorNavigation
)


var current_state: State = State.ENTERING
var reserved_chair: Chair

var entrance_inside_position: Vector2
var entrance_outside_position: Vector2


var game_config: GameConfig
var ordered_drink: DrinkDefinition
var customer_type: CustomerType
var payment_multiplier: float = 1.0

var _profiles_are_private: bool = false

## The customer AI foundation - see systems/customer_ai/ and
## docs/CUSTOMER_AI_SYSTEM.md. Both stay null if configure() is never given
## an ActivityRegistry, so a test or a future actor scene that does not want
## the AI system still works exactly as before it existed.
var needs: CustomerNeeds = null
var _brain: CustomerBrain = null

## Phase 2A: how many drinks this customer has been served and finished
## this visit. Order Drink becomes ineligible at
## CustomerAIBalanceConfig.maximum_drinks_per_visit - see get_activity_flags()'s
## under_drink_limit and CLEANUP_REPORT-style notes in
## docs/CUSTOMER_AI_SYSTEM.md. Replaces the old one-shot _order_attempted
## flag, which permanently blocked a second order - the actual repeat-order
## gate is now simply "not currently mid-order" (has_ordered_drink), which
## naturally re-opens once a drink finishes.
var drinks_consumed_this_visit: int = 0

## True once this customer has actually finished a drink this visit, purely
## for anything that wants to distinguish "left without ordering" from
## "left after being served" - not currently read by any activity condition.
var has_had_a_drink: bool = false

## True only while this customer actually holds a drink that has been
## served and is being consumed - i.e. between interact() successfully
## serving it and _on_drink_finished() completing. This is what
## DrinkActivity's DomainFlagCondition gates on, so a customer can never be
## chosen into "Drink" before being served one. See
## docs/CUSTOMER_AI_SYSTEM.md's note on the bug this fixed.
var _has_drink_to_consume: bool = false

## Phase 2B: scheduled once, at seating, for the mandatory visit-time
## departure - see begin_relaxing()'s sibling _on_visit_time_expired().
var _visit_time_event: ScheduledTimeEvent = null

## Phase 2C scheduled events - same pattern as _relax_event: cancelled
## through the existing _cancel_all_scheduled() so leaving or being freed
## mid-activity never leaves stray bookings behind.
var _social_event: ScheduledTimeEvent = null
var _activity_use_event: ScheduledTimeEvent = null

## Phase 2C: the other customer currently linked by Socialise at Seat, if
## any - null the rest of the time. Public because the partner side of a
## socialise (find_nearby_social_partner()'s search, and
## notify_being_socialised_with()) needs to read/set it from outside.
var social_partner: Customer = null

## Phase 2C: pending Socialise effects, stashed between begin_socialising()
## and _on_socialise_finished() the same way _drink_duration_minutes
## already bridges choose_order() and interact().
var _social_satisfaction_gain: float = 0.0
var _social_partner_satisfaction_gain: float = 0.0
var _social_engagement_gain: float = 0.0

## Phase 2C: which TavernActivityPoint this customer is currently visiting
## or travelling to/from - null the rest of the time.
var _current_activity_point: TavernActivityPoint = null

## Phase 2C: incremented on a failed activity-point journey or a failed
## return-to-seat journey, reported in VisitRecord - see
## get_diagnostics_snapshot().
var _activity_reservation_failures: int = 0
var _return_to_seat_failures: int = 0

var _balance_config: CustomerAIBalanceConfig = null
var _diagnostics_config: CustomerAIDiagnosticsConfig = null
var _report_manager: CustomerAIReportManager = null

## This session's stable id for this customer, allocated by
## CustomerAIReportManager at configure time - stays -1 (and every
## report_manager call becomes a safe no-op) when reporting is not wired up.
var runtime_customer_id: int = -1

## Group this customer belongs to, or empty for a solo visitor.
##
## Read by [method SharedServing.is_consumer_eligible], which is what lets a
## member drink from its own group's pitcher and nobody else's. Stamped by
## [method CustomerGroup.add_member].
var group_id: StringName = &""

## The controller running this customer's group visit.
var group_controller: Node = null

## Where the group wants this member to stand, when standing.
var group_slot_position: Vector2 = Vector2.ZERO

## The centre of the group, used for facing.
var group_centre_position: Vector2 = Vector2.ZERO

## World minute this member may next take a drink from the shared serving.
var next_group_drink_minutes: int = -1

## Portions taken from a shared serving this visit. Counted apart from
## [member drinks_consumed_this_visit] so the report can show that keg
## drinking happened even when no individual drink was ever ordered.
var shared_drinks_consumed: int = 0

## Times the group had to recover this member onto its formation slot.
var group_slot_recoveries: int = 0

## Temporary position this member steps out to while a keg is delivered.
##
## Held apart from [member group_slot_position] on purpose: the normal
## drinking slot must survive the whole delivery unchanged, so the group can
## put everybody back exactly where they were.
var delivery_slot_position: Vector2 = Vector2.ZERO

## True while this member is standing clear for a delivery.
var is_stepped_back_for_delivery: bool = false

## Activity point booked for this member by its group during leisure.
##
## Held here rather than in [CustomerBrain] because a group member's leisure
## is chosen by the group, not by the utility brain - but it is released
## through exactly the same [Reservable] API, so darts cannot end up with two
## competing booking systems.
var group_activity_reservation: Reservable = null

## Activity this member did last, so leisure does not repeat it immediately.
var last_group_activity_id: StringName = &""

## World minute this customer entered EXITING. Minus one when it has not.
var _exit_started_minutes: int = -1

## World minute this customer entered LEAVING_TO_DOOR. Minus one when it has
## not. Drives the bounded exit-route recovery in _check_leaving_progress().
var _leaving_started_minutes: int = -1
var _leaving_refresh_attempts: int = 0
var _group_wait_started_msec: int = -1
var _group_entry_started_msec: int = -1

## Real-time group-entry safety. A parked member must never occupy a tavern
## population slot forever.
@export_range(2.0, 60.0, 0.5)
var group_outside_timeout_seconds: float = 30.0

## Empty until departure begins; set to exactly one of &"patience_expired",
## &"visit_time_expired" or &"utility_decision" the moment begin_leaving()
## runs - see that method. Read by finish_customer() when reporting this
## visit's departure.
var departure_reason: StringName = &""


func configure(
	config: GameConfig,
	new_customer_type: CustomerType,
	activity_registry: ActivityRegistry = null,
	balance_config: CustomerAIBalanceConfig = null,
	diagnostics_config: CustomerAIDiagnosticsConfig = null,
	report_manager: CustomerAIReportManager = null,
	intent_registry: VisitIntentRegistry = null,
	identity_seed: int = 0
) -> void:
	if config == null:
		push_error(
			name + " received an empty GameConfig."
		)
		return

	if new_customer_type == null:
		push_error(
			name + " received an empty CustomerType."
		)
		return

	game_config = config
	customer_type = new_customer_type
	_balance_config = balance_config
	_diagnostics_config = diagnostics_config
	_report_manager = report_manager

	_visit_intent_registry = intent_registry
	_identity_seed = identity_seed

	apply_game_config()
	apply_customer_type()
	_configure_ai(activity_registry)


## Sets up the customer AI foundation. Safe to skip entirely: every call
## site below that would otherwise use the brain checks for null first, so
## a customer configured without an ActivityRegistry behaves exactly as it
## did before this system existed.
## This customer's identity for the visit - type, their own jittered
## personality, and their visit intention. Null until configure() runs, and
## on any customer configured without an ActivityRegistry.
var identity: CustomerIdentity = null

var _visit_intent_registry: VisitIntentRegistry = null

## Non-zero makes this customer's traits and decisions reproducible - the
## deterministic diagnostic mode passes the spawn index.
var _identity_seed: int = 0


## Applies the visit intention's shape to the freshly seeded needs.
##
## Deliberately after seed_from rather than inside it: seed_from is shared
## with any future actor that has needs but no visit intention, and folding
## intent handling into it would have made every caller carry an intent it
## may not have.
func _apply_intent_to_needs() -> void:
	if identity == null or identity.visit_intent == null or needs == null:
		return

	var intent: VisitIntentConfig = identity.visit_intent

	needs.visit_duration_minutes = maxf(
		1.0,
		needs.visit_duration_minutes * intent.visit_duration_multiplier
	)

	needs.remaining_visit_minutes = needs.visit_duration_minutes


func _configure_ai(
	activity_registry: ActivityRegistry
) -> void:
	if activity_registry == null:
		return

	# Identity first: it owns this customer's private, jittered personality,
	# and CustomerNeeds must seed from that rather than from the type's
	# shared authored resource. Seeding from the shared one is what made
	# every customer of a type behave identically.
	identity = CustomerIdentity.new()
	identity.initialise(
		customer_type,
		_visit_intent_registry,
		runtime_customer_id,
		_identity_seed
	)

	needs = CustomerNeeds.new()
	needs.seed_from(customer_type, identity.personality, _balance_config)

	_apply_intent_to_needs()

	# Individual walking character: which side this customer passes on, how
	# far off the path centreline they walk, how fast. Seeded from the same
	# identity seed as their personality, so a deterministic run reproduces
	# how they move as well as how they behave.
	if actor_navigation != null:
		var restlessness: float = 0.5

		if identity.personality != null:
			restlessness = identity.personality.restlessness

		actor_navigation.seed_personal_movement(
			_identity_seed, restlessness
		)

	if _report_manager != null:
		runtime_customer_id = _report_manager.allocate_customer_id()

		var personality_name: String = (
			customer_type.personality.resource_path.get_file()
			if customer_type.personality != null else ""
		)

		_report_manager.register_spawn(
			runtime_customer_id,
			customer_type.display_name,
			personality_name,
			needs.wealth,
			needs.thirst,
			needs.mood
		)

	_brain = CustomerBrain.new()
	add_child(_brain)

	_brain.activity_forced.connect(_on_activity_forced)

	_brain.debug_enabled = (
		_diagnostics_config != null
		and _diagnostics_config.console_debug_enabled
	)

	_brain.report_manager = _report_manager
	_brain.runtime_customer_id = runtime_customer_id
	_brain.identity = identity
	_brain.configure(self, needs, activity_registry)

	CustomerBehaviourEvents.emit_identity_initialised(identity)


## Phase 2B.2: the single place departure_reason is set for any *forced*
## departure (patience, visit-time, out-of-money, and any future reason
## CustomerBrain.force_activity() is given) - CustomerBrain only knows it
## forced "leave" for some reason string, not that Customer keeps a
## departure_reason at all, which is exactly the decoupling
## docs/CUSTOMER_AI_SYSTEM.md's Phase 2B.2 section describes.
func _on_activity_forced(
	activity_id: StringName,
	reason: StringName
) -> void:
	if activity_id == &"leave" and departure_reason.is_empty():
		departure_reason = reason


func apply_game_config() -> void:
	navigation_arrival_distance = (
		game_config.navigation_arrival_distance
	)

	seat_arrival_distance = (
		game_config.seat_arrival_distance
	)

	stuck_check_interval = (
		game_config.stuck_check_interval
	)

	minimum_stuck_movement = (
		game_config.minimum_stuck_movement
	)

	maximum_stuck_checks = (
		game_config.maximum_stuck_checks
	)

	maximum_path_refreshes = (
		game_config.maximum_path_refreshes
	)

	walking_avoidance_radius = (
		game_config.walking_avoidance_radius
	)

	walking_avoidance_priority = (
		game_config.walking_avoidance_priority
	)

	_apply_tuning_to_profiles()


func apply_customer_type() -> void:
	movement_speed = customer_type.movement_speed

	seat_movement_speed = (
		customer_type.seat_movement_speed
	)

	_order_delay_minutes = customer_type.order_delay_minutes
	_patience_duration_minutes = customer_type.patience_duration_minutes

	payment_multiplier = (
		customer_type.payment_multiplier
	)

	if customer_type.customer_texture != null:
		customer_sprite.texture = (
			customer_type.customer_texture
		)
	else:
		push_warning(
			customer_type.display_name
			+ " has no customer texture assigned."
		)

	_apply_tuning_to_profiles()


## Copies the shared navigation resources so this actor owns its own tuning.
##
## Profiles are Resources, so without this every customer would be writing its
## personal speed onto the one asset the whole tavern shares. Idempotent: safe
## to call again if an actor is reconfigured.
func _create_private_profiles() -> void:
	if _profiles_are_private:
		return

	if actor_movement != null and actor_movement.profile != null:
		actor_movement.profile = actor_movement.profile.duplicate()

	if actor_navigation != null and actor_navigation.profile != null:
		actor_navigation.profile = actor_navigation.profile.duplicate()

	_profiles_are_private = true


## Pushes this customer's exported and configured values onto its profiles.
##
## This is the seam between the old per-customer exports plus [GameConfig] and
## the new profile resources. Anything a future actor type wants to vary lives
## in the profile; this method simply feeds it.
func _apply_tuning_to_profiles() -> void:
	if actor_movement == null or actor_navigation == null:
		return

	_create_private_profiles()

	if actor_movement.profile != null:
		actor_movement.profile.maximum_speed = movement_speed
		actor_movement.profile.careful_speed = seat_movement_speed

	if actor_navigation.profile != null:
		actor_navigation.profile.avoidance_radius = (
			walking_avoidance_radius
		)

		actor_navigation.profile.avoidance_priority = (
			walking_avoidance_priority
		)

		actor_navigation.profile.stuck_check_interval = (
			stuck_check_interval
		)

		actor_navigation.profile.stuck_minimum_movement = (
			minimum_stuck_movement
		)

		actor_navigation.profile.stuck_checks_before_recovery = (
			maximum_stuck_checks
		)

		actor_navigation.profile.maximum_recovery_attempts = (
			maxi(maximum_path_refreshes, 1)
		)

	actor_navigation.set_profile(actor_navigation.profile)


func _ready() -> void:
	add_to_group("navigation_customers")

	order_icon.visible = false
	patience_bar.hide_bar()

	_apply_tuning_to_profiles()

	if not actor_navigation.destination_reached.is_connected(
		_on_destination_reached
	):
		actor_navigation.destination_reached.connect(
			_on_destination_reached
		)

	if not actor_navigation.destination_failed.is_connected(
		_on_destination_failed
	):
		actor_navigation.destination_failed.connect(
			_on_destination_failed
		)


func _process(
	_delta: float
) -> void:
	update_patience_visual()


func _physics_process(
	_delta: float
) -> void:
	# Movement is owned by ActorNavigation and ActorMovement. The customer only
	# decides *where* to go and what to do on arrival, which is the whole point
	# of the split: this state machine works identically for a bartender.
	#
	# The one exception is leaving. The exit marker sits outside the navigation
	# mesh, so the agent stops at the mesh edge and reports neither arrival nor
	# failure - customers piled up in the doorway forever, holding population
	# slots so nobody new could come in. This checks the distance itself.
	if current_state == State.EXITING:
		_check_exit_progress()
	elif current_state == State.LEAVING_TO_DOOR:
		_check_leaving_progress()
	elif current_state == State.GROUP_WAITING_OUTSIDE:
		_check_group_outside_timeout()
	elif current_state == State.GROUP_ENTERING:
		_check_group_entry_timeout()


func _check_group_outside_timeout() -> void:
	if _group_wait_started_msec < 0:
		_group_wait_started_msec = Time.get_ticks_msec()
		return

	if float(Time.get_ticks_msec() - _group_wait_started_msec) / 1000.0 < group_outside_timeout_seconds:
		return

	departure_reason = &"group_entry_timeout"
	finish_customer()


func _check_group_entry_timeout() -> void:
	if _group_entry_started_msec < 0:
		_group_entry_started_msec = Time.get_ticks_msec()
		return

	if float(Time.get_ticks_msec() - _group_entry_started_msec) / 1000.0 < group_outside_timeout_seconds:
		return

	departure_reason = &"group_entry_timeout"
	finish_customer()


## Bounded recovery for a customer that cannot reach the inside door point.
##
## Refreshes the route first, because the usual cause is a transient blockage,
## and only then pushes the customer into EXITING - which has its own timeout
## and its own distance-based completion, so the visit always ends.
func _check_leaving_progress() -> void:
	if _leaving_started_minutes < 0:
		_leaving_started_minutes = _get_world_minutes()
		return

	if _get_world_minutes() - _leaving_started_minutes < leaving_timeout_minutes:
		return

	_leaving_started_minutes = _get_world_minutes()

	if _leaving_refresh_attempts < maximum_leaving_refreshes:
		_leaving_refresh_attempts += 1

		if _report_manager != null:
			_report_manager.record_navigation_recovery(runtime_customer_id)

		_travel_to(
			entrance_inside_position,
			navigation_arrival_distance,
			"door, leaving"
		)

		return

	if _report_manager != null:
		_report_manager.report_issue(
			runtime_customer_id,
			&"leaving_route_timed_out",
			"Could not reach the door within %d minutes after %d retries; "
			% [leaving_timeout_minutes, _leaving_refresh_attempts]
			+ "moved straight to EXITING.",
			get_diagnostics_snapshot()
		)

	begin_exiting()


## Ends the visit once the customer has effectively left.
##
## Two ways out, because the exit point may be unreachable by path: close
## enough counts, and so does taking too long. Either way the customer must
## stop occupying the tavern.
func _check_exit_progress() -> void:
	if global_position.distance_to(entrance_outside_position) <= exit_arrival_radius:
		finish_customer()
		return

	if _exit_started_minutes < 0:
		_exit_started_minutes = _get_world_minutes()
		return

	if _get_world_minutes() - _exit_started_minutes < exit_timeout_minutes:
		return

	if _report_manager != null:
		_report_manager.report_issue(
			runtime_customer_id,
			&"exit_timed_out",
			"Could not reach the exit within %d minutes; removed at %.0f px "
			% [exit_timeout_minutes, global_position.distance_to(
				entrance_outside_position
			)]
			+ "from it.",
			get_diagnostics_snapshot()
		)

	finish_customer()


func choose_order() -> void:
	if ordered_drink != null and _report_manager != null:
		_report_manager.report_issue(
			runtime_customer_id,
			&"duplicate_active_order",
			"choose_order() called while an order was already active.",
			get_diagnostics_snapshot()
		)

	ordered_drink = (
		choose_drink_from_customer_type()
	)

	if ordered_drink == null:
		push_error(
			name
			+ " could not choose a valid drink."
		)

		begin_leaving()
		return

	order_icon.texture = (
		ordered_drink.order_icon_texture
	)

	_drink_duration_minutes = ordered_drink.drink_duration_minutes


func choose_drink_from_customer_type() -> DrinkDefinition:
	if customer_type == null:
		push_error(
			name + " has no CustomerType."
		)
		return null

	var valid_drinks: Array[DrinkDefinition] = []

	for drink: DrinkDefinition in (
		customer_type.available_drinks
	):
		if drink == null:
			continue

		if not valid_drinks.has(drink):
			valid_drinks.append(drink)

	# Phase 2B: narrow to what this customer can actually pay for, if money
	# is being tracked at all. CanAffordDrinkCondition already keeps Order
	# Drink ineligible once nothing is affordable - this handles the case
	# where SOME but not all of this customer type's drinks are affordable,
	# so the cheaper one gets picked rather than a random one that fails.
	if needs != null:
		var affordable_drinks: Array[DrinkDefinition] = []

		for drink: DrinkDefinition in valid_drinks:
			var price: int = roundi(
				float(drink.base_sell_price) * payment_multiplier
			)

			if price <= needs.wealth:
				affordable_drinks.append(drink)

		if not affordable_drinks.is_empty():
			valid_drinks = affordable_drinks

	if valid_drinks.is_empty():
		push_error(
			customer_type.display_name
			+ " has no available drinks."
		)

		return null

	var preferred: DrinkDefinition = (
		customer_type.preferred_drink
	)

	var preferred_is_valid: bool = (
		preferred != null
		and valid_drinks.has(preferred)
	)

	if (
		preferred_is_valid
		and randf()
		< customer_type.preferred_drink_chance
	):
		return preferred

	var alternative_drinks: Array[DrinkDefinition] = []

	for drink: DrinkDefinition in valid_drinks:
		if drink == preferred:
			continue

		alternative_drinks.append(drink)

	if not alternative_drinks.is_empty():
		return alternative_drinks.pick_random()

	if preferred_is_valid:
		return preferred

	return valid_drinks.pick_random()


func set_chair_target(
	chair: Chair
) -> void:
	if chair == null:
		push_error(
			"Customer received an empty chair target."
		)
		return

	reserved_chair = chair
	_set_state(State.ENTERING)

	_travel_to(
		entrance_inside_position,
		navigation_arrival_distance,
		"tavern entrance"
	)


func set_door_targets(
	inside_position: Vector2,
	outside_position: Vector2
) -> void:
	entrance_inside_position = inside_position
	entrance_outside_position = outside_position


## Sends this customer somewhere, through the shared navigation framework.
##
## Every journey the customer makes goes through here, so there is exactly one
## place that knows how a destination is described.
func _travel_to(
	world_position: Vector2,
	arrival_distance: float,
	label: String
) -> void:
	actor_navigation.unpark()

	actor_navigation.move_to(
		NavigationDestination.to_position(
			world_position,
			arrival_distance,
			label
		)
	)


## Sends this customer to a spot it must reach precisely, slowly.
##
## The seat, and later any workstation position that has to be stood on exactly.
func _travel_to_exactly(
	world_position: Vector2,
	arrival_distance: float,
	speed_scale: float,
	label: String
) -> void:
	actor_navigation.unpark()

	actor_navigation.move_to(
		NavigationDestination.to_exact_position(
			world_position,
			arrival_distance,
			speed_scale,
			label
		)
	)


## The navigation framework reports that this customer arrived.
##
## Replaces the old per-state arrival checks: the customer no longer measures
## distances, it is simply told.
func _on_destination_reached(
	_destination: NavigationDestination
) -> void:
	match current_state:
		State.ENTERING:
			begin_walking_to_staging()

		State.WALKING_TO_STAGING:
			begin_moving_to_seat()

		State.MOVING_TO_SEAT:
			arrive_at_seat()

		State.LEAVING_TO_DOOR:
			begin_exiting()

		State.EXITING:
			finish_customer()

		State.MOVING_TO_ACTIVITY:
			arrive_at_activity()

		State.RETURNING_TO_SEAT:
			_on_returned_to_seat()

		State.MOVING_TO_GROUP_SLOT:
			_on_reached_group_slot()

		State.GROUP_ENTERING:
			_on_group_entry_crossed()


## The navigation framework gave up on the current destination.
##
## By the time this fires the actor has already tried sidestepping and
## re-planning, so this really is the end of the road for that destination.
func _on_destination_failed(
	destination: NavigationDestination,
	reason: StringName
) -> void:
	if should_show_debug_messages():
		print(
			name,
			" could not reach ",
			"its destination" if destination == null else destination.get_label(),
			" (",
			reason,
			")."
		)

	if _report_manager != null:
		_report_manager.record_navigation_failure(runtime_customer_id)

	if current_state == State.EXITING:
		# Already outside and on the way out; there is nothing left to salvage.
		finish_customer()
		return

	if current_state == State.MOVING_TO_ACTIVITY:
		# Phase 2C: never a full departure - release the activity
		# reservation (via the brain, which is the only thing that knows it
		# is holding one) and try to get back to the chair instead. See
		# docs/CUSTOMER_AI_SYSTEM.md's Phase 2C "Navigation and failure
		# recovery" section and Scenario D.
		_activity_reservation_failures += 1

		if _report_manager != null:
			_report_manager.record_activity_reservation_failure(
				runtime_customer_id
			)

			_report_manager.report_issue(
				runtime_customer_id,
				&"activity_navigation_failed",
				"Navigation to '%s' failed (%s)." % [
					(
						_current_activity_point.activity_id
						if _current_activity_point != null else &"?"
					),
					reason,
				],
				get_diagnostics_snapshot()
			)

		if _brain != null:
			_brain.abandon_current_activity()

		_current_activity_point = null

		begin_returning_to_seat()
		return

	if current_state == State.RETURNING_TO_SEAT:
		# Already failed once trying to get back; do not retry forever -
		# fall through to the same generic recovery every other state uses.
		_return_to_seat_failures += 1

		if _report_manager != null:
			_report_manager.record_return_to_seat_failure(runtime_customer_id)

			_report_manager.report_issue(
				runtime_customer_id,
				&"return_to_seat_failed",
				"Navigation back to the reserved chair failed (%s)." % reason,
				get_diagnostics_snapshot()
			)

	handle_invalid_destination()


func begin_walking_to_staging() -> void:
	if reserved_chair == null:
		handle_invalid_destination()
		return

	_set_state(State.WALKING_TO_STAGING)

	_travel_to(
		reserved_chair.get_staging_position(),
		navigation_arrival_distance,
		"seat staging point"
	)


func begin_exiting() -> void:
	_set_state(State.EXITING)

	# The outside marker sits beyond the navigation mesh, so this is an exact
	# destination: the framework paths as far as the mesh allows and then walks
	# the remaining distance directly, with avoidance still running.
	_travel_to_exactly(
		entrance_outside_position,
		navigation_arrival_distance,
		1.0,
		"tavern exit"
	)


func begin_leaving() -> void:
	if departure_reason.is_empty():
		# Nothing forced this - a normal utility decision chose Leave. See
		# CustomerAIReportManager.record_departure()'s reason handling.
		departure_reason = &"utility_decision"

	_cancel_all_scheduled()

	order_icon.visible = false
	patience_bar.hide_bar()

	release_reserved_chair()
	customer_abandoned_seat.emit(self)

	_leaving_started_minutes = -1
	_leaving_refresh_attempts = 0

	_set_state(State.LEAVING_TO_DOOR)

	_travel_to(
		entrance_inside_position,
		navigation_arrival_distance,
		"door, leaving"
	)


func begin_moving_to_seat() -> void:
	if reserved_chair == null:
		handle_invalid_destination()
		return

	_set_state(State.MOVING_TO_SEAT)

	# A seat sits inside furniture and therefore off the navigation mesh. The
	# framework handles that as a final approach rather than as a special case
	# here, and unlike the old code it keeps avoidance running all the way in.
	var seat_speed_scale: float = 1.0

	if actor_movement.profile.maximum_speed > 0.0:
		seat_speed_scale = clampf(
			seat_movement_speed
			/ actor_movement.profile.maximum_speed,
			0.05,
			1.0
		)

	_travel_to_exactly(
		reserved_chair.get_seat_position(),
		seat_arrival_distance,
		seat_speed_scale,
		"seat"
	)


func arrive_at_seat() -> void:
	if reserved_chair == null:
		handle_invalid_destination()
		return

	# Parking keeps the customer in the avoidance solver at maximum priority, so
	# other actors flow around a seated customer instead of shoving it out of
	# its chair. The old code removed the customer from avoidance entirely.
	actor_navigation.park()

	reserved_chair.set_occupied_zone_enabled(true)

	# Phase 2C: makes this customer discoverable by
	# find_nearby_social_partner() - left in release_reserved_chair().
	add_to_group(&"seated_customers")

	# A seated group member is controlled by CustomerGroup from this point.
	# Previously this function continued into the solo AI path, causing every
	# member to place an individual order while GroupManager simultaneously
	# attempted to create the group's shared order.
	if has_group() and is_instance_valid(group_controller):
		_cancel_all_scheduled()
		order_icon.visible = false
		patience_bar.hide_bar()
		_set_state(State.IN_GROUP)
		next_group_drink_minutes = _get_world_minutes() + randi_range(0, 2)
		return

	if needs != null:
		# Phase 2B: the visit clock starts now, not at spawn, so time spent
		# walking to the table never eats into the intended visit length.
		needs.start_visit_clock(WorldTime.get_total_minutes())

		_visit_time_event = WorldTime.schedule_in(
			maxi(1, roundi(needs.visit_duration_minutes)),
			_on_visit_time_expired,
			&"customer_visit_time"
		)

	if _brain != null:
		# A freshly seated customer always wants to order today - there is no
		# real alternative yet for CustomerBrain to weigh, so this is a direct
		# transition rather than a full think(). See OrderDrinkBehaviour's
		# doc comment. It ends up calling choose_order() and
		# begin_waiting_to_order() below, just one hop further away.
		if not _brain.enter_activity(&"order_drink"):
			# No ActivityRegistry entry for order_drink - fall back rather
			# than leave a seated customer doing nothing.
			choose_order()

			if ordered_drink != null:
				begin_waiting_to_order()
	else:
		choose_order()

		if ordered_drink != null:
			begin_waiting_to_order()


## The rest of arriving at a seat, once a drink has been chosen: starts the
## order-delay clock and shows the seating debug message. Split out of
## arrive_at_seat() so OrderDrinkBehaviour can call it after choose_order()
## without duplicating it.
func begin_waiting_to_order() -> void:
	if ordered_drink == null:
		handle_invalid_destination()
		return

	_set_state(State.WAITING_TO_ORDER)
	order_icon.modulate = Color.WHITE
	_order_event = WorldTime.schedule_in(
		_order_delay_minutes,
		_on_order_ready,
		&"customer_order"
	)

	if should_show_debug_messages():
		print(
			name,
			" seated at ",
			reserved_chair.get_table().name,
			"/",
			reserved_chair.name
		)


## Phase 2A: starts Relax at Seat's timed pause, called from
## RelaxAtSeatBehaviour.on_enter(). Uses WorldTime's scheduler, the same
## event-driven mechanism as ordering and drinking - never a per-frame count.
## Cancelled the same way those are if this customer leaves or is freed
## mid-relax, via _cancel_all_scheduled().
func begin_relaxing(
	minimum_minutes: float,
	maximum_minutes: float
) -> void:
	_set_state(State.RELAXING)

	var duration_minutes: int = maxi(
		1,
		roundi(randf_range(minimum_minutes, maximum_minutes))
	)

	_relax_event = WorldTime.schedule_in(
		duration_minutes,
		_on_relax_finished,
		&"customer_relax"
	)

	if _report_manager != null:
		_report_manager.record_relax(runtime_customer_id)

		if needs != null and needs.remaining_visit_minutes <= 0.0:
			_report_manager.report_issue(
				runtime_customer_id,
				&"relaxing_after_mandatory_departure",
				"Relax started with no visit time remaining.",
				get_diagnostics_snapshot()
			)

	if _is_ai_debug_enabled():
		print(
			"[CustomerAI] ", name,
			" relaxing for ", duration_minutes, " world minutes."
		)


func _on_relax_finished() -> void:
	_relax_event = null

	if current_state != State.RELAXING:
		return

	if needs != null:
		needs.adjust(&"relax_count", 1.0)

	if _is_ai_debug_enabled():
		print(
			"[CustomerAI] ", name,
			" finished relaxing (relax_count=",
			(needs.relax_count if needs != null else -1.0),
			") - asking the brain to decide again."
		)

	if _return_group_member_after_activity(&"relax"):
		return

	if _brain != null:
		_brain.think()
	else:
		begin_leaving()


## Phase 2C: whether another customer may treat this one as a social
## partner right now. Deliberately narrow - only RELAXING - per the
## brief's "do not interrupt the partner if they are drinking, leaving or
## waiting for service" (WAITING_TO_ORDER counts as "waiting for service"
## too, so it is excluded here as well, not just DRINKING/LEAVING_TO_DOOR).
func is_available_for_social() -> bool:
	if has_group():
		# A group member standing at its slot is exactly as interruptible as
		# a solo customer relaxing in a chair.
		return current_state == State.IN_GROUP or current_state == State.RELAXING

	return current_state == State.RELAXING


## Phase 2C: the nearest other seated, available customer within
## [param range_pixels], or null. Shared by SocialiseAtSeatBehaviour (which
## actually starts the activity with whoever this finds) and
## get_activity_flags()'s has_social_partner (which only needs to know
## whether the search would succeed) - one search, two callers, so they
## can never disagree about whether a partner exists.
func find_nearby_social_partner(range_pixels: float) -> Customer:
	if not is_inside_tree():
		return null

	var best: Customer = null
	var best_distance: float = range_pixels

	for node: Node in get_tree().get_nodes_in_group(&"seated_customers"):
		var other: Customer = node as Customer

		if (
			other == null
			or other == self
			or not is_instance_valid(other)
			or not other.is_available_for_social()
		):
			continue

		var distance: float = global_position.distance_to(
			other.global_position
		)

		if distance <= best_distance:
			best_distance = distance
			best = other

	return best


## Phase 2C: called on the *partner* by SocialiseAtSeatBehaviour, purely so
## something is visibly true about them for debugging/future visuals - see
## the class doc comment on this phase's deliberately simple visual goal.
## Does not change the partner's own decisions; they keep making their own
## choices independently, per the brief's "one customer may initiate...
## do not require both to select at exactly the same time".
func notify_being_socialised_with(_initiator: Customer) -> void:
	if _is_ai_debug_enabled():
		print(
			"[CustomerAI] ", name,
			" is being socialised with by ", _initiator.name, "."
		)


## Phase 2C: starts Socialise at Seat. [param partner] may be null (no one
## was nearby when this was chosen - the activity still runs, just as a
## quiet moment rather than a conversation, and the partner-side effects
## simply do not apply).
func begin_socialising(
	partner: Customer,
	minimum_minutes: float,
	maximum_minutes: float,
	notify_partner: bool,
	satisfaction_gain: float,
	partner_satisfaction_gain: float,
	engagement_gain: float
) -> void:
	_set_state(State.SOCIALISING)
	social_partner = partner

	_social_satisfaction_gain = satisfaction_gain
	_social_partner_satisfaction_gain = partner_satisfaction_gain
	_social_engagement_gain = engagement_gain

	var duration_minutes: int = maxi(
		1,
		roundi(randf_range(minimum_minutes, maximum_minutes))
	)

	_social_event = WorldTime.schedule_in(
		duration_minutes,
		_on_socialise_finished,
		&"customer_socialise"
	)

	# A simple placeholder indicator, reusing the existing order-icon sprite
	# rather than a new asset/scene node - see docs/CUSTOMER_AI_SYSTEM.md's
	# Phase 2C "Socialise at Seat" section for why. Reset in
	# _on_socialise_finished() and defensively in begin_waiting_to_order().
	order_icon.modulate = Color(0.6, 0.8, 1.0, 1.0)
	order_icon.visible = true

	if partner != null and notify_partner and is_instance_valid(partner):
		partner.notify_being_socialised_with(self)

	if _report_manager != null:
		_report_manager.record_socialise(
			runtime_customer_id,
			partner.runtime_customer_id if partner != null else -1
		)

	if _is_ai_debug_enabled():
		print(
			"[CustomerAI] ", name,
			" socialising with ",
			(String(partner.name) if partner != null else "no one nearby"),
			" for ", duration_minutes, " world minutes."
		)


func _on_socialise_finished() -> void:
	_social_event = null

	if current_state != State.SOCIALISING:
		return

	order_icon.visible = false
	order_icon.modulate = Color.WHITE

	if needs != null:
		needs.adjust(&"mood", _social_satisfaction_gain)
		needs.adjust(&"engagement", _social_engagement_gain)
		needs.adjust(&"socialise_count", 1.0)

	if (
		social_partner != null
		and is_instance_valid(social_partner)
		and social_partner.needs != null
	):
		social_partner.needs.adjust(
			&"mood", _social_partner_satisfaction_gain
		)

	social_partner = null

	if _return_group_member_after_activity(&"socialise"):
		return

	if _is_ai_debug_enabled():
		print(
			"[CustomerAI] ", name,
			" finished socialising (socialise_count=",
			(needs.socialise_count if needs != null else -1.0),
			") - asking the brain to decide again."
		)

	if _brain != null:
		_brain.think()
	else:
		begin_leaving()


## Phase 2C: starts travelling to a reserved TavernActivityPoint, called by
## VisitTavernActivityBehaviour once CustomerBrain has already reserved it.
## reserved_chair is left completely untouched - see the class-level note
## on chair retention in docs/CUSTOMER_AI_SYSTEM.md's Phase 2C section.
func begin_visiting_activity(point: TavernActivityPoint) -> void:
	_current_activity_point = point
	_set_state(State.MOVING_TO_ACTIVITY)

	_travel_to(
		point.get_use_position(),
		navigation_arrival_distance,
		"activity: " + String(point.activity_id)
	)


func arrive_at_activity() -> void:
	if _current_activity_point == null:
		handle_invalid_destination()
		return

	actor_navigation.park()

	_set_state(State.USING_ACTIVITY)

	var duration_minutes: int = maxi(
		1,
		roundi(_current_activity_point.activity_duration_minutes)
	)

	_activity_use_event = WorldTime.schedule_in(
		duration_minutes,
		_on_activity_use_finished,
		&"customer_activity_use"
	)

	if _is_ai_debug_enabled():
		print(
			"[CustomerAI] ", name,
			" using '", _current_activity_point.activity_id,
			"' for ", duration_minutes, " world minutes."
		)


func _on_activity_use_finished() -> void:
	_activity_use_event = null

	if current_state != State.USING_ACTIVITY or _current_activity_point == null:
		return

	var point: TavernActivityPoint = _current_activity_point

	if needs != null:
		needs.adjust(&"mood", point.satisfaction_effect)
		needs.adjust(&"engagement", point.engagement_effect)

		if point.intoxication_effect > 0.0:
			needs.adjust(&"intoxication", point.intoxication_effect)

		if point.money_cost > 0:
			needs.adjust(&"wealth", -float(point.money_cost))

		if point.activity_id == &"darts":
			needs.adjust(&"darts_count", 1.0)

	if _report_manager != null:
		_report_manager.record_tavern_activity(
			runtime_customer_id, String(point.activity_id)
		)

	if _is_ai_debug_enabled():
		print(
			"[CustomerAI] ", name,
			" finished using '", point.activity_id, "'."
		)

	if _return_group_member_after_activity(point.activity_id):
		return

	if point.return_to_seat_after_use and _brain != null:
		_brain.enter_activity(&"return_to_seat")
	else:
		_current_activity_point = null

		if _brain != null:
			_brain.think()
		else:
			begin_leaving()


## Phase 2C: called by both ReturnToSeatBehaviour (the normal path) and
## _on_destination_failed()'s MOVING_TO_ACTIVITY recovery (the customer
## never actually reached the activity, but is still "returning" in the
## sense of heading back to the known-good chair).
func begin_returning_to_seat() -> void:
	_current_activity_point = null

	if reserved_chair == null:
		handle_invalid_destination()
		return

	_set_state(State.RETURNING_TO_SEAT)

	_travel_to_exactly(
		reserved_chair.get_seat_position(),
		seat_arrival_distance,
		1.0,
		"back to chair"
	)


func _on_returned_to_seat() -> void:
	actor_navigation.park()

	if has_group():
		_on_reached_group_slot()
		_notify_group_member_returned()

		return

	if reserved_chair != null:
		reserved_chair.set_occupied_zone_enabled(true)

	if _brain != null:
		_brain.think()
	else:
		begin_leaving()


## Phase 2C: called by VisitTavernActivityBehaviour when the reservation
## CustomerBrain._enter() made cannot actually be used (defensive - should
## be rare given DestinationAvailableCondition already checked). Releases
## the brain's hold on it and reports the anomaly, then falls back to a
## normal decision rather than getting stuck.
func abandon_activity_visit(issue_type: StringName) -> void:
	if _brain != null:
		_brain.abandon_current_activity()

	if _report_manager != null:
		_report_manager.report_issue(
			runtime_customer_id,
			issue_type,
			"Visit Tavern Activity could not start.",
			get_diagnostics_snapshot()
		)

	if _brain != null:
		_brain.think()
	else:
		begin_leaving()


## Phase 2B: the mandatory visit-time departure, scheduled once in
## arrive_at_seat(). Mirrors _on_patience_expired()'s forced-transition
## pattern exactly - see CustomerBrain.force_activity()'s doc comment on
## why this does not compete through normal utility scoring.
func _on_visit_time_expired() -> void:
	_visit_time_event = null

	if (
		current_state == State.LEAVING_TO_DOOR
		or current_state == State.EXITING
	):
		return

	departure_reason = &"visit_time_expired"

	if _is_ai_debug_enabled():
		print(
			"[CustomerAI] ", name,
			" ran out of intended visit time and is leaving."
		)

	if _brain != null:
		if not _brain.force_activity(&"leave", &"visit_time_expired"):
			begin_leaving()
	else:
		begin_leaving()


func handle_invalid_destination() -> void:
	_cancel_all_scheduled()

	order_icon.visible = false
	patience_bar.hide_bar()

	if (
		current_state == State.LEAVING_TO_DOOR
		or current_state == State.EXITING
	):
		finish_customer()
		return

	if should_show_debug_messages():
		print(
			name,
			" could not reach its destination and will leave."
		)

	begin_leaving()


## Ends this visit's chair reservation - the single place that happens,
## called from begin_leaving(), finish_customer() and _exit_tree() alike, so
## every departure path (normal, patience-expiry, forced removal) is
## covered the same way. Marks the chair for cleaning if this customer ever
## consumed a drink; otherwise releases it plainly, since nothing was ever
## served there. Idempotent - safe to call more than once per visit.
func release_reserved_chair() -> void:
	if reserved_chair == null:
		return

	var chair: Chair = reserved_chair
	reserved_chair = null

	remove_from_group(&"seated_customers")

	if drinks_consumed_this_visit > 0:
		chair.require_cleaning()
	else:
		chair.release_reservation(self)

	if _is_ai_debug_enabled():
		print(
			"[CustomerAI] ", name,
			" released ", chair.name,
			" (cleaning required: ", (drinks_consumed_this_visit > 0), ")"
		)


## Cancels every outstanding booking this customer holds.
##
## Called anywhere the old code stopped three timers, and on the way out, so a
## customer that is freed never leaves work booked behind it.
func _cancel_all_scheduled() -> void:
	WorldTime.cancel_scheduled(_order_event)
	WorldTime.cancel_scheduled(_drink_event)
	WorldTime.cancel_scheduled(_patience_event)
	WorldTime.cancel_scheduled(_relax_event)
	WorldTime.cancel_scheduled(_visit_time_event)
	WorldTime.cancel_scheduled(_social_event)
	WorldTime.cancel_scheduled(_activity_use_event)

	_order_event = null
	_drink_event = null
	_patience_event = null
	_relax_event = null
	_visit_time_event = null
	_social_event = null
	_activity_use_event = null
	_patience_total_minutes = 0


func _cancel_patience() -> void:
	WorldTime.cancel_scheduled(_patience_event)

	_patience_event = null
	_patience_total_minutes = 0


func update_patience_visual() -> void:
	if current_state != State.ORDERING:
		return

	if _patience_event == null or _patience_total_minutes <= 0:
		return

	# Read against the fractional world minute so the bar slides smoothly and
	# drains faster under fast-forward, rather than stepping once a minute.
	var remaining: float = (
		_patience_end_minutes
		- WorldTime.get_total_minutes_precise()
	)

	patience_bar.set_patience_ratio(
		clampf(
			remaining / float(_patience_total_minutes),
			0.0,
			1.0
		)
	)


func _on_order_ready() -> void:
	if ordered_drink == null:
		handle_invalid_destination()
		return

	_set_state(State.ORDERING)
	order_icon.visible = true

	if _report_manager != null:
		_report_manager.record_order(runtime_customer_id)

	if (
		game_config == null
		or not game_config.disable_patience
	):
		_patience_total_minutes = _patience_duration_minutes

		_patience_end_minutes = (
			WorldTime.get_total_minutes_precise()
			+ float(_patience_total_minutes)
		)

		_patience_event = WorldTime.schedule_in(
			_patience_duration_minutes,
			_on_patience_expired,
			&"customer_patience"
		)

		patience_bar.show_bar()
	else:
		patience_bar.hide_bar()

	if should_show_debug_messages():
		print(
			name,
			" ordered ",
			ordered_drink.display_name,
			". Patience: ",
			_patience_duration_minutes,
			" world minutes."
		)

	# Phase 3A: announce that a real requirement now exists in the tavern.
	# Emitted last, so any listener that immediately inspects this customer
	# sees a fully-configured order rather than a half-built one.
	service_state_changed.emit(self)


## The interaction-framework entry point, unchanged in behaviour.
##
## Phase 3A moved the body of this into [method try_serve] so that staff have
## the same authoritative path with a return value to check. The player's
## experience is identical: this is still what the interaction prompt runs, and
## it still fails silently with a debug line when the wrong thing is carried.
func interact(
	player: Node
) -> void:
	try_serve(player)


## Serves this customer from [param actor]'s hands. The one true serve.
##
## Called by the player through [method interact] and by a member of staff
## through [ServeDrinkExecutor]. Both go through exactly these checks, empty
## exactly these hands and run exactly the same [method _serve_drink], so there
## is no second, staff-only way to be served and no way for the two to drift.
##
## [param actor] only has to be able to carry items - it is duck-typed on
## [code]get_item_carrier[/code] rather than being a player, which is what let
## staff reuse this without a line of it changing.
##
## Returns false, harmlessly, when the customer is not waiting, when the actor
## carries the wrong drink, or when the actor cannot carry anything at all.
func try_serve(
	actor: Node
) -> bool:
	if not is_awaiting_service():
		if should_show_debug_messages():
			print(
				name,
				" is not ready to be served."
			)

		return false

	if actor == null or not actor.has_method(
		"get_item_carrier"
	):
		push_error(
			name
			+ " was offered a drink by something that cannot carry items."
		)

		return false

	var carrier: ItemCarrier = actor.get_item_carrier()

	if carrier == null:
		push_error(
			name
			+ " could not access the server's ItemCarrier."
		)

		return false

	var carried_definition: ItemDefinition = (
		carrier.get_carried_definition()
	)

	# Compare stable item ids, never display names.
	if (
		carried_definition == null
		or carried_definition.item_id != ordered_drink.item_id
	):
		if should_show_debug_messages():
			if carried_definition == null:
				print(
					name,
					" wants ",
					ordered_drink.display_name,
					", but ",
					actor.name,
					" is carrying nothing."
				)
			else:
				print(
					name,
					" wants ",
					ordered_drink.display_name,
					", not ",
					carried_definition.display_name,
					"."
				)

		return false

	_cancel_patience()
	patience_bar.hide_bar()

	# The drink leaves the item system here: the customer consumes it.
	# Future work: hand it to a chair service slot instead of clearing it.
	carrier.clear_carried_item()

	_serve_drink()

	return true


## True when this customer is sitting waiting for a drink right now.
##
## The single question every serving decision asks - the task coordinator to
## decide whether a job exists, the executor to decide whether to walk over,
## and [method try_serve] to decide whether to hand anything across. Having one
## method answer it for all three is what stops them ever disagreeing.
func is_awaiting_service() -> bool:
	return (
		current_state == State.ORDERING
		and ordered_drink != null
	)


## What this customer asked for, or null when they are not waiting.
func get_requested_drink() -> DrinkDefinition:
	if not is_awaiting_service():
		return null

	return ordered_drink


## How badly this customer needs serving, from 0 to 1.
##
## Zero at the moment of ordering, approaching one as patience runs out, so a
## customer about to walk out naturally out-scores one who has just sat down.
## Returns a mild constant when patience is disabled in [GameConfig], because
## "no patience system" should not mean "nobody is in a hurry".
## World minutes before this customer gives up waiting.
##
## The deadline a serving task is measured against. Returns -1 when there is
## no patience timer at all - patience disabled in GameConfig, or a customer
## who is not currently waiting - which the viability system reads as "cannot
## expire" rather than "expires immediately".
func get_patience_remaining_minutes() -> float:
	if current_state != State.ORDERING:
		return -1.0

	if _patience_total_minutes <= 0:
		return -1.0

	return maxf(
		_patience_end_minutes - WorldTime.get_total_minutes_precise(),
		0.0
	)


func get_service_urgency() -> float:
	if not is_awaiting_service():
		return 0.0

	if _patience_total_minutes <= 0:
		return 0.35

	var remaining: float = (
		_patience_end_minutes
		- WorldTime.get_total_minutes_precise()
	)

	var fraction_left: float = clampf(
		remaining / float(_patience_total_minutes),
		0.0,
		1.0
	)

	return 1.0 - fraction_left


## Where a server should stand to reach this customer.
##
## A seated customer is normally inside a hole in the navigation mesh - the
## table and chair are solid - so their own position is not somewhere anyone
## can walk. The chair's staging position is walkable by construction: it is
## the spot the customer themselves stood on before sitting down.
func get_service_approach_position() -> Vector2:
	if reserved_chair != null and is_instance_valid(reserved_chair):
		return reserved_chair.get_staging_position()

	return global_position


## The actual "this customer has now been served" transition, shared by
## interact() (after the player/carrier/item checks above pass) and
## force_serve_now() (the F10 dev tool, which has no real player or carried
## item to check - see its own doc comment for why skipping straight to
## this method is still "respecting existing serve logic" rather than
## bypassing it).
func _serve_drink() -> void:
	if reserved_chair != null:
		reserved_chair.begin_use(
			ordered_drink
		)

	order_icon.visible = false
	_set_state(State.DRINKING)
	_drink_event = WorldTime.schedule_in(
		_drink_duration_minutes,
		_on_drink_finished,
		&"customer_drinking"
	)

	_has_drink_to_consume = true

	# Phase 3A: the requirement is met, whoever met it. Any outstanding serve
	# task for this customer is cancelled off the back of this, which is how a
	# worker mid-walk finds out the player got there first.
	service_state_changed.emit(self)

	if needs != null and _balance_config != null:
		needs.adjust(&"mood", _balance_config.satisfaction_gain_on_service)

	if _report_manager != null:
		_report_manager.record_serve(runtime_customer_id)

		if reserved_chair != null:
			_report_manager.record_chair(runtime_customer_id, reserved_chair.name)

	if _brain != null:
		# Bookkeeping only - see DrinkBehaviour's doc comment for why the
		# actual serving mechanics stay right here rather than moving into it.
		_brain.enter_activity(&"drink")

	if should_show_debug_messages():
		print(
			name,
			" was served ",
			ordered_drink.display_name,
			"."
		)


## Phase 2B.1: the F10 "Serve All Drinks" developer shortcut calls this
## directly on every customer currently in State.ORDERING, standing in for
## the player physically walking over with the right drink. Does nothing to
## a customer not currently waiting for one - see StockDevPanel's caller,
## which only gathers customers in that state to begin with, but this
## method re-checks it too so it is never misused into serving someone
## mid-drink or mid-relax and duplicating a serve.
func force_serve_now() -> void:
	if current_state != State.ORDERING or ordered_drink == null:
		return

	_cancel_patience()
	patience_bar.hide_bar()

	_serve_drink()


## Phase 2C: lets the F10 panel's "Force Selected Customer to Socialise"/
## "...to Use Darts" buttons go through the real CustomerBrain.force_activity()
## rather than StockDevPanel reaching into a private _brain field - keeps
## the encapsulation the rest of Customer.gd already has around _brain.
## Returns false (and does nothing) if this customer has no brain
## configured at all.
func force_activity_for_testing(activity_id: StringName) -> bool:
	if _brain == null:
		return false

	return _brain.force_activity(activity_id, &"developer_forced")


func _on_drink_finished() -> void:
	if ordered_drink == null:
		push_error(
			name
			+ " finished drinking without a valid "
			+ "DrinkDefinition."
		)

		if _report_manager != null:
			_report_manager.report_issue(
				runtime_customer_id,
				&"duplicate_drink_finished",
				"_on_drink_finished() fired with no active order - "
				+ "a stale or duplicate scheduled event.",
				get_diagnostics_snapshot()
			)

		return

	var payment_amount: int = roundi(
		float(
			ordered_drink.base_sell_price
		)
		* payment_multiplier
	)

	if should_show_debug_messages():
		print(
			name,
			" finished drinking ",
			ordered_drink.display_name,
			"."
		)

		print(
			name,
			" paid £",
			payment_amount
		)

	customer_paid.emit(payment_amount)

	customer_paid_for_drink.emit(
		payment_amount,
		ordered_drink.item_id,
		ordered_drink.base_sell_price,
		get_stable_customer_id()
	)

	# Phase 2A: the chair used to be released and marked for cleaning right
	# here. It no longer is - the same chair now carries the customer through
	# Relax and any further orders, and is only released when the visit
	# actually ends (see release_reserved_chair(), called from
	# begin_leaving()/finish_customer()/_exit_tree()).
	drinks_consumed_this_visit += 1

	# Phase 2B: exactly once per completed purchase, alongside the existing
	# payment signal above - money leaves the customer the same instant it
	# is recorded as tavern income.
	if needs != null:
		needs.adjust(&"wealth", -payment_amount)
		needs.adjust(&"drinks_consumed", 1.0)

		if _balance_config != null:
			needs.adjust(
				&"thirst",
				-_balance_config.thirst_reduction_per_drink
			)

			var temperance: float = 0.5

			if (
				customer_type != null
				and customer_type.personality != null
			):
				temperance = customer_type.personality.temperance

			needs.adjust(
				&"intoxication",
				ordered_drink.alcohol_strength
				* _balance_config.intoxication_gain_scale
				* (2.0 - temperance)
			)

	ordered_drink = null
	has_had_a_drink = true
	_has_drink_to_consume = false

	if _report_manager != null:
		_report_manager.record_payment(runtime_customer_id)

		if needs != null:
			_report_manager.record_drink_consumed(
				runtime_customer_id,
				needs.wealth,
				needs.thirst,
				needs.mood,
				needs.intoxication
			)

	if _is_ai_debug_enabled():
		var limit: int = get_effective_drink_limit()

		print(
			"[CustomerAI] ", name,
			" drinks_consumed_this_visit=", drinks_consumed_this_visit,
			"/", limit,
			" chair_reserved=", (reserved_chair != null),
			" money=", (needs.wealth if needs != null else -1),
			" thirst=", (needs.thirst if needs != null else -1.0),
			" intoxication=", (needs.intoxication if needs != null else -1.0)
		)

	if _brain != null:
		# Re-evaluate rather than always leaving directly - Relax, another
		# Order, or Leave all compete on utility from here. See
		# docs/CUSTOMER_AI_SYSTEM.md's Phase 2A section.
		_brain.think()
	else:
		begin_leaving()


## A stable identifier for this customer for the lifetime of the visit.
##
## Uses the instance id rather than runtime_customer_id, which is only
## allocated when a diagnostics report manager is present and is -1 otherwise.
## Daily statistics must count unique people whether or not diagnostics are on.
func get_stable_customer_id() -> StringName:
	return StringName("customer_%d" % get_instance_id())


func _on_patience_expired() -> void:
	if current_state != State.ORDERING:
		return

	order_icon.visible = false
	patience_bar.hide_bar()

	if should_show_debug_messages():
		print(
			name,
			" ran out of patience and is leaving."
		)

	ordered_drink = null
	departure_reason = &"patience_expired"

	# Phase 3A: nobody is waiting any more, so any serve task for this
	# customer describes work that no longer needs doing.
	service_state_changed.emit(self)

	if needs != null and _balance_config != null:
		needs.adjust(
			&"mood",
			-_balance_config.satisfaction_loss_on_patience_expiry
		)

	if _brain != null:
		# Mandatory, not a normal decision: running out of patience must
		# result in leaving, not compete with whatever else happens to be
		# scoring well at that instant. See CustomerBrain.force_activity's
		# doc comment and docs/CUSTOMER_AI_SYSTEM.md.
		if not _brain.force_activity(&"leave", &"patience_expired"):
			begin_leaving()
	else:
		begin_leaving()


## Read by CustomerBrain (via ActivityContext.domain_flags) so
## DomainFlagCondition can gate activities on this customer's concrete
## state without the activity framework itself knowing what a customer is.
## Phase 2C: CustomerAIBalanceConfig.maximum_drinks_per_visit scaled by
## Personality.preferred_drink_count_multiplier, clamped to
## CustomerAIBalanceConfig.absolute_maximum_drinks_per_visit regardless -
## see docs/CUSTOMER_AI_SYSTEM.md's Phase 2C "Drink-limit preparation".
func get_effective_drink_limit() -> int:
	if _balance_config == null:
		return 2

	var multiplier: float = 1.0

	if customer_type != null and customer_type.personality != null:
		multiplier = customer_type.personality.preferred_drink_count_multiplier

	var typical: int = roundi(
		float(_balance_config.maximum_drinks_per_visit) * multiplier
	)

	return clampi(
		typical,
		1,
		_balance_config.absolute_maximum_drinks_per_visit
	)


func get_activity_flags() -> Dictionary:
	var limit: int = get_effective_drink_limit()

	var away_from_chair: bool = (
		current_state == State.MOVING_TO_ACTIVITY
		or current_state == State.USING_ACTIVITY
		or current_state == State.RETURNING_TO_SEAT
	)

	return {
		&"is_seated": reserved_chair != null,
		&"has_ordered_drink": ordered_drink != null,
		&"has_drink_to_consume": _has_drink_to_consume,
		&"under_drink_limit": drinks_consumed_this_visit < limit,
		&"has_social_partner": find_nearby_social_partner(
			_balance_config.social_discovery_range_pixels
			if _balance_config != null else 220.0
		) != null,
		&"is_at_chair": reserved_chair != null and not away_from_chair,
	}


## Read by CustomerBrain when reporting a decision to CustomerAIReportManager
## - see _report_decision() there. Kept separate from get_activity_flags()
## because that dictionary is bool-only (DomainFlagCondition's contract);
## this one carries the richer typed values a diagnostic record needs.
func get_diagnostics_snapshot() -> Dictionary:
	return {
		"money": needs.wealth if needs != null else 0,
		"thirst": needs.thirst if needs != null else 0.0,
		"satisfaction": needs.mood if needs != null else 0.0,
		"intoxication": needs.intoxication if needs != null else 0.0,
		"visit_time_remaining_minutes": (
			needs.remaining_visit_minutes if needs != null else 0.0
		),
		"drinks_consumed": drinks_consumed_this_visit,
		"has_active_order": ordered_drink != null,
		"engagement": needs.engagement if needs != null else 0.0,
		"current_activity_point": (
			String(_current_activity_point.activity_id)
			if _current_activity_point != null else ""
		),
		"social_partner_customer_id": (
			social_partner.runtime_customer_id
			if social_partner != null and is_instance_valid(social_partner)
			else -1
		),
	}


func should_show_debug_messages() -> bool:
	if game_config == null:
		return true

	return game_config.show_debug_messages


## Phase 2A: gates the extra print()s this file adds for drink-limit/chair-
## lifecycle diagnostics (requirement 8). Separate from
## should_show_debug_messages(). Phase 2B: reads
## CustomerAIDiagnosticsConfig.console_debug_enabled - the same switch
## CustomerBrain logs against - moved off GameConfig so every Customer AI
## debug/diagnostic setting lives in one dedicated resource.
func _is_ai_debug_enabled() -> bool:
	return (
		_diagnostics_config != null
		and _diagnostics_config.console_debug_enabled
	)


## The reason recorded for this departure, never left as "unknown" when the
## customer is plainly part of a group.
##
## A member removed while still IN_GROUP or MOVING_TO_GROUP_SLOT used to be
## filed as "unknown", which said nothing about what had actually gone wrong.
## Group membership is enough to name it.
func _resolve_departure_reason() -> StringName:
	if not departure_reason.is_empty():
		return departure_reason

	if has_group():
		match current_state:
			State.IN_GROUP, State.MOVING_TO_GROUP_SLOT, \
			State.GROUP_INSIDE_STAGING:
				return &"group_departure"
			State.GROUP_WAITING_OUTSIDE, State.GROUP_ENTERING:
				return &"group_entry_abandoned"
			_:
				return &"group_departure"

	return &"unknown"


## The owning group's state, for the diagnostic record. Empty when solo.
func _describe_group_state() -> String:
	if not is_instance_valid(group_controller):
		return ""

	if group_controller.has_method(&"get_state_label"):
		return String(group_controller.call(&"get_state_label"))

	return ""


func finish_customer() -> void:
	actor_navigation.stop()
	_cancel_all_scheduled()

	order_icon.visible = false
	patience_bar.hide_bar()

	# Phase 3A safety net: a customer removed while still nominally waiting
	# (an invalid destination, a developer tool) must not leave a serve task
	# pointing at them. The board would sweep it eventually; saying so here
	# means it never has to.
	service_state_changed.emit(self)

	# One departure announcement, at the single point every exit funnels
	# through, carrying enough for a listener to tell a satisfied customer
	# from a lost one.
	customer_departed.emit(
		self,
		_resolve_departure_reason(),
		drinks_consumed_this_visit > 0
	)

	if _report_manager != null and needs != null:
		var limit: int = get_effective_drink_limit()

		_report_manager.record_group_state(
			runtime_customer_id, _describe_group_state()
		)

		_report_manager.record_departure(
			runtime_customer_id,
			_resolve_departure_reason(),
			needs.wealth,
			needs.thirst,
			needs.mood,
			needs.intoxication,
			drinks_consumed_this_visit >= limit
		)

	# Normally a no-op here - begin_leaving() already released the chair on
	# the way to the door. Kept as a safety net for handle_invalid_destination()
	# reaching finish_customer() directly while still seated, and for
	# consistency with _exit_tree() below.
	release_reserved_chair()
	release_group_activity_reservation()
	hide_group_order_icon()

	customer_finished.emit(self)
	queue_free()


## Defensive safety net for a customer forcibly removed or freed outside the
## normal begin_leaving()/finish_customer() paths (a future dev tool, a scene
## reload) - see docs/CUSTOMER_AI_SYSTEM.md's Phase 2A section. Idempotent:
## release_reserved_chair() is a no-op if the chair was already released.
func _exit_tree() -> void:
	if reserved_chair != null and _report_manager != null:
		# Normal departure always calls release_reserved_chair() via
		# begin_leaving()/finish_customer() before the node is ever freed -
		# reaching here with a chair still reserved means this customer was
		# removed outside that path, which is exactly how a reservation leak
		# would start.
		_report_manager.report_issue(
			runtime_customer_id,
			&"reservation_leak_precursor",
			"Customer freed while still holding a chair reservation ('"
			+ reserved_chair.name
			+ "') - being freed outside the normal departure path.",
			get_diagnostics_snapshot()
		)

	release_reserved_chair()
	release_group_activity_reservation()


# --- Group visits ------------------------------------------------------------
#
# A group member is an ordinary customer with a destination chosen by its group
# instead of by its own utility brain. Everything below only sets intent - the
# existing navigation, avoidance and stuck recovery carry it out unchanged,
# which is why groups needed no navigation work at all.


func has_group() -> bool:
	return not group_id.is_empty()


## Stamps this customer as part of [param new_group_id].
##
## One entry point for membership so the diagnostic record learns the group id
## at the same moment the customer does. [CustomerGroup] used to set() the
## property directly, which worked but left the report with no group column.
func join_group(new_group_id: StringName, controller: Node) -> void:
	group_id = new_group_id
	group_controller = controller

	if _report_manager != null:
		_report_manager.record_group_context(
			runtime_customer_id, String(new_group_id)
		)


## Clears this customer's group membership. Idempotent.
func leave_group() -> void:
	group_id = &""
	group_controller = null
	group_slot_position = Vector2.ZERO
	group_centre_position = Vector2.ZERO
	delivery_slot_position = Vector2.ZERO
	is_stepped_back_for_delivery = false

	hide_group_order_icon()


## Holds a group member safely outside until the group releases it.
func wait_for_group_entry(queue_position: Vector2) -> void:
	_cancel_all_scheduled()
	_set_state(State.GROUP_WAITING_OUTSIDE)
	_group_wait_started_msec = Time.get_ticks_msec()
	_group_entry_started_msec = -1
	global_position = queue_position
	actor_navigation.park()


## Starts the controlled doorway crossing for this member.
func begin_group_entry() -> void:
	_group_entry_started_msec = Time.get_ticks_msec()
	_set_state(State.GROUP_ENTERING)
	_travel_to(
		entrance_inside_position,
		navigation_arrival_distance,
		"group entrance"
	)


func _on_group_entry_crossed() -> void:
	_group_wait_started_msec = -1
	_group_entry_started_msec = -1
	_set_state(State.GROUP_INSIDE_STAGING)
	actor_navigation.park()
	group_entry_crossed.emit(self)


## Sends this member to a standing position assigned by its group.
func assign_group_position(
	target: Vector2,
	centre: Vector2
) -> void:
	group_slot_position = target
	group_centre_position = centre

	_cancel_all_scheduled()

	_set_state(State.MOVING_TO_GROUP_SLOT)

	_travel_to(
		target,
		navigation_arrival_distance,
		"group position"
	)


## Sends this member to a chair the group reserved on its behalf.
##
## The chair is already booked by the group, so this hands it over rather than
## reserving again - a second reservation would fail against the group's own.
func assign_group_chair(chair: Node) -> void:
	var seat: Chair = chair as Chair

	if seat == null:
		handle_invalid_destination()
		return

	# Take ownership of the reservation. The group booked this chair as the
	# group, but from here the member is who sits in it and who releases it -
	# and Reservable ignores a release from anyone but the holder, so without
	# this handover the chair would never be freed.
	seat.transfer_reservation(self)

	reserved_chair = seat

	begin_moving_to_seat()


func _on_reached_group_slot() -> void:
	_set_state(State.IN_GROUP)

	# Face roughly toward the group, not exactly - see GroupFormation.
	var facing: Vector2 = GroupFormation.get_facing(
		global_position, group_centre_position
	)

	if facing.length_squared() > 0.001:
		_update_facing(facing)

	# Stagger the first drink so members do not all reach for the cask on the
	# same tick. Without this a group drinks in lockstep, which reads as
	# obviously scripted.
	next_group_drink_minutes = _get_world_minutes() + randi_range(2, 5)


## Sends this member outward so staff can reach the middle of the group.
##
## The tavern hand could not get to the centre: the ring of members is not
## occupying the delivery point, but their avoidance radii close the gaps
## between them, and the carried keg has nowhere to be put down. Stepping
## outward for the length of the delivery opens a real path without touching
## collision shapes or letting staff walk through anybody.
func begin_delivery_step_back(target: Vector2) -> void:
	delivery_slot_position = target
	is_stepped_back_for_delivery = true

	_cancel_all_scheduled()

	_set_state(State.MOVING_TO_GROUP_SLOT)

	_travel_to(
		target,
		navigation_arrival_distance,
		"stepping back for delivery"
	)


## Re-issues the step-back journey. Part of the bounded clearance recovery.
func refresh_delivery_step_back() -> void:
	if delivery_slot_position == Vector2.ZERO:
		return

	group_slot_recoveries += 1

	if _report_manager != null:
		_report_manager.record_navigation_recovery(runtime_customer_id)

	begin_delivery_step_back(delivery_slot_position)


## Accepts this member as clear without waiting for it to finish walking.
func accept_delivery_clearance(snap_to_slot: bool = false) -> void:
	if snap_to_slot and delivery_slot_position != Vector2.ZERO:
		global_position = delivery_slot_position

	actor_navigation.park()

	if current_state != State.IN_GROUP:
		_set_state(State.IN_GROUP)


## Puts this member back on its original drinking slot after a delivery.
func end_delivery_step_back() -> void:
	is_stepped_back_for_delivery = false
	delivery_slot_position = Vector2.ZERO

	if group_slot_position == Vector2.ZERO:
		return

	_cancel_all_scheduled()

	_set_state(State.MOVING_TO_GROUP_SLOT)

	_travel_to(
		group_slot_position,
		navigation_arrival_distance,
		"reforming after delivery"
	)


## How far this member is from a point, for clearance checks.
func get_distance_to(point: Vector2) -> float:
	return global_position.distance_to(point)


# --- Group order icon --------------------------------------------------------
#
# Reuses the same OrderIcon sprite a solo customer uses. There is deliberately
# no second icon system: the group simply asks its leader to show the one this
# customer already owns.

## True while this customer is showing its group's order icon.
var _showing_group_order_icon: bool = false


## Shows the shared-order icon above this member, as the group's leader.
func show_group_order_icon(texture: Texture2D) -> void:
	if texture != null:
		order_icon.texture = texture

	order_icon.modulate = Color.WHITE
	order_icon.visible = true

	_showing_group_order_icon = true


## Hides the group order icon. Idempotent, and safe on a non-leader.
func hide_group_order_icon() -> void:
	if not _showing_group_order_icon:
		return

	_showing_group_order_icon = false

	order_icon.visible = false
	order_icon.modulate = Color.WHITE


func is_showing_group_order_icon() -> bool:
	return _showing_group_order_icon


## Re-issues the journey to this member's assigned formation slot.
##
## Used by the group's bounded assembly recovery. Deliberately goes back
## through assign_group_position() so there is one path to a slot, not two.
func refresh_group_slot() -> void:
	if group_slot_position == Vector2.ZERO:
		return

	group_slot_recoveries += 1

	if _report_manager != null:
		_report_manager.record_navigation_recovery(runtime_customer_id)
		_report_manager.record_group_slot_recovery(runtime_customer_id)

	assign_group_position(group_slot_position, group_centre_position)


## Accepts this member as arrived at its slot without waiting for navigation.
##
## The group calls this when a member is already within tolerance, or when
## every retry has been used and the member has to be placed. The member is
## never removed or abandoned - it joins the group either way.
func accept_group_slot_arrival(snap_to_slot: bool = false) -> void:
	if current_state == State.IN_GROUP:
		return

	if snap_to_slot and group_slot_position != Vector2.ZERO:
		global_position = group_slot_position

	group_slot_recoveries += 1

	if _report_manager != null:
		_report_manager.record_group_slot_recovery(runtime_customer_id)

	actor_navigation.park()

	_on_reached_group_slot()


## True when this member is ready for another pull from the shared serving.
func is_ready_for_group_drink() -> bool:
	if current_state != State.IN_GROUP:
		return false

	# A member that has had its fill stops taking portions. Without this the
	# rotation kept handing the keg to somebody who should have stopped.
	if drinks_consumed_this_visit >= get_effective_drink_limit():
		return false

	return _get_world_minutes() >= next_group_drink_minutes


## Records that this member just drank, and sets the next opportunity.
##
## [param drink] is the shared serving's drink, used for intoxication. It is
## optional so the existing single-argument call site keeps working.
func on_group_drink_taken(
	minutes_between: int,
	drink: DrinkDefinition = null
) -> void:
	drinks_consumed_this_visit += 1
	shared_drinks_consumed += 1
	has_had_a_drink = true

	# Jittered rather than fixed, so the group keeps drifting out of sync
	# instead of settling into a rhythm.
	next_group_drink_minutes = (
		_get_world_minutes() + minutes_between + randi_range(0, 2)
	)

	# Drinking satisfies thirst. Uses the generic adjust() rather than a
	# drink-specific call so the needs model stays unaware of groups.
	if needs != null:
		if _balance_config != null:
			needs.adjust(
				&"thirst",
				-_balance_config.thirst_reduction_per_drink
			)
		else:
			needs.adjust(&"thirst", -0.35)

		needs.adjust(&"drinks_consumed", 1.0)

		_apply_group_intoxication(drink)

	# The report's drinks_consumed comes from here, not from the counter
	# above. Keg drinking used to reduce thirst while every group member was
	# reported as having consumed nothing at all.
	if _report_manager != null and needs != null:
		_report_manager.record_drink_consumed(
			runtime_customer_id,
			needs.wealth,
			needs.thirst,
			needs.mood,
			needs.intoxication
		)
		_report_manager.record_shared_drink(runtime_customer_id)


## Applies the same intoxication maths an individually served drink uses.
func _apply_group_intoxication(drink: DrinkDefinition) -> void:
	if needs == null or _balance_config == null or drink == null:
		return

	var temperance: float = 0.5

	if customer_type != null and customer_type.personality != null:
		temperance = customer_type.personality.temperance

	needs.adjust(
		&"intoxication",
		drink.alcohol_strength
		* _balance_config.intoxication_gain_scale
		* (2.0 - temperance)
	)


# --- Group leisure -----------------------------------------------------------
#
# The group decides WHEN a member takes a break and WHICH break it is; the
# member performs it with the same methods a solo customer uses. There is
# deliberately no group-only darts, socialising or relaxing implementation -
# begin_relaxing(), begin_socialising() and begin_visiting_activity() below are
# the same calls CustomerBrain's behaviours make.


## Whether this member is standing with its group and free to do something.
func is_group_member_idle() -> bool:
	return has_group() and current_state == State.IN_GROUP


## Whether this member is part-way through a leisure activity.
func is_group_member_busy() -> bool:
	return current_state in [
		State.RELAXING,
		State.SOCIALISING,
		State.MOVING_TO_ACTIVITY,
		State.USING_ACTIVITY,
		State.RETURNING_TO_SEAT,
	]


## Books [param point] for this member and sends it there.
##
## The reservation goes through the ordinary [Reservable] on the activity
## point, so a group member and a solo customer compete for the darts board on
## exactly equal terms.
func begin_group_activity(point: TavernActivityPoint) -> bool:
	if point == null or point.reservable == null:
		return false

	if not point.reservable.reserve(self):
		return false

	group_activity_reservation = point.reservable
	last_group_activity_id = point.activity_id

	begin_visiting_activity(point)

	return true


## Starts a relax at this member's own group slot. No chair is involved.
func begin_group_relax(
	minimum_minutes: float,
	maximum_minutes: float
) -> void:
	last_group_activity_id = &"relax"

	begin_relaxing(minimum_minutes, maximum_minutes)


## Starts a conversation with [param partner], both standing at their slots.
func begin_group_socialise(
	partner: Customer,
	minimum_minutes: float,
	maximum_minutes: float,
	satisfaction_gain: float,
	partner_satisfaction_gain: float,
	engagement_gain: float
) -> void:
	last_group_activity_id = &"socialise"

	begin_socialising(
		partner,
		minimum_minutes,
		maximum_minutes,
		true,
		satisfaction_gain,
		partner_satisfaction_gain,
		engagement_gain
	)


## Sends a group member back to its assigned formation slot.
##
## Reuses RETURNING_TO_SEAT rather than adding a state: the meaning is
## identical - going back to where the visit is anchored - and _on_returned_
## to_seat() already branches on group membership.
func begin_returning_to_group_slot() -> void:
	_current_activity_point = null

	release_group_activity_reservation()

	if group_slot_position == Vector2.ZERO:
		if is_instance_valid(group_controller):
			_set_state(State.IN_GROUP)
			_notify_group_member_returned()
		else:
			handle_invalid_destination()

		return

	_set_state(State.RETURNING_TO_SEAT)

	_travel_to(
		group_slot_position,
		navigation_arrival_distance,
		"back to group slot"
	)


## Ends any leisure activity immediately, releasing whatever it held.
##
## Called by the group when it starts recalling. Safe from any state, and safe
## to call more than once.
func cancel_group_activity() -> void:
	_cancel_all_scheduled()

	release_group_activity_reservation()

	social_partner = null
	_current_activity_point = null

	order_icon.visible = false
	order_icon.modulate = Color.WHITE


## Returns the activity point booking, if this member holds one. Idempotent.
func release_group_activity_reservation() -> void:
	if group_activity_reservation == null:
		return

	var held: Reservable = group_activity_reservation

	group_activity_reservation = null

	if is_instance_valid(held) and held.is_held_by(self):
		held.release(self)


## Sends a group member back to its slot after finishing a leisure activity.
##
## Returns true when this customer is a group member and has been handled, so
## the caller knows not to fall through to the solo brain.
func _return_group_member_after_activity(activity_id: StringName) -> bool:
	if not has_group() or not is_instance_valid(group_controller):
		return false

	last_group_activity_id = activity_id

	if group_controller.has_method(&"on_member_activity_finished"):
		group_controller.call(&"on_member_activity_finished", self, activity_id)

	begin_returning_to_group_slot()

	return true


func _notify_group_member_returned() -> void:
	if not is_instance_valid(group_controller):
		return

	if group_controller.has_method(&"on_member_returned_to_slot"):
		group_controller.call(&"on_member_returned_to_slot", self)


## Called by the group when the whole party is leaving.
func begin_group_departure() -> void:
	cancel_group_activity()
	hide_group_order_icon()

	is_stepped_back_for_delivery = false
	delivery_slot_position = Vector2.ZERO

	if current_state == State.LEAVING_TO_DOOR or current_state == State.EXITING:
		return

	departure_reason = &"group_departure"

	begin_leaving()


func _update_facing(direction: Vector2) -> void:
	# Uses whatever facing hook the sprite already exposes; silently does
	# nothing when there is none, so this never becomes a hard dependency.
	if has_method(&"set_facing_direction"):
		call(&"set_facing_direction", direction)
	elif customer_sprite != null:
		customer_sprite.flip_h = direction.x < 0.0


func _get_world_minutes() -> int:
	var world_time: Node = get_node_or_null(^"/root/WorldTime")

	if world_time == null or not world_time.has_method(&"get_timestamp"):
		return 0

	var stamp: Variant = world_time.call(&"get_timestamp")

	return int(stamp.total_minutes) if stamp != null else 0


# --- Diagnostics -------------------------------------------------------------


## Sets the state and records it for the diagnostics report.
##
## Every state change goes through here rather than assigning current_state
## directly. That is the point: a lifecycle trail with gaps in it is worse
## than none, because it makes a stuck visit look like it stopped somewhere it
## did not.
func _set_state(next_state: State) -> void:
	if current_state == next_state:
		return

	current_state = next_state

	if next_state == State.EXITING:
		_exit_started_minutes = _get_world_minutes()

	if _report_manager == null:
		# Resolve lazily: the first state change can happen before the AI is
		# configured, and a trail with a hole at the start is misleading.
		var found: Array[Node] = get_tree().get_nodes_in_group(
			&"customer_ai_report_manager"
		)

		if not found.is_empty():
			_report_manager = found[0]

	if _report_manager == null:
		return

	_report_manager.record_state(
		runtime_customer_id,
		State.keys()[next_state],
		float(_get_world_minutes())
	)

	# The two milestones that answer "did this customer actually get in, and
	# did it ever sit down?".
	match next_state:
		State.WALKING_TO_STAGING:
			_report_manager.record_reached_inside(
				runtime_customer_id, float(_get_world_minutes())
			)

		State.WAITING_TO_ORDER:
			_report_manager.record_seated(
				runtime_customer_id, float(_get_world_minutes())
			)

		State.ORDERING:
			_report_manager.record_first_order(
				runtime_customer_id, float(_get_world_minutes())
			)


## Current position and destination, for the report exporter.
func report_position_to(manager: Node, door_position: Vector2) -> void:
	if manager == null or not manager.has_method(&"record_position"):
		return

	var target: Vector2 = Vector2.ZERO
	var label: String = ""

	if navigation_agent != null and navigation_agent.target_position != Vector2.ZERO:
		target = navigation_agent.target_position
		label = State.keys()[current_state]

	manager.call(
		&"record_position",
		runtime_customer_id,
		global_position,
		door_position,
		target,
		label
	)
