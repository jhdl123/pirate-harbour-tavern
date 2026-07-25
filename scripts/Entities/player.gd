extends CharacterBody2D


@export_category("Movement")
@export var movement_speed: float = 250.0


@export_category("Camera Zoom")
@export var minimum_camera_zoom: float = 1.0
@export var maximum_camera_zoom: float = 2.0
@export var camera_zoom_step: float = 0.25
@export var camera_zoom_speed: float = 10.0
@export var default_camera_zoom: float = 1.0


var carried_drink: DrinkDefinition = null
var target_camera_zoom: float = 1.0


@onready var camera: Camera2D = $Camera2D

@onready var interaction_detector: Area2D = (
	$InteractionDetector
)

@onready var carried_item_sprite: Sprite2D = (
	$CarriedItemSprite
)

@onready var action_runner: ActionRunner = (
	$ActionRunner
)


func _ready() -> void:
	update_carried_drink_visual()

	target_camera_zoom = clampf(
		default_camera_zoom,
		minimum_camera_zoom,
		maximum_camera_zoom
	)

	camera.zoom = Vector2.ONE * target_camera_zoom

	if not action_runner.action_started.is_connected(
		_on_action_started
	):
		action_runner.action_started.connect(
			_on_action_started
		)

	if not action_runner.action_progressed.is_connected(
		_on_action_progressed
	):
		action_runner.action_progressed.connect(
			_on_action_progressed
		)

	if not action_runner.action_completed.is_connected(
		_on_action_completed
	):
		action_runner.action_completed.connect(
			_on_action_completed
		)

	if not action_runner.action_cancelled.is_connected(
		_on_action_cancelled
	):
		action_runner.action_cancelled.connect(
			_on_action_cancelled
		)


func _physics_process(
	_delta: float
) -> void:
	if action_runner.is_movement_blocked():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input_direction: Vector2 = Input.get_vector(
		"player_move_left",
		"player_move_right",
		"player_move_up",
		"player_move_down"
	)

	velocity = input_direction * movement_speed
	move_and_slide()


func _process(
	delta: float
) -> void:
	handle_camera_zoom_input()
	update_camera_zoom(delta)

	if Input.is_action_just_pressed(
		"player_interact"
	):
		try_interact()


func handle_camera_zoom_input() -> void:
	if Input.is_action_just_pressed(
		"camera_zoom_in"
	):
		target_camera_zoom += camera_zoom_step

	if Input.is_action_just_pressed(
		"camera_zoom_out"
	):
		target_camera_zoom -= camera_zoom_step

	if Input.is_action_just_pressed(
		"camera_zoom_reset"
	):
		target_camera_zoom = default_camera_zoom

	target_camera_zoom = clampf(
		target_camera_zoom,
		minimum_camera_zoom,
		maximum_camera_zoom
	)


func update_camera_zoom(
	delta: float
) -> void:
	var current_zoom: float = camera.zoom.x

	var new_zoom: float = move_toward(
		current_zoom,
		target_camera_zoom,
		camera_zoom_speed * delta
	)

	camera.zoom = Vector2.ONE * new_zoom


func is_carrying_drink() -> bool:
	return carried_drink != null


func get_carried_drink() -> DrinkDefinition:
	return carried_drink


func set_carried_drink(
	drink: DrinkDefinition
) -> void:
	carried_drink = drink
	update_carried_drink_visual()


func clear_carried_drink() -> void:
	carried_drink = null
	update_carried_drink_visual()


func update_carried_drink_visual() -> void:
	if carried_drink == null:
		carried_item_sprite.texture = null
		carried_item_sprite.visible = false
		return

	if carried_drink.carried_texture == null:
		push_warning(
			carried_drink.display_name
			+ " has no carried texture assigned."
		)

		carried_item_sprite.texture = null
		carried_item_sprite.visible = false
		return

	carried_item_sprite.texture = (
		carried_drink.carried_texture
	)

	carried_item_sprite.visible = true


func try_interact() -> void:
	if action_runner.is_running:
		return

	var nearby_areas: Array[Area2D] = (
		interaction_detector.get_overlapping_areas()
	)

	for area: Area2D in nearby_areas:
		if not area.is_in_group("interactable"):
			continue

		var interactable_object: Node = area.get_parent()

		if not interactable_object.has_method(
			"interact"
		):
			continue

		interactable_object.interact(self)
		return


func start_action(
	action: ActionDefinition
) -> bool:
	if action == null:
		push_warning(
			"Player cannot start a null ActionDefinition."
		)
		return false

	return action_runner.start_action(action)


func cancel_current_action() -> bool:
	return action_runner.cancel_current_action()


func is_performing_action() -> bool:
	return action_runner.is_running


func get_action_runner() -> ActionRunner:
	return action_runner


func _on_action_started(
	action: ActionDefinition
) -> void:
	print(
		"Started action: ",
		action.display_name
	)


func _on_action_progressed(
	_action: ActionDefinition,
	_progress: float,
	_remaining_seconds: float
) -> void:
	pass


func _on_action_completed(
	action: ActionDefinition
) -> void:
	print(
		"Completed action: ",
		action.display_name
	)


func _on_action_cancelled(
	action: ActionDefinition
) -> void:
	print(
		"Cancelled action: ",
		action.display_name
	)
