class_name BeverageTransferResult
extends RefCounted

## The outcome of one attempt to move liquid between containers.
##
## Deliberately shaped like [ItemTransferResult]: a status, an amount actually
## moved, and a message a human can read. Partial moves are a success, not a
## failure - filling a service cask from a nearly-empty hogshead should move
## what is there and say so.


enum Status {
	## Everything requested was moved.
	SUCCESS,

	## Some was moved. Check [member amount_moved].
	PARTIAL,

	## Nothing was moved.
	FAILED,
}


var status: Status = Status.FAILED
var amount_moved: int = 0
var amount_requested: int = 0
var refusal: FilledContainer.Refusal = FilledContainer.Refusal.NONE
var content_id: StringName = &""


static func success(
	moved: int,
	requested: int,
	moved_content_id: StringName
) -> BeverageTransferResult:
	var result: BeverageTransferResult = BeverageTransferResult.new()
	result.amount_moved = moved
	result.amount_requested = requested
	result.content_id = moved_content_id
	result.status = (
		Status.SUCCESS if moved >= requested else Status.PARTIAL
	)

	return result


static func failure(
	reason: FilledContainer.Refusal,
	requested: int = 0
) -> BeverageTransferResult:
	var result: BeverageTransferResult = BeverageTransferResult.new()
	result.status = Status.FAILED
	result.refusal = reason
	result.amount_requested = requested

	return result


func is_success() -> bool:
	return status == Status.SUCCESS or status == Status.PARTIAL


func is_complete() -> bool:
	return status == Status.SUCCESS


func get_message() -> String:
	match status:
		Status.SUCCESS:
			return "Moved %d measures." % amount_moved
		Status.PARTIAL:
			return "Moved %d of %d measures." % [
				amount_moved,
				amount_requested,
			]
		_:
			return _get_refusal_message()


func _get_refusal_message() -> String:
	match refusal:
		FilledContainer.Refusal.CONTAINER_MISSING:
			return "A container is missing."
		FilledContainer.Refusal.CONTENT_MISMATCH:
			return "The destination already holds something else."
		FilledContainer.Refusal.CONTENT_INCOMPATIBLE:
			return "That container cannot hold this."
		FilledContainer.Refusal.SOURCE_EMPTY:
			return "The source is empty."
		FilledContainer.Refusal.DESTINATION_FULL:
			return "The destination is full."
		FilledContainer.Refusal.NOT_TRANSFERABLE:
			return "That container cannot be decanted."
		FilledContainer.Refusal.INVALID_QUANTITY:
			return "That is not a valid amount."
		FilledContainer.Refusal.SPOILED:
			return "The source has spoiled."
		_:
			return "The transfer could not be made."
