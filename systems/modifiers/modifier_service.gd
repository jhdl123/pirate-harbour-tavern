class_name ModifierService
extends Node

## The one place a contextual value is worked out.
##
## Autoloaded as [code]Modifiers[/code]. Any system with a number that events,
## weather, reputation, time of day or upgrades might want to influence asks
## here instead of owning its own multiplier bookkeeping:
##
## [codeblock]
## var rate := Modifiers.evaluate(
##     ModifierTargets.CUSTOMER_ARRIVAL_RATE,
##     1.0
## )
## [/codeblock]
##
## The system stays ignorant of what is adjusting it, and every adjustment is
## explainable by [method explain] - which is the point. A hidden multiplier
## with no traceable source is the thing this framework exists to prevent.
##
## [b]Expiry[/b]
##
## Modifiers expire by world time, and expiry is checked lazily on evaluation
## as well as on a sweep. That combination is what makes a large time skip
## behave: a modifier whose window passed entirely during the skip is simply
## never active again, with no catch-up pass required.


## A modifier was added, replaced, refreshed or stacked.
signal modifier_added(modifier: Modifier)

## A modifier was removed, expired or cleared.
signal modifier_removed(modifier: Modifier, reason: StringName)


const REASON_EXPIRED: StringName = &"expired"
const REASON_REMOVED: StringName = &"removed"
const REASON_REPLACED: StringName = &"replaced"
const REASON_CLEARED: StringName = &"cleared"


## Seconds between expiry sweeps. Evaluation also checks, so this is only a
## tidy-up to keep the active list and its signals honest when nothing is
## asking for values.
@export_range(0.1, 60.0, 0.1)
var sweep_interval_seconds: float = 1.0

## Whether an unknown target logs a warning when a modifier is added.
@export var warn_on_unknown_target: bool = true


## target -> Array[Modifier]
var _by_target: Dictionary = {}

## stack key -> Modifier, for stacking decisions.
var _by_stack_key: Dictionary = {}

var _sweep_elapsed: float = 0.0

## Bounded history for the diagnostic export.
var _history: Array[Dictionary] = []

var _stacking_prevented: int = 0
var _unknown_targets: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(
	delta: float
) -> void:
	_sweep_elapsed += delta

	if _sweep_elapsed < sweep_interval_seconds:
		return

	_sweep_elapsed = 0.0

	_expire_due()


# -----------------------------------------------------------------------------
# Adding and removing
# -----------------------------------------------------------------------------

## Adds [param modifier], honouring its stacking rule.
##
## Returns the modifier now in force for that stack key, which may be an
## existing one - so a caller that triggers the same event twice gets the same
## object back rather than quietly doubling its effect.
func add(
	modifier: Modifier
) -> Modifier:
	if modifier == null:
		return null

	if warn_on_unknown_target and not ModifierTargets.is_known(
		modifier.target
	):
		_unknown_targets[String(modifier.target)] = int(
			_unknown_targets.get(String(modifier.target), 0)
		) + 1

		push_warning(
			"Modifier '%s' targets '%s', which is not registered in "
			% [String(modifier.modifier_id), String(modifier.target)]
			+ "ModifierTargets. It will never apply to anything."
		)

	var key: String = modifier.get_stack_key()
	var existing: Modifier = _by_stack_key.get(key) as Modifier

	if existing != null:
		return _apply_stacking(existing, modifier, key)

	_by_stack_key[key] = modifier

	_target_list(modifier.target).append(modifier)

	_record(&"added", modifier)

	modifier_added.emit(modifier)

	return modifier


