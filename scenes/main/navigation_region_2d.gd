class_name NavigationRegionManager
extends NavigationRegion2D

signal navigation_ready
signal navigation_rebake_started
signal navigation_rebake_finished

@export var automatically_bake_on_ready: bool = true
@export var rebake_delay: float = 0.1

var is_navigation_ready: bool = false

var rebake_requested: bool = false
var rebake_in_progress: bool = false
var rebake_timer: SceneTreeTimer


func _ready() -> void:
	bake_finished.connect(_on_bake_finished)

	if automatically_bake_on_ready:
		request_navigation_rebake()
	else:
		# Even a navigation polygon saved in the scene needs one physics
		# frame to synchronise with NavigationServer2D.
		await get_tree().physics_frame
		_mark_navigation_ready()


func request_navigation_rebake() -> void:
	rebake_requested = true

	if rebake_in_progress:
		return

	if rebake_timer != null:
		return

	rebake_timer = get_tree().create_timer(rebake_delay)
	rebake_timer.timeout.connect(_begin_requested_rebake)


func _begin_requested_rebake() -> void:
	rebake_timer = null

	if !rebake_requested:
		return

	if navigation_polygon == null:
		push_error(
			"NavigationRegionManager has no NavigationPolygon assigned."
		)
		return

	rebake_requested = false
	rebake_in_progress = true
	is_navigation_ready = false

	navigation_rebake_started.emit()

	bake_navigation_polygon(true)


func _on_bake_finished() -> void:
	rebake_in_progress = false

	_mark_navigation_ready()
	navigation_rebake_finished.emit()

	# Furniture might have changed while the previous bake was running.
	if rebake_requested:
		request_navigation_rebake()


func _mark_navigation_ready() -> void:
	if is_navigation_ready:
		return

	is_navigation_ready = true
	navigation_ready.emit()
