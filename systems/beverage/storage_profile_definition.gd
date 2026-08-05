class_name StorageProfileDefinition
extends Resource

## Where a kind of stock belongs, and what that location does to it.
##
## A storage profile is attached to stock, not to a room. It answers "may this
## go in the cellar?" and "does the cellar keep it fresher?" without any
## location needing to know what a hogshead is. Delivered stock is routed by
## intersecting the profile's tags with a container's accepted tags, which is
## why adding a new storage location is a data change.


enum Temperature {
	## No temperature requirement.
	ANY,

	## Cool storage. A cellar.
	COOL,

	## Room temperature.
	AMBIENT,

	## Deliberately warm - near a fire or stove.
	WARM,
}


@export_category("Identity")

@export var profile_id: StringName = &""

@export var display_name: String = "Unnamed Storage Profile"

@export_multiline var description: String = ""


@export_category("What this describes")

## Content tags this profile applies to.
##
## This is the "which stock is this about" half: a bulk cellar cask profile
## lists spirit and liquid tags, a dry ingredient profile lists dry_good.
##
## Deliberately NOT the same vocabulary as the storage tags below. Conflating
## "what kind of thing is this" with "where may it live" is exactly the bug
## that let water be refused by the bar, so the two lists stay separate.
@export var content_tags: Array[StringName] = []

## Container categories this profile applies to.
##
## Content tags alone cannot separate a hogshead of brandy from a crate of
## brandy bottles - both are a premium spirit, but only one belongs in the
## locked cabinet. Naming the categories breaks that tie.
##
## Empty means "any container", which is the right default for ingredients.
@export var container_categories: Array[ContainerDefinition.Category] = []


@export_category("Where it may live")

## Storage-location tags this stock may be kept in.
##
## Matched against a location's own tags. Normally left empty and driven by
## the four flags below, which is easier to author and impossible to get out
## of step - see [method get_effective_storage_tags].
@export var valid_storage_tags: Array[StringName] = []

@export var cellar_compatible: bool = true
@export var behind_bar_compatible: bool = false
@export var dry_storage_compatible: bool = false
@export var locked_storage_compatible: bool = false


@export_category("Conditions")

@export var temperature_category: Temperature = Temperature.ANY

## Multiplier on the spoilage rate of anything stored under this profile.
##
## Below 1.0 preserves; above 1.0 accelerates. 1.0 is neutral, and is what
## every profile uses until spoilage balancing is done.
@export_range(0.0, 10.0, 0.05)
var spoilage_modifier: float = 1.0


@export_category("Security")

## How attractive this stock is to thieves, for a future security system.
@export_range(0, 100, 1)
var theft_value: int = 0


@export_category("Space")

## Bulk floor space one unit of this stock takes.
@export_range(0.0, 1000.0, 0.1)
var bulk_space_requirement: float = 1.0

## Shelf space one unit of this stock takes.
@export_range(0.0, 1000.0, 0.1)
var shelf_space_requirement: float = 0.0


## True when a location carrying [param location_tags] may hold this stock.
##
## Checks the EFFECTIVE tags, so the flags and the explicit list always agree.
func is_compatible_with_location(
	location_tags: Array[StringName]
) -> bool:
	var allowed: Array[StringName] = get_effective_storage_tags()

	if allowed.is_empty():
		return true

	return ItemTags.has_any(location_tags, allowed)


## True when this profile describes stock carrying [param tags].
func applies_to_content(tags: Array[StringName]) -> bool:
	if content_tags.is_empty():
		return false

	return ItemTags.has_any(tags, content_tags)


## True when this profile covers [param category].
func applies_to_container(
	category: ContainerDefinition.Category
) -> bool:
	if container_categories.is_empty():
		return true

	return container_categories.has(category)


## How well this profile fits a batch, for choosing the most specific match.
##
## Container agreement is weighted above tag overlap: a profile that names the
## right container category beats one that merely shares more tags.
func get_match_score(
	tags: Array[StringName],
	category: ContainerDefinition.Category
) -> int:
	if not applies_to_content(tags):
		return 0

	if not applies_to_container(category):
		return 0

	var score: int = 0

	for tag: StringName in content_tags:
		if tags.has(tag):
			score += 1

	if not container_categories.is_empty():
		score += 10

	return score


## Every storage tag this profile is willing to live in.
##
## Built from the individual flags so authors can set either the flags or the
## explicit tag list and get the same answer.
func get_effective_storage_tags() -> Array[StringName]:
	var effective: Array[StringName] = valid_storage_tags.duplicate()

	if cellar_compatible and not effective.has(BeverageTags.CELLAR_STORAGE):
		effective.append(BeverageTags.CELLAR_STORAGE)

	if behind_bar_compatible and not effective.has(BeverageTags.BAR_STORAGE):
		effective.append(BeverageTags.BAR_STORAGE)

	if dry_storage_compatible and not effective.has(BeverageTags.DRY_STORAGE):
		effective.append(BeverageTags.DRY_STORAGE)

	if locked_storage_compatible and not effective.has(BeverageTags.LOCKED_STORAGE):
		effective.append(BeverageTags.LOCKED_STORAGE)

	return effective


func is_valid() -> bool:
	return (
		not profile_id.is_empty()
		and spoilage_modifier >= 0.0
	)


func validate_or_warn() -> bool:
	if profile_id.is_empty():
		push_error(
			"StorageProfileDefinition at "
			+ resource_path
			+ " has no profile_id."
		)
		return false

	if get_effective_storage_tags().is_empty():
		push_warning(
			"StorageProfileDefinition '"
			+ String(profile_id)
			+ "' allows no storage location at all. Delivered stock using it "
			+ "will have nowhere to go."
		)

	if content_tags.is_empty():
		push_warning(
			"StorageProfileDefinition '"
			+ String(profile_id)
			+ "' names no content_tags, so no stock will ever match it."
		)

	return true
