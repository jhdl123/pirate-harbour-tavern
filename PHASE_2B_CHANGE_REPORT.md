# Phase 2B Change Report — Customer Attributes, Decision Making & Test Export

## Summary

Customers now carry independent runtime attributes - money, thirst,
satisfaction, intoxication, and an intended visit duration - seeded per
customer from a new `CustomerAIBalanceConfig` resource and biased by four
new `Personality` multipliers. All three existing activities (Order Drink,
Relax at Seat, Leave) score against these attributes through a much larger
set of `NeedThresholdCondition` resources, plus one new condition class
(`CanAffordDrinkCondition`) that hard-gates ordering on real drink prices.
Intoxication and money now have teeth: a drink actually costs money and
raises intoxication (scaled by `Personality.temperance`); above a
configurable intoxication threshold, Order Drink is not a candidate at all.
Visit duration decreases via plain elapsed-time arithmetic against
`WorldTime`, never a per-frame or repeating-timer countdown, with a single
scheduled mandatory departure at zero remaining time - the same pattern
patience-expiry already used.

A new, fully decoupled diagnostic system (`CustomerAIReportManager` and
three data-record classes) collects a session summary, one record per
customer visit, a capped decision history per customer, and detected
anomalies, and writes them as a single timestamped JSON file to
`user://customer_ai_reports/` on request - via a new button on the existing
F10 developer panel, or by calling the same method directly. Every part of
this system is a no-op when disabled; normal gameplay never depends on it.

No new customer activities were added.

## Files supplied

### New files

| File | Destination |
|---|---|
| Balance config resource class | `res://systems/customer_ai/customer_ai_balance_config.gd` |
| Balance config instance | `res://Data/customer_ai/balance_config.tres` |
| Diagnostics config resource class | `res://systems/customer_ai/diagnostics/customer_ai_diagnostics_config.gd` |
| Diagnostics config instance | `res://Data/customer_ai/diagnostics_config.tres` |
| Visit record data class | `res://systems/customer_ai/diagnostics/visit_record.gd` |
| Decision record data class | `res://systems/customer_ai/diagnostics/decision_record.gd` |
| Issue record data class | `res://systems/customer_ai/diagnostics/issue_record.gd` |
| Report manager | `res://systems/customer_ai/diagnostics/customer_ai_report_manager.gd` |
| Afford-a-drink condition class | `res://systems/customer_ai/activities/conditions/can_afford_drink_condition.gd` |
| Afford-a-drink condition instance | `res://Data/customer_ai/conditions/can_afford_drink.tres` |
| Order Drink: intoxication gate | `res://Data/customer_ai/conditions/intoxication_order_gate.tres` |
| Order Drink: thirst scoring | `res://Data/customer_ai/conditions/order_thirst_scoring.tres` |
| Order Drink: visit-time scoring | `res://Data/customer_ai/conditions/order_visit_time_scoring.tres` |
| Order Drink: money scoring | `res://Data/customer_ai/conditions/order_money_scoring.tres` |
| Order Drink: satisfaction scoring | `res://Data/customer_ai/conditions/order_satisfaction_scoring.tres` |
| Relax: visit-time scoring | `res://Data/customer_ai/conditions/relax_visit_time_scoring.tres` |
| Relax: satisfaction scoring | `res://Data/customer_ai/conditions/relax_satisfaction_scoring.tres` |
| Relax: thirst scoring | `res://Data/customer_ai/conditions/relax_thirst_scoring.tres` |
| Relax: intoxication scoring | `res://Data/customer_ai/conditions/relax_intoxication_scoring.tres` |
| Leave: visit-time scoring | `res://Data/customer_ai/conditions/leave_visit_time_scoring.tres` |
| Leave: money scoring | `res://Data/customer_ai/conditions/leave_money_scoring.tres` |
| Leave: intoxication scoring | `res://Data/customer_ai/conditions/leave_intoxication_scoring.tres` |
| Leave: thirst scoring | `res://Data/customer_ai/conditions/leave_thirst_scoring.tres` |

### Modified files (replace your copy with the supplied one)

| File | Destination |
|---|---|
| Customer | `res://scripts/Entities/customer.gd` |
| GameManager | `res://scripts/Managers/game_manager.gd` |
| GameConfig | `res://scripts/Managers/game_config.gd` |
| Stock dev panel | `res://scripts/UI/stock_dev_panel.gd` |
| CustomerBrain | `res://systems/customer_ai/customer_brain.gd` |
| CustomerNeeds | `res://systems/customer_ai/customer_needs.gd` |
| Personality | `res://systems/customer_ai/personality.gd` |
| DrinkDefinition | `res://systems/items/drink_definition.gd` |
| Grog resource | `res://Data/items/drinks/grog.tres` |
| Ale resource | `res://Data/items/drinks/ale.tres` |
| Order Drink activity definition | `res://Data/customer_ai/activities/order_drink.tres` |
| Relax at Seat activity definition | `res://Data/customer_ai/activities/relax_at_seat.tres` |
| Leave activity definition | `res://Data/customer_ai/activities/leave.tres` |
| Main scene | `res://scenes/main/main.tscn` |
| Customer AI architecture doc | `res://docs/CUSTOMER_AI_SYSTEM.md` |

