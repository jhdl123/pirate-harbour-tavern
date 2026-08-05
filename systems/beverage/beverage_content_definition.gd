class_name BeverageContentDefinition
extends Resource

## What is actually inside a container: the liquid, not the drink.
##
## This is the piece that lets one container hold anything. A hogshead does not
## know it holds rum - it holds [code]kill_devil[/code], and the same hogshead
## resource can hold [code]madeira[/code] tomorrow. Bulk stock, service casks,
## recipes and shared vessels all refer to contents by [member content_id].
##
## Contents are deliberately separate from [DrinkDefinition]:
##
## [codeblock]
## BeverageContentDefinition   kill_devil        the liquid in the cask
## DrinkDefinition             kill_devil        what a customer orders
## ServingFormatDefinition     dram / mug        how much of it they get
## [/codeblock]
##
## They often share a name and that is fine. What matters is that a recipe
## consumes *contents*, a customer orders a *drink*, and neither concept has to
## change when the other does. Coffee is the clear case: the content is brewed
## coffee, the drink is Coffee, and the recipe turns beans plus water into the
## content.


@export_category("Identity")

## Stable internal identifier used by stock, recipes and save data.
@export var content_id: StringName = &""

@export var display_name: String = "Unnamed Content"

@export_multiline var description: String = ""


@export_category("Classification")

## Tags describing the content itself - see [BeverageTags].
##
## Containers use these to decide what they may hold, via
## [member ContainerDefinition.supported_content_tags]. A cask that supports
## [constant BeverageTags.LIQUID] will not accept a dry good.
@export var tags: Array[StringName] = [BeverageTags.LIQUID]

## Unit one measure represents, for display only.
##
## Balance uses whole measures throughout; this is the word shown beside them.
@export var measure_name: String = "measure"


@export_category("Economy")

## Baseline value of one measure, before container and format modifiers.
@export_range(0, 999999, 1)
var base_value_per_measure: int = 1


@export_category("Spoilage")

## Whether this content can go off at all.
##
## When false every spoilage field is ignored and freshness always reads 1.0.
## That is the safe default for sealed spirits.
@export var can_spoil: bool = false

## Profile used when [member can_spoil] is true. Safe to leave empty.
@export var spoilage_profile: SpoilageProfileDefinition


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func has_any_tag(any_tags: Array[StringName]) -> bool:
	return ItemTags.has_any(tags, any_tags)


## True when this content may be put into [param container].
func is_compatible_with_container(
	container: ContainerDefinition
) -> bool:
	if container == null:
		return false

	return container.accepts_content(self)


func get_spoilage_profile() -> SpoilageProfileDefinition:
	if not can_spoil:
		return null

	return spoilage_profile


func is_valid() -> bool:
	return (
		not content_id.is_empty()
		and not display_name.strip_edges().is_empty()
		and base_value_per_measure >= 0
	)


func validate_or_warn() -> bool:
	if content_id.is_empty():
		push_error(
			"BeverageContentDefinition at "
			+ resource_path
			+ " has no content_id. A stable id is required for stock and saves."
		)
		return false

	if display_name.strip_edges().is_empty():
		push_error(
			"BeverageContentDefinition '"
			+ String(content_id)
			+ "' has no display name."
		)
		return false

	if can_spoil and spoilage_profile == null:
		push_warning(
			"BeverageContentDefinition '"
			+ String(content_id)
			+ "' is marked can_spoil but has no spoilage_profile. It will "
			+ "never actually spoil."
		)

	return true
