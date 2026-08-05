class_name GroupOrderService
extends Node

## Chooses what a group orders, and turns that choice into a real shared drink.
##
## Selection is weighted and configurable, never hardcoded: the group's own
## definition supplies the preferences, the Beverage Framework supplies what is
## actually orderable, and this class intersects the two. Adding a drink or a
## serving format changes what groups order without touching this file.
##
## The customer chooses. The tavern does not pick a format on their behalf -
## it only refuses one it genuinely cannot make.


signal order_selected(order: GroupOrder)
signal serving_created(serving: SharedServing)
signal order_failed(order: GroupOrder)


@export_category("References")

@export var registry: BeverageRegistry
@export var vessel_pool: VesselPool
@export var preparation_service: PreparationService

@export_category("Scope")

## Whether groups may order drinks that need preparing.
##
## OFF for now. Mixed drinks, recipes and ingredients are a later pass, so a
## group orders only what can be poured straight from a cask - a pitcher, a
## table cask, a firkin. Turning this on is all that is needed to let Rum
## Punch and Drinking Chocolate back into group ordering once the preparation
## task is connected to staff.
@export var allow_prepared_drinks: bool = false

## Whether a station able to serve the drink must actually exist.
##
## Keeps groups from ordering something the tavern has no equipment for. A
## drink with no capable station is skipped during selection rather than
## failing later at the counter.
@export var require_capable_station: bool = true


@export_category("Milestone")

## Forces every shared group order to be one Ale keg.
##
## The basic group milestone is deliberately one shape: Ale in a table cask.
## Weighted selection across every drink and format still exists below and is
## used as the fallback, so turning this off restores the general behaviour
## without any other change.
@export var force_ale_table_cask: bool = true

## Drink used when [member force_ale_table_cask] is on.
@export var forced_drink_id: StringName = &"ale"

## Serving format used when [member force_ale_table_cask] is on.
@export var forced_serving_format_id: StringName = &"table_cask"

## Milestone-only switch: keeps the basic group loop testable even when the
## tavern has run out of service stock. The normal stock-aware path remains
## intact and is restored simply by turning this off in the Inspector.
@export var basic_loop_ignore_stock: bool = true


@export_category("Scene")

## Scene used for a delivered shared drink. Falls back to a bare node.
@export var shared_serving_scene: PackedScene

## Placeholder texture shown when the serving scene has no art.
@export var placeholder_texture: Texture2D


var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"group_order_service")
	_rng.randomize()


# --- Selection ---------------------------------------------------------------

## Picks a shared drink and format for [param group], or null when none fit.
##
## Walks every drink the registry knows, keeps the pairings that are both
## shared and acceptable to this group, weights them by the group's preferred
## tags, and draws one. A group that finds nothing acceptable returns null and
## the caller falls back to individual orders.
## Why the last shared order could not be chosen. Read by the group.
var last_selection_failure: String = ""


