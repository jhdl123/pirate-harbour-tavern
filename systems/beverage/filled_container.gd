class_name FilledContainer
extends Resource

## A real container with real contents in it, right now.
##
## This is the runtime object the brief calls a stock batch. It is the only
## thing that knows a particular hogshead currently holds 340 measures of
## Kill-Devil - the [ContainerDefinition] knows only that hogsheads hold 400 of
## something, and the [BeverageContentDefinition] knows only what Kill-Devil is.
##
## Because the pairing lives here, no class is ever needed for a combination.
## Hogshead-of-Madeira and Hogshead-of-Kill-Devil are the same two resources
## with a different [member content_id].
##
## Freshness is not stored as a number that something has to tick. It is
## derived from [member filled_at_minutes] whenever it is read, so a batch
## sitting in a cellar for three game days costs exactly nothing until someone
## looks at it. See [method get_freshness].


## Reason a transfer or draw was refused. Mirrors [ItemTransferResult]'s
## approach so callers can report a real cause instead of just failing.
enum Refusal {
	NONE,
	CONTAINER_MISSING,
	CONTENT_MISMATCH,
	CONTENT_INCOMPATIBLE,
	SOURCE_EMPTY,
	DESTINATION_FULL,
	NOT_TRANSFERABLE,
	INVALID_QUANTITY,
	SPOILED,
}


@export_category("Identity")

## Stable per-batch id, so a save can point at this exact cask.
@export var batch_id: StringName = &""


@export_category("Container")

@export var container: ContainerDefinition


@export_category("Contents")

## What is in it. Empty means the container is empty and unassigned.
##
## An empty container keeps its previous content id until it is explicitly
## cleared, which is what stops ale being poured into an unwashed rum cask by
## accident.
@export var content_id: StringName = &""

@export_range(0, 100000, 1)
var quantity: int = 0


@export_category("State")

## World minute at which this batch was filled or prepared.
##
## Minus one means "never filled", which reads as permanently fresh.
@export var filled_at_minutes: int = -1

## Whether the container is sealed. A sealed container does not age when its
## spoilage profile pauses on sealing.
@export var sealed: bool = true

## Free-form location id: which storage this batch is sitting in.
@export var storage_location_id: StringName = &""

## Measures promised to a pending order or task but not yet drawn.
##
## Reserved stock still counts as present but is not available. This is what
## stops two staff both committing the last of a cask.
@export_range(0, 100000, 1)
var reserved_quantity: int = 0


var _cached_spoilage: SpoilageProfileDefinition = null
var _cached_content: BeverageContentDefinition = null


## Creates a batch of [param content_definition] in [param container_definition].
static func create(
	container_definition: ContainerDefinition,
	content_definition: BeverageContentDefinition,
	starting_quantity: int,
	world_minutes: int = -1
) -> FilledContainer:
	var batch: FilledContainer = FilledContainer.new()
	batch.container = container_definition

	if content_definition != null:
		batch.content_id = content_definition.content_id
		batch._cached_content = content_definition

	batch.quantity = clampi(
		starting_quantity,
		0,
		container_definition.maximum_capacity if container_definition != null else starting_quantity
	)
	batch.filled_at_minutes = world_minutes
	batch.batch_id = StringName(
		"%s_%s_%d" % [
			String(container_definition.container_id) if container_definition != null else "unknown",
			String(batch.content_id),
			Time.get_ticks_usec(),
		]
	)

	return batch


## Creates an empty container with no contents assigned.
static func create_empty(
	container_definition: ContainerDefinition
) -> FilledContainer:
	return FilledContainer.create(container_definition, null, 0)


# --- Basic state -------------------------------------------------------------

func is_empty() -> bool:
	return quantity <= 0


func is_full() -> bool:
	return quantity >= get_maximum_quantity()


func get_maximum_quantity() -> int:
	if container == null:
		return 0

	return container.maximum_capacity


func get_remaining_capacity() -> int:
	return maxi(get_maximum_quantity() - quantity, 0)


## Measures that may actually be taken: quantity minus reservations.
func get_available_quantity() -> int:
	return maxi(quantity - reserved_quantity, 0)


