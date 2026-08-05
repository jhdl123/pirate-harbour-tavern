class_name CustomerGroupDefinition
extends Resource

## What kind of party this is.
##
## A group definition is the configurable half of a visit: how many people, how
## likely they are to share a drink, whether they will stand, how long they
## stay. The runtime [CustomerGroup] reads it and never hardcodes any of it.
##
## Adding a new archetype - a press gang, a wedding party, a governor's retinue -
## is one resource and a registry entry. No script changes.


## How the leader is picked out of the members.
enum LeaderRule {
	## Whoever spawned first.
	FIRST_MEMBER,

	## Chosen at random.
	RANDOM,

	## The member whose archetype has the highest spend multiplier - the
	## captain of the party rather than a random hand.
	WEALTHIEST,

	## The Captain, when the party has one; otherwise the first member.
	CAPTAIN_IF_PRESENT,
}


## What kind of place this group wants.
enum PlacePreference {
	## Sit if at all possible; stand only as a fallback.
	PREFER_SEATED,

	## Stand by choice, even when seats exist. Dock workers at the bar.
	PREFER_STANDING,

	## Take whatever is free first.
	NO_PREFERENCE,
}


@export_category("Identity")

@export var group_id: StringName = &""

@export var display_name: String = "Unnamed Group"

@export_multiline var description: String = ""


@export_category("Size")

@export_range(2, 50, 1)
var minimum_size: int = 2

@export_range(2, 50, 1)
var maximum_size: int = 4

## Relative chance of this archetype being chosen. Zero disables it.
@export_range(0.0, 100.0, 0.1)
var spawn_weight: float = 1.0

## Weights per size, as size to weight, e.g. {2: 3.0, 3: 2.0, 4: 1.0}.
##
## Empty means every size in range is equally likely. Authored as a dictionary
## rather than an array so a gap in the range is impossible to create by
## accident.
@export var size_weights: Dictionary = {}


@export_category("Members")

## Customer archetype ids this group may be built from.
##
## Empty means any archetype. Populated, the group draws only from these -
## a pirate crew is not half merchants.
@export var allowed_customer_type_ids: Array[StringName] = []

@export var leader_rule: LeaderRule = LeaderRule.FIRST_MEMBER

## Chance this group arrives led by a Captain rather than an ordinary member.
##
## Data, not a hard-coded roll: a merchant party and a pirate crew want very
## different odds, and a Captain is never required for a keg order.
@export_range(0.0, 1.0, 0.05)
var captain_chance: float = 0.25

## The customer-type category a Captain has. Matched against
## [member CustomerType.customer_category] rather than a display name.
@export var captain_category: StringName = &"captain"


@export_category("Place")

@export var place_preference: PlacePreference = PlacePreference.PREFER_SEATED

## Whether this group will stand when it cannot sit.
##
## False means the group is turned away rather than standing. A merchant party
## may refuse to stand at the bar.
@export var standing_allowed: bool = true

## Whether the group will split across separate tables.
##
## False everywhere for now; present so a future large crew can be allowed to
## spread out without a code change.
@export var may_split_across_tables: bool = false


@export_category("Ordering")

## Chance this group orders one shared drink rather than individual ones.
@export_range(0.0, 1.0, 0.01)
var shared_order_chance: float = 0.5

## Serving-format tags this group prefers, most-wanted first.
##
## Matched against [member ServingFormatDefinition.valid_drink_tags] and the
## drink's own tags. Sailors lean to shared casks, merchants to bottles.
@export var preferred_serving_tags: Array[StringName] = []

## Smallest shared serving this group considers worth ordering.
##
## Stops a pair ordering a firkin. Measured in portions.
@export_range(1, 100, 1)
var minimum_shared_portions: int = 3

## Largest shared serving this group will order.
@export_range(1, 100, 1)
var maximum_shared_portions: int = 24

## Maximum shared orders in one visit. Bounds reordering.
@export_range(1, 20, 1)
var maximum_orders_per_visit: int = 3

