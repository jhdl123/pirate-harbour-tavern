class_name PreparationRequest
extends RefCounted

## One attempt to make a recipe, and everything that attempt reserved.
##
## Reservations are held on the request rather than scattered across the stock
## that backs them. That is what makes failure safe: cancelling the request
## hands every reservation back, so a preparation that falls over cannot leak
## ingredients or leave a cask permanently short.


enum Status {
	## Checked and reserved, not yet made.
	READY,

	## Cannot proceed. See [member failure_reason].
	BLOCKED,

	## Made and consumed.
	COMPLETED,

	## Abandoned, reservations returned.
	CANCELLED,
}


enum Failure {
	NONE,
	NO_RECIPE,
	MISSING_INGREDIENTS,
	MISSING_CONTENT,
	NO_STATION,
	NO_VESSEL,
	ALREADY_RESOLVED,
}


var recipe: DrinkRecipeDefinition = null
var format: ServingFormatDefinition = null
var batches: int = 1
var status: Status = Status.BLOCKED
var failure_reason: Failure = Failure.NONE

## Ingredient lines that could not be satisfied, for a readable message.
var missing: Array[Dictionary] = []

## Station capabilities the chosen station did not have.
var missing_capabilities: Array[StringName] = []

## Item reservations taken, as item id to count.
var reserved_items: Dictionary = {}

## Content reservations taken, as the batch reserved from to measures.
var reserved_contents: Array[Dictionary] = []

## Whether a vessel was reserved and must be handed back on cancel.
var reserved_vessel_id: StringName = &""


func is_ready() -> bool:
	return status == Status.READY


func get_message() -> String:
	match failure_reason:
		Failure.NO_RECIPE:
			return "There is no recipe for that."
		Failure.MISSING_INGREDIENTS:
			return "Missing: %s." % _describe_missing()
		Failure.MISSING_CONTENT:
			return "Not enough stock: %s." % _describe_missing()
		Failure.NO_STATION:
			return "No station can do that%s." % _describe_capabilities()
		Failure.NO_VESSEL:
			return "No clean vessel is available."
		Failure.ALREADY_RESOLVED:
			return "That preparation has already finished."
		_:
			return "Ready to prepare."


func _describe_missing() -> String:
	var parts: PackedStringArray = PackedStringArray()

	for entry: Dictionary in missing:
		parts.append("%s (need %d, have %d)" % [
			String(entry.get("id", "")),
			int(entry.get("required", 0)),
			int(entry.get("available", 0)),
		])

	return ", ".join(parts)


func _describe_capabilities() -> String:
	if missing_capabilities.is_empty():
		return ""

	var parts: PackedStringArray = PackedStringArray()

	for capability: StringName in missing_capabilities:
		parts.append(StationCapabilities.get_display_name(capability))

	return " (needs %s)" % ", ".join(parts)
