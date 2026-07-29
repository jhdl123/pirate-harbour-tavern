class_name IssueRecord
extends RefCounted

## One detected anomaly, for the diagnostic report's issue list.
##
## Only for anomalies this pass can actually detect reliably - see
## CustomerAIReportManager.report_issue()'s callers for the full list. Never
## invents a diagnosis; if nothing calls report_issue() for a given visit,
## nothing is wrong as far as this system can tell.


var customer_id: int = -1
var game_time_minutes: float = 0.0
var issue_type: StringName = &""
var message: String = ""

## Small, free-form snapshot - whatever the caller judged relevant, not a
## fixed schema, since different issue types need different context.
var state_snapshot: Dictionary = {}


func to_dictionary() -> Dictionary:
	return {
		"customer_id": customer_id,
		"game_time_minutes": game_time_minutes,
		"issue_type": String(issue_type),
		"message": message,
		"state": state_snapshot,
	}
