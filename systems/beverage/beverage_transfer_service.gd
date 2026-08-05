class_name BeverageTransferService
extends RefCounted

## Moves liquid between filled containers.
##
## Every check happens in one place so nothing can bypass it: content
## compatibility, capacity, availability, reservations and quantity
## conservation. A transfer either moves exactly what it says it moved, or it
## moves nothing.
##
## The typical journey is bulk to service:
##
## [codeblock]
## Hogshead of Kill-Devil  (cellar, 400 measures)
##   -> transfer 60
##   -> Firkin of Kill-Devil  (behind the bar, 60 measures)
##   -> station draws single servings out of the firkin
## [/codeblock]
##
## Nothing forces a drink through that path. Bottled stock is delivered as
## bottles and served straight from them, which is why
## [method can_transfer] refuses rather than inventing a route.
##
## Transfer duration and spillage are not simulated yet. The hooks are here -
## [method estimate_transfer_minutes] - so adding them later does not change
## any call site.


## Whether [param requested] measures could move from source to destination.
##
## Returns a result rather than a bool so the UI can say why not.
static func can_transfer(
	source: FilledContainer,
	destination: FilledContainer,
	requested: int,
	registry: BeverageRegistry = null
) -> BeverageTransferResult:
	if requested <= 0:
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.INVALID_QUANTITY, requested
		)

	if source == null or destination == null:
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.CONTAINER_MISSING, requested
		)

	if source.container == null or destination.container == null:
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.CONTAINER_MISSING, requested
		)

	if not source.container.transferable or not source.container.can_be_transfer_source:
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.NOT_TRANSFERABLE, requested
		)

	if not destination.container.transferable or not destination.container.can_be_transfer_destination:
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.NOT_TRANSFERABLE, requested
		)

	if not source.has_content() or source.get_available_quantity() <= 0:
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.SOURCE_EMPTY, requested
		)

	# The rule that stops ale ending up in a rum cask. A destination holding
	# something else refuses outright rather than mixing - there is no
	# blending in this game and an accidental blend would be unrecoverable.
	if destination.has_content() and destination.content_id != source.content_id:
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.CONTENT_MISMATCH, requested
		)

	if not destination.accepts_content_id(source.content_id, registry):
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.CONTENT_INCOMPATIBLE, requested
		)

	if destination.get_remaining_capacity() <= 0:
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.DESTINATION_FULL, requested
		)

	var movable: int = mini(
		mini(requested, source.get_available_quantity()),
		destination.get_remaining_capacity()
	)

	return BeverageTransferResult.success(
		movable, requested, source.content_id
	)


## Moves up to [param requested] measures from source to destination.
##
## Conservation is enforced by construction: the amount added to the
## destination is the amount removed from the source, and the removal happens
## only if the addition succeeded.
static func transfer(
	source: FilledContainer,
	destination: FilledContainer,
	requested: int,
	world_minutes: int = -1,
	registry: BeverageRegistry = null
) -> BeverageTransferResult:
	var prediction: BeverageTransferResult = can_transfer(
		source, destination, requested, registry
	)

	if not prediction.is_success():
		return prediction

	var moving: int = prediction.amount_moved
	var moved_content_id: StringName = source.content_id

	var added: int = destination.add(
		moving, moved_content_id, world_minutes, registry
	)

	if added <= 0:
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.DESTINATION_FULL, requested
		)

	var removed: int = source.remove(added)

	if removed < added:
		# Should be impossible after can_transfer, but if the source changed
		# underneath us, hand back the difference rather than creating stock.
		destination.remove(added - removed, true)
		added = removed

	if added <= 0:
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.SOURCE_EMPTY, requested
		)

	if source.is_empty():
		source.clear_contents()

	return BeverageTransferResult.success(added, requested, moved_content_id)


## Fills [param destination] as far as it will go from [param source].
static func fill(
	source: FilledContainer,
	destination: FilledContainer,
	world_minutes: int = -1,
	registry: BeverageRegistry = null
) -> BeverageTransferResult:
	if destination == null:
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.CONTAINER_MISSING
		)

	return transfer(
		source,
		destination,
		destination.get_remaining_capacity(),
		world_minutes,
		registry
	)


## Draws [param measures] out of [param source] without a destination.
##
## Used when the destination is a customer's glass rather than another tracked
## container - the liquid leaves the world at that point.
static func draw(
	source: FilledContainer,
	measures: int,
	include_reserved: bool = false
) -> BeverageTransferResult:
	if measures <= 0:
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.INVALID_QUANTITY, measures
		)

	if source == null or source.container == null:
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.CONTAINER_MISSING, measures
		)

	if not source.has_content():
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.SOURCE_EMPTY, measures
		)

	var content_id: StringName = source.content_id
	var removed: int = source.remove(measures, include_reserved)

	if removed <= 0:
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.SOURCE_EMPTY, measures
		)

	if source.is_empty():
		source.clear_contents()

	return BeverageTransferResult.success(removed, measures, content_id)


## The best source for [param content_id] out of [param candidates].
##
## Prefers the container with the least in it that can still cover the request,
## which keeps part-full casks moving and leaves full ones sealed. Returns null
## when nothing can cover it.
static func find_best_source(
	candidates: Array,
	content_id: StringName,
	required: int
) -> FilledContainer:
	var best: FilledContainer = null

	for candidate: Variant in candidates:
		var batch: FilledContainer = candidate as FilledContainer

		if batch == null or batch.content_id != content_id:
			continue

		if batch.get_available_quantity() < required:
			continue

		if best == null or batch.get_available_quantity() < best.get_available_quantity():
			best = batch

	return best


## Total available measures of [param content_id] across [param batches].
static func count_available(
	batches: Array,
	content_id: StringName
) -> int:
	var total: int = 0

	for candidate: Variant in batches:
		var batch: FilledContainer = candidate as FilledContainer

		if batch != null and batch.content_id == content_id:
			total += batch.get_available_quantity()

	return total


## World minutes a transfer of [param measures] would take.
##
## Returns zero today: transfers are instant, config-driven stock movement in
## this phase. The hook exists so timed decanting can be introduced without
## touching any caller.
static func estimate_transfer_minutes(_measures: int) -> int:
	return 0