func choose_shared_order(group: CustomerGroup) -> GroupOrder:
	last_selection_failure = ""

	if group == null or registry == null:
		last_selection_failure = "no_registry"
		return null

	if force_ale_table_cask:
		var forced: GroupOrder = _choose_forced_order(group)

		if forced != null:
			return forced

		# The milestone order is the only shared order groups place. Falling
		# through to weighted selection here would quietly serve something
		# else and hide exactly the failure this reason exists to report.
		#
		# The single exception is a group the forced format cannot hold at
		# all. That is not a tavern fault and no retry will ever fix it, so
		# the group is allowed to pick something it can actually share
		# rather than being turned away for being the wrong size.
		if last_selection_failure != "group_size_outside_format_range":
			return null

	var size: int = group.get_valid_members().size()
	var definition: CustomerGroupDefinition = group.definition
	var candidates: Array[Dictionary] = []

	for drink: DrinkDefinition in registry.get_all_drinks():
		if not _is_drink_in_scope(drink):
			continue

		for format: ServingFormatDefinition in registry.get_serving_formats_for_drink(drink):
			if not format.is_shared:
				continue

			# A forced pairing narrows the field to one; a normal group has
			# none set and sees every candidate exactly as before.
			if not group.accepts_pairing(drink.item_id, format.format_id):
				continue

			if definition != null and not definition.accepts_serving_format(format, size):
				continue

			if size > format.maximum_group_size:
				continue

			# There must be enough in a cask somewhere to actually fill it.
			if find_source_station(drink, format) == null:
				continue

			# A format that needs a table is no use to a standing group.
			if format.requires_table:
				if group.place != null and group.place.is_standing():
					continue

			candidates.append({
				"drink": drink,
				"format": format,
				"weight": _score_pairing(drink, format, definition),
			})

	if candidates.is_empty():
		return null

	var chosen: Dictionary = _weighted_pick(candidates)

	if chosen.is_empty():
		return null

	var drink: DrinkDefinition = chosen["drink"]
	var format: ServingFormatDefinition = chosen["format"]

	var order: GroupOrder = GroupOrder.create(
		group.group_id,
		StringName(group.leader.name) if is_instance_valid(group.leader) else &"",
		drink.item_id,
		format.format_id,
		true
	)
	order.price = order.calculate_price(registry)
	order.destination_place_id = (
		group.place.get_place_id() if group.place != null else &""
	)

	order_selected.emit(order)

	return order


## Builds the milestone Ale keg order, or records why it cannot be made.
func _choose_forced_order(group: CustomerGroup) -> GroupOrder:
	# A group may pin its own order - the developer test group does. The
	# service defaults are used only when it has not.
	var drink_id: StringName = (
		group.required_drink_id if not group.required_drink_id.is_empty()
		else forced_drink_id
	)
	var format_id: StringName = (
		group.required_serving_format_id
		if not group.required_serving_format_id.is_empty()
		else forced_serving_format_id
	)

	var drink: DrinkDefinition = registry.get_drink(drink_id)
	var format: ServingFormatDefinition = registry.get_serving_format(format_id)

	if drink == null or format == null:
		last_selection_failure = "unknown_drink_or_format"
		return null

	var size: int = group.get_valid_members().size()

	if size > format.maximum_group_size or size < format.minimum_group_size:
		last_selection_failure = "group_size_outside_format_range"
		return null

	if format.requires_table and group.place != null and group.place.is_standing():
		last_selection_failure = "format_requires_a_table"
		return null

	var station: DrinksStation = (
		find_capable_station(drink, format, false)
		if basic_loop_ignore_stock
		else find_source_station(drink, format)
	)

	if station == null:
		last_selection_failure = _diagnose_missing_station(drink, format)
		return null

	var order: GroupOrder = GroupOrder.create(
		group.group_id,
		StringName(group.leader.name) if is_instance_valid(group.leader) else &"",
		drink.item_id,
		format.format_id,
		true
	)
	order.price = order.calculate_price(registry)
	order.destination_place_id = (
		group.place.get_place_id() if group.place != null else &""
	)

	order_selected.emit(order)

	return order


## Says which of the three station conditions actually failed.
##
## "No station" is three different problems - wrong equipment, wrong drink, or
## an empty cask - and only the third is a stock problem. Reporting them apart
## is what makes insufficient_stock mean what it says.
func _diagnose_missing_station(
	drink: DrinkDefinition,
	format: ServingFormatDefinition
) -> String:
	var fill_capability: StringName = _get_fill_capability(format)
	var saw_drink_source: bool = false
	var saw_capable_station: bool = false

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station == null or not station.can_serve_drink(drink):
			continue

		saw_drink_source = true

		if not fill_capability.is_empty():
			if not station.has_capability(fill_capability):
				continue

		saw_capable_station = true

	if not saw_drink_source:
		return "no_station_serves_%s" % String(drink.item_id)

	if not saw_capable_station:
		return "no_station_can_fill_%s" % String(format.format_id)

	return "insufficient_stock"


