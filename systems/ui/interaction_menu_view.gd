class_name InteractionMenuView
extends Control

## Base class for context-specific menus opened from world interactions.
##
## A menu receives a context dictionary from the world object that opened it.
## It never searches for the player or gameplay managers itself unless the
## context deliberately omits something optional.

signal close_requested(result: Dictionary)

var menu_context: Dictionary = {}


func setup(context: Dictionary) -> void:
	menu_context = context.duplicate(false)


func request_close(result: Dictionary = {}) -> void:
	close_requested.emit(result)
