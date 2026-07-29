class_name StaffTaskStep
extends RefCounted

## One instruction from a [StaffTaskExecutor] to a [StaffMember].
##
## The split matters more than it looks. [StaffMember] owns navigation, the
## action runner, recovery and reporting, and knows nothing about drinks or
## chairs. An executor knows everything about one kind of work and owns no
## movement code at all. They meet here, at a five-value instruction.
##
## Because a step is recomputed from the world every time it is asked for, an
## executor is naturally self-correcting: if the player takes the drink the
## worker was walking towards, the next step is simply a different one.


enum Kind {
	## Walk to [member position] and ask again on arrival.
	MOVE,

	## Do the thing. [StaffMember] calls
	## [method StaffTaskExecutor.perform_action].
	ACT,

	## Nothing to do yet. Wait [member wait_seconds] and ask again.
	WAIT,

	## The requirement is met. Complete the task.
	COMPLETE,

	## Hand the task back, still needed. Costs a retry.
	RELEASE,

	## The task cannot be done. Costs a failure.
	FAIL,
}


var kind: Kind = Kind.WAIT

## Where to go, for [constant Kind.MOVE].
var position: Vector2 = Vector2.ZERO

## How close counts as arrived, in pixels.
var arrival_distance: float = 8.0

## Human-readable, used in navigation labels and diagnostics.
var label: String = ""

## Why, for [constant Kind.RELEASE] and [constant Kind.FAIL].
var reason: StringName = &""

## Seconds, for [constant Kind.WAIT].
var wait_seconds: float = 0.25


static func move_to(
	world_position: Vector2,
	arrival: float,
	step_label: String
) -> StaffTaskStep:
	var step: StaffTaskStep = StaffTaskStep.new()

	step.kind = Kind.MOVE
	step.position = world_position
	step.arrival_distance = arrival
	step.label = step_label

	return step


static func act(
	step_label: String = ""
) -> StaffTaskStep:
	var step: StaffTaskStep = StaffTaskStep.new()

	step.kind = Kind.ACT
	step.label = step_label

	return step


static func wait(
	seconds: float = 0.25,
	step_label: String = ""
) -> StaffTaskStep:
	var step: StaffTaskStep = StaffTaskStep.new()

	step.kind = Kind.WAIT
	step.wait_seconds = seconds
	step.label = step_label

	return step


static func complete() -> StaffTaskStep:
	var step: StaffTaskStep = StaffTaskStep.new()

	step.kind = Kind.COMPLETE

	return step


static func release(
	release_reason: StringName
) -> StaffTaskStep:
	var step: StaffTaskStep = StaffTaskStep.new()

	step.kind = Kind.RELEASE
	step.reason = release_reason

	return step


static func fail(
	fail_reason: StringName
) -> StaffTaskStep:
	var step: StaffTaskStep = StaffTaskStep.new()

	step.kind = Kind.FAIL
	step.reason = fail_reason

	return step


func get_kind_name() -> String:
	return Kind.keys()[kind]
