class_name StockAlertCoordinator
extends Node

## Turns drink-station stock states into staff-attributed tavern alerts.
##
## The division of labour here is the one the whole communication framework is
## built around:
##
## [codeblock]
## DrinksStation          owns the fact.  "I am on 3 servings, which my own
##                        configured thresholds call LOW."
## StockStorage           owns the answer to "is there a replacement?"
## this coordinator       owns the sentence, and who says it
## CommunicationService   owns whether the player has already been told
## [/codeblock]
##
## No part of that chain polls anything. Stations emit
## [signal DrinksStation.stock_state_changed] only when they cross a threshold,
## which is a handful of times per session rather than a handful of times per
## second.
##
## [b]Why the worker is only the messenger[/b]
##
## The alert is created the instant the station crosses its threshold,
## regardless of whether any staff exist, whether they are paused, busy,
## off-screen or unable to reach the player. A worker is attached as the
## speaker if one is available, and a speech bubble is shown if it happens to
## be somewhere useful - but neither is allowed to gate the warning. A stock
## warning you did not get because the barman was stuck behind a table is worse
## than no staff at all.


@export_category("Wiring")

## Where replacement stock is kept. Found by group when left empty.
@export var stock_storage: StockStorage


@export_category("Behaviour")

## Whether an available worker is named as the speaker on stock alerts.
@export var attribute_alerts_to_staff: bool = true

## Whether the speaker also shows a speech bubble over their head.
##
## Cosmetic only, and deliberately separate from the alert itself.
@export var show_speech_bubbles: bool = true


@export_category("Debug")

@export var show_debug_messages: bool = false


## Stations we have already wired up.
var _connected_stations: Array[DrinksStation] = []


func _ready() -> void:
	call_deferred(&"_connect_stations")


func _connect_stations() -> void:
	if stock_storage == null:
		stock_storage = _find_storage()

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station == null or _connected_stations.has(station):
			continue

		if not station.stock_state_changed.is_connected(
			_on_station_stock_state_changed
		):
			station.stock_state_changed.connect(
				_on_station_stock_state_changed.bind(station)
			)

		_connected_stations.append(station)

		# A station that starts the session already low should say so.
		if station.get_stock_state() != DrinksStation.StockState.OK:
			_on_station_stock_state_changed(
				DrinksStation.StockState.OK,
				station.get_stock_state(),
				station
			)


func _find_storage() -> StockStorage:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(&"stock_storage")

	if nodes.is_empty():
		return null

	return nodes[0] as StockStorage


# -----------------------------------------------------------------------------
# Reacting to stations
# -----------------------------------------------------------------------------

func _on_station_stock_state_changed(
	_previous: DrinksStation.StockState,
	current: DrinksStation.StockState,
	station: DrinksStation
) -> void:
	if station == null or not is_instance_valid(station):
		return

	var key: String = _get_alert_key(station)

	if current == DrinksStation.StockState.OK:
		# Refilled past the reset threshold. The condition has genuinely
		# cleared, so the alert withdraws itself and the log records why.
		if Comms.resolve_by_key(key, &"stock_restored"):
			if show_debug_messages:
				print("[StockAlerts] ", station.name, " restored - alert cleared")

		return

	_raise_stock_alert(station, current, key)


func _raise_stock_alert(
	station: DrinksStation,
	state: DrinksStation.StockState,
	key: String
) -> void:
	var replacement: int = _count_replacement_stock(station)
	var is_empty: bool = state == DrinksStation.StockState.EMPTY
	var has_replacement: bool = replacement > 0

	var drink_name: String = (
		"stock" if station.served_drink == null
		else station.served_drink.display_name
	)

	var message: CommMessage = CommMessage.new()

	message.type = CommMessage.Type.ALERT
	message.category = CommMessage.Category.STOCK
	message.deduplication_key = key
	message.group_key = "station:%d" % station.get_instance_id()
	message.is_persistent = true
	message.auto_dismiss_seconds = 0.0
	message.set_source(station)

	# Two things make this worse: being empty rather than low, and having no
	# replacement, because that one cannot be fixed without placing an order.
	message.severity = (
		CommMessage.Severity.CRITICAL if (is_empty or not has_replacement)
		else CommMessage.Severity.WARNING
	)

	message.title = (
		"%s has run out" % drink_name if is_empty
		else "%s is running low" % drink_name
	)

	message.body = _build_sentence(drink_name, is_empty, has_replacement)

	message.details = [
		"%s: %d serving%s remaining" % [
			station.get_interaction_display_name(),
			station.current_servings,
			("" if station.current_servings == 1 else "s"),
		],
		_describe_replacement(station, replacement),
	]

	# The alert withdraws itself the moment the station is genuinely restocked,
	# with nothing having to remember to call resolve().
	message.auto_resolve = func() -> bool:
		if station == null or not is_instance_valid(station):
			return true

		return station.get_stock_state() == DrinksStation.StockState.OK

	message.metadata = {
		"station": String(station.name),
		"servings": station.current_servings,
		"replacement_stock": replacement,
	}

	_attach_speaker(message)

	var posted: CommMessage = Comms.post(message)

	if posted != null and show_debug_messages:
		print(
			"[StockAlerts] ",
			station.name,
			" -> ",
			posted.get_severity_name(),
			" (",
			posted.deduplication_count + 1,
			" post(s))"
		)


