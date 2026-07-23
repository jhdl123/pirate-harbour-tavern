extends CharacterBody2D

@export var movement_speed: float = 250.0

var carrying_item: ItemType.Type = ItemType.Type.NONE


func _physics_process(_delta: float) -> void:
	var input_direction := Input.get_vector(
		"player_move_left",
		"player_move_right",
		"player_move_up",
		"player_move_down"
	)

	velocity = input_direction * movement_speed
	move_and_slide()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("player_interact"):
		try_interact()


func set_carried_item(item: ItemType.Type) -> void:
	carrying_item = item

	if carrying_item == ItemType.Type.NONE:
		$CarriedItemSprite.visible = false
	else:
		$CarriedItemSprite.visible = true


func try_interact() -> void:
	var nearby_areas: Array[Area2D] = $InteractionDetector.get_overlapping_areas()

	for area: Area2D in nearby_areas:
		if area.is_in_group("interactable"):
			var interactable_object: Node = area.get_parent()

			if interactable_object.has_method("interact"):
				interactable_object.interact(self)
				return
