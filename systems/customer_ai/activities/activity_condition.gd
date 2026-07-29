class_name ActivityCondition
extends Resource

## One reusable rule an [ActivityDefinition] can be built from.
##
## This is what makes "create activity resource, register it, give it
## conditions, done" true for most new activities: a designer drags a few
## condition resources onto an [ActivityDefinition] instead of writing a
## script. [NeedThresholdCondition], [ProbabilityCondition] and
## [DestinationAvailableCondition] cover the common cases; a bespoke
## condition is still just a new [ActivityCondition] subclass, not a change
## to [ActivityDefinition] or [CustomerBrain].
##
## Stateless and shareable: the same condition [Resource] instance is safe to
## reference from several [ActivityDefinition]s at once, the same way one
## [ItemDefinition] is shared by every stack of that item.


## Phase 2C: which named bucket this condition's [method score] is grouped
## under in a decision report's utility contribution breakdown (e.g.
## [code]&"thirst_contribution"[/code], [code]&"repetition_contribution"[/code]).
## Empty (default) means "not broken out separately" - existing Phase 1/2A/2B
## condition resources do not set this and are unaffected; only set it where
## a breakdown is actually wanted, per "only include factors genuinely used"
## in docs/CUSTOMER_AI_SYSTEM.md's Phase 2C section.
@export var contribution_label: StringName = &""


## Hard gate. An activity with any condition returning false here is not a
## candidate at all this think cycle - not "available but low-scoring".
## Default: always satisfied, so a condition that only wants to influence
## scoring (see [method score]) can skip overriding this entirely.
func is_satisfied(_context: ActivityContext) -> bool:
	return true


## Soft preference. Added into [method ActivityDefinition.get_utility]
## alongside every other condition's score and the activity's own
## [member ActivityDefinition.base_utility]. Default: no opinion.
func score(_context: ActivityContext) -> float:
	return 0.0


## Diagnostics only - describes why [method is_satisfied] currently returns
## false, for [member CustomerBrain.debug_enabled] logging. Only called when
## [method is_satisfied] has already returned false, so it never needs to
## re-check that itself. Override for a specific message; the default names
## the condition's own class, which is still more useful than nothing for a
## condition that does not override this.
func get_rejection_reason(_context: ActivityContext) -> String:
	var script_resource: Script = get_script()

	if script_resource != null and script_resource.get_global_name() != "":
		return "%s not satisfied" % script_resource.get_global_name()

	return "condition not satisfied"
