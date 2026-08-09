@tool
class_name StockedDisplay
extends StaticBody2D

## A world object whose visible contents stand for stored stock.
##
## Bottle shelves, cask stacks and wine crates are all this node with a
## different unit texture and a different list of unit offsets. That is
## deliberate: the only thing that actually varies between them is what one
## unit looks like and where the units sit, so a new kind of store is a scene
## with data on it rather than another script.
##
## Set [member storage_backed] and the prop becomes a real
## [BeverageStorage] location: deliveries land in it, and the number of units
## on show is recomputed from what is actually stored. Leave it off and the
## prop is pure scenery with an inspector-driven unit count, which is what
## decoration wants.

## Emitted whenever the number of units on show changes.
signal visible_units_changed(current: int, capacity: int)


@export_category("Identity")

## Beverage content this store holds - see [BeverageRegistry] contents.
##
## Matches a [BeverageContentDefinition] id such as [code]&"ale"[/code] or
## [code]&"madeira"[/code]. Left empty the prop is pure decoration.
@export var content_id: StringName = &"":
	set(value):
		content_id = value
		update_configuration_warnings()

## Shown in the interaction prompt and diagnostics.
@export var display_name: String = "Storage"


@export_category("Stock display")

## Texture used for one unit - one bottle, one cask, one crate.
@export var unit_texture: Texture2D:
	set(value):
		unit_texture = value
		_rebuild_units()

## Where each unit sits, relative to this node.
##
## Authored rather than generated. The hand-placed layout is the art, and
## evenly spacing them in code would move every bottle by a pixel or two.
## Order is draw order: units are hidden from the END of this list first, so
## list them in the order they should disappear last-in-first-out.
@export var unit_offsets: Array[Vector2] = []:
	set(value):
		unit_offsets = value
		_visible_units = mini(_visible_units, value.size()) if _visible_units >= 0 else -1
		_rebuild_units()

## How many units are on show. -1 means all of them.
##
## The whole point of this node. When the delivery pass lands it will drive
## this from real stock; until then it is an inspector value.
@export_range(-1, 64, 1) var visible_units: int = -1:
	set(value):
		set_visible_units(value)
	get:
		return _visible_units

## Units are drawn on top of the backing sprite by this much.
@export_range(-4096, 4096, 1) var unit_z_index: int = 0:
	set(value):
		unit_z_index = value
		_rebuild_units()


@export_category("Collision")

## Overrides the size of the scene's own CollisionShape2D.
##
## Zero leaves the shape exactly as the scene authored it. Exported so three
## differently sized cask piles are three configured instances of one scene
## rather than three scenes - the shape is duplicated per instance, so setting
## it never resizes its siblings.
@export var collision_size: Vector2 = Vector2.ZERO

## Moves the collision shape relative to this node.
@export var collision_offset: Vector2 = Vector2.ZERO


@export_category("Storage")

## Whether this prop holds real stock.
##
## Off, it is scenery and [member visible_units] is whatever the inspector
## says. On, it owns a [BeverageStorage] child, joins the
## [code]beverage_storage[/code] group so deliveries can be routed to it, and
## drives its own unit count from what is stored.
@export var storage_backed: bool = false:
	set(value):
		storage_backed = value
		update_configuration_warnings()

## Stable id for the owned [BeverageStorage].
@export var storage_location_id: StringName = &""

## Storage tags this location offers - see [BeverageTags].
@export var storage_tags: Array[StringName] = []

## Container one visible unit represents - see [ContainerDefinition] ids.
##
## A shelf bottle is a [code]bottle[/code]; a stacked cask is a
## [code]firkin[/code]. Units shown = stored measures of [member content_id]
## divided by this container's capacity.
@export var container_id: StringName = &""

## Beverage registry, needed to resolve content and container capacity.
@export var registry: BeverageRegistry

## Delivery preference against other storage - see
## [member BeverageStorage.storage_priority]. Visible stores outrank the
## abstract Cellar so stock lands where the player can see it.
@export_range(-100, 100, 1)
var storage_priority: int = 10

## A [DrinksStation] whose stock this prop displays instead of its own.
##
## For a back-bar shelf the bottles on show ARE the station's stock: pour one
## and it leaves the shelf. Pointing at a station is mutually exclusive with
## [member storage_backed] - two sources of truth for the same bottles is how
## a display and its stock drift apart.
@export var mirror_station: NodePath


var _visible_units: int = -1
var _units_root: Node2D = null
var _storage: BeverageStorage = null
var _mirrored_station: DrinksStation = null


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(&"stocked_display")

	_apply_collision_override()
	_rebuild_units()

	if not Engine.is_editor_hint():
		_setup_storage()
		_setup_mirrored_station()


