class_name DrinksStation
extends StaticBody2D

signal stock_changed(current: int, maximum: int)

## Servings actually leaving the station.
##
## The authoritative stock-usage event. Deliberately separate from
## [signal stock_changed], which also fires on refills: usage is what was
## consumed, not what the level happens to be now.
signal serving_consumed(item_id: StringName, quantity: int)

## Phase 3A: the station's own judgement of its stock level changed.
##
## Deliberately not the same as [signal stock_changed], which fires on every
## single serving. This fires only when the station crosses one of its
## configured thresholds, which is a few times a session rather than a few
## times a minute - and that difference is the whole reason the player is not
## drowned in warnings. See [method _evaluate_stock_state].
signal stock_state_changed(
	previous: StockState,
	current: StockState
)


## What the station thinks of its own stock level.
##
## The station owns this fact. The communication system owns what, if
## anything, the player is told about it.
enum StockState {
	## Comfortable. Nothing to say.
	OK,

	## Below the low threshold. Worth a warning.
	LOW,

	## Nothing left to pour.
	EMPTY,
}

@export_category("Drink")
@export var served_drink: DrinkDefinition
@export var refill_item: ItemDefinition
@export_range(1, 999, 1) var maximum_servings: int = 20
@export_range(0, 999, 1) var starting_servings: int = 20
@export_range(1, 999, 1) var servings_per_refill_item: int = 20

@export_category("Beverage Framework")

## What this station is able to do - see [StationCapabilities].
##
## A drink or recipe declares the capabilities it needs; this is the other
## half of that join. Empty means the station is un-migrated and falls back to
## the legacy single-drink behaviour, which is why existing scenes keep
## working untouched.
@export var station_capabilities: Array[StringName] = []

## The tapped cask, keg or bottle this station serves out of.
##
## When set, stock becomes real measures in a [FilledContainer] rather than an
## integer counter, and the station can be filled from bulk storage. When left
## empty, [member current_servings] stays authoritative exactly as before.
@export var service_container: ContainerDefinition

## Content the service container is tapped with.
##
## Normally left empty and taken from [member served_drink]'s content_id, so a
## station only needs configuring when it serves something other than its
## drink's default liquid.
@export var service_content_id: StringName = &""

@export var beverage_registry: BeverageRegistry

@export_category("Stock Alerts")

## Servings at or below which the station reports [constant StockState.LOW].
##
## Four is roughly "one more round". Tuned per station because a station
## holding twenty servings and one holding sixty should not warn at the same
## absolute number.
@export_range(0, 999, 1) var low_stock_threshold: int = 4

## Servings the station must climb back to before it reports OK again.
##
## Must be comfortably above [member low_stock_threshold]. The gap between them
## is the hysteresis: without it, a station sitting exactly on the threshold
## would flip between LOW and OK on every pour and raise a fresh warning each
## time.
@export_range(0, 999, 1) var stock_reset_threshold: int = 8

@export_category("Interaction")
@export var serve_verb: String = "Pour"
@export var return_verb: String = "Put back"
@export var refill_verb: String = "Refill"

@export_category("Visuals")
@export var normal_texture: Texture2D
@export var empty_texture: Texture2D
@export_range(2, 20, 1) var indicator_segments: int = 10

@export_category("Debug")
@export var show_transfer_messages: bool = false

@onready var interactable: Interactable = $InteractionArea
@onready var sprite: Sprite2D = $Sprite2D

var output_container: ItemContainer
var current_servings: int = 0
var _indicator: VBoxContainer

## The real stock at this station, when it has been migrated.
##
## Null on a legacy station. Everything that reads stock goes through
## [member current_servings], which is kept in step with this batch, so no
## caller has to know which mode the station is in.
var _service_batch: FilledContainer = null

## Current stock judgement. Only ever changed by _evaluate_stock_state().
var _stock_state: StockState = StockState.OK

