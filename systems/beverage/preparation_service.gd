class_name PreparationService
extends Node

## Turns a recipe plus real stock into a prepared drink.
##
## The contract is strict on purpose, because a mixing system that is loose
## about stock is a duplication bug waiting to happen:
##
## [codeblock]
## reserve()   checks everything and holds what it will need, or fails
## complete()  consumes exactly what was reserved, once
## cancel()    hands every reservation back, whatever went wrong
## [/codeblock]
##
## Nothing consumes stock outside [method complete]. A staff task that is
## dropped, a station that is destroyed mid-preparation, a worker who wanders
## off - all end at [method cancel], and the ingredients come back. That is
## what keeps a failed preparation from getting stuck or eating the sugar.


signal preparation_reserved(request: PreparationRequest)
signal preparation_completed(request: PreparationRequest)
signal preparation_cancelled(request: PreparationRequest)


@export_category("Registry")

@export var registry: BeverageRegistry

@export var vessel_pool: VesselPool


@export_category("Stock Sources")

## Group name of nodes that hold ingredient items.
@export var ingredient_storage_group: StringName = &"stock_storage"

## Group name of nodes that hold liquid stock.
@export var liquid_storage_group: StringName = &"beverage_storage"


func _ready() -> void:
	add_to_group(&"preparation_service")


## Checks a recipe and reserves everything it needs.
##
## Returns a request that is either READY - with reservations held - or
## BLOCKED with a reason. Reserving is the only place stock is checked, so a
## caller never has to pre-validate.
func reserve(
	recipe: DrinkRecipeDefinition,
	format: ServingFormatDefinition = null,
	station_capabilities: Array[StringName] = [],
	batches: int = 1
) -> PreparationRequest:
	var request: PreparationRequest = PreparationRequest.new()
	request.recipe = recipe
	request.format = format
	request.batches = maxi(batches, 1)

	if recipe == null:
		request.failure_reason = PreparationRequest.Failure.NO_RECIPE
		return request

	# Station first: it is the cheapest check and the most common failure.
	var required: Array[StringName] = recipe.get_all_required_capabilities()

	if not StationCapabilities.satisfies(station_capabilities, required):
		request.failure_reason = PreparationRequest.Failure.NO_STATION
		request.missing_capabilities = StationCapabilities.get_missing(
			station_capabilities, required
		)
		return request

	var vessel_id: StringName = _get_required_vessel_id(recipe, format)

	if not vessel_id.is_empty():
		if vessel_pool == null or not vessel_pool.has_available(vessel_id):
			request.failure_reason = PreparationRequest.Failure.NO_VESSEL
			return request

	if not _check_and_reserve_ingredients(request):
		# Anything already taken during the partial pass is returned before
		# the caller ever sees the request.
		_release_reservations(request)
		return request

	if not vessel_id.is_empty():
		if not vessel_pool.reserve(vessel_id):
			_release_reservations(request)
			request.failure_reason = PreparationRequest.Failure.NO_VESSEL
			return request

		request.reserved_vessel_id = vessel_id

	request.status = PreparationRequest.Status.READY
	request.failure_reason = PreparationRequest.Failure.NONE

	preparation_reserved.emit(request)

	return request


## Consumes everything the request reserved. Returns false if already resolved.
func complete(request: PreparationRequest) -> bool:
	if request == null or not request.is_ready():
		if request != null:
			request.failure_reason = PreparationRequest.Failure.ALREADY_RESOLVED
		return false

	# Items: the reservation was a promise, so take them for real now.
	for key: Variant in request.reserved_items:
		var item_id: StringName = key
		var amount: int = int(request.reserved_items[key])

		_consume_items(item_id, amount)

	# Contents: the measures were already held off the available pool, so
	# remove them including the reservation rather than twice.
	for entry: Dictionary in request.reserved_contents:
		var batch: FilledContainer = entry.get("batch") as FilledContainer
		var amount: int = int(entry.get("amount", 0))

		if batch == null or amount <= 0:
			continue

		batch.release_reservation(amount)
		batch.remove(amount)

		if batch.is_empty():
			batch.clear_contents()

	request.status = PreparationRequest.Status.COMPLETED

	preparation_completed.emit(request)

	return true


## Abandons a request and hands everything back.
##
## Safe to call more than once and safe to call on a blocked request, which is
## what lets a task's failure path call it without checking anything first.
func cancel(request: PreparationRequest) -> void:
	if request == null:
		return

	if request.status == PreparationRequest.Status.COMPLETED:
		return

	if request.status == PreparationRequest.Status.CANCELLED:
		return

	_release_reservations(request)

	request.status = PreparationRequest.Status.CANCELLED

	preparation_cancelled.emit(request)


