class_name GroupSpawner
extends Node

## Creates a whole group visit as one decision.
##
## Deliberately separate from the solo spawn path in [GameManager] rather than
## folded into it. The solo path refuses to create a customer unless a chair is
## free - correct for one visitor, wrong for a group, which may be standing.
## Keeping them apart means group spawning could be added without touching the
## working solo loop at all.
##
## One spawn decision produces several customers, all stamped with the same
## group id and entering together with a small stagger so they do not appear
## inside one another.


signal group_spawned(group: CustomerGroup)
signal group_rejected(reason: StringName)


@export_category("Scenes")

@export var customer_scene: PackedScene

## Where group nodes and members are parented.
@export var entities_path: NodePath


@export_category("Definitions")

## Group archetypes that may visit. Weighted by their own spawn_weight.
@export var group_definitions: Array[CustomerGroupDefinition] = []

## Customer archetypes members are drawn from.
@export var customer_types: Array[CustomerType] = []

## True while the party currently being built is a Captain-and-crew group.
var _spawning_captain_group: bool = false


@export_category("Rates")

## Relative weight of a group arriving rather than a single customer.
##
## Compared against [member individual_visit_weight]. 1.0 against 4.0 means
## roughly one visit in five is a group.
@export_range(0.0, 100.0, 0.1)
var group_visit_weight: float = 1.0

@export_range(0.0, 100.0, 0.1)
var individual_visit_weight: float = 4.0


@export_category("Developer Actions")

## Definition used by the F10 "Spawn Test Group" action.
@export_file("*.tres")
var test_group_definition_path: String = "res://Data/groups/dock_workers.tres"

## Party size the F10 action creates.
@export_range(2, 8, 1)
var test_group_size: int = 4

## Drink the test group must order. Empty leaves selection weighted as usual.
@export var test_group_drink_id: StringName = &"ale"

## Serving format the test group must order.
@export var test_group_serving_format_id: StringName = &"table_cask"


@export_category("Spawning")

## Spacing between members as they appear, in pixels.
@export_range(0.0, 128.0, 1.0)
var member_spacing: float = 28.0

## Seconds between each member entering, so a crew files in.
@export_range(0.0, 5.0, 0.05)
var member_entry_delay: float = 0.5


@export_category("References")

@export var registry: BeverageRegistry
@export var vessel_pool: VesselPool
@export var group_manager: GroupManager
@export var game_config: GameConfig

## The tavern door. Found automatically when left unset.
@export var customer_door: CustomerDoor


var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _entities: Node = null
var _game_manager: Node = null


func _ready() -> void:
	add_to_group(&"group_spawner")

	_rng.randomize()

	if not entities_path.is_empty():
		_entities = get_node_or_null(entities_path)

	if _entities == null:
		_entities = get_parent()

	if registry == null:
		registry = load("res://Data/beverage/beverage_registry.tres")

	if group_manager == null:
		var found: Array[Node] = get_tree().get_nodes_in_group(&"group_manager")

		if not found.is_empty():
			group_manager = found[0] as GroupManager

	if _entities != null and _entities.name == "Managers":
		# Members are entities, not managers. Without this they are parented
		# beside the spawner, which makes every diagnostic path in the scene
		# read oddly and keeps customers out of the Entities subtree.
		var entities: Node = _entities.get_parent().get_node_or_null(^"Entities")

		if entities != null:
			_entities = entities

	if customer_types.is_empty():
		_borrow_customer_types()


## Falls back to the GameManager's archetype list when none are configured.
##
## An unconfigured spawner would otherwise produce groups with no members and
## reject every visit silently. Borrowing keeps one list of customer types in
## the project rather than a second copy that can drift out of step.
func _borrow_customer_types() -> void:
	var game_manager: Node = get_parent().get_node_or_null(^"GameManager")

	if game_manager == null:
		return

	var borrowed: Variant = game_manager.get(&"customer_types")

	if borrowed == null:
		return

	for entry: Variant in borrowed:
		var customer_type: CustomerType = entry as CustomerType

		if customer_type != null:
			customer_types.append(customer_type)

	if customer_types.is_empty():
		push_warning(
			"GroupSpawner has no customer_types and could not borrow any. "
			+ "No group will ever spawn."
		)