## Picks an individual drink and format for one member.
func choose_individual_order(
	group: CustomerGroup,
	member: Node
) -> GroupOrder:
	if group == null or registry == null:
		return null

	var definition: CustomerGroupDefinition = group.definition
	var candidates: Array[Dictionary] = []

	for drink: DrinkDefinition in registry.get_all_drinks():
		if not _is_drink_in_scope(drink):
			continue

		for format: ServingFormatDefinition in registry.get_serving_formats_for_drink(drink):
			if format.is_shared:
				continue

			if find_source_station(drink, format) == null:
				continue

			candidates.append({
				"drink": drink,
				"format": format,
				"weight": _score_pairing(drink, format, definition),
			})

	if candidates.is_empty():
		return null

	var chosen: Dictionary = _weighted_pick(candidates)

	if chosen.is_empty():
		return null

	var drink: DrinkDefinition = chosen["drink"]
	var format: ServingFormatDefinition = chosen["format"]

	var order: GroupOrder = GroupOrder.create(
		group.group_id,
		StringName(member.name) if is_instance_valid(member) else &"",
		drink.item_id,
		format.format_id,
		false
	)
	order.price = order.calculate_price(registry)

	return order


## How much this group wants this pairing.
##
## Starts from the drink's general popularity so a common ale beats a rare
## brandy by default, then multiplies for every preferred tag the pairing
## carries. Weights stay in the definition, so re-balancing who drinks what is
## a resource edit.
func _score_pairing(
	drink: DrinkDefinition,
	format: ServingFormatDefinition,
	definition: CustomerGroupDefinition
) -> float:
	var weight: float = maxf(drink.general_popularity, 0.05)

	if definition == null:
		return weight

	for tag: StringName in definition.preferred_serving_tags:
		if drink.has_tag(tag):
			weight *= 2.5

		if format.valid_drink_tags.has(tag):
			weight *= 1.5

	return weight


func _weighted_pick(candidates: Array[Dictionary]) -> Dictionary:
	var total: float = 0.0

	for candidate: Dictionary in candidates:
		total += maxf(float(candidate["weight"]), 0.0)

	if total <= 0.0:
		return candidates[_rng.randi_range(0, candidates.size() - 1)]

	var roll: float = _rng.randf() * total

	for candidate: Dictionary in candidates:
		roll -= maxf(float(candidate["weight"]), 0.0)

		if roll <= 0.0:
			return candidate

	return candidates.back()


# --- Scope and sourcing ------------------------------------------------------

## Whether this drink is inside the ordering scope configured above.
func _is_drink_in_scope(drink: DrinkDefinition) -> bool:
	if drink == null:
		return false

	if not allow_prepared_drinks and drink.requires_preparation():
		return false

	return true


## A station that could fill [param format] with [param drink] right now.
##
## Checks three things together, because all three must hold for the order to
## be servable: the station has the drink's required capabilities, it has the
## capability for this shared vessel, and it actually has the measures.
## Returns null when nothing qualifies, which removes the pairing from
## selection rather than letting a group order it and be disappointed.
func find_source_station(
	drink: DrinkDefinition,
	format: ServingFormatDefinition
) -> DrinksStation:
	return find_capable_station(drink, format, true)


## A station able to fill this format with this drink.
##
## [param require_measures] off returns a station with the right capabilities
## even when its cask is too low, which is what tells "no equipment" apart from
## "not enough in it" for diagnostics.
func find_capable_station(
	drink: DrinkDefinition,
	format: ServingFormatDefinition,
	require_measures: bool
) -> DrinksStation:
	if drink == null or format == null:
		return null

	if not require_capable_station:
		return _any_station()

	var needed_measures: int = format.measures_per_serving
	var fill_capability: StringName = _get_fill_capability(format)

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station == null or not station.can_serve_drink(drink):
			continue

		if not fill_capability.is_empty():
			if not station.has_capability(fill_capability):
				continue

		if require_measures and station.get_available_measures() < needed_measures:
			continue

		return station

	return null