## Resolves a collision between an existing modifier and a new one.
func _apply_stacking(
	existing: Modifier,
	incoming: Modifier,
	key: String
) -> Modifier:
	match incoming.stacking:
		Modifier.Stacking.NONE:
			# Triggering the same event twice must not double its effect.
			_stacking_prevented += 1

			_record(&"stack_prevented", incoming)

			return existing

		Modifier.Stacking.REPLACE:
			remove(existing, REASON_REPLACED)

			_by_stack_key[key] = incoming

			_target_list(incoming.target).append(incoming)

			_record(&"replaced", incoming)

			modifier_added.emit(incoming)

			return incoming

		Modifier.Stacking.REFRESH:
			existing.end_minutes = incoming.end_minutes

			_record(&"refreshed", existing)

			return existing

		Modifier.Stacking.STACK_LIMITED:
			if existing.stacks >= existing.maximum_stacks:
				_stacking_prevented += 1

				_record(&"stack_capped", existing)

				return existing

			existing.stacks += 1
			existing.end_minutes = incoming.end_minutes

			_record(&"stacked", existing)

			return existing

		Modifier.Stacking.STACK_UNLIMITED:
			existing.stacks += 1
			existing.end_minutes = incoming.end_minutes

			_record(&"stacked", existing)

			return existing

	return existing


func remove(
	modifier: Modifier,
	reason: StringName = REASON_REMOVED
) -> void:
	if modifier == null:
		return

	_target_list(modifier.target).erase(modifier)

	var key: String = modifier.get_stack_key()

	if _by_stack_key.get(key) == modifier:
		_by_stack_key.erase(key)

	_record(reason, modifier)

	modifier_removed.emit(modifier, reason)


## Removes everything applied by [param source_id].
##
## How an event ends: one call, whatever it added. An event never has to
## remember its own modifier list.
func remove_source(
	source_id: StringName
) -> int:
	var removed: int = 0

	for modifier: Modifier in get_all_modifiers():
		if modifier.source_id != source_id:
			continue

		remove(modifier, REASON_REMOVED)

		removed += 1

	return removed


func clear_all() -> void:
	for modifier: Modifier in get_all_modifiers():
		remove(modifier, REASON_CLEARED)

	_by_target.clear()
	_by_stack_key.clear()


func _expire_due() -> void:
	var now: float = WorldTime.get_total_minutes_precise()

	for modifier: Modifier in get_all_modifiers():
		if modifier.is_expired_at(now):
			remove(modifier, REASON_EXPIRED)


func _target_list(
	target: StringName
) -> Array:
	if not _by_target.has(target):
		_by_target[target] = []

	return _by_target[target]


# -----------------------------------------------------------------------------
# Evaluating
# -----------------------------------------------------------------------------

## The final value of [param target], starting from [param base_value].
func evaluate(
	target: StringName,
	base_value: float,
	context: Dictionary = {}
) -> float:
	return float(explain(target, base_value, context)["final_value"])


## The final value plus every step taken to reach it.
##
## Returned in the order the operations were applied, so the breakdown printed
## by the debug panel and the report is the calculation, not a reconstruction
## of it.
func explain(
	target: StringName,
	base_value: float,
	context: Dictionary = {}
) -> Dictionary:
	var now: float = WorldTime.get_total_minutes_precise()

	var applicable: Array[Modifier] = []

	for modifier: Modifier in _target_list(target):
		if not modifier.is_active_at(now):
			continue

		if not modifier.matches_context(context):
			continue

		applicable.append(modifier)

	# Priority order within each operation group, so a breakdown always reads
	# in the same sequence for the same set of modifiers.
	applicable.sort_custom(
		func(a: Modifier, b: Modifier) -> bool:
			return a.priority < b.priority
	)

	var steps: Array[Dictionary] = []
	var running: float = base_value

	# 1. additions
	for modifier: Modifier in applicable:
		if modifier.operation != Modifier.Operation.ADD:
			continue

		running += modifier.get_effective_value()

		steps.append(_step(modifier, running))

	# 2. multipliers
	for modifier: Modifier in applicable:
		if modifier.operation != Modifier.Operation.MULTIPLY:
			continue

		running *= modifier.get_effective_value()

		steps.append(_step(modifier, running))

	# 3. limits
	var minimum: float = -INF
	var maximum: float = INF

	for modifier: Modifier in applicable:
		if modifier.operation == Modifier.Operation.MINIMUM:
			minimum = maxf(minimum, modifier.get_effective_value())

			steps.append(_step(modifier, running))

		elif modifier.operation == Modifier.Operation.MAXIMUM:
			maximum = minf(maximum, modifier.get_effective_value())

			steps.append(_step(modifier, running))

	running = clampf(running, minimum, maximum)

	# 4. override, highest priority wins, ignoring everything above
	var override: Modifier = null

	for modifier: Modifier in applicable:
		if modifier.operation != Modifier.Operation.OVERRIDE:
			continue

		if override == null or modifier.priority >= override.priority:
			override = modifier

	if override != null:
		running = override.get_effective_value()

		steps.append(_step(override, running))

	return {
		"target": String(target),
		"base_value": base_value,
		"steps": steps,
		"minimum_clamp": (0.0 if minimum == -INF else minimum),
		"maximum_clamp": (0.0 if maximum == INF else maximum),
		"has_minimum": minimum != -INF,
		"has_maximum": maximum != INF,
		"modifier_count": applicable.size(),
		"final_value": running,
	}


