extends Node

## Neutral customer behaviour events, for a future information/rumour system
## to consume without any further customer refactor.
##
## [b]These emit facts, never intelligence.[/b] Nothing here generates a
## rumour, a secret, or an information record - that is explicitly out of
## scope. What this does is guarantee that when the information system is
## built, every moment it would care about (who talked to whom, for how
## long, about what kind of subject, how discreet they are) has already
## happened somewhere it can hear it.
##
## [b]Payloads are plain data.[/b] Stable ids and values, never node
## references, so a listener can queue an event and process it later without
## keeping a departed customer's node alive - and so a payload can be
## serialised into a save or a diagnostic report unchanged.
##
## An autoload, registered in project.godot, following the same pattern as
## the existing Comms and TaskBoard singletons. Emitting into an empty
## signal costs effectively nothing, so these fire whether or not anything
## is listening yet.


signal customer_identity_initialized(payload: Dictionary)
signal customer_visit_intention_selected(payload: Dictionary)
signal customer_decision_evaluated(payload: Dictionary)
signal customer_action_selected(payload: Dictionary)
signal customer_activity_started(payload: Dictionary)
signal customer_activity_completed(payload: Dictionary)
signal customer_activity_interrupted(payload: Dictionary)
signal customer_social_interaction_started(payload: Dictionary)
signal customer_social_interaction_ended(payload: Dictionary)
signal customer_joined_social_group(payload: Dictionary)
signal customer_left_social_group(payload: Dictionary)
signal customer_reordered(payload: Dictionary)
signal customer_decided_to_leave(payload: Dictionary)
signal customer_departed(payload: Dictionary)


## When true, every emitted payload is also appended to [member event_log]
## for the diagnostics exporter. Off during normal play - an unbounded log
## of every decision by every customer is exactly the sort of thing that
## quietly eats memory over a long session.
var logging_enabled: bool = false

## Cap on [member event_log], oldest dropped first.
var maximum_logged_events: int = 2000

var event_log: Array[Dictionary] = []


func emit_identity_initialised(identity: CustomerIdentity) -> void:
	if identity == null:
		return

	_dispatch(
		customer_identity_initialized,
		&"customer_identity_initialized",
		identity.build_event_payload()
	)


func emit_intention_selected(identity: CustomerIdentity) -> void:
	if identity == null:
		return

	_dispatch(
		customer_visit_intention_selected,
		&"customer_visit_intention_selected",
		identity.build_event_payload()
	)


## The full candidate set for one decision. [param eligible] and
## [param rejected] are the same arrays CustomerBrain already builds for its
## report, passed through rather than rebuilt.
func emit_decision_evaluated(
	identity: CustomerIdentity,
	eligible: Array,
	rejected: Array,
	selected_id: StringName
) -> void:
	var payload: Dictionary = _base_payload(identity)

	payload["eligible"] = eligible.duplicate()
	payload["rejected"] = rejected.duplicate()
	payload["selected_activity_id"] = String(selected_id)

	_dispatch(
		customer_decision_evaluated, &"customer_decision_evaluated", payload
	)


func emit_action_selected(
	identity: CustomerIdentity,
	activity_id: StringName,
	score: float
) -> void:
	var payload: Dictionary = _base_payload(identity)

	payload["activity_id"] = String(activity_id)
	payload["score"] = score

	_dispatch(
		customer_action_selected, &"customer_action_selected", payload
	)


func emit_activity_started(
	identity: CustomerIdentity,
	activity_id: StringName
) -> void:
	var payload: Dictionary = _base_payload(identity)

	payload["activity_id"] = String(activity_id)

	_dispatch(
		customer_activity_started, &"customer_activity_started", payload
	)


## Routes to completed or interrupted depending on [param completed], so a
## listener can distinguish "finished their game of darts" from "was pulled
## away mid-game" without inspecting the payload.
func emit_activity_ended(
	identity: CustomerIdentity,
	activity_id: StringName,
	completed: bool
) -> void:
	var payload: Dictionary = _base_payload(identity)

	payload["activity_id"] = String(activity_id)
	payload["completed"] = completed

	if completed:
		_dispatch(
			customer_activity_completed,
			&"customer_activity_completed",
			payload
		)
	else:
		_dispatch(
			customer_activity_interrupted,
			&"customer_activity_interrupted",
			payload
		)