## Files to remove

**None.** Two `GameConfig` fields (`maximum_drinks_per_visit`,
`show_customer_ai_debug_messages`) were removed from that script and moved
to the new dedicated resources instead - if your existing
`default_game_config.tres` still has values saved under those keys, Godot
will simply ignore them on load; nothing needs manual cleanup.

## Concise installation guide

1. Copy every file above into your project at the exact path shown,
   overwriting where one already exists.
2. Open the project in Godot 4.7.1 and let it re-import.
3. Confirm no parser errors appear in the Output panel.
4. Open `res://Data/customer_ai/diagnostics_config.tres` in the Inspector
   and set `console_debug_enabled = true` (and `export_enabled = true` if
   you want a JSON report from this session) before testing.
5. Run the game, let a few customers complete visits, then press **F10**
   and click **"Export Customer AI report"** to write the JSON file.

Everything else (the `CustomerAIReportManager` node, the new resource
references on `GameManager` and `StockDevPanel`) is already wired inside
the supplied `main.tscn` - no manual node setup needed.

## Configuration

- **Starting money/thirst/satisfaction/visit-duration ranges, satisfaction
  change amounts, thirst-per-drink reduction, intoxication gain scale, and
  the drink-per-visit limit:** `Data/customer_ai/balance_config.tres`.
- **Personality biases (wealth, drink appetite, intoxication tolerance,
  visit duration, plus the existing temperance/generosity/etc.):** each
  `Personality` `.tres` under `Data/customer_ai/personalities/`.
- **Per-activity scoring thresholds/weights:** the individual condition
  `.tres` files under `Data/customer_ai/conditions/` listed above.
- **Alcohol strength per drink:** each `DrinkDefinition` `.tres` under
  `Data/items/drinks/` (`alcohol_strength`, 0.0 for a future non-alcoholic
  drink).
- **Console logging / JSON export / report size limits:**
  `Data/customer_ai/diagnostics_config.tres`.

## Test procedure

With `console_debug_enabled = true`:

1. Spawn a handful of customers and confirm the console block
   (`Customer <name>: Money / Visit Time Remaining / Thirst / Intoxication
   / Satisfaction`, then each activity's score, then `Chosen:`) appears
   after each drink finishes.
2. Watch two or three customers through full visits and confirm they don't
   all order the same number of drinks or relax the same number of times -
   that variety should trace back to different starting money/thirst/
   personality, not just the small random variance term.
3. Lower `maximum_starting_money` in the balance config toward the price of
   your cheapest drink and confirm some customers now leave without ever
   ordering (or after fewer drinks than the visit-duration/limit would
   otherwise allow).
4. Raise `intoxication_gain_scale` or lower a drink's threshold-adjacent
   condition (`intoxication_order_gate.tres`'s `threshold`) temporarily and
   confirm a customer stops ordering and leaves once sufficiently
   intoxicated, without ever ordering a drink again in that visit.
5. Let a customer's `visit_duration_minutes` run out with no patience
   event involved (i.e. after being served) and confirm they leave via the
   mandatory visit-time path, not a normal utility choice - check the
   decision history's `was_forced`/`forced_reason` once you generate a
   report.
6. Press F10 → "Export Customer AI report" and open the resulting file
   from `user://customer_ai_reports/` (see the Windows path in the updated
   `docs/CUSTOMER_AI_SYSTEM.md`) in any text editor or JSON viewer; confirm
   it parses and that completed vs. still-active visits are clearly
   distinguished (`is_completed`).
7. Confirm the game behaves identically with
   `Data/customer_ai/diagnostics_config.tres`'s `export_enabled` left
   `false` for a session - no console spam, no report content, no
   behavioural difference.

## Known limitations

Same activity list as Phase 2A (Order Drink, Relax at Seat, Leave) - no
new activities, conversations, groups, wandering, VIPs, staff AI, long-term
reputation, memories, relationship systems, economy simulation, or
navigation changes were added, per this phase's explicit scope. Navigation
recovery counts exist as a field in the report schema but are not currently
incremented by anything - see `docs/CUSTOMER_AI_SYSTEM.md`'s "Known
limitations" for the full, honest list of what this phase does not measure
or simulate.
