# Phase 2B.2 Change Report — Utility Balancing & Natural Departures

## Summary

Found and fixed the real cause of the "almost no voluntary Leave" pattern
your diagnostic reports revealed: `leave_money_scoring.tres` was
accidentally hard-gating Leave (`is_satisfied()` required `wealth <= 0`),
because `NeedThresholdCondition` had no way to be scoring-only -
`DomainFlagCondition` got that ability back in Phase 2B; this class never
did. Fixed the class itself, then re-derived every affected condition's
threshold/weight using a more robust pattern that doesn't assume a fixed
maximum for unbounded values like money or visit duration. Added a
mandatory "broke and nothing left to finish" departure, diminishing
returns on repeated Relax, a gradual per-drink pull toward Leave, disabled
Wander from selection (framework untouched), and expanded decision
diagnostics with top/second/margin scores. No new customer activities.

## Root cause

See `docs/CUSTOMER_AI_SYSTEM.md`'s Phase 2B.2 section for the full
explanation with the exact rejection-reason string your report already
showed (`"need 'wealth' is 13.00, needed at most 0.00"`) as evidence.

## Files supplied

### New files

| File | Destination |
|---|---|
| Repeat-decay condition class | `res://systems/customer_ai/activities/conditions/repeat_decay_condition.gd` |
| Relax repeat-decay instance | `res://Data/customer_ai/conditions/relax_repeat_decay.tres` |
| Leave: gradual drinks-consumed scoring | `res://Data/customer_ai/conditions/leave_drinks_scoring.tres` |

### Modified files (replace your copy with the supplied one)

| File | Destination |
|---|---|
| NeedThresholdCondition (the fix) | `res://systems/customer_ai/activities/conditions/need_threshold_condition.gd` |
| CustomerBrain (mandatory broke-departure, top/second/margin) | `res://systems/customer_ai/customer_brain.gd` |
| CustomerNeeds (`relax_count`, `drinks_consumed`) | `res://systems/customer_ai/customer_needs.gd` |
| Customer (`_on_activity_forced`, need increments) | `res://scripts/Entities/customer.gd` |
| Report manager (forced-reason categorisation) | `res://systems/customer_ai/diagnostics/customer_ai_report_manager.gd` |
| Decision record (`top_score`/`second_score`/`margin`) | `res://systems/customer_ai/diagnostics/decision_record.gd` |
| Order Drink: thirst scoring | `res://Data/customer_ai/conditions/order_thirst_scoring.tres` |
| Order Drink: visit-time scoring | `res://Data/customer_ai/conditions/order_visit_time_scoring.tres` |
| Order Drink: money scoring | `res://Data/customer_ai/conditions/order_money_scoring.tres` |
| Order Drink: satisfaction scoring | `res://Data/customer_ai/conditions/order_satisfaction_scoring.tres` |
| Relax: visit-time scoring | `res://Data/customer_ai/conditions/relax_visit_time_scoring.tres` |
| Relax: satisfaction scoring | `res://Data/customer_ai/conditions/relax_satisfaction_scoring.tres` |
| Relax: thirst scoring | `res://Data/customer_ai/conditions/relax_thirst_scoring.tres` |
| Relax: intoxication scoring | `res://Data/customer_ai/conditions/relax_intoxication_scoring.tres` |
| Relax at Seat activity definition (adds repeat-decay) | `res://Data/customer_ai/activities/relax_at_seat.tres` |
| Leave: visit-time scoring | `res://Data/customer_ai/conditions/leave_visit_time_scoring.tres` |
| Leave: money scoring (the critical fix) | `res://Data/customer_ai/conditions/leave_money_scoring.tres` |
| Leave: intoxication scoring | `res://Data/customer_ai/conditions/leave_intoxication_scoring.tres` |
| Leave: thirst scoring | `res://Data/customer_ai/conditions/leave_thirst_scoring.tres` |
| Leave: satisfaction scoring (Phase 1 resource, now fixed) | `res://Data/customer_ai/conditions/leave_mood_scoring.tres` |
| Leave activity definition (adds drinks scoring) | `res://Data/customer_ai/activities/leave.tres` |
| Activity registry (Wander removed from selection) | `res://Data/customer_ai/activity_registry.tres` |
| Customer AI architecture doc | `res://docs/CUSTOMER_AI_SYSTEM.md` |

