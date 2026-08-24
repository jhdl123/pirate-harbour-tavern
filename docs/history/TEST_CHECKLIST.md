# Test Checklist — Pirate Harbour Tavern

How to read this list: every item is marked with how it was actually
verified during this cleanup pass.

- **[TRACED]** — the code path was read and hand-traced against this exact
  behaviour, and found correct (or fixed and re-traced). Still worth a quick
  live confirmation, but this pass has real confidence in it.
- **[FIXED — CONFIRM LIVE]** — this pass found and fixed a bug here. High
  priority to confirm with real play, since it's the highest-risk category.
- **[NOT RE-VERIFIED]** — read for context but not specifically traced
  against this behaviour this pass. No known problem, just not specifically
  checked.

No item is marked as "passed" from an actual play session, because this
pass did not have the Godot editor available to run one. See
`CLEANUP_REPORT.md`'s methodology note.

---

## Player

- [ ] [NOT RE-VERIFIED] Movement in all directions, collision with furniture/walls
- [ ] [TRACED] Interaction (E) triggers the currently-selected object's primary action
- [ ] [TRACED] Highlight follows the selected object as the player moves
- [ ] [TRACED] Carrying an item shows it visually and blocks/enables the right interactions
- [ ] [TRACED] Actions (e.g. cleaning) block movement while running (`ActionRunner.is_movement_blocked()`)
- [ ] [TRACED] Escape cancels a cancellable action (`ActionRunner.cancel_current_action()` checks `can_cancel`)
- [ ] [TRACED] Opening any menu (M, ledger, storage, F10) pauses; closing the last one resumes

## Customers

- [ ] [NOT RE-VERIFIED] Customers spawn at the configured rate and stop at `maximum_active_customers`
- [ ] [TRACED] Customers navigate to their assigned chair via staging point then seat
- [ ] [TRACED] Seat assignment picks the best-scoring available chair (`GameManager.find_best_available_chair`)
- [ ] [TRACED] Customers order according to their `CustomerType`'s available/preferred drinks
- [ ] [NOT RE-VERIFIED] Patience bar depletes and customer leaves if not served in time
- [ ] [TRACED] Customer drinks for `drink_duration_minutes`, then pays and leaves
- [ ] [TRACED] Seat cleanup: `require_cleaning()` releases the reservation and starts a `CleaningTask`
- [ ] [NOT RE-VERIFIED] Multiple customers operating simultaneously without interfering
- [ ] [TRACED] Behaviour when no seats are available: `spawn_customer()` returns early, logs, retries next scheduled attempt
- [ ] [NOT RE-VERIFIED] Behaviour when a route is genuinely unreachable (navigation recovery path)

## Drinks

- [ ] [TRACED] Preparing grog / ale: `DrinksStation._serve_drink()` only decrements `current_servings` after `ItemTransferService` confirms the carrier received it
- [ ] [TRACED] Serving the correct drink: station only offers its own `served_drink`
- [ ] [TRACED] Station stock decreasing by exactly 1 per successful serve
- [ ] [TRACED] Empty stations block drink preparation (`current_servings <= 0` marks the action unavailable)
- [ ] [TRACED] Correct refill item accepted, wrong one rejected (`refill_item.item_id` check in `_refill_from_carrier`)
- [ ] [TRACED] Refill item consumed only when the station accepts and applies it
- [ ] [TRACED] Carried drink / carried stock: `ItemCarrier` slot rules, one item at a time

## Inventory

- [ ] [TRACED] `ItemStack` quantities never go negative or over capacity (`ItemTransferService` plan/apply split)
- [ ] [TRACED] Failed transfer leaves both sides unchanged (traced the rollback path in `_apply_swap` and the "put back what was refused" path in `_apply_plan`)
- [ ] [TRACED] Player carried item, bar slots, storage slots all go through the same `ItemTransferService`
- [ ] [NOT RE-VERIFIED] UI refresh after changes (storage menu, stock page) — signal wiring looks correct, not watched live

## Time

- [ ] [TRACED] Normal advancement via `WorldTime._process` → `_advance_to`
- [ ] [TRACED] Pause stops advancement (`WorldTime` subscribes to `Simulation.state_changed`)
- [ ] [TRACED] Multiple pause sources compose correctly via the `Simulation` state stack (traced `push_state`/`pop_state`, not observed live with two menus open at once)
- [ ] [NOT RE-VERIFIED] Skip 24 hours end-to-end visual/UI feedback
- [ ] [TRACED] Day rollover triggers `StatisticsTracker`'s daily reset
- [ ] [FIXED — CONFIRM LIVE] Delivery processing across a skip / multiple due orders does not duplicate stock (bug 1 in `CLEANUP_REPORT.md` — **this is the single highest-priority item in this whole checklist to confirm live**: submit an order, fill storage so it can only partially deliver, then trigger a second delivery pass and confirm it does not add more than was ordered)
- [ ] [TRACED] No duplicate `WorldTime.time_changed` connections (single `_ready()` connection in each subscriber, checked `OrderManager`, `StatisticsTracker`, `BarManagementMenu`)

