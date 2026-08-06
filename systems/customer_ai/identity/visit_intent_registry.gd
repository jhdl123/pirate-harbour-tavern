class_name VisitIntentRegistry
extends Resource

## Every [VisitIntentConfig] the game knows about, plus weighted selection.
##
## Deliberately the same shape as [ActivityRegistry]: an authored array, a
## lazily built id lookup, and a [method rebuild] for anything that edits the
## array at runtime. Nothing here holds per-customer state.


@export var intents: Array[VisitIntentConfig] = []

var _lookup: Dictionary = {}
var _lookup_built: bool = false


func get_intent(intent_id: StringName) -> VisitIntentConfig:
	_ensure_lookup()
	return _lookup.get(intent_id, null)


func has_intent(intent_id: StringName) -> bool:
	_ensure_lookup()
	return _lookup.has(intent_id)


## Every enabled intent with a valid id.
func get_enabled() -> Array[VisitIntentConfig]:
	var result: Array[VisitIntentConfig] = []

	for intent: VisitIntentConfig in intents:
		if intent == null or not intent.enabled:
			continue

		if intent.intent_id.is_empty():
			continue

		result.append(intent)

	return result


## Picks one intent using [param weights] - a Dictionary of intent id to
## weight, normally [member CustomerType.visit_intent_weights].
##
## Falls back in three steps rather than returning null, because a customer
## with no intent would silently lose every intent-driven modifier and look
## like a balancing problem instead of a data problem:
## [br]1. weighted pick among enabled, positively weighted intents;
## [br]2. any enabled intent, if the weights matched nothing;
## [br]3. null only when the registry itself is empty.
##
## [param rng] is required so the caller controls determinism - see
## [method CustomerIdentity.initialise].
func select_weighted(
	weights: Dictionary,
	rng: RandomNumberGenerator
) -> VisitIntentConfig:
	var enabled: Array[VisitIntentConfig] = get_enabled()

	if enabled.is_empty():
		return null

	var candidates: Array[VisitIntentConfig] = []
	var candidate_weights: Array[float] = []
	var total: float = 0.0

	for intent: VisitIntentConfig in enabled:
		var weight: float = 0.0
		var key: String = String(intent.intent_id)

		if weights.has(key):
			var raw: Variant = weights[key]

			if raw is float or raw is int:
				weight = maxf(0.0, float(raw))

		if weight <= 0.0:
			continue

		candidates.append(intent)
		candidate_weights.append(weight)
		total += weight

	if candidates.is_empty() or total <= 0.0:
		return enabled[rng.randi() % enabled.size()]

	var roll: float = rng.randf() * total
	var running: float = 0.0

	for index: int in candidates.size():
		running += candidate_weights[index]

		if roll <= running:
			return candidates[index]

	return candidates[candidates.size() - 1]


func rebuild() -> void:
	_lookup.clear()
	_lookup_built = false
	_ensure_lookup()


func validate_or_warn() -> bool:
	var valid: bool = true

	for intent: VisitIntentConfig in intents:
		if intent == null:
			push_warning(
				"VisitIntentRegistry '%s' holds a null entry." % resource_path
			)
			valid = false
			continue

		if not intent.validate_or_warn():
			valid = false

	return valid


func _ensure_lookup() -> void:
	if _lookup_built:
		return

	_lookup.clear()

	for intent: VisitIntentConfig in intents:
		if intent == null or intent.intent_id.is_empty():
			continue

		if _lookup.has(intent.intent_id):
			push_warning(
				"VisitIntentRegistry has duplicate intent_id '%s'."
				% intent.intent_id
			)
			continue

		_lookup[intent.intent_id] = intent

	_lookup_built = true
