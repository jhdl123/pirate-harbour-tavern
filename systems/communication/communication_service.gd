class_name CommunicationService
extends Node

## The one place a message is created, updated, deduplicated and withdrawn.
##
## Autoloaded as [code]Comms[/code].
##
## [b]What this owns[/b]
##
## Message lifecycle, and nothing else. It has no opinion about grog, does not
## know what a drink station is, and cannot tell you how much stock is in
## storage. Systems that know those things - see [StockAlertCoordinator] -
## decide [i]what is true[/i]; this decides [i]what the player is told, once[/i].
##
## [codeblock]
## station stock changes
##   -> station evaluates its own configured thresholds
##   -> emits a stock-state signal
##   -> StockAlertCoordinator builds the sentence and the numbers
##   -> Comms.post()  deduplicates, escalates or resolves
##   -> toast / alert panel / speaker panel
##   -> acknowledgement, or automatic resolution
## [/codeblock]
##
## [b]Why deduplication lives here[/b]
##
## Because every producer would otherwise have to remember it, and one that
## forgot would spam the player with no single place to fix it. Posting the
## same [member CommMessage.deduplication_key] twice updates the first message
## and increments its [member CommMessage.deduplication_count]. Producers can
## therefore be as enthusiastic as they like.


## A message became visible for the first time.
signal message_posted(message: CommMessage)

## An existing message was updated in place rather than duplicated.
signal message_updated(message: CommMessage)

## The player acknowledged a message.
signal message_acknowledged(message: CommMessage)

## A message withdrew, because it was resolved, dismissed or expired.
signal message_resolved(message: CommMessage)

## The player pressed one of a speaker message's buttons.
signal choice_selected(
	message: CommMessage,
	choice_id: StringName
)


const DEFAULT_CONFIG_PATH: String = (
	"res://Data/communication/communication_config.tres"
)


@export var config: CommunicationConfig = null


## deduplication_key -> CommMessage, active messages only.
var _by_key: Dictionary = {}

## Every active message, in post order.
var _active: Array[CommMessage] = []

## Resolved messages, bounded.
var _history: Array[CommMessage] = []

## deduplication_key -> ticks_msec when it resolved, for the recreate cooldown.
var _recent_resolutions: Dictionary = {}

var _next_message_number: int = 1
var _history_dropped: int = 0

var _total_posted: int = 0
var _total_deduplicated: int = 0
var _total_escalated: int = 0
var _total_resolved: int = 0
var _total_acknowledged: int = 0

var _auto_resolve_elapsed: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_resolve_config()


func _resolve_config() -> void:
	if config != null:
		return

	if ResourceLoader.exists(DEFAULT_CONFIG_PATH):
		config = load(DEFAULT_CONFIG_PATH) as CommunicationConfig

	if config != null:
		return

	push_warning(
		"Comms could not load "
		+ DEFAULT_CONFIG_PATH
		+ " - running with built-in defaults."
	)

	config = CommunicationConfig.new()


func _process(
	delta: float
) -> void:
	# Auto-resolution is a world question ("is the station still low?"), so it
	# stops while the simulation is paused. Toast timers live in the UI and are
	# real-time, because reading is not part of the simulation.
	if not Simulation.updates_actors():
		return

	_auto_resolve_elapsed += delta

	if _auto_resolve_elapsed < 0.5:
		return

	_auto_resolve_elapsed = 0.0

	_run_auto_resolution()


# -----------------------------------------------------------------------------
# Posting
# -----------------------------------------------------------------------------

## Publishes [param message], or folds it into an identical existing one.
##
## Returns the message that is actually live - which may not be the one passed
## in. Callers that want to keep updating a message should hold onto the return
## value, not their own copy.
func post(
	message: CommMessage
) -> CommMessage:
	if message == null:
		return null

	if not message.deduplication_key.is_empty():
		var existing: CommMessage = _by_key.get(
			message.deduplication_key
		) as CommMessage

		if existing != null and existing.is_active():
			return _merge_into(existing, message)

		if _is_in_recreate_cooldown(message.deduplication_key):
			_total_deduplicated += 1

			return existing

	message.message_id = StringName("msg_%05d" % _next_message_number)
	_next_message_number += 1

	message.created_minutes = _now_minutes()
	message.displayed_minutes = message.created_minutes

	if message.auto_dismiss_seconds <= 0.0 and not message.is_persistent:
		message.auto_dismiss_seconds = _default_seconds_for(message)

	_active.append(message)

	if not message.deduplication_key.is_empty():
		_by_key[message.deduplication_key] = message

	_total_posted += 1

	if config.console_debug_enabled:
		print(
			"[Comms] posted ",
			message.message_id,
			" [", message.get_severity_name(), "] ",
			message.title
		)

	message_posted.emit(message)

	return message


