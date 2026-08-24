class_name TavernActivitySlot
extends Node2D

## One participant position on a [TavernActivityPoint]: a [Reservable] plus
## the [Marker2D] that participant stands at.
##
## A point with N slot children supports N simultaneous users - a one-slot
## point behaves exactly as a [TavernActivityPoint] always has. Each slot's
## [Reservable] is reserved independently, so two participants on the same
## point never contend over one reservation, and either can be released
## without disturbing the other.
##
## Plain settable properties rather than [code]@onready $NodePath[/code]
## lookups, so [method TavernActivityPoint._ready] can wire a slot up two
## ways: reading an authored [TavernActivitySlot] scene node's own
## [Reservable]/[Marker2D] children, or synthesizing a slot in code that
## points at a bare [Reservable]/[Marker2D] built directly under the point
## itself - the shape every point had before this class existed, still used
## by at least one existing test harness that constructs a point in code.


var reservable: Reservable = null
var use_position: Marker2D = null


func _ready() -> void:
	if reservable == null:
		reservable = get_node_or_null("Reservable")

	if use_position == null:
		use_position = get_node_or_null("UsePosition")


func get_use_position() -> Vector2:
	if use_position != null:
		return use_position.global_position

	return global_position