## The station an existing order would draw from. Diagnostics only.
func find_source_station_for_order(order: GroupOrder) -> DrinksStation:
	if order == null or registry == null:
		return null

	return find_capable_station(
		registry.get_drink(order.drink_id),
		registry.get_serving_format(order.serving_format_id),
		false
	)


## Measures currently in the station this order draws from.
func get_stock_for_order(order: GroupOrder) -> int:
	var station: DrinksStation = find_source_station_for_order(order)

	return station.get_available_measures() if station != null else -1


## Why no shared order could be made for [param group].
##
## Walks the same candidate join as [method choose_shared_order] and reports
## the furthest point any pairing reached, so "the tavern has no cask for it"
## and "the cask is nearly empty" are never confused for each other.
func explain_shared_failure(group: CustomerGroup) -> StringName:
	if group == null or registry == null:
		return &"no_order_service"

	var size: int = group.get_valid_members().size()
	var definition: CustomerGroupDefinition = group.definition
	var acceptable_formats: int = 0
	var capable_station_found: bool = false

	for drink: DrinkDefinition in registry.get_all_drinks():
		if not _is_drink_in_scope(drink):
			continue

		for format: ServingFormatDefinition in registry.get_serving_formats_for_drink(drink):
			if not format.is_shared:
				continue

			if not group.accepts_pairing(drink.item_id, format.format_id):
				continue

			if definition != null and not definition.accepts_serving_format(format, size):
				continue

			if size > format.maximum_group_size:
				continue

			if format.requires_table:
				if group.place != null and group.place.is_standing():
					continue

			acceptable_formats += 1

			if find_capable_station(drink, format, false) != null:
				capable_station_found = true

	if acceptable_formats == 0:
		return &"no_shared_format_for_group"

	if not capable_station_found:
		return &"no_capable_station"

	return &"insufficient_stock"


## A short reason for a failed order, for the group's diagnostics.
func describe_order_failure(order: GroupOrder) -> StringName:
	if order == null:
		return &"no_order"

	match order.failure_reason:
		GroupOrder.Failure.NO_STOCK:
			return &"insufficient_stock"
		GroupOrder.Failure.NO_VESSEL:
			return &"no_vessel"
		GroupOrder.Failure.NO_STATION:
			return &"no_capable_station"
		GroupOrder.Failure.NO_STAFF:
			return &"no_staff"
		GroupOrder.Failure.CANNOT_AFFORD:
			return &"cannot_afford"
		GroupOrder.Failure.ABANDONED:
			return &"abandoned"
		_:
			return &"order_refused"


## The capability needed to fill this kind of shared vessel.
##
## Derived from the container category rather than the format id, so a new
## shared format inherits the right requirement without being listed here.
func _get_fill_capability(
	format: ServingFormatDefinition
) -> StringName:
	if not format.is_shared or registry == null:
		return &""

	var container: ContainerDefinition = registry.get_container(
		format.required_container_id
	)

	if container == null:
		return &""

	match container.category:
		ContainerDefinition.Category.PITCHER:
			return StationCapabilities.FILL_PITCHER
		ContainerDefinition.Category.BOWL:
			return StationCapabilities.FILL_SHARED_BOWL
		ContainerDefinition.Category.TABLE_CASK, \
		ContainerDefinition.Category.CASK:
			return StationCapabilities.FILL_SHARED_CASK
		_:
			return &""


func _any_station() -> DrinksStation:
	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station != null:
			return station

	return null


# --- Fulfilment --------------------------------------------------------------