## Files to remove

None. `Data/customer_ai/activities/wander.tres`,
`systems/customer_ai/activities/behaviours/wander_behaviour.gd`, and
`Data/customer_ai/conditions/wander_chance.tres` are all still present and
unmodified - Wander is disabled by omission from the registry's
`definitions` array, not deleted, per the brief's explicit instruction to
preserve the framework.

## Installation guide

1. Copy every file above into your project at the exact path shown,
   overwriting where one already exists.
2. Open the project in Godot 4.7.1 and let it re-import.
3. Confirm no parser errors in the Output panel.
4. Play a session and confirm (via the F10 export or live console output)
   that some visits now end with `departure_reason: "utility_decision"` or
   `"out_of_money"`, not exclusively `"patience_expired"`/
   `"visit_time_expired"`.

## Configuration

- **Money influence**: `Data/customer_ai/conditions/order_money_scoring.tres`
  and `leave_money_scoring.tres`.
- **Satisfaction influence**: `order_satisfaction_scoring.tres`,
  `relax_satisfaction_scoring.tres`, `leave_mood_scoring.tres`.
- **Visit-time influence**: `order_visit_time_scoring.tres`,
  `relax_visit_time_scoring.tres`, `leave_visit_time_scoring.tres`.
- **Relax diminishing factor**: `relax_repeat_decay.tres`
  (`decay_per_repeat`, `reference_utility`).
- **Drink influence on Leave**: `leave_drinks_scoring.tres` (gradual) and
  `at_drink_limit_scoring.tres` (Phase 2A's bonus once at the hard limit).
- **Intoxication influence**: `intoxication_order_gate.tres` (the hard
  gate/threshold), `relax_intoxication_scoring.tres`,
  `leave_intoxication_scoring.tres`.
- **Leave weighting overall**: `leave.tres`'s own `base_utility` plus every
  condition listed above under "Leave".

## Test procedure

1. Run a 10-20 minute session across several tables, export a Customer AI
   report, and confirm `total_normal_utility_departures` and/or a
   forced-but-not-timer reason (`out_of_money`) are now non-zero alongside
   `total_patience_departures`/`total_visit_time_departures` - not zero, as
   in the report that prompted this pass.
2. Spot-check a `decisions_by_customer_id` entry where `selected_activity`
   is `"leave"` and `was_forced` is `false` - confirm the customer's
   `state.money` in that decision is low relative to their starting money,
   or their `state.satisfaction` is low, consistent with a voluntary
   choice rather than a forced one.
3. Watch a customer relax several times in a row (console output or the
   decisions list) and confirm each successive Relax score is lower than
   the last, relative to Order Drink/Leave's scores at the same point.
4. Let a customer's money hit exactly 0 with no drink in progress and
   confirm they leave immediately with `departure_reason: "out_of_money"`,
   even with plenty of visit time left.
5. Confirm Wander never appears as a `selected_activity` or even a
   rejected/eligible entry in a fresh session's decisions.
6. Confirm the project still loads with no parser errors and no missing
   resources.

## Known limitations

The weights above were derived algebraically and hand-traced against
three representative scenarios (see `docs/CUSTOMER_AI_SYSTEM.md`), not
tuned against a large batch of real sessions - if particular archetypes
still feel off in practice (too eager to leave, too reluctant), the
relevant single condition `.tres` file is where to adjust it; nothing is
scattered across scripts. No new customer activities, conversations,
groups, or other Phase 2C-scope systems were added, per this update's
explicit scope.