## Whether a recipe could be made right now, without reserving anything.
##
## Used by the UI to grey out an option. Deliberately separate from
## [method reserve] so asking the question never has a side effect.
func can_prepare(
	recipe: DrinkRecipeDefinition,
	format: ServingFormatDefinition = null,
	station_capabilities: Array[StringName] = [],
	batches: int = 1
) -> PreparationRequest:
	var request: PreparationRequest = reserve(
		recipe, format, station_capabilities, batches
	)

	if request.is_ready():
		cancel(request)
		request.status = PreparationRequest.Status.READY

	return request


# --- Internals ---------------------------------------------------------------

func _get_required_vessel_id(
	recipe: DrinkRecipeDefinition,
	format: ServingFormatDefinition
) -> StringName:
	if not recipe.required_vessel_container_id.is_empty():
		return recipe.required_vessel_container_id

	if format != null:
		return format.required_container_id

	return &""


func _check_and_reserve_ingredients(
	request: PreparationRequest
) -> bool:
	var recipe: DrinkRecipeDefinition = request.recipe
	var satisfied: bool = true

	for ingredient: RecipeIngredient in recipe.ingredients:
		if ingredient == null:
			continue

		var required: int = ingredient.get_required_quantity(request.batches)

		if ingredient.is_item():
			var available: int = _count_items(ingredient.item_id)

			if available < required:
				# An optional line that is absent is simply skipped. That is
				# how "spices where configured" works with one recipe.
				if ingredient.optional:
					continue

				satisfied = false
				request.failure_reason = (
					PreparationRequest.Failure.MISSING_INGREDIENTS
				)
				request.missing.append({
					"id": ingredient.item_id,
					"required": required,
					"available": available,
				})
				continue

			request.reserved_items[ingredient.item_id] = (
				int(request.reserved_items.get(ingredient.item_id, 0)) + required
			)
			continue

		# Content line: reserve measures out of real casks.
		var batches_found: Array = _find_content_batches(ingredient.content_id)
		var available_measures: int = BeverageTransferService.count_available(
			batches_found, ingredient.content_id
		)

		if available_measures < required:
			if ingredient.optional:
				continue

			satisfied = false
			request.failure_reason = PreparationRequest.Failure.MISSING_CONTENT
			request.missing.append({
				"id": ingredient.content_id,
				"required": required,
				"available": available_measures,
			})
			continue

		var still_needed: int = required

		for candidate: Variant in batches_found:
			if still_needed <= 0:
				break

			var batch: FilledContainer = candidate as FilledContainer

			if batch == null or batch.content_id != ingredient.content_id:
				continue

			var taken: int = batch.reserve(still_needed)

			if taken <= 0:
				continue

			still_needed -= taken

			request.reserved_contents.append({
				"batch": batch,
				"amount": taken,
			})

	return satisfied


func _release_reservations(request: PreparationRequest) -> void:
	for entry: Dictionary in request.reserved_contents:
		var batch: FilledContainer = entry.get("batch") as FilledContainer
		var amount: int = int(entry.get("amount", 0))

		if batch != null and amount > 0:
			batch.release_reservation(amount)

	request.reserved_contents.clear()
	request.reserved_items.clear()

	if not request.reserved_vessel_id.is_empty() and vessel_pool != null:
		vessel_pool.release(request.reserved_vessel_id)
		request.reserved_vessel_id = &""


func _count_items(item_id: StringName) -> int:
	var total: int = 0

	for node: Node in get_tree().get_nodes_in_group(ingredient_storage_group):
		if node.has_method(&"count_item"):
			total += int(node.call(&"count_item", item_id))

	return total


func _consume_items(item_id: StringName, amount: int) -> int:
	var remaining: int = amount

	for node: Node in get_tree().get_nodes_in_group(ingredient_storage_group):
		if remaining <= 0:
			break

		if not node.has_method(&"remove_item"):
			continue

		remaining -= int(node.call(&"remove_item", item_id, remaining))

	return amount - remaining


func _find_content_batches(content_id: StringName) -> Array:
	var found: Array = []

	for node: Node in get_tree().get_nodes_in_group(liquid_storage_group):
		if not node.has_method(&"get_batches"):
			continue

		for candidate: Variant in node.call(&"get_batches"):
			var batch: FilledContainer = candidate as FilledContainer

			if batch != null and batch.content_id == content_id:
				found.append(batch)

	return found