func _ready() -> void:
	add_to_group(&"drink_stations")
	_build_output_container()
	_build_service_batch()
	current_servings = clampi(starting_servings, 0, maximum_servings)
	_sync_batch_from_servings()
	_validate_stock_thresholds()
	_stock_state = _calculate_stock_state(StockState.OK)
	_build_indicator()
	if normal_texture == null and sprite != null:
		normal_texture = sprite.texture
	_refresh_output()
	_refresh_visuals()

func _build_output_container() -> void:
	var rules := ItemSlotRules.new()
	rules.capacity = 1
	rules.accepted_tags = [ItemTags.PREPARED_DRINK]
	rules.allow_insert = true
	rules.allow_remove = true
	rules.allow_merge = false
	rules.allow_swap = true
	rules.allow_partial = false
	output_container = ItemContainer.new(StringName("%s_output" % name.to_snake_case()), 1, rules)
	output_container.container_tags = [&"station", &"service"]

func get_output_slot() -> ItemSlot:
	return output_container.get_slot(0) if output_container != null else null

func get_interaction_display_name() -> String:
	return "%s Station" % served_drink.display_name if served_drink != null else String(name).capitalize()

func can_interact(request: InteractionRequest) -> bool:
	return served_drink != null and request.get_actor_carrier() != null

func get_interaction_actions(request: InteractionRequest) -> Array[InteractionAction]:
	var actions: Array[InteractionAction] = []
	var carrier := request.get_actor_carrier()
	if carrier == null or served_drink == null:
		return actions
	if refill_item != null and carrier.is_carrying_item(refill_item.item_id):
		var refill_action := InteractionAction.create(&"refill", refill_verb, get_interaction_display_name())
		if current_servings >= maximum_servings:
			refill_action.as_unavailable("Already full")
		actions.append(refill_action)
		return actions
	if carrier.is_carrying_item(served_drink.item_id):
		actions.append(InteractionAction.create(&"return", return_verb, served_drink.display_name))
		return actions
	var verb := serve_verb if not carrier.is_carrying() else "Swap for"
	var action := InteractionAction.create(&"serve", verb, "%s (%d/%d)" % [served_drink.display_name, current_servings, maximum_servings])
	if current_servings <= 0:
		action.as_unavailable("Empty - needs %s" % (refill_item.display_name if refill_item != null else "stock"))
	else:
		var predicted := ItemTransferService.can_transfer(get_output_slot(), carrier.get_slot())
		if not predicted.is_success():
			action.as_unavailable(predicted.get_message().trim_suffix("."))
	actions.append(action)
	return actions

func perform_interaction(request: InteractionRequest) -> bool:
	var carrier := request.get_actor_carrier()
	if carrier == null:
		return false
	match request.action_id:
		&"refill": return _refill_from_carrier(carrier)
		&"return": return _return_carried_drink(carrier)
		_: return _serve_drink(carrier)


## Staff-facing equivalent of the normal pour interaction.
func staff_dispense_to(carrier: ItemCarrier) -> bool:
	return _serve_drink(carrier)

## Staff-facing equivalent of the normal refill interaction.
func staff_refill_from(carrier: ItemCarrier) -> bool:
	return _refill_from_carrier(carrier)

func _serve_drink(carrier: ItemCarrier) -> bool:
	if current_servings <= 0:
		return false
	_refresh_output()
	var output_slot := get_output_slot()
	var result := carrier.take_from(output_slot)
	if not result.is_success():
		return false
	if result.status == ItemTransferResult.Status.SWAPPED:
		_on_drink_returned(output_slot.clear())
	var consumed: int = mini(current_servings, 1)

	# Migrated stations draw real measures; legacy ones decrement the counter.
	# Both end up with current_servings correct, so every existing reader -
	# the task coordinator, the stock alerts, the UI - is unaffected.
	if _service_batch != null:
		var measures: int = get_measures_per_serving()
		var drawn: BeverageTransferResult = BeverageTransferService.draw(
			_service_batch, measures
		)

		if not drawn.is_success():
			return false

		_sync_servings_from_batch()
	else:
		current_servings = maxi(current_servings - 1, 0)

	if consumed > 0 and served_drink != null:
		serving_consumed.emit(served_drink.item_id, consumed)
	_refresh_output()
	_refresh_visuals()
	return true

