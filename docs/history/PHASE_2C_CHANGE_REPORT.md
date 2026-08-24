# Phase 2C Change Report — Tavern Activities, Social Behaviour & Reasons to Stay

## Summary

Three new activities join the existing Order Drink / Drink / Relax at Seat /
Leave: **Socialise at Seat** (talks with a nearby seated customer, found
through a plain group rather than a new discovery system), **Visit Tavern
Activity** (a generic behaviour that travels to, uses, and returns from any
`TavernActivityPoint`), and **Return to Seat** (the deterministic hand-off
back to the chair, a real tracked activity rather than an untracked engine
state). One new reusable world-object framework, `TavernActivityPoint`,
built entirely on the existing `Reservable` system - no second reservation
system was created. One proof-of-concept instance of it, **Darts**.

Customers keep their reserved chair the entire time they are away at an
activity - nothing about the existing one-chair-per-visit design needed to
change for that to be true. A failed journey to or from an activity
recovers (releases the reservation, retries returning to the chair) rather
than ending the visit. `CustomerNeeds.engagement` ("reasons to stay") rises
from a successful Socialise or Darts visit and decays a little every
decision, pulling Leave down without ever being able to block it entirely.
Every scoring condition project-wide - not just this phase's new ones - now
declares which named "contribution bucket" it belongs to, so a decision
report can show a full breakdown of why an activity scored the way it did.
Wander stays disabled. No `main.tscn` node paths were replaced - one
instanced sub-scene and its `ext_resource` line were added; everything
else is exactly as Phase 2B.2 left it.

## Files supplied

### New files

| File | Destination |
|---|---|
| TavernActivityPoint (the reusable framework) | `res://systems/tavern_activities/tavern_activity_point.gd` |
| SocialiseAtSeatBehaviour | `res://systems/customer_ai/activities/behaviours/socialise_at_seat_behaviour.gd` |
| VisitTavernActivityBehaviour | `res://systems/customer_ai/activities/behaviours/visit_tavern_activity_behaviour.gd` |
| ReturnToSeatBehaviour | `res://systems/customer_ai/activities/behaviours/return_to_seat_behaviour.gd` |
| EndOfVisitPressureCondition | `res://systems/customer_ai/activities/conditions/end_of_visit_pressure_condition.gd` |
| NearestPointDistanceCondition | `res://systems/customer_ai/activities/conditions/nearest_point_distance_condition.gd` |
| Darts point scene | `res://scenes/furniture/darts_point.tscn` |
| Socialise: partner-availability gate | `res://Data/customer_ai/conditions/has_social_partner.tres` |
| Socialise: repeat decay | `res://Data/customer_ai/conditions/socialise_repeat_decay.tres` |
| Socialise: satisfaction scoring | `res://Data/customer_ai/conditions/socialise_satisfaction_scoring.tres` |
| Socialise: visit-time scoring | `res://Data/customer_ai/conditions/socialise_visit_time_scoring.tres` |
| Socialise: intoxication scoring | `res://Data/customer_ai/conditions/socialise_intoxication_scoring.tres` |
| Socialise: thirst scoring | `res://Data/customer_ai/conditions/socialise_thirst_scoring.tres` |
| Visit Activity: availability gate | `res://Data/customer_ai/conditions/visit_activity_availability.tres` |
| Visit Activity: minimum-time gate | `res://Data/customer_ai/conditions/visit_activity_min_time_remaining.tres` |
| Visit Activity: distance scoring | `res://Data/customer_ai/conditions/visit_activity_distance_scoring.tres` |
| Darts repeat decay | `res://Data/customer_ai/conditions/darts_repeat_decay.tres` |
| Visit Activity: satisfaction scoring | `res://Data/customer_ai/conditions/visit_activity_satisfaction_scoring.tres` |
| Visit Activity: thirst scoring | `res://Data/customer_ai/conditions/visit_activity_thirst_scoring.tres` |
| Leave: engagement scoring | `res://Data/customer_ai/conditions/leave_engagement_scoring.tres` |
| Leave: end-of-visit pressure | `res://Data/customer_ai/conditions/leave_end_of_visit_pressure.tres` |
| Relax: engagement scoring | `res://Data/customer_ai/conditions/relax_engagement_scoring.tres` |
| Socialise at Seat behaviour instance | `res://Data/customer_ai/behaviours/socialise_at_seat.tres` |
| Visit Tavern Activity behaviour instance | `res://Data/customer_ai/behaviours/visit_tavern_activity.tres` |
| Return to Seat behaviour instance | `res://Data/customer_ai/behaviours/return_to_seat.tres` |
| Socialise at Seat activity definition | `res://Data/customer_ai/activities/socialise_at_seat.tres` |
| Visit Tavern Activity activity definition | `res://Data/customer_ai/activities/visit_tavern_activity.tres` |
| Return to Seat activity definition | `res://Data/customer_ai/activities/return_to_seat.tres` |