## Checks an order can actually be made, reserving what it needs.
##
## A prepared drink goes through [PreparationService] so ingredients and the
## vessel are held exactly as they are for any other recipe - the group system
## does not get its own stock path. A poured drink only needs its vessel.
func reserve_order(
	order: GroupOrder,
	station_capabilities: Array[StringName] = []
) -> bool:
	if order == null or registry == null:
		return false

	var drink: DrinkDefinition = registry.get_drink(order.drink_id)
	var format: ServingFormatDefinition = registry.get_serving_format(
		order.serving_format_id
	)

	if drink == null or format == null:
		order.fail(GroupOrder.Failure.NO_STOCK)
		order_failed.emit(order)
		return false

	if drink.requires_preparation():
		if preparation_service == null:
			order.fail(GroupOrder.Failure.NO_STAFF)
			order_failed.emit(order)
			return false

		var recipe: DrinkRecipeDefinition = registry.get_recipe(drink.recipe_id)
		var request: PreparationRequest = preparation_service.reserve(
			recipe, format, station_capabilities
		)

		if not request.is_ready():
			order.fail(_map_failure(request.failure_reason))
			order_failed.emit(order)
			return false

		order.preparation_request = request
		order.status = GroupOrder.Status.RESERVED

		return true

	# Poured straight from stock. Two things must hold: a station with the
	# measures, and a free vessel. The station is checked first because a
	# vessel reserved against a drink that cannot be poured would have to be
	# handed straight back.
	var station: DrinksStation = (
		find_capable_station(drink, format, false)
		if basic_loop_ignore_stock
		else find_source_station(drink, format)
	)

	if require_capable_station and station == null:
		last_selection_failure = _diagnose_missing_station(drink, format)
		order.fail(GroupOrder.Failure.NO_STOCK)
		order_failed.emit(order)
		return false

	if vessel_pool != null and not vessel_pool.reserve_for_format(format):
		order.fail(GroupOrder.Failure.NO_VESSEL)
		order_failed.emit(order)
		return false

	order.status = GroupOrder.Status.RESERVED

	return true


## Consumes the reservation and builds the shared drink in the world.
func fulfil_order(
	order: GroupOrder,
	group: CustomerGroup
) -> SharedServing:
	if order == null or group == null or registry == null:
		return null

	if order.status != GroupOrder.Status.RESERVED:
		return null

	# One active keg per group, whatever else happens. A second call must not
	# create a second cask sitting on top of the first.
	if is_instance_valid(group.shared_serving):
		return group.shared_serving

	group.source_station_name = ""
	group.stock_before_measures = -1
	group.stock_after_measures = -1

	if order.preparation_request != null:
		if not preparation_service.complete(order.preparation_request):
			order.fail(GroupOrder.Failure.NO_STOCK)
			order_failed.emit(order)
			return null
	else:
		# Poured order: take the measures out of a station's cask now. This is
		# the only place stock leaves for a group order, so a serving can never
		# hold more than the tavern actually had.
		if not _draw_from_station(order, group):
			last_selection_failure = "insufficient_stock"
			order.fail(GroupOrder.Failure.NO_STOCK)
			order_failed.emit(order)
			return null

	var serving: SharedServing = _create_serving(order, group)

	if serving == null:
		order.fail(GroupOrder.Failure.NO_VESSEL)
		order_failed.emit(order)
		return null

	order.shared_serving = serving
	order.status = GroupOrder.Status.DELIVERED

	group.shared_serving = serving
	group.current_order = order

	serving_created.emit(serving)

	return serving


## Takes the measures a poured order needs out of a real station.
##
## Fails without taking anything when the station cannot cover the whole
## serving - a half-filled pitcher is not a thing the tavern sells.
func _draw_from_station(
	order: GroupOrder,
	group: CustomerGroup = null
) -> bool:
	# The milestone loop can deliberately ignore stock so group behaviour can
	# be tested independently from ordering, deliveries and restocking.
	if basic_loop_ignore_stock:
		if group != null:
			var diagnostic_station: DrinksStation = find_source_station_for_order(order)
			group.source_station_name = (
				String(diagnostic_station.name)
				if diagnostic_station != null else "milestone_virtual_stock"
			)
			group.stock_before_measures = (
				diagnostic_station.get_available_measures()
				if diagnostic_station != null else 0
			)
			group.stock_after_measures = group.stock_before_measures
		return true

	if not require_capable_station:
		return true

	var drink: DrinkDefinition = registry.get_drink(order.drink_id)
	var format: ServingFormatDefinition = registry.get_serving_format(
		order.serving_format_id
	)

	if drink == null or format == null:
		return false

	var station: DrinksStation = find_source_station(drink, format)

	if station == null:
		return false

	var needed: int = format.measures_per_serving

	if group != null:
		group.source_station_name = String(station.name)
		group.stock_before_measures = station.get_available_measures()

	var drawn: int = station.draw_measures(needed)

	if drawn < needed:
		# Put back anything partial rather than serving short measure.
		if drawn > 0:
			station.grant_service_stock(drawn)

		if group != null:
			group.stock_after_measures = station.get_available_measures()

		return false

	if group != null:
		group.stock_after_measures = station.get_available_measures()

	return true