## Folds a re-post into the message that is already up.
##
## This is where escalation happens: a warning that comes back as critical
## rewrites the live alert rather than sitting beneath a second one. Two
## unrelated alerts for the same condition is the specific outcome this
## prevents.
func _merge_into(
	existing: CommMessage,
	incoming: CommMessage
) -> CommMessage:
	existing.deduplication_count += 1
	_total_deduplicated += 1

	if incoming.severity != existing.severity:
		existing.record_escalation(incoming.severity, _now_minutes())

		_total_escalated += 1

		# A condition that got worse deserves to be looked at again, even if
		# the player had already ticked it off.
		if incoming.severity > existing.severity:
			existing.is_acknowledged = false
			existing.acknowledged_minutes = -1.0

	if not incoming.title.is_empty():
		existing.title = incoming.title

	if not incoming.body.is_empty():
		existing.body = incoming.body

	existing.details = incoming.details.duplicate()

	if not incoming.speaker_id.is_empty():
		existing.speaker_id = incoming.speaker_id
		existing.speaker_name = incoming.speaker_name

	if incoming.auto_resolve.is_valid():
		existing.auto_resolve = incoming.auto_resolve

	if not incoming.metadata.is_empty():
		existing.metadata.merge(incoming.metadata, true)

	if config.console_debug_enabled:
		print(
			"[Comms] updated ",
			existing.message_id,
			" (seen ", existing.deduplication_count + 1, " times)"
		)

	message_updated.emit(existing)

	return existing


# -----------------------------------------------------------------------------
# Convenience posting
# -----------------------------------------------------------------------------

## Posts a brief, self-dismissing notification.
func notify(
	text: String,
	category: CommMessage.Category = CommMessage.Category.SYSTEM,
	severity: CommMessage.Severity = CommMessage.Severity.INFO
) -> CommMessage:
	return post(
		CommMessage.create_notification(text, category, severity)
	)


## Raises or updates a persistent management alert.
func raise_alert(
	key: String,
	title: String,
	body: String,
	category: CommMessage.Category = CommMessage.Category.SYSTEM,
	severity: CommMessage.Severity = CommMessage.Severity.WARNING
) -> CommMessage:
	return post(
		CommMessage.alert(key, title, body, category, severity)
	)


## Posts a line attributed to somebody.
func say(
	speaker_name: String,
	text: String,
	category: CommMessage.Category = CommMessage.Category.STAFF
) -> CommMessage:
	return post(
		CommMessage.speaker(speaker_name, text, category)
	)


# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

func acknowledge(
	message: CommMessage
) -> bool:
	if message == null or message.is_acknowledged or message.is_resolved:
		return false

	message.is_acknowledged = true
	message.acknowledged_minutes = _now_minutes()

	_total_acknowledged += 1

	if config.console_debug_enabled:
		print("[Comms] acknowledged ", message.message_id)

	message_acknowledged.emit(message)

	# An acknowledged message that nothing is waiting on has done its job.
	if not message.is_persistent:
		resolve(message, &"acknowledged")

	return true


func acknowledge_by_key(
	key: String
) -> bool:
	return acknowledge(find_by_key(key))


## Withdraws [param message].
func resolve(
	message: CommMessage,
	reason: StringName = &"resolved"
) -> bool:
	if message == null or message.is_resolved:
		return false

	message.is_resolved = true
	message.resolved_minutes = _now_minutes()
	message.resolution_reason = reason

	_active.erase(message)

	if not message.deduplication_key.is_empty():
		if _by_key.get(message.deduplication_key) == message:
			_by_key.erase(message.deduplication_key)

		_recent_resolutions[message.deduplication_key] = (
			Time.get_ticks_msec()
		)

	_history.append(message)

	while _history.size() > config.maximum_history_entries:
		_history.pop_front()
		_history_dropped += 1

	_total_resolved += 1

	if config.console_debug_enabled:
		print("[Comms] resolved ", message.message_id, " (", reason, ")")

	message_resolved.emit(message)

	return true


func resolve_by_key(
	key: String,
	reason: StringName = &"resolved"
) -> bool:
	return resolve(find_by_key(key), reason)


## Called by the UI when the player presses a choice button.
func select_choice(
	message: CommMessage,
	choice_id: StringName
) -> void:
	if message == null:
		return

	choice_selected.emit(message, choice_id)

	# The speaker gets first refusal on its own buttons, which is what lets a
	# worker handle "take a break" without the service knowing what that means.
	var source: Node = message.get_source()

	if source != null and source.has_method(&"handle_message_choice"):
		source.call(&"handle_message_choice", choice_id)

	resolve(message, &"choice_selected")


func _run_auto_resolution() -> void:
	# Copy: resolving mutates the active list.
	for message: CommMessage in _active.duplicate():
		if not message.auto_resolve.is_valid():
			continue

		if bool(message.auto_resolve.call()):
			resolve(message, &"condition_cleared")


func _is_in_recreate_cooldown(
	key: String
) -> bool:
	if not _recent_resolutions.has(key):
		return false

	var elapsed_ms: int = (
		Time.get_ticks_msec() - int(_recent_resolutions[key])
	)

	return (
		float(elapsed_ms) / 1000.0
		< config.alert_recreate_cooldown_seconds
	)


func _default_seconds_for(
	message: CommMessage
) -> float:
	if message.type == CommMessage.Type.SPEAKER:
		return config.speaker_message_seconds

	return config.default_toast_seconds


