class_name ModifierTargets
extends RefCounted

## Every value the modifier framework can adjust.
##
## Centralised and validated rather than free strings, because a typo in a
## modifier target is silent: the modifier is added, never matches anything,
## and the event it belonged to simply does nothing. Registering targets here
## means [method is_known] can turn that into a warning at the moment the
## modifier is created.
##
## Adding a target is one constant plus one entry in [method get_all]. Nothing
## else needs to know it exists - a system asks
## [code]Modifiers.evaluate(target, base)[/code] and any modifier written
## against that name applies immediately.


# --- Proven in this phase ----------------------------------------------------

## Multiplier on how often customers arrive.
const CUSTOMER_ARRIVAL_RATE: StringName = &"customer_arrival_rate"

## Fraction of seating the tavern is trying to fill right now.
const CUSTOMER_TARGET_OCCUPANCY: StringName = &"customer_target_occupancy"

## Per-archetype selection weight. Scoped by customer tag.
const CUSTOMER_TYPE_WEIGHT: StringName = &"customer_type_weight"

## How many people arrive together.
const CUSTOMER_GROUP_SIZE: StringName = &"customer_group_size"

## How long a customer stays before leaving.
const CUSTOMER_STAY_DURATION: StringName = &"customer_stay_duration"


# --- Declared for later systems ---------------------------------------------

const CUSTOMER_SPENDING: StringName = &"customer_spending"
const CUSTOMER_PATIENCE: StringName = &"customer_patience"
const CUSTOMER_DRINK_CONSUMPTION: StringName = &"customer_drink_consumption"
const HIGH_VALUE_CUSTOMER_CHANCE: StringName = &"high_value_customer_chance"
const FIGHT_CHANCE: StringName = &"fight_chance"
const STAFF_WORK_SPEED: StringName = &"staff_work_speed"
const STAFF_FATIGUE_RATE: StringName = &"staff_fatigue_rate"
const SUPPLIER_PRICE: StringName = &"supplier_price"
const DELIVERY_SPEED: StringName = &"delivery_speed"
const TIP_AMOUNT: StringName = &"tip_amount"
const RUMOUR_QUALITY: StringName = &"rumour_quality"
const SECURITY_RISK: StringName = &"security_risk"
const ILLEGAL_ACTIVITY_RISK: StringName = &"illegal_activity_risk"


static func get_all() -> Array[StringName]:
	return [
		CUSTOMER_ARRIVAL_RATE,
		CUSTOMER_TARGET_OCCUPANCY,
		CUSTOMER_TYPE_WEIGHT,
		CUSTOMER_GROUP_SIZE,
		CUSTOMER_STAY_DURATION,
		CUSTOMER_SPENDING,
		CUSTOMER_PATIENCE,
		CUSTOMER_DRINK_CONSUMPTION,
		HIGH_VALUE_CUSTOMER_CHANCE,
		FIGHT_CHANCE,
		STAFF_WORK_SPEED,
		STAFF_FATIGUE_RATE,
		SUPPLIER_PRICE,
		DELIVERY_SPEED,
		TIP_AMOUNT,
		RUMOUR_QUALITY,
		SECURITY_RISK,
		ILLEGAL_ACTIVITY_RISK,
	]


static func is_known(
	target: StringName
) -> bool:
	return get_all().has(target)