func _return_carried_drink(carrier: ItemCarrier) -> bool:
	if not carrier.is_carrying_item(served_drink.item_id):
		return false
	_on_drink_returned(carrier.clear_carried_item())
	_refresh_visuals()
	return true

func _refill_from_carrier(carrier: ItemCarrier) -> bool:
	if refill_item == null or not carrier.is_carrying_item(refill_item.item_id):
		return false
	if current_servings >= maximum_servings:
		return false
	carrier.clear_carried_item()
	current_servings = mini(
		current_servings + servings_per_refill_item, maximum_servings
	)
	_sync_batch_from_servings()
	_refresh_output()
	_refresh_visuals()
	return true

func _refresh_output() -> void:
	var slot := get_output_slot()
	if slot == null:
		return
	if current_servings <= 0:
		slot.clear()
		return
	if slot.is_empty() and served_drink != null:
		ItemTransferService.give_to_slot(slot, ItemStack.create(served_drink, 1))

func _build_indicator() -> void:
	_indicator = VBoxContainer.new()
	_indicator.position = Vector2(23, -34)
	_indicator.add_theme_constant_override("separation", 1)
	_indicator.visible = false
	add_child(_indicator)
	for _i in range(indicator_segments):
		var segment := ColorRect.new()
		segment.custom_minimum_size = Vector2(7, 4)
		_indicator.add_child(segment)


func set_interaction_highlighted(enabled: bool, _request: InteractionRequest) -> void:
	if _indicator != null:
		_indicator.visible = enabled or current_servings <= 0
	var highlight := get_node_or_null("InteractionHighlight")
	if highlight != null and highlight.has_method(&"set_highlighted"):
		highlight.call(&"set_highlighted", enabled)

func _refresh_visuals() -> void:
	if sprite != null:
		if current_servings <= 0 and empty_texture != null:
			sprite.texture = empty_texture
		elif normal_texture != null:
			sprite.texture = normal_texture
	if _indicator != null:
		var filled := ceili(float(current_servings) / float(maximum_servings) * indicator_segments)
		var children := _indicator.get_children()
		for i in range(children.size()):
			children[i].color = Color(0.25, 0.8, 0.35, 1) if i >= indicator_segments - filled else Color(0.16, 0.12, 0.09, 0.8)
		_indicator.visible = _indicator.visible or current_servings <= 0
	stock_changed.emit(current_servings, maximum_servings)
	_evaluate_stock_state()
	if interactable != null:
		interactable.notify_state_changed()

func set_servings(amount: int) -> void:
	current_servings = clampi(amount, 0, maximum_servings)
	_sync_batch_from_servings()
	_refresh_output()
	_refresh_visuals()

func fill_stock() -> void:
	set_servings(maximum_servings)

func empty_stock() -> void:
	set_servings(0)

## The station's stock level right now.
func get_stock_state() -> StockState:
	return _stock_state


func get_stock_state_name() -> String:
	return StockState.keys()[_stock_state]


## Re-judges the stock level and announces a genuine change.
##
## Called from _refresh_visuals(), so every path that alters stock - pouring,
## refilling, a developer tool, a future automatic restock - runs through it
## without any of them having to remember to.
func _evaluate_stock_state() -> void:
	var previous: StockState = _stock_state
	var current: StockState = _calculate_stock_state(previous)

	if current == previous:
		return

	_stock_state = current

	stock_state_changed.emit(previous, current)


## The hysteresis rule, in one place.
##
## Falling is immediate: the moment stock drops to the threshold the station
## says so. Recovering is deliberate: it takes a real refill up to the reset
## threshold, not one serving being put back, before the station is willing to
## call itself healthy again.
func _calculate_stock_state(
	previous: StockState
) -> StockState:
	if current_servings <= 0:
		return StockState.EMPTY

	if current_servings >= stock_reset_threshold:
		return StockState.OK

	if previous == StockState.OK:
		return (
			StockState.LOW if current_servings <= low_stock_threshold
			else StockState.OK
		)

	# Already LOW or EMPTY and not yet back above the reset threshold. A
	# partly-refilled station is LOW rather than OK, which is honest: it can
	# pour, but it still needs attention.
	return StockState.LOW


