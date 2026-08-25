class_name CustomerInspectionData
extends RefCounted

## One customer's inspection snapshot - the immutable middle layer
## DECISIONS.md §25 requires: [code]Customer -> CustomerInspectionData ->
## CustomerInspectorUI[/code]. [CustomerInspectorUI] renders only this; it
## never reads a [Customer], [CustomerBrain], [CustomerNeeds] or
## [ActivityRegistry] directly, so the decision architecture can change
## again without touching the UI - see CUSTOMER_INSPECTOR.md.
##
## Built once per inspection by [method Customer.get_inspection_data] -
## the one place allowed to read this customer's internals - not
## recomputed or re-derived anywhere else.


@export_category("Identity")
var customer_name: String = ""
var customer_type_name: String = ""
var current_state: String = ""
var current_activity_id: String = ""
var current_activity_display_name: String = ""


@export_category("Visit")
var visit_purpose: String = ""
var visit_elapsed_minutes: float = 0.0
var visit_expected_minutes: float = 0.0


@export_category("Needs")
## All 0.0-1.0. See CustomerNeeds' own doc comments for what each means -
## a need is "what would currently be valuable", not satisfaction.
var thirst: float = 0.0
var mood: float = 0.0
var patience: float = 0.0
var energy: float = 0.0
var intoxication: float = 0.0
var social: float = 0.0
var entertainment: float = 0.0
var relaxation: float = 0.0


@export_category("Decision")
## Stage 2's winner (CUSTOMER_MODEL.md §4) - "thirst"/"social"/
## "entertainment"/"relaxation", or "" if no scored decision has run yet.
var motivation: String = ""

## Array[Dictionary]: {"activity_id": String, "score": float,
## "selected": bool} for every candidate the last decision scored, sorted
## highest score first.
var candidates: Array[Dictionary] = []

## Array[Dictionary]: {"activity_id": String, "reason": String} - every
## candidate rejected before scoring, and why.
var rejected: Array[Dictionary] = []

## "" (fine) or what went wrong after the selected activity was entered -
## see CUSTOMER_INSPECTOR.md: "Reservation and execution outcomes must
## appear here, not only selection."
var execution_outcome: String = ""


@export_category("Group")
var group_id: String = ""
var group_role: String = ""


@export_category("Economy")
var money: int = 0
var drinks_consumed: int = 0


@export_category("Visit History")
## Activities completed so far this visit, oldest first - developer-only,
## CUSTOMER_INSPECTOR.md's later ask ("a small developer-only visit history
## showing the sequence of activities completed during the current visit").
## Array[Dictionary]: {"activity_id": String, "display_name": String,
## "at_minutes": float}.
var visit_history: Array[Dictionary] = []


## The brief's console format (CUSTOMER_INSPECTOR.md), as plain text -
## rendering only, no logic that reads anything beyond this snapshot's own
## fields.
func to_display_text() -> String:
	var lines: PackedStringArray = []

	var header: String = customer_name
	if not customer_type_name.is_empty():
		header += " (%s)" % customer_type_name
	header += " - %s" % current_state

	if not current_activity_display_name.is_empty():
		header += " (%s)" % current_activity_display_name

	lines.append(header)

	if not visit_purpose.is_empty():
		lines.append(
			"visit purpose: %s  (%.0f / %.0f min)"
			% [visit_purpose, visit_elapsed_minutes, visit_expected_minutes]
		)

	lines.append("")
	lines.append("needs:")
	lines.append("  thirst        %3d" % roundi(thirst * 100))
	lines.append("  mood          %3d" % roundi(mood * 100))
	lines.append("  patience      %3d" % roundi(patience * 100))
	lines.append("  energy        %3d" % roundi(energy * 100))
	lines.append("  intoxication  %3d" % roundi(intoxication * 100))
	lines.append("  social        %3d" % roundi(social * 100))
	lines.append("  entertainment %3d" % roundi(entertainment * 100))
	lines.append("  relaxation    %3d" % roundi(relaxation * 100))

	lines.append("")
	lines.append(
		"motivation: %s" % (motivation if not motivation.is_empty() else "-")
	)

	if not candidates.is_empty():
		for entry: Dictionary in candidates:
			var selected: bool = bool(entry.get("selected", false))
			var line: String = "  %-18s %6.1f" % [
				String(entry.get("activity_id", "")),
				float(entry.get("score", 0.0)),
			]

			if selected:
				line += "   selected"

			lines.append(line)

	if not rejected.is_empty():
		lines.append("rejected:")

		for entry: Dictionary in rejected:
			lines.append(
				"  %s: %s"
				% [entry.get("activity_id", ""), entry.get("reason", "")]
			)

	if not execution_outcome.is_empty():
		lines.append("")
		lines.append("-> %s" % execution_outcome)

	if not group_id.is_empty():
		lines.append("")
		lines.append("group: %s (%s)" % [group_id, group_role])

	if not visit_history.is_empty():
		lines.append("")
		lines.append("visit history:")

		for entry: Dictionary in visit_history:
			lines.append(
				"  %6.0f  %s"
				% [
					float(entry.get("at_minutes", 0.0)),
					String(
						entry.get(
							"display_name", entry.get("activity_id", "")
						)
					),
				]
			)

	lines.append("")
	lines.append(
		"money: £%d   drinks: %d" % [money, drinks_consumed]
	)

	return "\n".join(lines)
