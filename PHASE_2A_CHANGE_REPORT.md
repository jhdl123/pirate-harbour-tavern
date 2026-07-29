# Phase 2A Change Report — Multi-Activity Visits

## Summary

A customer visit is no longer hard-coded to Order → Drink → Leave. After a
drink finishes, `CustomerBrain.think()` now competes three real, registered
activities against each other: **Relax at Seat** (new), **Order Drink**
(again), and **Leave**. A chair is reserved for the customer's entire visit
rather than released after the first drink, so relaxing and re-ordering both
keep using the same seat. A configurable `maximum_drinks_per_visit`
safeguard (default 2) stops the Order/Relax cycle from running forever:
once reached, Order Drink becomes ineligible and Leave scores higher.
Patience-expiry continues to force Leave unconditionally, exactly as before
this phase, and still correctly releases the chair (a genuine pre-existing
bug in the chair-release path was found and fixed along the way — see
"Bug fixed" below).

## Files supplied

### New files

| File | Destination |
|---|---|
| Relax at Seat behaviour script | `res://systems/customer_ai/activities/behaviours/relax_at_seat_behaviour.gd` |
| Relax at Seat behaviour resource | `res://Data/customer_ai/behaviours/relax_at_seat.tres` |
| Relax at Seat activity definition | `res://Data/customer_ai/activities/relax_at_seat.tres` |
| Order Drink's drink-limit gate | `res://Data/customer_ai/conditions/under_drink_limit.tres` |
| Leave's at-limit scoring bonus | `res://Data/customer_ai/conditions/at_drink_limit_scoring.tres` |
| Shared random scoring variance | `res://Data/customer_ai/conditions/decision_variance.tres` |

### Modified files (replace your copy with the supplied one)

| File | Destination |
|---|---|
| Customer | `res://scripts/Entities/customer.gd` |
| Chair | `res://scripts/Interactables/chair.gd` |
| GameConfig | `res://scripts/Managers/game_config.gd` |
| DomainFlagCondition | `res://systems/customer_ai/activities/conditions/domain_flag_condition.gd` |
| Order Drink activity definition | `res://Data/customer_ai/activities/order_drink.tres` |
| Leave activity definition | `res://Data/customer_ai/activities/leave.tres` |
| Activity registry | `res://Data/customer_ai/activity_registry.tres` |
| Customer AI architecture doc | `res://docs/CUSTOMER_AI_SYSTEM.md` |

Every dependency the changed files need (`ActivityDefinition`,
`ActivityCondition`, `Reservable`, `WorldTime`, etc.) already exists in your
project from Phase 1 and the earlier cleanup pass — nothing outside this
list needed to change.

## Files to remove

**None required.** `Data/customer_ai/conditions/order_not_attempted.tres` is
now unreferenced (Order Drink reuses the existing `not_currently_ordering.tres`
instead — see "Order lifecycle" below) and is safe to delete if you want to
tidy up, but leaving it in place is harmless; nothing loads or points to it.

## Bug fixed along the way

`Customer.release_reserved_chair()` never actually called
`Reservable.release()` — it only toggled the navigation-avoidance zone. A
patience-expired customer (one who left before ever being served) would
leave their chair permanently stuck in the reserved state, unusable by any
future customer, silently shrinking your available seating over a play
session. This was pre-existing, not introduced by Phase 2A, but sits
squarely in the chair-lifecycle code this phase needed to touch anyway, and
is now fixed as part of the same rewrite (see `Chair.release_reservation()`
and `Customer.release_reserved_chair()`).

## Configuration

- **Relax duration:** `Data/customer_ai/behaviours/relax_at_seat.tres` →
  `minimum_duration_minutes` / `maximum_duration_minutes` (world minutes).
- **Maximum drinks per visit:** your `GameConfig` resource (e.g.
  `resources/config/default_game_config.tres`) → new "Customer AI" category
  → `maximum_drinks_per_visit` (default 2).
- **Utility scores:** each activity's `.tres` under `Data/customer_ai/activities/`
  → `base_utility`, plus the shared condition resources under
  `Data/customer_ai/conditions/` (`leave_mood_scoring.tres`,
  `at_drink_limit_scoring.tres`, `decision_variance.tres`) for the scoring
  nudges layered on top.
- **Debug output:** the same `GameConfig.show_customer_ai_debug_messages`
  flag from the previous patience-expiry fix now also gates this phase's
  extra `Customer`-side prints (drinks consumed, chair-reservation status,
  Relax start/finish) — one flag controls all of it, on `CustomerBrain` and
  on `Customer` alike.

## Test procedure

With your six-table tavern and `show_customer_ai_debug_messages` on:

1. Let one customer order, drink, and watch the `[CustomerBrain]`/
   `[CustomerAI]` log lines right after the drink finishes — confirm it
   shows `Relax at Seat`, `Order Drink`, or `Leave` being chosen, not an
   automatic Leave.
2. Follow one customer through a full `Order → Drink → Relax → Order →
   Drink → Leave` chain if you get one; confirm the chair never becomes
   available to another customer in between (check the table/chair debug
   output or just watch no one else sits there).
3. Confirm `drinks_consumed_this_visit` reaches your configured
   `maximum_drinks_per_visit` and that customer's next decision is reliably
   Leave, not another Relax.
4. Let a customer's patience expire before being served at all; confirm
   they leave immediately and their chair becomes available to the very
   next spawned customer.
5. Confirm the chair shows as needing cleaning after any visit that
   included at least one drink, and does not after a patience-expiry visit
   with zero drinks served.

## Known limitations

This phase deliberately does not include wealth, mood-driven drink choice,
intoxication, social activities (talking, groups, companions), VIP
customers, or full visit-duration simulation. `CustomerNeeds.mood` exists
and lightly influences Leave's scoring (as it did before this phase), but
nothing new here reads wealth, energy, or intoxication. The `maximum_drinks_per_visit`
safeguard is a simple counter, not a economic or physiological limit — it
exists purely so Relax/Order Drink cannot cycle forever, per this phase's
explicit scope.
