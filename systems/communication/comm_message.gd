class_name CommMessage
extends RefCounted

## One thing the tavern wants to tell the player.
##
## Deliberately one class for all of it. A toast, a persistent stock alert and
## a line of dialogue differ in [member type], [member severity] and how long
## they live - not in their shape. That is what stops the game growing three
## unrelated notification systems that cannot be searched, logged or silenced
## together.
##
## [b]The three types[/b]
##
## [codeblock]
## NOTIFICATION  brief, non-blocking, disappears on its own
##               "Delivery arrived", "£24 received"
##
## ALERT         a condition that is still true and still needs the player
##               "Grog station is nearly empty" - stays until it is resolved
##
## SPEAKER       somebody said something, and may be waiting for an answer
##               the Tavern Hand reporting in; later, a trader haggling
## [/codeblock]
##
## An alert is not "a notification that stays". It is a claim about the world
## that something is continuously responsible for withdrawing - see
## [member auto_resolve] and [method CommunicationService.resolve].


enum Type {
	## Brief and non-blocking. Auto-dismisses.
	NOTIFICATION,

	## A management condition that persists until resolved.
	ALERT,

	## Attributed to somebody, and may offer choices.
	SPEAKER,
}


enum Severity {
	## Background colour. Money received, delivery arrived.
	INFO,

	## Worth knowing, not worth acting on yet.
	LOW,

	## Needs attention soon. Stock running low.
	WARNING,

	## Needs attention now. Stock gone, customers leaving.
	CRITICAL,
}


enum Category {
	STAFF,
	CUSTOMER,
	STOCK,
	DELIVERY,
	VISITOR,
	EVENT,
	SYSTEM,
	TUTORIAL,
}


# --- Identity ----------------------------------------------------------------

## Allocated by [CommunicationService]. Never reused within a session.
var message_id: StringName = &""

var type: Type = Type.NOTIFICATION
var category: Category = Category.SYSTEM
var severity: Severity = Severity.INFO


# --- Content -----------------------------------------------------------------

var title: String = ""

var body: String = ""

## Extra factual lines shown under the body, for example
## [code]["Grog Station: 3 servings remaining", "Replacement stock: none"][/code].
##
## Kept separate from [member body] so the prose and the numbers can be styled
## and updated independently - escalating an alert rewrites the detail without
## touching the sentence.
var details: Array[String] = []


# --- Attribution -------------------------------------------------------------

## Stable id of whoever is talking, for example a worker's
## [member StaffMember.staff_id]. Empty for messages with no speaker.
var speaker_id: StringName = &""

var speaker_name: String = ""

var portrait: Texture2D = null

## What raised this. Held weakly so a freed station cannot keep a message alive.
var source_ref: WeakRef = null

## What the message is about, when that differs from the source.
var target_ref: WeakRef = null


# --- Lifecycle ---------------------------------------------------------------

## Messages sharing a key are the same message.
##
## The single most important field on this class. Posting a message whose key
## already exists updates the existing one instead of adding a second, which is
## the entire anti-spam mechanism: a station consuming its way down from four
## servings to one produces one alert, updated three times.
var deduplication_key: String = ""

## Optional grouping for the UI, for example all alerts about one station.
var group_key: String = ""

## True when this should stay on screen until something resolves it.
var is_persistent: bool = false

## True when the player must acknowledge it before it clears.
var requires_acknowledgement: bool = false

## True when the simulation should pause while this is up.
##
## Off for everything in this phase. Present because a future trader
## negotiation will want it, and retrofitting a pause flag through a UI is
## much worse than carrying an unused boolean.
var pauses_game: bool = false

## Seconds before a non-persistent message dismisses itself. Zero disables.
var auto_dismiss_seconds: float = 4.0

## Optional test that withdraws the message by itself.
##
## A [Callable] returning true when the condition has passed. This is what
## makes a refilled station clear its own warning with nobody having to
## remember to call [method CommunicationService.resolve].
var auto_resolve: Callable = Callable()

var is_acknowledged: bool = false
var is_resolved: bool = false

## Times, in world minutes. Negative means "has not happened".
var created_minutes: float = 0.0
var displayed_minutes: float = -1.0
var acknowledged_minutes: float = -1.0
var resolved_minutes: float = -1.0

## How many times this message was re-posted rather than duplicated.
var deduplication_count: int = 0

## Every severity change, as [code]{ minutes, from, to }[/code].
var escalation_history: Array[Dictionary] = []

## Why the message withdrew itself.
var resolution_reason: StringName = &""


# --- Interaction -------------------------------------------------------------

