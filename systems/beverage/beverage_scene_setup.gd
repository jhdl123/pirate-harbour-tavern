class_name BeverageSceneSetup
extends Node

## Configures the drink stations in a scene at runtime.
##
## One node in the scene tree instead of hand-edited property overrides on
## every station instance. That is deliberate: station wiring is a list of ids
## in one resource-shaped place, so re-laying-out the bar means moving nodes,
## not re-entering capabilities on each one.
##
## Each entry names a station by node name and says what it can do. Nothing
## here is drink-specific logic - it only assigns the capability list and the
## service container the station then uses generically.


## One station's wiring.
class StationSetup extends Resource:
	@export var station_name: StringName = &""
	@export var capabilities: Array[StringName] = []
	@export var service_container_id: StringName = &"service_cask"
	@export var content_id: StringName = &""
	@export_range(0, 10000, 1) var starting_measures: int = 0


@export_category("Registry")

@export var registry: BeverageRegistry


@export_category("Stations")

## Stations to configure, by node name.
##
## Left empty, [member default_cask_capabilities] is applied to every station
## in the drink_stations group - which is what makes a freshly duplicated
## station work without being listed here.
@export var stations: Array[StationSetup] = []

## Capabilities given to any station not explicitly listed above.
@export var default_cask_capabilities: Array[StringName] = [
	StationCapabilities.DRAW_FROM_CASK,
	StationCapabilities.FILL_PITCHER,
	StationCapabilities.FILL_SHARED_CASK,
]

## Container used for a station's own service stock.
@export var default_service_container_id: StringName = &"service_cask"


@export_category("Fallback Stock")

## Fill every configured station on startup.
##
## TEMPORARY. Until deliveries feed service stock automatically, a station
## would start empty and no group could ever be served. Turn this off once the
## storage and delivery pass lands - see docs/GROUP_FRAMEWORK.md.
@export var grant_starting_stock: bool = true

## Measures granted per station when [member grant_starting_stock] is on.
@export_range(0, 10000, 1)
var starting_measures: int = 96


func _ready() -> void:
	add_to_group(&"beverage_scene_setup")

	if registry == null:
		registry = load("res://Data/beverage/beverage_registry.tres")

	# One frame's grace so every station has run its own _ready first.
	await get_tree().process_frame

	configure_all()


## Applies wiring to every drink station in the scene.
func configure_all() -> int:
	var configured: int = 0

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station == null:
			continue

		if _configure_station(station):
			configured += 1

	return configured


func _configure_station(station: DrinksStation) -> bool:
	var setup: StationSetup = _find_setup(station.name)

	station.beverage_registry = registry

	# A named setup wins; otherwise anything the scene author already put on
	# the station is respected, exactly as service_container is below. Without
	# this a bottle station authored with pour_from_bottle was silently
	# overwritten with cask capabilities and could serve nothing.
	if setup != null and not setup.capabilities.is_empty():
		station.station_capabilities = setup.capabilities.duplicate()
	elif station.station_capabilities.is_empty():
		station.station_capabilities = default_cask_capabilities.duplicate()

	var container_id: StringName = (
		setup.service_container_id if setup != null
		else default_service_container_id
	)

	if station.service_container == null and registry != null:
		station.service_container = registry.get_container(container_id)

	if setup != null and not setup.content_id.is_empty():
		station.service_content_id = setup.content_id

	# Rebuild now that the container and content are known: the station's own
	# _ready ran before this and found nothing to build.
	station.rebuild_service_batch()

	if grant_starting_stock:
		var measures: int = (
			setup.starting_measures
			if setup != null and setup.starting_measures > 0
			else starting_measures
		)

		# Never pour in more than the station says it holds. The blanket 96 is
		# right for a cask but would put twelve bottles on a shelf with room
		# for five, leaving current_servings above maximum_servings.
		var station_limit: int = (
			station.maximum_servings * station.get_measures_per_serving()
		)

		if station_limit > 0:
			measures = mini(measures, station_limit)

		station.grant_service_stock(measures)

	return true


func _find_setup(station_name: StringName) -> StationSetup:
	for setup: StationSetup in stations:
		if setup != null and setup.station_name == station_name:
			return setup

	return null


## Every station and what it can serve, for the diagnostics panel.
func get_summary() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station != null:
			rows.append(station.get_beverage_summary())

	return rows