func _build_sentence(
	drink_name: String,
	is_empty: bool,
	has_replacement: bool
) -> String:
	if is_empty and not has_replacement:
		return (
			"We are out of %s, and there is nothing in storage to refill it."
			% drink_name.to_lower()
		)

	if is_empty:
		return (
			"The %s is empty - there is stock in storage waiting to go on."
			% drink_name.to_lower()
		)

	if not has_replacement:
		return (
			"We are nearly out of %s, and there are no replacements in storage."
			% drink_name.to_lower()
		)

	return "The %s barrel is nearly empty." % drink_name.to_lower()


func _describe_replacement(
	station: DrinksStation,
	replacement: int
) -> String:
	if station.refill_item == null:
		return "Replacement stock: not configured for this station"

	if replacement <= 0:
		return "Replacement stock: none - an order is needed"

	return "Replacement stock: %d x %s in storage" % [
		replacement,
		station.refill_item.display_name,
	]


# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------

## How many refill items for [param station] are actually in storage.
##
## Asks the real [ItemContainer], which totals across every matching stack, so
## two half-shelves of kegs are counted correctly and nothing here keeps a
## second copy of the tavern's inventory that could drift out of step.
func _count_replacement_stock(
	station: DrinksStation
) -> int:
	if station == null or station.refill_item == null:
		return 0

	if stock_storage == null:
		stock_storage = _find_storage()

	if stock_storage == null or stock_storage.inventory == null:
		return 0

	return stock_storage.inventory.get_total_quantity(
		station.refill_item.item_id
	)


func _get_alert_key(
	station: DrinksStation
) -> String:
	# One key per station covers both LOW and EMPTY on purpose: they are the
	# same condition getting worse, so the second must escalate the first
	# rather than appearing beside it.
	return "stock:%d" % station.get_instance_id()


# -----------------------------------------------------------------------------
# Speakers
# -----------------------------------------------------------------------------

func _attach_speaker(
	message: CommMessage
) -> void:
	if not attribute_alerts_to_staff:
		return

	# Whoever can actually do something about an empty barrel: the role that
	# refills stations. Falls through to any speaker, then to the neutral
	# station voice set by the caller.
	var speaker: Node = Comms.find_speaker_for_capability(
		StaffCapabilities.REFILL_STATIONS
	)

	if speaker == null:
		# Nobody appropriate exists - no bartender hired, or the only staff
		# are disabled. The station speaks for itself rather than borrowing a
		# worker's name, which keeps "who is telling me this" honest.
		message.speaker_id = &"station"
		var source_node: Node = message.get_source()

		message.speaker_name = (
			"Tavern" if source_node == null else String(source_node.name)
		)

		return

	if speaker.has_method(&"get_staff_id"):
		message.speaker_id = speaker.call(&"get_staff_id")

	message.speaker_name = String(
		speaker.call(&"get_interaction_display_name")
	) if speaker.has_method(&"get_interaction_display_name") else String(
		speaker.name
	)

	# Only bubble a warning the first time it is raised, not on every update,
	# or a station draining slowly would have the worker muttering constantly.
	if not show_speech_bubbles:
		return

	if Comms.has_active(message.deduplication_key):
		return

	if speaker.has_method(&"say"):
		speaker.call(&"say", message.body)