## Orders and Deliveries

- [ ] [NOT RE-VERIFIED] Ledger opens, quantity controls, cost calculation display
- [ ] [TRACED] Insufficient money correctly rejects the order (`EconomyManager.can_afford` checked before `spend_money`)
- [ ] [TRACED] Order placement deducts money and creates a pending order only after payment succeeds
- [ ] [FIXED — CONFIRM LIVE] Delivery timing / partial delivery / repeated delivery does not duplicate items (see Time section above — same bug, same fix)
- [ ] [TRACED] Forced delivery (`complete_next_delivery`/`complete_all_deliveries`) uses the same `_deliver_order` as scheduled delivery
- [ ] [NOT RE-VERIFIED] Multiple simultaneous pending orders, visually confirmed in the ledger/stock page

## UI

- [ ] [FIXED — CONFIRM LIVE] M menu Overview page shows real money/customers/seats/served-today instead of placeholder text (bug 2 in `CLEANUP_REPORT.md`)
- [ ] [FIXED — CONFIRM LIVE] M menu Progression page shows real served/days/earned/peak/milestone instead of blank design-time text (bug 2)
- [ ] [TRACED] M menu Stock page reads live storage/station/pending-delivery state (`_refresh_stock_page`, unchanged this pass, already correct)
- [ ] [TRACED] Ledger and Storage menus both pause via the shared `InteractionMenuController`
- [ ] [TRACED] F10 dev panel calls real system methods for every button (already correct; this pass added the `ItemRegistry` lookup and the shipping guard)
- [ ] [FIXED — CONFIRM LIVE] F10 dev panel does not build or respond to input in a release export (bug 6 — needs an actual export to confirm, see `KNOWN_ISSUES.md`)
- [ ] [TRACED] Escape closes the currently open menu
- [ ] [NOT RE-VERIFIED] Button focus / keyboard-only navigation through menus
- [ ] [TRACED] Correct pause restoration when closing one of several nested pausing surfaces (state-stack logic traced, not observed live with real nesting)

## Deliberately adversarial cases from the brief

- [ ] [TRACED] Attempt to refill ale station with grog stock → rejected by `refill_item.item_id` mismatch
- [ ] [TRACED] Try to prepare a drink from an empty station → action marked unavailable, `_serve_drink` also re-checks `current_servings <= 0`
- [ ] [NOT RE-VERIFIED] Open storage while carrying a prepared drink
- [ ] [TRACED] Place an order without enough money → rejected before any state changes
- [ ] [FIXED — CONFIRM LIVE] Skip several days with multiple pending orders → this is the exact scenario bug 1 affected; now fixed, needs live confirmation
- [ ] [FIXED — CONFIRM LIVE] Fill storage before a delivery arrives → same bug, same fix
- [ ] [NOT RE-VERIFIED] Open and close multiple paused interfaces in sequence
- [ ] [TRACED] Remove a customer while assigned to a seat → `customer_abandoned_seat` / `_on_customer_abandoned_seat` clears the table reservation
- [ ] [NOT RE-VERIFIED] Spawn more customers than available seating
- [ ] [TRACED] Repeatedly pressing interaction keys → `ActionRunner.start_action` returns false while already running, no double-start
- [ ] [NOT RE-VERIFIED] Attempt actions during an open menu
- [ ] [NOT RE-VERIFIED] Reload the main scene

---

# Phase 3A — Staff, Tasks and Communication

New marker for this phase:

- **[AUTOMATED]** — covered by `tests/phase_3a_headless_test.tscn`, which runs
  the real main scene in Godot 4.7.1 headless and asserts the behaviour. All
  41 checks passed on the delivered build.

Run it with:

```bash
godot --headless --path . res://tests/phase_3a_headless_test.tscn
```

## Scenario A — Basic service

- [ ] [AUTOMATED] Customer orders a drink; a `serve_drink` task appears
- [ ] [AUTOMATED] Player prepares the correct drink and places it in a bar service slot
- [ ] [AUTOMATED] Tavern Hand claims the task
- [ ] [AUTOMATED] Worker collects exactly one drink — the slot empties, nothing is spawned
- [ ] [AUTOMATED] Worker serves the correct customer
- [ ] [AUTOMATED] Customer proceeds to drinking normally
- [ ] [AUTOMATED] Task completes; worker is not left holding anything
- [ ] [TRACED] Payment arrives exactly once, at the normal point in the drink cycle