func _validate_stock_thresholds() -> void:
	if stock_reset_threshold > low_stock_threshold:
		return

	push_warning(
		"%s has stock_reset_threshold (%d) at or below low_stock_threshold "
		% [name, stock_reset_threshold]
		+ "(%d), which leaves no hysteresis and will produce repeated "
		% low_stock_threshold
		+ "warnings. Raise the reset threshold."
	)


func get_stock_summary() -> Dictionary:
	return {"name": get_interaction_display_name(), "current": current_servings, "maximum": maximum_servings, "refill_item": refill_item}

func interact(player: Node) -> void:
	perform_interaction(InteractionRequest.create(player, interactable))

func _on_drink_returned(returned_stack: ItemStack) -> void:
	if show_transfer_messages and returned_stack != null and not returned_stack.is_empty():
		print(name, " took back ", returned_stack.get_display_name())


# --- Beverage Framework ------------------------------------------------------
#
# Everything below is additive. A station with no service_container configured
# never enters any of it and behaves exactly as it did before the framework.


## Builds the tapped container this station serves from, when configured.
func _build_service_batch() -> void:
	if service_container == null:
		return

	var content_id: StringName = get_service_content_id()

	if content_id.is_empty():
		push_warning(
			"%s has a service container but no content to put in it. "
			% name
			+ "Set service_content_id, or give its drink a content_id."
		)
		return

	if beverage_registry == null:
		# Nothing is wrong yet. BeverageSceneSetup supplies the registry a
		# frame after every station's _ready() and then calls
		# rebuild_service_batch(), so warning here fires on every start-up for
		# every scene-authored station and says "falling back to legacy
		# servings" about a batch that is about to be built correctly.
		return

	var content: BeverageContentDefinition = beverage_registry.get_content(
		content_id
	)

	if content == null:
		push_warning(
			"%s cannot resolve content '%s'. Falling back to legacy servings."
			% [name, String(content_id)]
		)
		return

	_service_batch = FilledContainer.create(
		service_container, content, 0, _get_world_minutes()
	)
	_service_batch.sealed = false
	_service_batch.storage_location_id = StringName(name.to_snake_case())


## The liquid this station is tapped with.
func get_service_content_id() -> StringName:
	if not service_content_id.is_empty():
		return service_content_id

	if served_drink != null:
		return served_drink.content_id

	return &""


## Measures one serving costs, from the drink's default serving format.
##
## Falls back to one so a station is never able to pour for free.
func get_measures_per_serving() -> int:
	if beverage_registry == null or served_drink == null:
		return 1

	var format_id: StringName = served_drink.get_default_serving_format_id()

	if format_id.is_empty():
		return 1

	var format: ServingFormatDefinition = beverage_registry.get_serving_format(
		format_id
	)

	if format == null:
		return 1

	return maxi(format.measures_per_serving, 1)


func has_service_batch() -> bool:
	return _service_batch != null


func get_service_batch() -> FilledContainer:
	return _service_batch


## True when this station can serve [param drink] in [param format].
##
## The whole point of the capability system: no drink name appears in this
## script, and a new drink needing a capability this station has works
## immediately.
func can_serve_drink(
	drink: DrinkDefinition,
	format: ServingFormatDefinition = null
) -> bool:
	if drink == null:
		return false

	# An un-migrated station keeps its old single-drink rule.
	if station_capabilities.is_empty():
		return served_drink != null and served_drink.item_id == drink.item_id

	if not StationCapabilities.satisfies(
		station_capabilities, get_required_capabilities(drink)
	):
		return false

	if not _holds_content_for(drink):
		return false

	if format != null and not drink.is_compatible_with_format(format):
		return false

	return true


