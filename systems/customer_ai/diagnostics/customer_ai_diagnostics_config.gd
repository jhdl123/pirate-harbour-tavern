class_name CustomerAIDiagnosticsConfig
extends Resource

## Console logging and JSON report export settings - deliberately two
## independent switches (requirement: "Console logging and JSON diagnostic
## export should be independently configurable"), plus the report's size
## controls. See CustomerAIReportManager for what actually reads these.
##
## Moved here from GameConfig.show_customer_ai_debug_messages in Phase 2B so
## every diagnostics-related switch lives in one place alongside the report
## settings that are new this phase.


@export_category("Console Logging")

## Prints CustomerBrain's considered/rejected/chosen activities, forced
## transitions, and Customer's own drink/chair/relax lines. Off by default:
## fires on every decision, for every customer, and would drown normal
## output.
@export var console_debug_enabled: bool = false


@export_category("JSON Report Export")

## Master switch for the whole diagnostic-report system. When false,
## CustomerAIReportManager still exists and can be called safely, but does
## no recording at all and finalize_and_write_report() writes nothing - see
## its own doc comment for why normal play never depends on this being on.
@export var export_enabled: bool = false

@export var record_decision_history: bool = true
@export var record_rejection_reasons: bool = true

@export_range(1, 200, 1)
var maximum_decisions_per_customer: int = 20

@export_range(1, 5000, 1)
var maximum_completed_visits_retained: int = 500

@export var pretty_print_json: bool = true
