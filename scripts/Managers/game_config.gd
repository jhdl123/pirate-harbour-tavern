class_name GameConfig
extends Resource



@export_category("Customer Spawning")
## World minutes between customer spawn attempts.
@export_range(0, 600, 1)
var minimum_spawn_delay_minutes: int = 2

@export_range(0, 600, 1)
var maximum_spawn_delay_minutes: int = 10
@export var maximum_active_customers: int = 12
@export var maximum_door_queue_size: int = 5


@export_category("Customer Movement")
@export var navigation_arrival_distance: float = 6.0
@export var seat_arrival_distance: float = 2.0

@export_category("Seat Selection")
@export var occupied_seat_penalty: float = 1000.0
@export var travel_distance_weight: float = 1.0

@export_category("Navigation Tuning")
@export var stuck_check_interval: float = 0.5
@export var minimum_stuck_movement: float = 1.0
@export var maximum_stuck_checks: int = 3
@export var maximum_path_refreshes: int = 2
@export var walking_avoidance_radius: float = 12.0
@export var walking_avoidance_priority: float = 0.5


@export var starting_money: int = 0


@export_category("Door")
@export var door_opening_duration: float = 0.35
@export var door_hold_open_duration: float = 0.5
@export var door_closing_duration: float = 0.35
@export var customer_entry_pause: float = 0.1
@export var customer_exit_pause: float = 0.1

@export_category("Testing")
@export var show_debug_messages: bool = true

## Prints item transfer outcomes. Off by default: item transfers happen often
## enough that logging them would drown normal gameplay output.
@export var show_item_debug_messages: bool = false

@export var disable_patience: bool = false

## Skips scheduling both the hard visit-length departure and the Phase A
## leave-decision window. For a harness that fast-forwards world time to
## isolate one subsystem, same rationale as disable_patience: test the
## subsystem, not the visit clock racing it.
@export var disable_visit_timer: bool = false

@export var disable_broken_glass: bool = false
@export var ignore_customer_limit: bool = false
