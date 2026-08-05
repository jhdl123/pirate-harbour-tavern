class_name TavernTaskTypes
extends RefCounted

## Stable identifiers for every kind of work the tavern can need doing.
##
## These are only names. A type does nothing until two things exist:
##
## [codeblock]
## a TavernTaskDefinition resource   what it is called, how urgent it is,
##                                   what capability a worker needs
## a StaffTaskExecutor               how a worker actually performs it
## [/codeblock]
##
## Both are listed in one place each - see
## [member TavernTaskBoardConfig.task_definitions] and
## [method StaffTaskExecutor.create_for] - so adding a task type is two
## registrations and one new executor script, never an edit to [StaffMember].
##
## The types below the divider are declared now purely so that producers,
## save data and diagnostics agree on spelling when they arrive. Nothing
## creates them yet and nothing needs to.


# --- Implemented this phase --------------------------------------------------

## Carry a prepared drink from a service slot to a waiting customer.
const SERVE_DRINK: StringName = &"serve_drink"

## Run the existing cleaning action on a seat that a customer left dirty.
const CLEAN_SEAT: StringName = &"clean_seat"


# --- Declared for later phases ----------------------------------------------

const PREPARE_DRINK: StringName = &"prepare_drink"
const REFILL_STATION: StringName = &"refill_station"
const MOVE_STOCK: StringName = &"move_stock"

## Carry one filled shared keg from storage to a waiting customer group.
const DELIVER_GROUP_KEG: StringName = &"deliver_group_keg"
const UNLOAD_DELIVERY: StringName = &"unload_delivery"
const CLEAR_BROKEN_GLASS: StringName = &"clear_broken_glass"
const REPAIR_FURNITURE: StringName = &"repair_furniture"
const ATTEND_CUSTOMER: StringName = &"attend_customer"
const ESCORT_VISITOR: StringName = &"escort_visitor"
const GUARD_AREA: StringName = &"guard_area"
const COOK_FOOD: StringName = &"cook_food"
const PERFORM_ENTERTAINMENT: StringName = &"perform_entertainment"


## Every type this phase can actually execute.
##
## Used by developer tools and diagnostics to tell "not implemented yet" apart
## from "implemented but nothing needs doing".
static func get_implemented_types() -> Array[StringName]:
	return [
		SERVE_DRINK,
		CLEAN_SEAT,
		PREPARE_DRINK,
		REFILL_STATION,
	]
