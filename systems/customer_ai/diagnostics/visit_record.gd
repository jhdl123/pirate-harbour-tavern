class_name VisitRecord
extends RefCounted

## One customer visit's diagnostic summary, from spawn to departure.
##
## A plain data holder - CustomerAIReportManager owns the list of these and
## writes them into the JSON report. Kept separate from CustomerNeeds/
## Customer themselves so a visit's final numbers survive after the
## customer node is freed.


var customer_id: int = -1
var customer_type_name: String = ""
var personality_name: String = ""

var spawn_game_time_minutes: float = 0.0
var departure_game_time_minutes: float = -1.0

var starting_money: int = 0
var ending_money: int = 0
var starting_thirst: float = 0.0
var ending_thirst: float = 0.0
var starting_satisfaction: float = 0.0
var ending_satisfaction: float = 0.0
var final_intoxication: float = 0.0

var drinks_ordered: int = 0
var drinks_served: int = 0
var drinks_consumed: int = 0
var payments_made: int = 0

var relax_count: int = 0

## Phase 2C
var socialise_count: int = 0

## Runtime customer ids of every partner socialised with this visit
## (-1 entries mean no partner was nearby that time) - see
## CustomerAIReportManager.record_socialise().
var social_partner_ids: Array[int] = []
var tavern_activity_count: int = 0
var darts_count: int = 0
var activity_reservation_failures: int = 0
var return_to_seat_failures: int = 0
var maximum_engagement_reached: float = 0.0

## Every distinct activity_id this visit ever entered, in first-seen order -
## "unique activities completed".
var unique_activities_completed: Array[String] = []

## The last few activity ids entered, oldest first, capped at a small fixed
## length (see CustomerAIReportManager.record_activity_entered()) - enough
## to see a recent sequence without the report growing per-decision.
var recent_activity_history: Array[String] = []

var chair_id: String = ""
var kept_same_chair_for_visit: bool = true

## &"" while still active. One of &"patience_expired", &"visit_time_expired",
## &"utility_decision", &"out_of_money", or &"unknown" once departed - see
## Customer.departure_reason.
var departure_reason: StringName = &""

var patience_expired: bool = false
var visit_time_expired: bool = false
var maximum_drinks_reached: bool = false

var activity_failures: int = 0
var navigation_recovery_count: int = 0

## True once departure_game_time_minutes has been set - lets the report
## distinguish a completed visit from one still in progress when the
## report was generated, without relying on a separate collection.
var is_completed: bool = false


func get_visit_duration_minutes() -> float:
	if not is_completed:
		return -1.0

	return departure_game_time_minutes - spawn_game_time_minutes


## Phase 2C: called by CustomerAIReportManager whenever an activity is
## entered, to keep unique_activities_completed/recent_activity_history
## current without CustomerBrain or Customer needing to know this record
## exists.
func note_activity_entered(activity_id: String, history_length: int) -> void:
	if not unique_activities_completed.has(activity_id):
		unique_activities_completed.append(activity_id)

	recent_activity_history.append(activity_id)

	while recent_activity_history.size() > history_length:
		recent_activity_history.pop_front()


func to_dictionary() -> Dictionary:
	return {
		"customer_id": customer_id,
		"customer_type": customer_type_name,
		"personality": personality_name,
		"spawn_game_time_minutes": spawn_game_time_minutes,
		"departure_game_time_minutes": departure_game_time_minutes,
		"visit_duration_minutes": get_visit_duration_minutes(),
		"is_completed": is_completed,
		"starting_money": starting_money,
		"ending_money": ending_money,
		"starting_thirst": starting_thirst,
		"ending_thirst": ending_thirst,
		"starting_satisfaction": starting_satisfaction,
		"ending_satisfaction": ending_satisfaction,
		"final_intoxication": final_intoxication,
		"drinks_ordered": drinks_ordered,
		"drinks_served": drinks_served,
		"drinks_consumed": drinks_consumed,
		"payments_made": payments_made,
		"relax_count": relax_count,
		"socialise_count": socialise_count,
		"social_partner_ids": social_partner_ids,
		"tavern_activity_count": tavern_activity_count,
		"darts_count": darts_count,
		"activity_reservation_failures": activity_reservation_failures,
		"return_to_seat_failures": return_to_seat_failures,
		"maximum_engagement_reached": maximum_engagement_reached,
		"unique_activities_completed": unique_activities_completed,
		"recent_activity_history": recent_activity_history,
		"chair_id": chair_id,
		"kept_same_chair_for_visit": kept_same_chair_for_visit,
		"departure_reason": String(departure_reason),
		"patience_expired": patience_expired,
		"visit_time_expired": visit_time_expired,
		"maximum_drinks_reached": maximum_drinks_reached,
		"activity_failures": activity_failures,
		"navigation_recovery_count": navigation_recovery_count,
	}