func _apply_collision_override() -> void:
	var shape_node := get_node_or_null(^"CollisionShape2D") as CollisionShape2D

	if shape_node == null:
		return

	shape_node.position = collision_offset

	if collision_size == Vector2.ZERO:
		return

	var rectangle := shape_node.shape as RectangleShape2D

	if rectangle == null:
		return

	# Duplicate first: the shape comes from the shared scene, so resizing it in
	# place would resize every other instance too.
	var owned: RectangleShape2D = rectangle.duplicate()
	owned.size = collision_size
	shape_node.shape = owned


# --- Stock display -----------------------------------------------------------

## Total units this prop can show when full.
func get_unit_capacity() -> int:
	return unit_offsets.size()


## Units currently on show.
func get_visible_units() -> int:
	return get_unit_capacity() if _visible_units < 0 else _visible_units


## Shows [param count] units, hiding the rest.
##
## The one call the future stock system needs. Negative means "full", which is
## why an unconfigured prop looks stocked rather than empty.
func set_visible_units(count: int) -> void:
	var capacity: int = get_unit_capacity()
	var clamped: int = -1 if count < 0 else clampi(count, 0, capacity)

	if clamped == _visible_units:
		return

	_visible_units = clamped
	_apply_visibility()
	visible_units_changed.emit(get_visible_units(), capacity)


## Everything a diagnostics panel or the later storage pass needs.
func get_storage_summary() -> Dictionary:
	return {
		"node": String(name),
		"display_name": display_name,
		"content_id": String(content_id),
		"container_id": String(container_id),
		"storage_location_id": String(storage_location_id),
		"storage_tags": storage_tags.duplicate(),
		"visible_units": get_visible_units(),
		"unit_capacity": get_unit_capacity(),
	}


# --- Unit sprites ------------------------------------------------------------

func _rebuild_units() -> void:
	if not is_inside_tree():
		return

	_ensure_units_root()

	for child: Node in _units_root.get_children():
		child.queue_free()

	if unit_texture == null:
		return

	for i: int in range(unit_offsets.size()):
		var sprite := Sprite2D.new()
		sprite.name = "Unit%d" % i
		sprite.texture = unit_texture
		sprite.position = unit_offsets[i]
		sprite.z_index = unit_z_index
		_units_root.add_child(sprite)

	_apply_visibility()


func _ensure_units_root() -> void:
	if _units_root != null and is_instance_valid(_units_root):
		return

	# Generated, never saved: the units are derived from unit_offsets, so
	# writing them into the .tscn would give two sources of truth for the
	# layout.
	_units_root = get_node_or_null(^"Units") as Node2D

	if _units_root == null:
		_units_root = Node2D.new()
		_units_root.name = "Units"
		add_child(_units_root)


func _apply_visibility() -> void:
	if _units_root == null or not is_instance_valid(_units_root):
		return

	var shown: int = get_visible_units()

	for i: int in range(_units_root.get_child_count()):
		var sprite := _units_root.get_child(i) as Sprite2D

		if sprite != null:
			sprite.visible = i < shown


# --- Mirrored station stock -------------------------------------------------

func _setup_mirrored_station() -> void:
	if mirror_station.is_empty():
		return

	if storage_backed:
		push_warning(
			"%s sets both storage_backed and mirror_station. " % name
			+ "Mirroring wins; the owned storage is ignored."
		)

	_mirrored_station = get_node_or_null(mirror_station) as DrinksStation

	if _mirrored_station == null:
		push_warning("%s could not resolve mirror_station." % name)
		return

	_mirrored_station.stock_changed.connect(_on_mirrored_stock_changed)

	# The station fills its cask during BeverageSceneSetup, a frame after
	# everyone's _ready. Reading it now would show an empty shelf until the
	# first pour, so take the level once that has had a chance to run.
	call_deferred(&"_refresh_units_from_station")


func _on_mirrored_stock_changed(_current: int, _maximum: int) -> void:
	_refresh_units_from_station()


func _refresh_units_from_station() -> void:
	if _mirrored_station == null or not is_instance_valid(_mirrored_station):
		return

	set_visible_units(_mirrored_station.current_servings)


# --- Real stock --------------------------------------------------------------

## The owned storage location, or null when this prop is scenery.
func get_storage() -> BeverageStorage:
	return _storage


## Measures of [member content_id] currently stored here.
func get_stored_measures() -> int:
	return 0 if _storage == null else _storage.count_content(content_id)


