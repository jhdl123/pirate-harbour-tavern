class_name ItemTransferResult
extends RefCounted

## The outcome of one [ItemTransferService] operation.
##
## Every transfer returns one of these, successful or not, so callers never have
## to guess what happened. UI can use [method get_message] for a prompt, gameplay
## can branch on [member status], and debug code can log the whole thing.


enum Status {
	## Nothing happened yet. Only used while a plan is being built.
	NONE,

	## The whole source stack moved into an empty destination.
	MOVED,

	## The whole source stack merged into a matching destination stack.
	MERGED,

	## Some of the source stack moved into an empty destination.
	PARTIALLY_MOVED,

	## Some of the source stack merged into a matching destination stack.
	PARTIALLY_MERGED,

	## Source and destination exchanged their contents.
	SWAPPED,

	## The destination's tag or id filters refused the item.
	REJECTED_ITEM,

	## The destination is full, or its capacity is already reached.
	NO_CAPACITY,

	## There was nothing in the source to move.
	SOURCE_EMPTY,

	## The destination does not allow items to be inserted.
	DESTINATION_LOCKED,

	## The source does not allow items to be removed.
	SOURCE_LOCKED,

	## Null slots, a negative amount, or a slot transferring into itself.
	INVALID_REQUEST,

	## Same item, but metadata or merge permission prevents combining, and a
	## swap was not possible either.
	INCOMPATIBLE_STACKS,
}


## What happened.
var status: Status = Status.NONE

## How many items actually moved. Always zero for a failure.
var amount_moved: int = 0

## How many items the caller asked to move.
var amount_requested: int = 0

## The item involved, when there was one.
var definition: ItemDefinition = null


func _init(
	result_status: Status = Status.NONE,
	moved: int = 0,
	requested: int = 0,
	moved_definition: ItemDefinition = null
) -> void:
	status = result_status
	amount_moved = maxi(moved, 0)
	amount_requested = maxi(requested, 0)
	definition = moved_definition


## True when at least one item changed hands.
func is_success() -> bool:
	return (
		status == Status.MOVED
		or status == Status.MERGED
		or status == Status.PARTIALLY_MOVED
		or status == Status.PARTIALLY_MERGED
		or status == Status.SWAPPED
	)


## True when the request succeeded but some items were left behind.
func is_partial() -> bool:
	return (
		status == Status.PARTIALLY_MOVED
		or status == Status.PARTIALLY_MERGED
	)


## Items the source still holds because they did not fit.
func get_amount_remaining() -> int:
	return maxi(amount_requested - amount_moved, 0)


func get_status_name() -> String:
	return Status.keys()[status]


## Short human-readable summary, useful for debug output and future UI prompts.
func get_message() -> String:
	var item_label: String = "item"

	if definition != null:
		item_label = definition.display_name

	match status:
		Status.MOVED:
			return "Moved %d x %s." % [amount_moved, item_label]
		Status.MERGED:
			return "Merged %d x %s." % [amount_moved, item_label]
		Status.PARTIALLY_MOVED:
			return "Moved %d of %d x %s." % [
				amount_moved,
				amount_requested,
				item_label
			]
		Status.PARTIALLY_MERGED:
			return "Merged %d of %d x %s." % [
				amount_moved,
				amount_requested,
				item_label
			]
		Status.SWAPPED:
			return "Swapped %s." % item_label
		Status.REJECTED_ITEM:
			return "%s is not accepted here." % item_label
		Status.NO_CAPACITY:
			return "There is no room for %s." % item_label
		Status.SOURCE_EMPTY:
			return "There is nothing to move."
		Status.DESTINATION_LOCKED:
			return "That cannot hold items."
		Status.SOURCE_LOCKED:
			return "That item cannot be taken."
		Status.INVALID_REQUEST:
			return "Invalid transfer request."
		Status.INCOMPATIBLE_STACKS:
			return "Those %s cannot be combined." % item_label
		_:
			return "Nothing happened."


## Convenience constructor for a failed transfer.
static func failure(
	failure_status: Status,
	requested: int = 0,
	failed_definition: ItemDefinition = null
) -> ItemTransferResult:
	return ItemTransferResult.new(
		failure_status,
		0,
		requested,
		failed_definition
	)