## Buttons offered on a speaker message, as
## [code]{ "id": StringName, "label": String }[/code].
##
## The service emits [signal CommunicationService.choice_selected] with the id.
## Nothing branches on choices this phase; the shape exists so that a future
## dialogue does not need the message class changed underneath it.
var choices: Array[Dictionary] = []

## Free-form extras for whatever raised the message.
var metadata: Dictionary = {}


func get_source() -> Node:
	return _resolve(source_ref)


func get_target() -> Node:
	return _resolve(target_ref)


func _resolve(
	reference: WeakRef
) -> Node:
	if reference == null:
		return null

	var node: Node = reference.get_ref() as Node

	if node == null or not is_instance_valid(node):
		return null

	return node


func set_source(
	node: Node
) -> void:
	source_ref = (null if node == null else weakref(node))


func set_target(
	node: Node
) -> void:
	target_ref = (null if node == null else weakref(node))


## Alias so callers can write [code]message.source = station[/code].
##
## GDScript has no property setters on plain variables here, so this is a
## method; the weak reference is what actually matters.
var source: Node:
	get:
		return get_source()
	set(value):
		set_source(value)


var target: Node:
	get:
		return get_target()
	set(value):
		set_target(value)


func is_active() -> bool:
	return not is_resolved


func get_type_name() -> String:
	return Type.keys()[type]


func get_severity_name() -> String:
	return Severity.keys()[severity]


func get_category_name() -> String:
	return Category.keys()[category]


## The full text, body plus details, as the UI shows it.
func get_full_text() -> String:
	var lines: Array[String] = []

	if not body.is_empty():
		lines.append(body)

	for detail: String in details:
		lines.append(detail)

	return "\n".join(lines)


## Records a severity change. Called by [CommunicationService].
func record_escalation(
	new_severity: Severity,
	now_minutes: float
) -> void:
	if new_severity == severity:
		return

	escalation_history.append({
		"minutes": now_minutes,
		"from": get_severity_name(),
		"to": Severity.keys()[new_severity],
	})

	severity = new_severity


func to_dictionary() -> Dictionary:
	var source_node: Node = get_source()

	return {
		"message_id": String(message_id),
		"type": get_type_name(),
		"category": get_category_name(),
		"severity": get_severity_name(),
		"title": title,
		"body": body,
		"details": details.duplicate(),
		"speaker_id": String(speaker_id),
		"speaker_name": speaker_name,
		"source": ("" if source_node == null else String(source_node.name)),
		"deduplication_key": deduplication_key,
		"group_key": group_key,
		"is_persistent": is_persistent,
		"requires_acknowledgement": requires_acknowledgement,
		"is_acknowledged": is_acknowledged,
		"is_resolved": is_resolved,
		"created_minutes": created_minutes,
		"displayed_minutes": displayed_minutes,
		"acknowledged_minutes": acknowledged_minutes,
		"resolved_minutes": resolved_minutes,
		"deduplication_count": deduplication_count,
		"escalation_history": escalation_history.duplicate(true),
		"resolution_reason": String(resolution_reason),
		"metadata": metadata.duplicate(true),
	}


# -----------------------------------------------------------------------------
# Builders
# -----------------------------------------------------------------------------

## A brief, self-dismissing message.
##
## Named create_notification rather than notification because Object
## already has a notification() method, and GDScript cannot resolve a
## static member that shadows a built-in one.
static func create_notification(
	text: String,
	message_category: Category = Category.SYSTEM,
	message_severity: Severity = Severity.INFO
) -> CommMessage:
	var message: CommMessage = CommMessage.new()

	message.type = Type.NOTIFICATION
	message.category = message_category
	message.severity = message_severity
	message.body = text

	return message


## A persistent management condition.
##
## [param key] is the deduplication key and is required: an alert with no key
## cannot be updated or resolved later, which makes it a notification wearing
## the wrong hat.
static func alert(
	key: String,
	alert_title: String,
	text: String,
	message_category: Category = Category.SYSTEM,
	message_severity: Severity = Severity.WARNING
) -> CommMessage:
	var message: CommMessage = CommMessage.new()

	message.type = Type.ALERT
	message.category = message_category
	message.severity = message_severity
	message.deduplication_key = key
	message.title = alert_title
	message.body = text
	message.is_persistent = true
	message.auto_dismiss_seconds = 0.0

	return message


## Something somebody said.
static func speaker(
	speaker_display_name: String,
	text: String,
	message_category: Category = Category.STAFF
) -> CommMessage:
	var message: CommMessage = CommMessage.new()

	message.type = Type.SPEAKER
	message.category = message_category
	message.speaker_name = speaker_display_name
	message.title = speaker_display_name
	message.body = text
	message.auto_dismiss_seconds = 8.0

	return message
