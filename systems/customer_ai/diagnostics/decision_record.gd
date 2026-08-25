class_name DecisionRecord
extends RefCounted

## One CustomerBrain decision, snapshotted for the diagnostic report.
##
## Built by CustomerAIReportManager.record_decision(), fed by whatever
## CustomerBrain.think()/force_activity() already knows - this class does
## not query the game state itself, so it stays honest about only recording
## what actually happened.


var customer_id: int = -1
var game_time_minutes: float = 0.0

var previous_activity_id: String = ""

## Array[Dictionary]: [{"activity_id": String, "score": float}, ...] for
## every eligible (available) candidate.
var eligible_activities: Array[Dictionary] = []

## Array[Dictionary]: [{"activity_id": String, "reason": String}, ...] -
## only populated when CustomerAIDiagnosticsConfig.record_rejection_reasons
## is on.
var rejected_activities: Array[Dictionary] = []

var selected_activity_id: String = ""
var was_forced: bool = false
var forced_reason: String = ""

## Stage 2's winner (CUSTOMER_MODEL.md §4) - "thirst"/"social"/
## "entertainment"/"relaxation", or "" when this decision bypassed scoring
## (enter_activity()/force_activity()) and stage 2 never ran.
var motivation: String = ""

## "" (fine) or a short player-facing description of what went wrong
## entering [member selected_activity_id] - see
## CustomerBrain's `_last_execution_outcome` doc comment.
## CUSTOMER_INSPECTOR.md: "Reservation and execution outcomes must appear
## here, not only selection."
var execution_outcome: String = ""

## Phase 2C: makes close calls visible without opening every eligible
## activity's score by hand - see CustomerBrain.think()'s doc comment on
## how these three are derived (always from eligible_activities, so they
## stay consistent with it even if this record is inspected on its own).
var top_score: float = 0.0
var second_score: float = 0.0
var margin: float = 0.0

## Phase 2C: Array[Dictionary], one entry per eligible activity, each a
## contribution breakdown from ActivityDefinition.get_utility_breakdown() -
## only populated when CustomerAIDiagnosticsConfig.record_decision_history
## is on (see CustomerBrain._report_decision()'s cost note). Empty means
## either breakdowns were not requested, or every activity this decision
## point had was entered directly (enter_activity()/force_activity()) and
## so was never scored at all - was_forced or an empty
## eligible_activities list distinguishes the two.
var utility_contributions: Array[Dictionary] = []

## Phase 2C: which reserved TavernActivityPoint (if any) this decision's
## selected activity is about - "" otherwise.
var selected_activity_point_id: String = ""

## Phase 2C: the other customer's runtime id if the selected activity is
## Socialise at Seat and a partner was found - -1 otherwise.
var social_partner_customer_id: int = -1

## The other customer's runtime id if this decision started (or joined) a
## shared multi-participant activity like two-player Darts - -1 otherwise.
## Mirrors social_partner_customer_id's shape for a second kind of partner.
var activity_partner_customer_id: int = -1

## Phase 2C: whether the selected activity will send this customer back to
## reserved_chair once finished (true for anything using a
## TavernActivityPoint with return_to_seat_after_use, and implicitly for
## anything that never left the chair to begin with).
var return_to_seat_required: bool = false

## CustomerNeeds.social/entertainment/relaxation at the moment of this
## decision - split from a single "engagement" field, see
## docs/history/2026-08-25_CUSTOMER_ARCHITECTURE_AUDIT.md.
var social: float = 0.0
var entertainment: float = 0.0
var relaxation: float = 0.0

## Phase 2C: VisitRecord.recent_activity_history at the moment of this
## decision - a shallow copy, so later appends to the live list do not
## retroactively change an already-recorded decision.
var recent_activity_history: Array[String] = []

var money: int = 0
var thirst: float = 0.0
var satisfaction: float = 0.0
var intoxication: float = 0.0
var visit_time_remaining_minutes: float = 0.0
var drinks_consumed: int = 0
var has_active_order: bool = false


func to_dictionary() -> Dictionary:
	return {
		"game_time_minutes": game_time_minutes,
		"previous_activity": previous_activity_id,
		"eligible_activities": eligible_activities,
		"rejected_activities": rejected_activities,
		"selected_activity": selected_activity_id,
		"was_forced": was_forced,
		"forced_reason": forced_reason,
		"motivation": motivation,
		"execution_outcome": execution_outcome,
		"top_score": top_score,
		"second_score": second_score,
		"margin": margin,
		"utility_contributions": utility_contributions,
		"selected_activity_point_id": selected_activity_point_id,
		"social_partner_customer_id": social_partner_customer_id,
		"activity_partner_customer_id": activity_partner_customer_id,
		"return_to_seat_required": return_to_seat_required,
		"social": social,
		"entertainment": entertainment,
		"relaxation": relaxation,
		"recent_activity_history": recent_activity_history,
		"state": {
			"money": money,
			"thirst": thirst,
			"satisfaction": satisfaction,
			"intoxication": intoxication,
			"visit_time_remaining_minutes": visit_time_remaining_minutes,
			"drinks_consumed": drinks_consumed,
			"has_active_order": has_active_order,
		},
	}