## Whether the next arrival should be a group rather than a lone customer.
func should_spawn_group() -> bool:
	var total: float = group_visit_weight + individual_visit_weight

	if total <= 0.0:
		return false

	return _rng.randf() * total < group_visit_weight


## Creates a group visit. Returns null when one cannot be started.
func spawn_group(
	spawn_position: Vector2,
	forced_definition: CustomerGroupDefinition = null,
	forced_size: int = 0,
	maximum_members: int = -1
) -> CustomerGroup:
	if customer_scene == null:
		push_error("GroupSpawner has no customer_scene.")
		return null

	var definition: CustomerGroupDefinition = (
		forced_definition if forced_definition != null
		else _choose_definition()
	)

	if definition == null:
		group_rejected.emit(&"no_definition")
		return null

	# Reject before creating a group or customer node when the full minimum
	# party cannot fit. This prevents half-created groups from leaking into the
	# active-customer roster.
	if maximum_members >= 0 and maximum_members < definition.minimum_size:
		group_rejected.emit(&"population_limit")
		return null

	var effective_maximum: int = definition.maximum_size
	if maximum_members >= 0:
		effective_maximum = mini(effective_maximum, maximum_members)

	var size: int = (
		forced_size if forced_size > 0 else definition.choose_size(_rng)
	)
	size = clampi(size, definition.minimum_size, effective_maximum)

	if group_manager != null and not group_manager.can_spawn_group(size):
		group_rejected.emit(&"group_limit")
		return null

	var group: CustomerGroup = CustomerGroup.new()
	group.name = "Group_%d" % Time.get_ticks_usec()
	group.definition = definition
	group.beverage_registry = registry
	group.vessel_pool = vessel_pool
	group.member_entry_delay = member_entry_delay

	_entities.add_child(group)

	# Rolled once for the whole party, before anybody spawns, so a group is
	# either Captain-and-crew or it is not - never half of one.
	_spawning_captain_group = (
		_find_captain_type(definition) != null
		and _rng.randf() < (
			definition.captain_chance if definition != null else 0.0
		)
	)

	for index: int in range(size):
		var member: Node = _spawn_member(
			spawn_position, index, definition
		)

		if member == null:
			continue

		group.add_member(member)

	if group.get_valid_members().is_empty():
		group.queue_free()
		group_rejected.emit(&"no_members")
		return null

	_apply_leader_rule(group, definition)

	if _spawning_captain_group and group.has_captain():
		print(
			"[Group %s] Captain-and-crew group created; leader is %s."
			% [String(group.group_id), group.leader.name]
		)

	group.set_state(CustomerGroup.State.ENTERING)

	if group_manager != null:
		group_manager.register_group(group)

	# Every spawn path registers, not just the developer one: a member that
	# never enters active_customers is never released from it either.
	register_members_with_game_manager(group)

	group_spawned.emit(group)

	return group


## The developer "Spawn Test Group of N" action.
##
## Deliberately the production path: it calls the same [method spawn_group]
## automatic arrivals use, and then registers the members exactly as
## [GameManager] does for an automatic group. A separate test implementation
## would prove nothing about the game.
##
## Uses the Dock Workers definition because it prefers standing, which is the
## simplest complete destination in the tavern, and prefers ale.
func spawn_test_group(size: int = 4) -> CustomerGroup:
	var definition: CustomerGroupDefinition = load(
		test_group_definition_path
	) as CustomerGroupDefinition

	if definition == null:
		push_error(
			"GroupSpawner could not load the test group definition at "
			+ test_group_definition_path
		)
		return null

	var door: CustomerDoor = _find_door()
	var spawn_position: Vector2 = (
		door.get_spawn_position() if door != null else Vector2.ZERO
	)

	var group: CustomerGroup = spawn_group(spawn_position, definition, size)

	if group == null:
		return null

	# Pinned so the milestone loop is repeatable: the same crew, the same ale,
	# the same small keg, every time the key is pressed.
	group.required_drink_id = test_group_drink_id
	group.required_serving_format_id = test_group_serving_format_id

	register_members_with_game_manager(group)

	return group


