class_name StaffCapabilities
extends RefCounted

## What a member of staff is allowed to do.
##
## Capabilities are the join between a worker and a task: a
## [TavernTaskDefinition] lists the capabilities it requires, a
## [StaffDefinition] lists the capabilities its archetype has, and the task
## board simply intersects the two. No worker script ever names a task type,
## and no task ever names a worker.
##
## That is what makes "add a cook" a data change: give the cook the
## [constant COOK_FOOD] capability and it starts picking up cooking tasks the
## moment a producer creates one.
##
## The Tavern Hand introduced in Phase 3A has exactly
## [constant SERVE_DRINKS] and [constant CLEAN_SEATS].


# --- Granted to the Phase 3A Tavern Hand -------------------------------------

## Carry prepared drinks from a service slot to a waiting customer.
const SERVE_DRINKS: StringName = &"serve_drinks"

## Run cleaning actions on dirty seats and tables.
const CLEAN_SEATS: StringName = &"clean_seats"


# --- Declared for later staff roles ------------------------------------------

const PREPARE_DRINKS: StringName = &"prepare_drinks"
const REFILL_STATIONS: StringName = &"refill_stations"
const MOVE_STOCK: StringName = &"move_stock"
const UNLOAD_DELIVERIES: StringName = &"unload_deliveries"
const REPAIR: StringName = &"repair"
const COOK: StringName = &"cook"
const GUARD: StringName = &"guard"
const ENTERTAIN: StringName = &"entertain"
const MANAGE: StringName = &"manage"


## True when [param held] covers every entry in [param required].
##
## An empty [param required] means "anybody can do this", which is deliberate:
## a task that needs no special skill should not need an explicit capability
## invented for it.
static func satisfies(
	held: Array[StringName],
	required: Array[StringName]
) -> bool:
	if required.is_empty():
		return true

	if held.is_empty():
		return false

	for capability: StringName in required:
		if not held.has(capability):
			return false

	return true