### Modified files (replace your copy with the supplied one)

| File | Destination |
|---|---|
| ActivityContext (`reserved_destination`) | `res://systems/customer_ai/activities/activity_context.gd` |
| ActivityCondition (`contribution_label`) | `res://systems/customer_ai/activities/activity_condition.gd` |
| ActivityDefinition (`get_utility_breakdown`) | `res://systems/customer_ai/activities/activity_definition.gd` |
| CustomerBrain | `res://systems/customer_ai/customer_brain.gd` |
| CustomerNeeds | `res://systems/customer_ai/customer_needs.gd` |
| CustomerAIBalanceConfig | `res://systems/customer_ai/customer_ai_balance_config.gd` |
| Personality | `res://systems/customer_ai/personality.gd` |
| VisitRecord | `res://systems/customer_ai/diagnostics/visit_record.gd` |
| DecisionRecord | `res://systems/customer_ai/diagnostics/decision_record.gd` |
| CustomerAIReportManager | `res://systems/customer_ai/diagnostics/customer_ai_report_manager.gd` |
| Customer | `res://scripts/Entities/customer.gd` |
| Stock dev panel | `res://scripts/UI/stock_dev_panel.gd` |
| Sailor personality | `res://Data/customer_ai/personalities/sailor.tres` |
| Impatient Sailor personality | `res://Data/customer_ai/personalities/sailor_impatient.tres` |
| Leave activity definition | `res://Data/customer_ai/activities/leave.tres` |
| Relax at Seat activity definition | `res://Data/customer_ai/activities/relax_at_seat.tres` |
| Activity registry | `res://Data/customer_ai/activity_registry.tres` |
| Main scene (Darts instanced - one node, one ext_resource) | `res://scenes/main/main.tscn` |
| Customer AI architecture doc | `res://docs/CUSTOMER_AI_SYSTEM.md` |

The following 19 existing condition resources were modified **only** to add
a `contribution_label` (for the new utility-contribution diagnostics) -
their actual gating/scoring values are unchanged from Phase 2B.2:

`can_afford_drink.tres`, `intoxication_order_gate.tres`,
`order_thirst_scoring.tres`, `order_visit_time_scoring.tres`,
`order_money_scoring.tres`, `order_satisfaction_scoring.tres`,
`decision_variance.tres`, `relax_visit_time_scoring.tres`,
`relax_satisfaction_scoring.tres`, `relax_thirst_scoring.tres`,
`relax_intoxication_scoring.tres`, `relax_repeat_decay.tres`,
`leave_mood_scoring.tres`, `at_drink_limit_scoring.tres`,
`leave_visit_time_scoring.tres`, `leave_money_scoring.tres`,
`leave_intoxication_scoring.tres`, `leave_thirst_scoring.tres`,
`leave_drinks_scoring.tres` - all under `res://Data/customer_ai/conditions/`.

## Files to remove

None. Wander (`wander.tres`, `wander_behaviour.gd`, `wander_chance.tres`)
is disabled by omission from the registry, not deleted.

## Installation guide

1. Copy every file above into your project at the paths shown.
2. Open the project in Godot 4.7.1 and let it re-import.
3. **Open `res://scenes/main/main.tscn` and check the `DartsPoint` node's
   position** (currently `Vector2(650, 450)`, a guess made without visual
   access to your room) - move it if it overlaps furniture or sits outside
   the walkable nav mesh.