func _create_serving(
	order: GroupOrder,
	group: CustomerGroup
) -> SharedServing:
	var drink: DrinkDefinition = registry.get_drink(order.drink_id)
	var format: ServingFormatDefinition = registry.get_serving_format(
		order.serving_format_id
	)

	if drink == null or format == null:
		return null

	var serving: SharedServing = null

	if shared_serving_scene != null:
		serving = shared_serving_scene.instantiate() as SharedServing

	if serving == null:
		serving = SharedServing.new()

	# Parented to the group's own parent rather than the group, so a shared
	# cask outlives a group that is freed mid-visit and can be cleaned up by
	# the normal sweep instead of vanishing with its owner.
	var parent: Node = group.get_parent()

	if parent == null:
		parent = group

	parent.add_child(serving)

	serving.group_id = group.group_id
	serving.configure(
		registry, vessel_pool, drink, format, _world_minutes()
	)

	if group.place != null and group.place.is_valid():
		serving.global_position = group.place.get_serving_position()
		serving.anchor_table = (
			group.place.table if group.place.is_seated() else null
		)
		# A standing group has no table, so eligibility falls back to the
		# group id - which every member carries.
		serving.shared_radius = maxf(
			serving.shared_radius,
			group.place.get_centre().distance_to(
				group.place.get_slot_for(0)
			) + 48.0
		)

	_add_placeholder_visual(serving)

	return serving


## Gives the serving something visible so it is not an abstract object.
func _add_placeholder_visual(serving: SharedServing) -> void:
	if serving.get_child_count() > 0:
		return

	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "PlaceholderSprite"

	if placeholder_texture != null:
		sprite.texture = placeholder_texture
	else:
		# No art yet: a plain coloured square is still better than an
		# invisible object sitting on a table.
		var image: Image = Image.create(12, 12, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.85, 0.6, 0.25))
		sprite.texture = ImageTexture.create_from_image(image)

	serving.add_child(sprite)


func _map_failure(
	reason: PreparationRequest.Failure
) -> GroupOrder.Failure:
	match reason:
		PreparationRequest.Failure.MISSING_INGREDIENTS, \
		PreparationRequest.Failure.MISSING_CONTENT:
			return GroupOrder.Failure.NO_STOCK
		PreparationRequest.Failure.NO_VESSEL:
			return GroupOrder.Failure.NO_VESSEL
		PreparationRequest.Failure.NO_STATION:
			return GroupOrder.Failure.NO_STATION
		_:
			return GroupOrder.Failure.NO_STOCK


## Cancels an order and returns everything it was holding.
func cancel_order(order: GroupOrder) -> void:
	if order == null:
		return

	if order.preparation_request != null and preparation_service != null:
		preparation_service.cancel(order.preparation_request)
		order.preparation_request = null

	if order.status == GroupOrder.Status.RESERVED and registry != null:
		var format: ServingFormatDefinition = registry.get_serving_format(
			order.serving_format_id
		)

		if format != null and vessel_pool != null:
			vessel_pool.release_for_format(format)

	if order.is_active():
		order.fail(GroupOrder.Failure.ABANDONED)


func _world_minutes() -> int:
	var world_time: Node = get_node_or_null(^"/root/WorldTime")

	if world_time == null or not world_time.has_method(&"get_timestamp"):
		return 0

	var stamp: Variant = world_time.call(&"get_timestamp")

	return int(stamp.total_minutes) if stamp != null else 0