## Puts every member on the normal active-customer roster.
##
## Panel and F10 spawns previously bypassed [GameManager], so their members
## never entered active_customers and never had customer_finished connected -
## which is how a test group quietly leaked population slots.
func register_members_with_game_manager(group: CustomerGroup) -> void:
	var manager: Node = _find_game_manager()

	if manager == null or not manager.has_method(&"_register_group_member"):
		return

	for member: Node in group.get_valid_members():
		manager.call(&"_register_group_member", member)


func _find_game_manager() -> Node:
	if _game_manager != null and is_instance_valid(_game_manager):
		return _game_manager

	_game_manager = get_parent().get_node_or_null(^"GameManager")

	if _game_manager == null:
		for node: Node in get_tree().get_nodes_in_group(&"game_manager"):
			_game_manager = node
			break

	return _game_manager


func _spawn_member(
	spawn_position: Vector2,
	index: int,
	definition: CustomerGroupDefinition
) -> Node:
	var customer_type: CustomerType = null

	# The first member is the Captain when this party rolled one. First rather
	# than random so the Captain leads the way in and lands in the leader slot
	# the formation already reserves for whoever arrives first.
	if index == 0 and _spawning_captain_group:
		customer_type = _find_captain_type(definition)

	if customer_type == null:
		customer_type = _choose_customer_type(definition)

	if customer_type == null:
		return null

	var member: Node = customer_scene.instantiate()

	# Named before it enters the tree so diagnostics read "Crew3_Member2"
	# rather than "@CharacterBody2D@186", which is the difference between a
	# usable group report and a wall of engine ids.
	member.name = "%s_M%d" % [
		String(definition.group_id) if definition != null else "group",
		index + 1,
	]

	_entities.add_child(member)

	# Queue members outside in a line extending away from the doorway. A ring
	# surrounds the entrance and makes later members block the leader.
	var door: CustomerDoor = _find_door()
	var queue_position: Vector2 = spawn_position

	if door != null and door.has_method(&"get_group_queue_position"):
		queue_position = door.get_group_queue_position(index, member_spacing, 2)
	elif door != null:
		queue_position = door.get_queue_position(index, member_spacing)
	else:
		var row: int = floori(float(index) / 2.0)
		var column: int = index % 2
		queue_position += Vector2(
			(float(column) - 0.5) * member_spacing,
			member_spacing * float(row + 1)
		)

	member.global_position = queue_position

	# Door targets are set here rather than by the caller. Spawning a group
	# from the debug panel bypasses GameManager entirely, and members without
	# their own door points all walk to the same coordinate and jam the
	# doorway - which is the failure this whole spread exists to prevent.
	_assign_door_targets(member)

	if member.has_method(&"configure"):
		# Group members are ordinary customers and need the same AI
		# configuration as a solo visitor. Passing nulls here left them with
		# no needs model, so drinking from the group's keg could not move
		# thirst, intoxication or satisfaction at all.
		var manager: Node = _find_game_manager()

		member.call(
			&"configure",
			game_config,
			customer_type,
			manager.get(&"activity_registry") if manager != null else null,
			manager.get(&"customer_ai_balance") if manager != null else null,
			manager.get(&"customer_ai_diagnostics") if manager != null else null,
			manager.get(&"customer_ai_report_manager") if manager != null else null
		)

	if member.has_method(&"wait_for_group_entry"):
		member.call(&"wait_for_group_entry", queue_position)

	return member


