class_name CommunicationConfig
extends Resource

## Presentation and lifecycle policy for every message the tavern sends.
##
## Loaded once by the [code]Comms[/code] autoload from
## [constant CommunicationService.DEFAULT_CONFIG_PATH].
##
## The point of this file is that no gameplay script decides what a warning
## looks like. A drink station knows it is low on grog; it does not know that
## warnings are amber, that they sit in the top right, or that three of them at
## once should queue rather than stack. All of that is here.


@export_category("Toasts")

## How many brief notifications may be on screen at once.
##
## Small on purpose. A screen of toasts is a screen the player stops reading,
## which is the exact failure the alert layer exists to avoid.
@export_range(1, 10, 1)
var maximum_visible_toasts: int = 3

## Default seconds a toast stays up when the message does not say.
@export_range(0.5, 30.0, 0.5)
var default_toast_seconds: float = 4.0

## Toasts waiting for a free slot. Beyond this the oldest queued are dropped.
@export_range(1, 100, 1)
var maximum_queued_toasts: int = 12


@export_category("Alerts")

## How many persistent alerts the panel lists before collapsing the rest.
@export_range(1, 30, 1)
var maximum_visible_alerts: int = 6

## Seconds before an identical alert may be raised again after resolving.
##
## Stops a station hovering exactly on its threshold from producing a new
## alert lifecycle every few seconds. The threshold hysteresis on the station
## is the first defence; this is the second.
@export_range(0.0, 600.0, 1.0)
var alert_recreate_cooldown_seconds: float = 10.0

## Whether resolved alerts fade out rather than vanishing.
@export var animate_alert_resolution: bool = true


@export_category("Speaker Messages")

## How many seconds a speaker message with no choices stays up.
@export_range(1.0, 60.0, 0.5)
var speaker_message_seconds: float = 8.0

## Whether a speaker message that offers choices blocks until answered.
##
## False this phase: nothing yet has consequences worth stopping the tavern
## for, and a blocking panel over a running simulation is a good way to lose a
## customer's patience while reading it.
@export var speaker_choices_pause_game: bool = false


@export_category("History")

## Messages retained in the log, oldest discarded first.
@export_range(10, 2000, 10)
var maximum_history_entries: int = 200


@export_category("Severity Colours")

@export var colour_info: Color = Color(0.72, 0.78, 0.86, 1.0)
@export var colour_low: Color = Color(0.62, 0.80, 0.62, 1.0)
@export var colour_warning: Color = Color(0.94, 0.76, 0.36, 1.0)
@export var colour_critical: Color = Color(0.92, 0.42, 0.36, 1.0)


@export_category("Debug")

## Prints every post, update, acknowledgement and resolution.
@export var console_debug_enabled: bool = false


## The colour for [param severity].
##
## Kept as a lookup rather than a match inside the UI so a future theme can
## replace this resource without touching a control script.
func get_severity_colour(
	severity: CommMessage.Severity
) -> Color:
	match severity:
		CommMessage.Severity.LOW:
			return colour_low

		CommMessage.Severity.WARNING:
			return colour_warning

		CommMessage.Severity.CRITICAL:
			return colour_critical

	return colour_info


## A short player-facing label for [param category].
func get_category_label(
	category: CommMessage.Category
) -> String:
	return CommMessage.Category.keys()[category].capitalize()