## Whether what is actually tapped here could pour [param drink].
##
## Capabilities alone say a station CAN draw from a cask; they say nothing
## about what is in it. Without this check every cask station answered yes to
## every cask drink, so an Ale order was happily sourced from the Grog cask and
## drew kill-devil measures. Stations with nothing tapped are left alone, so an
## unconfigured or legacy station behaves exactly as it did before.
func _holds_content_for(drink: DrinkDefinition) -> bool:
	# A prepared drink is built from ingredients rather than poured straight
	# out of this station's cask, so its content is not the deciding factor.
	if drink.requires_preparation():
		return true

	var tapped: StringName = get_service_content_id()

	if tapped.is_empty() or drink.content_id.is_empty():
		return true

	return tapped == drink.content_id


## Every capability [param drink] needs here, drink AND recipe.
##
## A prepared drink like Coffee declares nothing on the drink itself - its
## requirements live on the recipe, because that is where the method is
## described. Reading only the drink's own list let a plain cask station
## "brew" coffee, so both are merged in one place that every caller uses.
func get_required_capabilities(
	drink: DrinkDefinition
) -> Array[StringName]:
	if drink == null:
		return []

	var required: Array[StringName] = drink.required_station_capabilities.duplicate()

	if not drink.requires_preparation() or beverage_registry == null:
		return required

	var recipe: DrinkRecipeDefinition = beverage_registry.get_recipe(
		drink.recipe_id
	)

	if recipe == null:
		return required

	for capability: StringName in recipe.get_all_required_capabilities():
		if not required.has(capability):
			required.append(capability)

	return required


## Capabilities [param drink] needs that this station does not have.
func get_missing_capabilities(
	drink: DrinkDefinition
) -> Array[StringName]:
	if drink == null:
		return []

	return StationCapabilities.get_missing(
		station_capabilities, get_required_capabilities(drink)
	)


func has_capability(capability: StringName) -> bool:
	return station_capabilities.has(capability)


## Fills this station's service container from a bulk source.
##
## The bulk-to-service half of the transfer framework. Returns a result rather
## than a bool so the UI can report a mismatch or a full destination.
func receive_transfer(
	source: FilledContainer,
	measures: int = -1
) -> BeverageTransferResult:
	if _service_batch == null:
		return BeverageTransferResult.failure(
			FilledContainer.Refusal.CONTAINER_MISSING
		)

	var requested: int = (
		measures if measures > 0 else _service_batch.get_remaining_capacity()
	)

	var result: BeverageTransferResult = BeverageTransferService.transfer(
		source,
		_service_batch,
		requested,
		_get_world_minutes(),
		beverage_registry
	)

	if result.is_success():
		_sync_servings_from_batch()
		_refresh_output()
		_refresh_visuals()

	return result


## Recalculates the serving counter from the real stock in the container.
func _sync_servings_from_batch() -> void:
	if _service_batch == null:
		return

	var measures: int = get_measures_per_serving()

	@warning_ignore("integer_division")
	current_servings = clampi(
		int(_service_batch.quantity / measures), 0, maximum_servings
	)


## Seeds the container from the station's starting servings.
##
## Lets an authored station keep using starting_servings in the inspector
## while still holding real measures underneath.
func _sync_batch_from_servings() -> void:
	if _service_batch == null:
		return

	var wanted: int = current_servings * get_measures_per_serving()
	var content_id: StringName = get_service_content_id()

	_service_batch.clear_contents()
	_service_batch.add(
		wanted, content_id, _get_world_minutes(), beverage_registry
	)
	_service_batch.sealed = false

	_sync_servings_from_batch()


