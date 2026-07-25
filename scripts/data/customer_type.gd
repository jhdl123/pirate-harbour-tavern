class_name CustomerType
extends Resource


@export_category("Identity")
@export var display_name: String = "Customer"
@export var customer_texture: Texture2D


@export_category("Spawning")

@export_range(0.0, 100.0, 0.1)
var spawn_weight: float = 1.0


@export_category("Movement")

@export var movement_speed: float = 120.0
@export var seat_movement_speed: float = 45.0


@export_category("Service")

@export var order_delay: float = 2.0
@export var patience_duration: float = 15.0


@export_category("Drink Preferences")

@export var available_drinks: Array[DrinkDefinition] = []

@export var preferred_drink: DrinkDefinition

@export_range(0.0, 1.0, 0.05)
var preferred_drink_chance: float = 0.75


@export_category("Economy")

@export_range(0.0, 5.0, 0.05)
var payment_multiplier: float = 1.0