## Chance the group orders again once a shared serving empties.
@export_range(0.0, 1.0, 0.01)
var reorder_chance: float = 0.5


@export_category("Modifiers")

## Multiplier on how long members will wait before giving up.
@export_range(0.1, 10.0, 0.05)
var patience_modifier: float = 1.0

## Multiplier on what each member is willing to spend.
@export_range(0.1, 10.0, 0.05)
var spending_modifier: float = 1.0

## Multiplier on how long the visit lasts.
@export_range(0.1, 10.0, 0.05)
var visit_duration_modifier: float = 1.0


@export_category("Tags")

## Free-form tags for future event, reputation and information systems.
##
## Nothing reads these yet. They exist so a "carries_rumours" or
## "high_value_visitor" group can be authored now and wired up later.
@export var social_tags: Array[StringName] = []


## A size drawn from [member size_weights], or uniform when none are set.
func choose_size(rng: RandomNumberGenerator = null) -> int:
	var generator: RandomNumberGenerator = rng

	if generator == null:
		generator = RandomNumberGenerator.new()
		generator.randomize()

	if size_weights.is_empty():
		return generator.randi_range(minimum_size, maximum_size)

	var total: float = 0.0

	for key: Variant in size_weights:
		var size: int = int(key)

		if size < minimum_size or size > maximum_size:
			continue

		total += maxf(float(size_weights[key]), 0.0)

	if total <= 0.0:
		return generator.randi_range(minimum_size, maximum_size)

	var roll: float = generator.randf() * total

	for key: Variant in size_weights:
		var size: int = int(key)

		if size < minimum_size or size > maximum_size:
			continue

		roll -= maxf(float(size_weights[key]), 0.0)

		if roll <= 0.0:
			return size

	return maximum_size


func allows_customer_type(type_id: StringName) -> bool:
	if allowed_customer_type_ids.is_empty():
		return true

	return allowed_customer_type_ids.has(type_id)


func wants_shared_order(rng: RandomNumberGenerator = null) -> bool:
	var generator: RandomNumberGenerator = rng

	if generator == null:
		generator = RandomNumberGenerator.new()
		generator.randomize()

	return generator.randf() < shared_order_chance


func wants_to_reorder(
	orders_so_far: int,
	rng: RandomNumberGenerator = null
) -> bool:
	if orders_so_far >= maximum_orders_per_visit:
		return false

	var generator: RandomNumberGenerator = rng

	if generator == null:
		generator = RandomNumberGenerator.new()
		generator.randomize()

	return generator.randf() < reorder_chance


## Whether [param format] is an acceptable shared serving for this group.
func accepts_serving_format(
	format: ServingFormatDefinition,
	group_size: int
) -> bool:
	if format == null or not format.is_shared:
		return false

	if format.portion_count < minimum_shared_portions:
		return false

	if format.portion_count > maximum_shared_portions:
		return false

	# The format's own group bounds still apply. A firkin declares it wants at
	# least six drinkers, and that is what stops two customers ordering one.
	if group_size < format.minimum_group_size:
		return false

	return true


func is_valid() -> bool:
	return (
		not group_id.is_empty()
		and minimum_size >= 2
		and maximum_size >= minimum_size
	)


func validate_or_warn() -> bool:
	if group_id.is_empty():
		push_error(
			"CustomerGroupDefinition at "
			+ resource_path
			+ " has no group_id."
		)
		return false

	if maximum_size < minimum_size:
		push_error(
			"CustomerGroupDefinition '"
			+ String(group_id)
			+ "' has maximum_size below minimum_size."
		)
		return false

	if minimum_shared_portions > maximum_shared_portions:
		push_error(
			"CustomerGroupDefinition '"
			+ String(group_id)
			+ "' has minimum_shared_portions above maximum_shared_portions."
		)
		return false

	if not standing_allowed and place_preference == PlacePreference.PREFER_STANDING:
		push_warning(
			"CustomerGroupDefinition '"
			+ String(group_id)
			+ "' prefers standing but is not allowed to stand. It will always "
			+ "need a table."
		)

	return true