func _step(
	modifier: Modifier,
	running: float
) -> Dictionary:
	return {
		"source": String(modifier.source_id),
		"label": modifier.label,
		"operation": Modifier.Operation.keys()[modifier.operation],
		"value": modifier.get_effective_value(),
		"stacks": modifier.stacks,
		"running_value": running,
	}


## The breakdown as readable lines, for the debug panel and the console.
func explain_text(
	target: StringName,
	base_value: float,
	context: Dictionary = {}
) -> String:
	var breakdown: Dictionary = explain(target, base_value, context)

	var lines: Array[String] = []

	lines.append("Target: %s" % breakdown["target"])
	lines.append("Base value: %.2f" % breakdown["base_value"])
	lines.append("")

	for step: Dictionary in breakdown["steps"]:
		var symbol: String = "x"

		match String(step["operation"]):
			"ADD":
				symbol = "+"
			"MINIMUM":
				symbol = ">="
			"MAXIMUM":
				symbol = "<="
			"OVERRIDE":
				symbol = "="

		lines.append(
			"%-32s %s%.2f  -> %.2f" % [
				step["label"],
				symbol,
				step["value"],
				step["running_value"],
			]
		)

	lines.append("")
	lines.append("Final value: %.2f" % breakdown["final_value"])

	if bool(breakdown["has_minimum"]):
		lines.append("Minimum clamp: %.2f" % breakdown["minimum_clamp"])

	if bool(breakdown["has_maximum"]):
		lines.append("Maximum clamp: %.2f" % breakdown["maximum_clamp"])

	return "\n".join(lines)


# -----------------------------------------------------------------------------
# Reading
# -----------------------------------------------------------------------------

func get_all_modifiers() -> Array[Modifier]:
	var all: Array[Modifier] = []

	for target: StringName in _by_target.keys():
		for modifier: Modifier in _by_target[target]:
			all.append(modifier)

	return all


func get_modifiers_for_target(
	target: StringName
) -> Array[Modifier]:
	var list: Array[Modifier] = []

	list.assign(_target_list(target))

	return list


func has_source(
	source_id: StringName
) -> bool:
	for modifier: Modifier in get_all_modifiers():
		if modifier.source_id == source_id:
			return true

	return false


func _record(
	action: StringName,
	modifier: Modifier
) -> void:
	_history.append({
		"world_minutes": WorldTime.get_total_minutes_precise(),
		"action": String(action),
		"modifier": modifier.to_dictionary(),
	})

	while _history.size() > 400:
		_history.pop_front()


func build_report_section() -> Dictionary:
	var active: Array = []

	for modifier: Modifier in get_all_modifiers():
		active.append(modifier.to_dictionary())

	return {
		"active_modifiers": active,
		"history": _history.duplicate(true),
		"stacking_prevented": _stacking_prevented,
		"unknown_targets": _unknown_targets.duplicate(true),
	}
