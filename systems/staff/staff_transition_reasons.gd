class_name StaffTransitionReason
extends RefCounted

## Every reason a worker changes state, task or carried item.
##
## Phase 3A recorded the string [code]"transition"[/code] for almost every
## state change, which made the exported report describe what happened without
## ever explaining why. These constants replace that.
##
## They are constants rather than free strings for one practical reason: a
## typo in a reason code is invisible until somebody tries to aggregate a
## report by reason and finds two spellings of the same thing. Referring to
## [code]StaffTransitionReason.TASK_CLAIMED[/code] fails loudly at parse time
## instead.
##
## Reasons are grouped by what they explain, but they share one namespace on
## purpose: a state change, a task cancellation and a carried-item outcome can
## all be caused by the same event, and reporting should be able to line them
## up.


# --- Task lifecycle ----------------------------------------------------------

const TASK_CLAIMED: StringName = &"task_claimed"
const TASK_COMPLETED: StringName = &"task_completed"
const TASK_CANCELLED: StringName = &"task_cancelled"
const TASK_RELEASED: StringName = &"task_released"
const TASK_FAILED: StringName = &"task_failed"
const TASK_INVALIDATED: StringName = &"task_invalidated"
const CLAIM_LOST: StringName = &"claim_lost"


# --- Why a requirement stopped existing --------------------------------------

const CUSTOMER_DEPARTED: StringName = &"customer_departed"
const CUSTOMER_NO_LONGER_WAITING: StringName = &"customer_no_longer_waiting"
const TARGET_INVALIDATED: StringName = &"target_invalidated"
const DESTINATION_UNREACHABLE: StringName = &"destination_unreachable"
const SOURCE_UNAVAILABLE: StringName = &"source_unavailable"
const REQUIRED_ITEM_UNAVAILABLE: StringName = &"required_item_unavailable"
const STOCK_UNAVAILABLE: StringName = &"stock_unavailable"
const CLEANED_BY_OTHER: StringName = &"cleaned_by_other"
const COMPLETED_BY_PLAYER: StringName = &"completed_by_player"
const COMPLETED_BY_OTHER_WORKER: StringName = &"completed_by_other_worker"
const EXTERNAL_COMPLETION: StringName = &"external_completion"
const NO_LONGER_REQUIRED: StringName = &"no_longer_required"
const SUPERSEDED: StringName = &"superseded"


# --- Carried items -----------------------------------------------------------

const CARRIED_ITEM_INCOMPATIBLE: StringName = &"carried_item_incompatible"
const CARRIED_ITEM_REASSIGNED: StringName = &"carried_item_reassigned"
const CARRIED_ITEM_RETURNED: StringName = &"carried_item_returned"
const CARRIED_ITEM_RESTOCKED: StringName = &"carried_item_restocked"
const CARRIED_ITEM_DISPOSED: StringName = &"carried_item_disposed"
const CARRIED_ITEM_RETAINED: StringName = &"carried_item_retained"
const CARRIED_ITEM_RECOVERY_FAILED: StringName = &"carried_item_recovery_failed"
const CARRIED_ITEM_REUSED: StringName = &"carried_item_reused"
const RECOVERING_CARRIED_ITEM: StringName = &"recovering_carried_item"


# --- Selection ---------------------------------------------------------------

const BETTER_TASK_SELECTED: StringName = &"better_task_selected"
const CRITICAL_TASK_PREEMPTION: StringName = &"critical_task_preemption"
const NO_VIABLE_TASK: StringName = &"no_viable_task"
const NOT_VIABLE: StringName = &"not_viable"
const SCHEDULED_REEVALUATION: StringName = &"scheduled_reevaluation"
const WOKEN_BY_NEW_TASK: StringName = &"woken_by_new_task"
const COMMITTED_TO_CURRENT_TASK: StringName = &"committed_to_current_task"
const CLAIM_COOLDOWN: StringName = &"claim_cooldown"
const CAPABILITY_MISMATCH: StringName = &"capability_mismatch"
const NO_EXECUTOR: StringName = &"no_executor"
const EXECUTOR_REFUSED: StringName = &"executor_refused"


# --- Movement and idling -----------------------------------------------------

const RETURNING_TO_IDLE: StringName = &"returning_to_idle"
const IDLE_ARRIVAL: StringName = &"idle_arrival"
const MOVING_TO_SOURCE: StringName = &"moving_to_source"
const MOVING_TO_TARGET: StringName = &"moving_to_target"
const ARRIVED: StringName = &"arrived"
const STUCK_RECOVERY: StringName = &"stuck_recovery"
const NAVIGATION_FAILED: StringName = &"navigation_failed"


# --- Worker control ----------------------------------------------------------

const WORKER_DISABLED: StringName = &"worker_disabled"
const WORKER_ENABLED: StringName = &"worker_enabled"
const READY: StringName = &"ready"
const DEVELOPER_ACTION: StringName = &"developer_action"

const OTHER: StringName = &"other"


## Reasons the report groups under "cancellation", so a new one added above is
## picked up by the aggregate section without editing the report manager.
##
## Anything not listed is counted under [constant OTHER], which is deliberate:
## a growing "other" bucket in a report is a visible prompt to classify a
## reason properly rather than a silent gap.
static func get_cancellation_reasons() -> Array[StringName]:
	return [
		CUSTOMER_NO_LONGER_WAITING,
		CUSTOMER_DEPARTED,
		CLEANED_BY_OTHER,
		COMPLETED_BY_PLAYER,
		COMPLETED_BY_OTHER_WORKER,
		EXTERNAL_COMPLETION,
		STOCK_UNAVAILABLE,
		REQUIRED_ITEM_UNAVAILABLE,
		SOURCE_UNAVAILABLE,
		TARGET_INVALIDATED,
		DESTINATION_UNREACHABLE,
		SUPERSEDED,
		WORKER_DISABLED,
		NO_LONGER_REQUIRED,
		NOT_VIABLE,
	]


## True when [param reason] is one the report should count as a cancellation.
static func is_cancellation_reason(
	reason: StringName
) -> bool:
	return get_cancellation_reasons().has(reason)