# -----------------------------------------------------------------------------
# Reading
# -----------------------------------------------------------------------------

func find_by_key(
	key: String
) -> CommMessage:
	return _by_key.get(key) as CommMessage


func has_active(
	key: String
) -> bool:
	var message: CommMessage = find_by_key(key)

	return message != null and message.is_active()


func get_active_messages() -> Array[CommMessage]:
	var active: Array[CommMessage] = []

	active.assign(_active)

	return active


func get_active_alerts() -> Array[CommMessage]:
	var alerts: Array[CommMessage] = []

	for message: CommMessage in _active:
		if message.type == CommMessage.Type.ALERT:
			alerts.append(message)

	# Worst first, so the panel never buries a critical under three warnings.
	alerts.sort_custom(
		func(a: CommMessage, b: CommMessage) -> bool:
			if a.severity != b.severity:
				return a.severity > b.severity

			return a.created_minutes < b.created_minutes
	)

	return alerts


func get_history() -> Array[CommMessage]:
	var history: Array[CommMessage] = []

	history.assign(_history)

	return history


## How many live alerts name [param speaker_id] as their speaker.
##
## Used by the staff inspection panel to answer "what has this worker been
## warning me about?".
func count_active_alerts_from_speaker(
	speaker_id: StringName
) -> int:
	var count: int = 0

	for message: CommMessage in _active:
		if message.type != CommMessage.Type.ALERT:
			continue

		if message.speaker_id == speaker_id:
			count += 1

	return count


# -----------------------------------------------------------------------------
# Speakers
# -----------------------------------------------------------------------------

## Picks a member of staff to attribute a tavern message to, or null.
##
## Availability is checked, not proximity: a warning must be just as reliable
## when the only worker is across the room, mid-delivery or off-screen. If
## nobody can speak, the caller posts the message unattributed rather than
## suppressing it - the player still needs to know the grog is low even with an
## empty payroll.
## Any staff member willing to speak. The fallback when nothing more specific
## is appropriate.
func find_speaker() -> Node:
	return find_speaker_for_capability(&"")


## The most appropriate speaker for a message about [param capability].
##
## Preference order, and the order matters more than it looks:
##
## [codeblock]
## 1. an enabled worker whose role covers the capability   the bartender, for
##                                                         a stock message
## 2. any enabled worker willing to speak                  better than silence
## 3. null - the caller uses a neutral station voice       better than a lie
## [/codeblock]
##
## Phase 3A.1 returned whichever staff member the group happened to yield
## first, which is why every stock alert in the long test was attributed to
## the Tavern Hand - a worker with no responsibility for, or ability to do
## anything about, an empty barrel. Naming the wrong person is worse than
## naming nobody, because it teaches the player to look in the wrong place.
##
## Passing an empty [param capability] skips step one and asks only for
## somebody who can talk.
func find_speaker_for_capability(
	capability: StringName
) -> Node:
	var tree: SceneTree = get_tree()

	if tree == null:
		return null

	var fallback: Node = null

	for node: Node in tree.get_nodes_in_group(&"tavern_staff"):
		if node == null or not is_instance_valid(node):
			continue

		if not node.has_method(&"can_speak_for_tavern"):
			continue

		if not bool(node.call(&"can_speak_for_tavern")):
			continue

		# A paused or disabled worker should not be quoted as if it were
		# standing there reporting the problem.
		if "is_work_enabled" in node and not bool(node.get("is_work_enabled")):
			continue

		if capability.is_empty():
			return node

		if fallback == null:
			fallback = node

		if not node.has_method(&"get_staff_capabilities"):
			continue

		var capabilities: Array[StringName] = node.call(
			&"get_staff_capabilities"
		)

		if capabilities.has(capability):
			return node

	return fallback


# -----------------------------------------------------------------------------
# Diagnostics
# -----------------------------------------------------------------------------

func get_summary() -> Dictionary:
	return {
		"messages_posted": _total_posted,
		"messages_deduplicated": _total_deduplicated,
		"messages_escalated": _total_escalated,
		"messages_acknowledged": _total_acknowledged,
		"messages_resolved": _total_resolved,
		"active_messages": _active.size(),
		"active_alerts": get_active_alerts().size(),
		"history_entries": _history.size(),
		"history_dropped": _history_dropped,
	}


func build_report_section() -> Dictionary:
	var active: Array = []
	var history: Array = []

	for message: CommMessage in _active:
		active.append(message.to_dictionary())

	for message: CommMessage in _history:
		history.append(message.to_dictionary())

	return {
		"summary": get_summary(),
		"active": active,
		"history": history,
	}


## Clears the log without touching live messages.
func clear_history() -> int:
	var cleared: int = _history.size()

	_history.clear()

	return cleared


## Resolves everything and empties the log. Developer tooling only.
func reset() -> void:
	for message: CommMessage in _active.duplicate():
		resolve(message, &"developer_reset")

	_history.clear()
	_by_key.clear()
	_recent_resolutions.clear()

	_history_dropped = 0


func _now_minutes() -> float:
	return WorldTime.get_total_minutes_precise()
