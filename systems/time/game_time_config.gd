class_name GameTimeConfig
extends Resource

## The day number when a new game begins.
@export_range(1, 9999, 1) var starting_day: int = 1

## Starting clock time.
@export_range(0, 23, 1) var starting_hour: int = 8
@export_range(0, 59, 1) var starting_minute: int = 0

## Number of in-game minutes that pass per real-world second.
@export_range(0.01, 60.0, 0.01) var game_minutes_per_real_second: float = 1.0

## Available game-speed multipliers.
@export var available_speed_multipliers: Array[float] = [
	1.0,
	2.0,
	4.0
]