## Everything the management UI and diagnostics panel want to show.
func get_beverage_summary() -> Dictionary:
	var summary: Dictionary = {
		"station": get_interaction_display_name(),
		"migrated": _service_batch != null,
		"capabilities": station_capabilities,
		"drink_id": served_drink.item_id if served_drink != null else &"",
		"drink_name": served_drink.display_name if served_drink != null else "",
		"servings": current_servings,
		"maximum_servings": maximum_servings,
		"measures_per_serving": get_measures_per_serving(),
		"stock_state": get_stock_state_name(),
	}

	if _service_batch == null:
		return summary

	summary["container_name"] = (
		_service_batch.container.get_display_name_with_explanation()
		if _service_batch.container != null
		else "Unknown"
	)
	summary["content_id"] = _service_batch.content_id
	summary["measures"] = _service_batch.quantity
	summary["measures_maximum"] = _service_batch.get_maximum_quantity()
	summary["reserved"] = _service_batch.reserved_quantity
	summary["fill"] = _service_batch.get_fill_fraction()

	if beverage_registry != null:
		summary["display_name"] = _service_batch.get_display_name(
			beverage_registry
		)
		summary["freshness"] = _service_batch.get_freshness(
			_get_world_minutes(), beverage_registry
		)

	return summary


func to_save_dict() -> Dictionary:
	var data: Dictionary = {
		"station_name": String(name),
		"current_servings": current_servings,
	}

	if _service_batch != null:
		data["batch"] = _service_batch.to_save_dict()

	return data


func from_save_dict(data: Dictionary) -> void:
	current_servings = clampi(
		int(data.get("current_servings", 0)), 0, maximum_servings
	)

	if data.has("batch") and beverage_registry != null:
		var restored: FilledContainer = FilledContainer.from_save_dict(
			data["batch"], beverage_registry
		)

		if restored != null:
			_service_batch = restored
			_sync_servings_from_batch()

	_refresh_output()
	_refresh_visuals()


func _get_world_minutes() -> int:
	var world_time: Node = get_node_or_null(^"/root/WorldTime")

	if world_time == null or not world_time.has_method(&"get_timestamp"):
		return 0

	var stamp: Variant = world_time.call(&"get_timestamp")

	return int(stamp.total_minutes) if stamp != null else 0


## Rebuilds the service container after its configuration changed.
##
## Needed because a station's _ready runs before any scene-level setup node can
## assign its container and content. Safe to call at any time; a station with
## no container configured simply stays on the legacy counter.
func rebuild_service_batch() -> void:
	if service_container == null:
		return

	var previous_quantity: int = (
		_service_batch.quantity if _service_batch != null else 0
	)

	_service_batch = null
	_build_service_batch()

	if _service_batch != null and previous_quantity > 0:
		_service_batch.add(
			previous_quantity,
			get_service_content_id(),
			_get_world_minutes(),
			beverage_registry
		)
		_sync_servings_from_batch()


## Puts [param measures] into the service container directly.
##
## TEMPORARY convenience for setup and debugging. Real stock should arrive by
## transfer from bulk storage - see receive_transfer(). This exists so a
## station is not empty before the delivery chain is connected.
func grant_service_stock(measures: int) -> int:
	if _service_batch == null or measures <= 0:
		return 0

	var added: int = _service_batch.add(
		measures,
		get_service_content_id(),
		_get_world_minutes(),
		beverage_registry
	)

	if added > 0:
		_service_batch.sealed = false
		_sync_servings_from_batch()
		_refresh_output()
		_refresh_visuals()

	return added


## Draws [param measures] out for a shared serving.
##
## The path a group order takes: real measures leave the station's cask, so a
## pitcher or table cask costs the tavern exactly what it holds. Returns how
## many were actually drawn.
func draw_measures(measures: int) -> int:
	if _service_batch == null or measures <= 0:
		return 0

	var result: BeverageTransferResult = BeverageTransferService.draw(
		_service_batch, measures
	)

	if not result.is_success():
		return 0

	_sync_servings_from_batch()
	_refresh_output()
	_refresh_visuals()

	return result.amount_moved


## Measures available for a shared order right now.
func get_available_measures() -> int:
	if _service_batch == null:
		# Legacy station: fall back to the serving counter so a group order
		# can still be costed against it.
		return current_servings * get_measures_per_serving()

	return _service_batch.get_available_quantity()