## Gives [param member] its own arrival and exit points at the door.
func _assign_door_targets(member: Node) -> void:
	if not member.has_method(&"set_door_targets"):
		return

	var door: CustomerDoor = _find_door()

	if door == null:
		return

	member.call(
		&"set_door_targets",
		door.get_inside_position(member),
		door.get_exit_position(member)
	)


func _find_door() -> CustomerDoor:
	if customer_door != null:
		return customer_door

	for node: Node in get_tree().get_nodes_in_group(&"customer_door"):
		customer_door = node as CustomerDoor

		if customer_door != null:
			return customer_door

	return null


func _choose_definition() -> CustomerGroupDefinition:
	var total: float = 0.0

	for definition: CustomerGroupDefinition in group_definitions:
		if definition != null:
			total += maxf(definition.spawn_weight, 0.0)

	if total <= 0.0:
		return null

	var roll: float = _rng.randf() * total

	for definition: CustomerGroupDefinition in group_definitions:
		if definition == null:
			continue

		roll -= maxf(definition.spawn_weight, 0.0)

		if roll <= 0.0:
			return definition

	return group_definitions.back()


## The Captain in this party, or null when it has none.
func _find_captain(
	members: Array[Node],
	definition: CustomerGroupDefinition
) -> Node:
	var category: StringName = (
		definition.captain_category if definition != null else &"captain"
	)

	for member: Node in members:
		if _is_of_category(member, category):
			return member

	return null


func _is_of_category(member: Node, category: StringName) -> bool:
	var customer_type: Variant = member.get(&"customer_type")

	if customer_type == null:
		return false

	return StringName(customer_type.get(&"customer_category")) == category


## The Captain customer type, or null when none is configured.
func _find_captain_type(definition: CustomerGroupDefinition) -> CustomerType:
	var category: StringName = (
		definition.captain_category if definition != null else &"captain"
	)

	for customer_type: CustomerType in customer_types:
		if customer_type != null and customer_type.customer_category == category:
			return customer_type

	return null


func _choose_customer_type(
	definition: CustomerGroupDefinition
) -> CustomerType:
	var allowed: Array[CustomerType] = []

	for customer_type: CustomerType in customer_types:
		if customer_type == null:
			continue

		# CustomerType has no stable id field yet, so archetype restriction
		# matches on the display name. Worth replacing with a real type_id
		# when CustomerType next gets touched - noted in the docs.
		var type_id: StringName = StringName(
			customer_type.display_name.to_snake_case()
		)

		if definition.allows_customer_type(type_id):
			allowed.append(customer_type)

	if allowed.is_empty():
		# The archetype restriction excluded everything. Better a mixed group
		# than no group, so fall back to any type rather than refusing.
		allowed = customer_types.duplicate()

	if allowed.is_empty():
		return null

	return allowed[_rng.randi_range(0, allowed.size() - 1)]


## Picks the leader according to the definition's rule.
func _apply_leader_rule(
	group: CustomerGroup,
	definition: CustomerGroupDefinition
) -> void:
	var members: Array[Node] = group.get_valid_members()

	if members.is_empty():
		return

	match definition.leader_rule:
		CustomerGroupDefinition.LeaderRule.RANDOM:
			group.set_leader(members[_rng.randi_range(0, members.size() - 1)])

		CustomerGroupDefinition.LeaderRule.CAPTAIN_IF_PRESENT:
			var captain: Node = _find_captain(members, definition)

			group.set_leader(captain if captain != null else members[0])

		CustomerGroupDefinition.LeaderRule.WEALTHIEST:
			var best: Node = members[0]
			var best_spend: float = -1.0

			for member: Node in members:
				var multiplier: Variant = member.get(&"payment_multiplier")
				var value: float = (
					float(multiplier) if multiplier != null else 1.0
				)

				if value > best_spend:
					best_spend = value
					best = member

			group.set_leader(best)

		_:
			group.set_leader(members[0])
