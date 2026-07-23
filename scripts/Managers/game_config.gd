class_name GameConfig
extends Resource


@export_category("Customer Spawning")
@export var minimum_spawn_delay: float = 2.0
@export var maximum_spawn_delay: float = 10.0
@export var maximum_active_customers: int = 12

@export_category("Customer Timing")
@export var order_delay: float = 2.0
@export var patience_duration: float = 15.0
@export var drink_duration: float = 8.0

@export_category("Customer Movement")
@export var movement_speed: float = 120.0
@export var seat_movement_speed: float = 45.0

@export_category("Economy")
@export var drink_payment_amount: int = 5

@export_category("Seat Selection")
@export var occupied_seat_penalty: float = 1000.0
@export var travel_distance_weight: float = 1.0

@export_category("Testing")
@export var show_debug_messages: bool = true