4. Confirm no parser errors in the Output panel.
5. Press F10 and confirm the five new Customer AI buttons appear.

## Configuration

See `docs/CUSTOMER_AI_SYSTEM.md`'s Phase 2C section for the full
per-feature breakdown. Quick index:

- **Socialising** (duration/range/gains): `Data/customer_ai/behaviours/socialise_at_seat.tres`.
- **Darts** (duration/effects/cooldown field): the `DartsPoint` node itself
  in `main.tscn`, or any future point's own node.
- **Engagement decay**: `CustomerAIBalanceConfig.engagement_decay_per_decision`.
- **Social discovery range**: `CustomerAIBalanceConfig.social_discovery_range_pixels`.
- **Drink-limit personality scaling**: `Personality.preferred_drink_count_multiplier`
  and `CustomerAIBalanceConfig.absolute_maximum_drinks_per_visit`.
- **End-of-visit pressure curve**: `leave_end_of_visit_pressure.tres`.
- **Repetition penalties**: each activity's own repeat-decay `.tres`
  (`relax_repeat_decay.tres`, `socialise_repeat_decay.tres`,
  `darts_repeat_decay.tres`).

## Test procedure

Run a session long enough to spawn at least 10 customers and complete at
least 5 visits (your six-table tavern should manage this in 10-20 minutes),
with diagnostics export on (the default since Phase 2B.1), then export a
report and check:

1. **Scenario F (variety)** - open `decisions_by_customer_id` for a couple
   of customers and confirm sequences other than
   `Order Drink -> Drink -> Relax -> Relax -> Relax -> Leave` appear -
   Socialise and Darts should show up.
2. **Scenario A (social table)** - find a decision with
   `selected_activity: "socialise_at_seat"` and a non-`-1`
   `social_partner_customer_id`; confirm that partner's own visit record
   shows `kept_same_chair_for_visit: true` and a normal continuation
   afterward.
3. **Scenario B (darts)** - find a customer whose
   `recent_activity_history` includes `"visit_tavern_activity"` followed
   by `"return_to_seat"`; confirm their `chair_id` never changes across
   the whole visit and `tavern_activity_count`/`darts_count` are non-zero.
4. **Scenario C (competition)** - with several customers active at once,
   confirm at most one customer's decisions ever show
   `selected_activity_point_id: "darts"` at the same game time - Darts has
   capacity 1 this phase (see known limitations), so a genuine second
   claim should be structurally impossible, not just unlikely.
5. **Scenario D (navigation failure)** - if you temporarily move or
   disable the `DartsPoint` after a customer starts travelling to it (F10 →
   "Enable/disable tavern activities" is the easy way to force this),
   confirm the customer returns to their chair rather than getting stuck,
   and check `issues` for an `activity_navigation_failed` entry.
6. **Scenario E (departure mid-activity)** - let a customer's visit time
   or patience expire while `USING_ACTIVITY`/`MOVING_TO_ACTIVITY`; confirm
   the activity reservation is released (F10 → "Show activity
   reservations" should show it free again) and the chair is eventually
   released too.
7. Confirm `utility_contributions` appears on decision records for scored
   (not forced) decisions, and that each entry's contribution values sum
   to (approximately) its own `final_score`.
8. Confirm `issues` stays empty during a session where nothing actually
   went wrong.
9. Confirm the project still loads with no parser errors and no missing
   resources.

## Known limitations

See `docs/CUSTOMER_AI_SYSTEM.md`'s Phase 2C "Known limitations, honestly"
section for the full list: capacity is not implemented beyond 1 per
activity point; cooldown is recorded but not enforced; the Darts scene
position is an unverified guess; "selected customer" in the F10 tools
means "the first active customer," not a real picker; personality
integration is limited to `travel_willingness` and
`preferred_drink_count_multiplier` this phase, with the longer list of
future trait dimensions prepared only as free-form tags on `Personality`.
No new stuck-detection was built - activity-visit navigation failures are
recovered through the existing `ActorNavigation` framework's own recovery,
surfaced through the same `_on_destination_failed()` callback every other
navigation failure already uses.