## A social interaction beginning. [param participant_ids] are customer ids.
## [param topic_tags] come from the visit intent's descriptive tags - they
## describe what the conversation is nominally about, and generate nothing.
func emit_social_interaction_started(
	identity: CustomerIdentity,
	participant_ids: Array,
	area_id: StringName,
	activity_id: StringName,
	topic_tags: Array,
	world_minutes: float
) -> void:
	var payload: Dictionary = _base_payload(identity)

	payload["participant_ids"] = participant_ids.duplicate()
	payload["area_id"] = String(area_id)
	payload["activity_id"] = String(activity_id)
	payload["topic_tags"] = topic_tags.duplicate()
	payload["started_at_minutes"] = world_minutes

	_dispatch(
		customer_social_interaction_started,
		&"customer_social_interaction_started",
		payload
	)


func emit_social_interaction_ended(
	identity: CustomerIdentity,
	participant_ids: Array,
	duration_minutes: float,
	outcome: StringName
) -> void:
	var payload: Dictionary = _base_payload(identity)

	payload["participant_ids"] = participant_ids.duplicate()
	payload["duration_minutes"] = duration_minutes
	payload["outcome"] = String(outcome)

	_dispatch(
		customer_social_interaction_ended,
		&"customer_social_interaction_ended",
		payload
	)


func emit_joined_social_group(
	identity: CustomerIdentity,
	group_id: StringName
) -> void:
	var payload: Dictionary = _base_payload(identity)

	payload["social_group_id"] = String(group_id)

	_dispatch(
		customer_joined_social_group, &"customer_joined_social_group", payload
	)


func emit_left_social_group(
	identity: CustomerIdentity,
	group_id: StringName
) -> void:
	var payload: Dictionary = _base_payload(identity)

	payload["social_group_id"] = String(group_id)

	_dispatch(
		customer_left_social_group, &"customer_left_social_group", payload
	)


func emit_reordered(
	identity: CustomerIdentity,
	drink_id: StringName,
	drinks_so_far: int
) -> void:
	var payload: Dictionary = _base_payload(identity)

	payload["drink_id"] = String(drink_id)
	payload["drinks_consumed"] = drinks_so_far

	_dispatch(customer_reordered, &"customer_reordered", payload)


func emit_decided_to_leave(
	identity: CustomerIdentity,
	reason: StringName
) -> void:
	var payload: Dictionary = _base_payload(identity)

	payload["reason"] = String(reason)

	_dispatch(
		customer_decided_to_leave, &"customer_decided_to_leave", payload
	)


func emit_departed(
	identity: CustomerIdentity,
	reason: StringName,
	visit_duration_minutes: float,
	drinks_consumed: int
) -> void:
	var payload: Dictionary = _base_payload(identity)

	payload["reason"] = String(reason)
	payload["visit_duration_minutes"] = visit_duration_minutes
	payload["drinks_consumed"] = drinks_consumed

	_dispatch(customer_departed, &"customer_departed", payload)


func clear_log() -> void:
	event_log.clear()


## Every logged event of one type, for the diagnostics exporter.
func get_logged_events(event_name: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for entry: Dictionary in event_log:
		if StringName(entry.get("event", &"")) == event_name:
			result.append(entry)

	return result


## Identity fields every payload carries. Tolerates a null identity so a
## customer built without one still emits usable events rather than
## crashing the emitter.
func _base_payload(identity: CustomerIdentity) -> Dictionary:
	if identity == null:
		return {
			"customer_id": -1,
			"customer_type_id": "",
			"group_id": "",
			"visit_intent_id": "",
		}

	return identity.build_event_payload()


func _dispatch(
	target: Signal,
	event_name: StringName,
	payload: Dictionary
) -> void:
	payload["event"] = String(event_name)

	target.emit(payload)

	if not logging_enabled:
		return

	event_log.append(payload)

	if event_log.size() > maximum_logged_events:
		event_log.remove_at(0)
