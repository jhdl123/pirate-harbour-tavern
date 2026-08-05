class_name ModifierPreset
extends Resource

## A named bundle of modifiers applied and removed together.
##
## This is how an event exists as data rather than as code. A harbour festival
## is a preset with four entries; applying it is one call, ending it is one
## call, and nothing in the spawner, the customer AI or the economy knows the
## festival exists.
##
## Entries are plain Dictionaries so a preset can be authored in the inspector
## without a second resource type per line:
##
## [codeblock]
## { target, operation, value, tags, label }
## [/codeblock]


@export_category("Identity")

## Also the modifier source id, so [method ModifierService.remove_source]
## removes exactly this preset's contributions.
@export var preset_id: StringName = &"preset"

@export var display_name: String = "Event"

## Shown to the player when the preset is applied. Empty means no message.
@export_multiline var announcement: String = ""


@export_category("Duration")

## World minutes this lasts. Zero or less means "until removed explicitly".
@export_range(0, 10080, 5)
var duration_minutes: int = 0


@export_category("Stacking")

@export var stacking: Modifier.Stacking = Modifier.Stacking.REPLACE

@export_range(1, 20, 1)
var maximum_stacks: int = 1


@export_category("Modifiers")

## One entry per adjustment. See the class description for the shape.
@export var entries: Array[Dictionary] = []


## Builds the modifiers this preset represents. Does not apply them.
func build_modifiers() -> Array[Modifier]:
	var built: Array[Modifier] = []

	var now: float = WorldTime.get_total_minutes_precise()

	for entry: Dictionary in entries:
		var target: StringName = StringName(entry.get("target", ""))

		if target.is_empty():
			push_warning(
				"ModifierPreset '%s' has an entry with no target."
				% String(preset_id)
			)

			continue

		var modifier: Modifier = Modifier.create(
			preset_id,
			target,
			_parse_operation(entry.get("operation", "MULTIPLY")),
			float(entry.get("value", 1.0)),
			String(entry.get("label", display_name))
		)

		modifier.stacking = stacking
		modifier.maximum_stacks = maximum_stacks
		modifier.priority = int(entry.get("priority", 0))

		var tags: Array = entry.get("tags", [])

		for tag: Variant in tags:
			modifier.required_tags.append(StringName(tag))

		var excluded: Array = entry.get("excluded_tags", [])

		for tag: Variant in excluded:
			modifier.excluded_tags.append(StringName(tag))

		# A preset touching two archetypes needs two independent stack keys on
		# the same target. This affects bookkeeping only - it must not change
		# whether the modifier applies, which is why it is not `scope`.
		if not modifier.required_tags.is_empty():
			modifier.stack_scope = modifier.required_tags[0]

		if duration_minutes > 0:
			modifier.end_minutes = now + float(duration_minutes)

		built.append(modifier)

	return built


static func _parse_operation(
	raw: Variant
) -> Modifier.Operation:
	if raw is int:
		return raw as Modifier.Operation

	match String(raw).to_upper():
		"ADD":
			return Modifier.Operation.ADD
		"MINIMUM":
			return Modifier.Operation.MINIMUM
		"MAXIMUM":
			return Modifier.Operation.MAXIMUM
		"OVERRIDE":
			return Modifier.Operation.OVERRIDE

	return Modifier.Operation.MULTIPLY