func _setup_storage() -> void:
	if not storage_backed:
		return

	if content_id.is_empty():
		push_warning(
			"%s is storage_backed with no content_id - it would accept "
			% name
			+ "anything. Set content_id or turn storage_backed off."
		)

	_storage = BeverageStorage.new()
	_storage.name = "Storage"
	_storage.location_id = (
		storage_location_id if not storage_location_id.is_empty()
		else StringName("storeroom_%s" % name.to_snake_case())
	)
	_storage.display_name = display_name
	_storage.storage_tags = storage_tags.duplicate()
	_storage.registry = registry
	_storage.storage_priority = storage_priority

	# One visible unit is one batch, so the prop can never be asked to show
	# more casks than it has offsets for.
	_storage.capacity = get_unit_capacity()

	if not content_id.is_empty():
		_storage.accepted_content_ids = [content_id]

	add_child(_storage)
	_storage.contents_changed.connect(_on_storage_contents_changed)
	_refresh_units_from_storage()


func _on_storage_contents_changed() -> void:
	_refresh_units_from_storage()


## Recomputes how many units are on show from what is actually stored.
func _refresh_units_from_storage() -> void:
	if _storage == null or _mirrored_station != null:
		return

	var per_unit: int = _get_measures_per_unit()

	if per_unit <= 0:
		# Cannot convert measures to units, so fall back to counting batches.
		# Better than showing an empty shelf because a registry is missing.
		set_visible_units(_storage.get_batch_count())
		return

	set_visible_units(
		int(ceil(float(get_stored_measures()) / float(per_unit)))
	)


func _get_measures_per_unit() -> int:
	if registry == null or container_id.is_empty():
		return 0

	var container: ContainerDefinition = registry.get_container(container_id)

	return 0 if container == null else container.maximum_capacity


# --- Stock source ------------------------------------------------------------
#
# The same three calls StockStorage offers, so a storeroom prop can BE the
# source of a refill task. It could not before: RefillStationExecutor.can_claim()
# asked the legacy singleton StockStorage whether it held the station's stock
# item, and deliveries stopped going there the moment the order catalogue moved
# to filled containers. Every refill task was created and none was ever
# claimable - 2 created / 0 claimed in the 9 Aug session.


## How many whole units of [param item_id] this prop holds.
##
## Matched by content, not item id: the prop stores measures of a beverage,
## and the stock item is whatever declares it provides that content.
func count_item(item_id: StringName) -> int:
	if _storage == null or not _provides_item(item_id):
		return 0

	var per_unit: int = _get_measures_per_unit()

	if per_unit <= 0:
		return _storage.get_batch_count()

	return int(floor(float(get_stored_measures()) / float(per_unit)))


## Removes one unit and hands it to [param carrier] as its stock item.
func take_one(item_id: StringName, carrier: ItemCarrier) -> ItemTransferResult:
	if carrier == null:
		return ItemTransferResult.failure(ItemTransferResult.Status.INVALID_REQUEST)

	if _storage == null or not _provides_item(item_id):
		return ItemTransferResult.failure(ItemTransferResult.Status.REJECTED_ITEM)

	var batches: Array[FilledContainer] = _storage.get_batches()

	if batches.is_empty():
		return ItemTransferResult.failure(ItemTransferResult.Status.SOURCE_EMPTY)

	var definition: ItemDefinition = _find_stock_definition(item_id)

	if definition == null:
		return ItemTransferResult.failure(ItemTransferResult.Status.REJECTED_ITEM)

	var given: ItemTransferResult = carrier.give(ItemStack.create(definition, 1))

	if not given.is_success():
		return given

	# Only remove the batch once the carrier has actually taken it, or a full
	# pair of hands would silently destroy a container.
	_storage.remove_batch(batches[0])

	return given


func _provides_item(item_id: StringName) -> bool:
	var definition: ItemDefinition = _find_stock_definition(item_id)

	return definition != null and definition.provides_content_id == content_id


func _find_stock_definition(item_id: StringName) -> ItemDefinition:
	var registry: ItemRegistry = load("res://Data/items/item_registry.tres")

	return null if registry == null else registry.get_definition(item_id)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()

	if unit_texture != null and unit_offsets.is_empty():
		warnings.append("unit_texture is set but unit_offsets is empty - nothing will be drawn.")

	if storage_backed and registry == null:
		warnings.append("storage_backed needs a registry to convert measures into visible units.")

	if storage_backed and container_id.is_empty():
		warnings.append("storage_backed needs a container_id to know what one unit holds.")

	if storage_backed and not mirror_station.is_empty():
		warnings.append("storage_backed and mirror_station both set - pick one source of truth.")

	return warnings


# --- Interaction -------------------------------------------------------------
#
# Deliberately not an Interactable yet. These props are scenery this pass; the
# interaction and transfer behaviour arrives with the delivery system so it can
# be written once against real stock rather than twice.

func get_interaction_display_name() -> String:
	return display_name