## Scenario B — Several service tasks

- [ ] [MANUAL] Several customers waiting, several prepared drinks on the bar
- [ ] [MANUAL] Worker prioritises the most urgent customer (watch the patience bars)
- [ ] [MANUAL] Every drink reaches a customer who ordered that drink
- [ ] [TRACED] No drink or customer is claimed by two tasks (dedup by target key)
- [ ] [MANUAL] Remaining tasks stay available and are worked through in turn

## Scenario C — Player overrides service

- [ ] [MANUAL] While the worker walks to the bar, take the drink yourself → worker re-plans or releases
- [ ] [MANUAL] While the worker carries a drink, serve the customer yourself → worker releases and returns the drink to the bar
- [ ] [TRACED] Reservations released; worker does not become stuck
- [ ] [MANUAL] Worker selects another task afterwards

## Scenario D — Cleaning

- [ ] [AUTOMATED] A dirty seat produces a `clean_seat` task
- [ ] [AUTOMATED] Worker reaches it and runs the existing cleaning action
- [ ] [AUTOMATED] Seat becomes clean; task completes
- [ ] [AUTOMATED] Cleaned seat is available for new customer reservations
- [ ] [AUTOMATED] Broken-glass complication produces a fresh task and the worker sees it through

## Scenario E — Player overrides cleaning

- [ ] [MANUAL] Worker claims a dirty seat; clean it yourself first
- [ ] [MANUAL] Worker releases safely, no duplicate cleaning action runs
- [ ] [TRACED] `can_start_cleaning()` refuses the second start

## Scenario F — Navigation failure

- [ ] [MANUAL] F10 → "Force navigation failure" while the worker is travelling
- [ ] [MANUAL] Worker reports the failure and pauses rather than re-pathing instantly
- [ ] [MANUAL] Task retries, then releases according to its definition
- [ ] [MANUAL] Reservations clear; worker returns to useful operation
- [ ] [MANUAL] Block a route with furniture in the editor and repeat

## Scenarios G–K — Stock alerts

- [ ] [AUTOMATED] G: crossing the low threshold raises exactly one alert lifecycle
- [ ] [MANUAL] G: Tavern Hand is named as speaker and a speech bubble appears
- [ ] [MANUAL] G: alert shows remaining servings and replacement stock count
- [ ] [AUTOMATED] H: further servings below the threshold create no duplicate alerts
- [ ] [AUTOMATED] I: reaching zero escalates the same alert to CRITICAL
- [ ] [AUTOMATED] I: no second alert is created
- [ ] [AUTOMATED] J: refilling resolves the alert automatically
- [ ] [AUTOMATED] J: resolution is recorded in history
- [ ] [MANUAL] J: station can trigger a fresh lifecycle if it goes low again later
- [ ] [MANUAL] K: with no matching stock in storage, severity and wording reflect that an order is needed
- [ ] [MANUAL] K: no false stock quantity is shown

## Staff interaction

- [ ] [MANUAL] Walk up to the Tavern Hand → prompt appears
- [ ] [MANUAL] Inspection shows name, role, state, current task, target, available task count, tasks completed, active warnings
- [ ] [MANUAL] Pause staff work → worker stops taking tasks and releases the current one cleanly
- [ ] [MANUAL] Resume staff work → worker picks up again

## Diagnostics

- [ ] [AUTOMATED] F10 → export report writes valid JSON to `user://staff_reports/`
- [ ] [AUTOMATED] Report contains `staff`, `tasks` and `communication` sections
- [ ] [MANUAL] Task history lets you follow one job from creation to completion
- [ ] [MANUAL] Issue list is empty during a normal session

## Scenario L — Regression

- [ ] [AUTOMATED] Customer spawning, seating, ordering, drinking, paying, leaving
- [ ] [MANUAL] Socialising and Darts still chosen and completed
- [ ] [MANUAL] Return to seat after an activity
- [ ] [MANUAL] Customer activity reservations and navigation recovery
- [ ] [MANUAL] Player item carrying, drink preparation, station stock consumption
- [ ] [MANUAL] Station refilling, storage, ordering stock, deliveries
- [ ] [MANUAL] Manual cleaning still works exactly as before
- [ ] [MANUAL] Interaction highlighting, time controls (F1–F4), F10 tools
- [ ] [MANUAL] Customer AI report export still works
