class_name InteractionInput
extends RefCounted

## Turns an input action into the key label shown in a prompt.
##
## Prompts read "[E] Pour Grog" because this class asks the [InputMap] what
## "player_interact" is currently bound to. Rebinding a key - in project
## settings today, in an options menu later - therefore updates every prompt in
## the game with no further work.
##
## Nothing here is interaction-specific; any future UI that needs to show a key
## hint should use it too.


## Names used in place of raw keycodes where the raw name reads badly.
const FRIENDLY_KEY_NAMES: Dictionary = {
	"Escape": "Esc",
	"Return": "Enter",
	"Kp Enter": "Enter",
}


## The label for the first key bound to [param action_name].
##
## Falls back to [param fallback] when the action does not exist or has no key
## bound, so a prompt never shows an empty bracket.
static func get_action_key_label(
	action_name: StringName,
	fallback: String = "?"
) -> String:
	if not InputMap.has_action(action_name):
		push_warning(
			"Input action '%s' does not exist."
			% String(action_name)
		)

		return fallback

	for event: InputEvent in InputMap.action_get_events(action_name):
		var key_event: InputEventKey = event as InputEventKey

		if key_event == null:
			continue

		var label: String = _get_key_event_label(key_event)

		if not label.is_empty():
			return label

	for event: InputEvent in InputMap.action_get_events(action_name):
		var button_event: InputEventMouseButton = (
			event as InputEventMouseButton
		)

		if button_event == null:
			continue

		return _get_mouse_button_label(button_event.button_index)

	return fallback


## The label wrapped in brackets, ready to sit in front of an action label.
static func get_action_key_hint(
	action_name: StringName,
	fallback: String = "?"
) -> String:
	return "[%s]" % get_action_key_label(action_name, fallback)


static func _get_key_event_label(
	key_event: InputEventKey
) -> String:
	var keycode: Key = key_event.physical_keycode

	if keycode == KEY_NONE:
		keycode = key_event.keycode

	if keycode == KEY_NONE:
		return ""

	var label: String = OS.get_keycode_string(keycode)

	if FRIENDLY_KEY_NAMES.has(label):
		return String(FRIENDLY_KEY_NAMES[label])

	return label


static func _get_mouse_button_label(
	button_index: MouseButton
) -> String:
	match button_index:
		MOUSE_BUTTON_LEFT:
			return "LMB"
		MOUSE_BUTTON_RIGHT:
			return "RMB"
		MOUSE_BUTTON_MIDDLE:
			return "MMB"
		_:
			return "Mouse %d" % button_index