func get_fill_fraction() -> float:
	var maximum: int = get_maximum_quantity()

	if maximum <= 0:
		return 0.0

	return clampf(float(quantity) / float(maximum), 0.0, 1.0)


func has_content() -> bool:
	return not content_id.is_empty()


# --- Contents ----------------------------------------------------------------

## Resolves and caches the content definition from [param registry].
func get_content(registry: BeverageRegistry) -> BeverageContentDefinition:
	if _cached_content != null:
		return _cached_content

	if registry == null or content_id.is_empty():
		return null

	_cached_content = registry.get_content(content_id)

	return _cached_content


## True when [param other_content_id] may be added to this batch.
##
## An empty container with no assigned content accepts anything its container
## definition supports. A part-full container accepts only more of the same.
func accepts_content_id(
	other_content_id: StringName,
	registry: BeverageRegistry = null
) -> bool:
	if other_content_id.is_empty():
		return false

	if container == null:
		return false

	if not content_id.is_empty() and content_id != other_content_id:
		return false

	if registry != null:
		var content: BeverageContentDefinition = registry.get_content(
			other_content_id
		)

		if content == null:
			return false

		if not container.accepts_content(content):
			return false

	return true


# --- Adding and removing -----------------------------------------------------

## Adds up to [param amount] measures. Returns how many were actually added.
##
## Never overfills and never silently mixes: adding a different content to a
## part-full container adds nothing.
func add(
	amount: int,
	adding_content_id: StringName,
	world_minutes: int = -1,
	registry: BeverageRegistry = null
) -> int:
	if amount <= 0 or container == null:
		return 0

	if not accepts_content_id(adding_content_id, registry):
		return 0

	var space: int = get_remaining_capacity()

	if space <= 0:
		return 0

	var added: int = mini(amount, space)
	var was_empty: bool = is_empty()

	quantity += added
	content_id = adding_content_id
	_cached_content = null
	_cached_spoilage = null

	# Refilling an empty container restarts its clock. Topping up a part-full
	# one does not: the older liquid is still the oldest liquid in there, and
	# pretending otherwise would let a cask be kept fresh forever by adding a
	# splash to it every day.
	if was_empty and world_minutes >= 0:
		filled_at_minutes = world_minutes

	return added


## Removes up to [param amount] measures. Returns how many were removed.
##
## Respects reservations: only [method get_available_quantity] can be taken
## unless [param include_reserved] is set, which the reservation holder does
## when it comes to collect.
func remove(amount: int, include_reserved: bool = false) -> int:
	if amount <= 0:
		return 0

	var takeable: int = quantity if include_reserved else get_available_quantity()
	var removed: int = mini(amount, takeable)

	if removed <= 0:
		return 0

	quantity -= removed

	if include_reserved:
		reserved_quantity = mini(reserved_quantity, quantity)

	return removed


## Empties the container and forgets what was in it.
func clear_contents() -> void:
	quantity = 0
	reserved_quantity = 0
	content_id = &""
	filled_at_minutes = -1
	_cached_content = null
	_cached_spoilage = null


# --- Reservations ------------------------------------------------------------

## Reserves [param amount] measures. Returns how many were actually reserved.
func reserve(amount: int) -> int:
	if amount <= 0:
		return 0

	var reservable: int = mini(amount, get_available_quantity())

	reserved_quantity += reservable

	return reservable


func release_reservation(amount: int) -> void:
	reserved_quantity = maxi(reserved_quantity - maxi(amount, 0), 0)


func clear_reservations() -> void:
	reserved_quantity = 0


# --- Freshness ---------------------------------------------------------------

## Freshness from 1.0 (fresh) to 0.0 (gone).
##
## Derived on read from elapsed world minutes. Returns 1.0 for anything that
## cannot spoil, which is why every caller can read this without checking
## whether spoilage applies.
func get_freshness(
	world_minutes: int,
	registry: BeverageRegistry,
	storage_modifier: float = 1.0
) -> float:
	var profile: SpoilageProfileDefinition = get_spoilage_profile(registry)

	if profile == null or not profile.is_enabled():
		return 1.0

	if sealed and profile.sealed_state_pauses_spoilage:
		return 1.0

	if filled_at_minutes < 0:
		return 1.0

	var elapsed: int = maxi(world_minutes - filled_at_minutes, 0)

	return profile.calculate_freshness(elapsed, storage_modifier)


func is_spoiled(
	world_minutes: int,
	registry: BeverageRegistry,
	storage_modifier: float = 1.0
) -> bool:
	var profile: SpoilageProfileDefinition = get_spoilage_profile(registry)

	if profile == null or not profile.is_enabled():
		return false

	return profile.is_spoiled_at_freshness(
		get_freshness(world_minutes, registry, storage_modifier)
	)


func get_spoilage_profile(
	registry: BeverageRegistry
) -> SpoilageProfileDefinition:
	if _cached_spoilage != null:
		return _cached_spoilage

	var content: BeverageContentDefinition = get_content(registry)

	if content == null:
		return null

	_cached_spoilage = content.get_spoilage_profile()

	return _cached_spoilage


## Opens the container, starting its clock if the profile pauses when sealed.
func unseal(world_minutes: int) -> void:
	if not sealed:
		return

	sealed = false

	if world_minutes >= 0:
		filled_at_minutes = world_minutes


# --- Display -----------------------------------------------------------------

## "Hogshead (very large cask) of Kill-Devil".
func get_display_name(registry: BeverageRegistry) -> String:
	if container == null:
		return "Unknown Container"

	var container_text: String = container.get_display_name_with_explanation()

	if not has_content():
		return "Empty %s" % container_text

	var content: BeverageContentDefinition = get_content(registry)
	var content_text: String = (
		content.display_name if content != null else String(content_id)
	)

	return "%s of %s" % [container_text, content_text]


func get_quantity_text() -> String:
	var unit: String = container.unit_name if container != null else "measures"

	return "%d / %d %s" % [quantity, get_maximum_quantity(), unit]


# --- Persistence -------------------------------------------------------------

## Plain, save-friendly data. Stores ids, never resource paths.
func to_save_dict() -> Dictionary:
	return {
		"batch_id": String(batch_id),
		"container_id": (
			String(container.container_id) if container != null else ""
		),
		"content_id": String(content_id),
		"quantity": quantity,
		"reserved_quantity": reserved_quantity,
		"filled_at_minutes": filled_at_minutes,
		"sealed": sealed,
		"storage_location_id": String(storage_location_id),
	}


## Rebuilds a batch from save data. Returns null when the container is unknown.
static func from_save_dict(
	data: Dictionary,
	registry: BeverageRegistry
) -> FilledContainer:
	if registry == null:
		return null

	var container_id: StringName = StringName(
		String(data.get("container_id", ""))
	)

	if container_id.is_empty():
		return null

	var container_definition: ContainerDefinition = registry.get_container(
		container_id
	)

	if container_definition == null:
		push_warning(
			"FilledContainer save data refers to unknown container '"
			+ String(container_id)
			+ "'. The batch was dropped."
		)
		return null

	var batch: FilledContainer = FilledContainer.new()
	batch.container = container_definition
	batch.batch_id = StringName(String(data.get("batch_id", "")))
	batch.content_id = StringName(String(data.get("content_id", "")))
	batch.quantity = int(data.get("quantity", 0))
	batch.reserved_quantity = int(data.get("reserved_quantity", 0))
	batch.filled_at_minutes = int(data.get("filled_at_minutes", -1))
	batch.sealed = bool(data.get("sealed", true))
	batch.storage_location_id = StringName(
		String(data.get("storage_location_id", ""))
	)

	batch.quantity = clampi(batch.quantity, 0, batch.get_maximum_quantity())
	batch.reserved_quantity = clampi(
		batch.reserved_quantity, 0, batch.quantity
	)

	return batch


func duplicate_batch() -> FilledContainer:
	var copy: FilledContainer = FilledContainer.new()
	copy.batch_id = batch_id
	copy.container = container
	copy.content_id = content_id
	copy.quantity = quantity
	copy.reserved_quantity = reserved_quantity
	copy.filled_at_minutes = filled_at_minutes
	copy.sealed = sealed
	copy.storage_location_id = storage_location_id

	return copy
