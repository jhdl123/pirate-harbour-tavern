# Phase 4A — Player-Facing Loop

**The loop is now reachable without F10.** Status per item below, labelled
Complete / Partial / Deferred.

---

## 1. Root causes

| Missing thing | Root cause |
|---|---|
| Summary never appeared | `TavernLifecycle.summary_available` had **zero listeners**. No summary screen existed anywhere in the project. |
| No way to end the day | `end_day()` was called from exactly one place: `stock_dev_panel.gd`. |
| No way to start the next day | `advance_to_next_day()` — same. Only F10. |

The backend was complete and correct. It had no consumer, which is why it
looked finished in a report and did nothing in the game.

---

## 2. What was added — **Complete**

### Daily control bar (`scripts/UI/daily_control_bar.gd`)

Permanent top bar: `F10 / Debug`, `Open Tavern`, `Last Orders`, `Close Tavern`,
`End Day`, `View Summary`, `Start Next Day`, plus a live
`Day N   HH:MM   <state>` readout.

Every button calls a public lifecycle API. None writes a lifecycle variable.
Buttons enable by state, disabled ones carry a tooltip explaining why, and a
disabled button does nothing even if its signal fires (asserted by test).

| State | Enabled |
|---|---|
| Preparing | Open Tavern |
| Open | Last Orders, Close Tavern |
| Last Orders | Close Tavern |
| Closing | Close Tavern |
| Closed | End Day |
| End of Day | View Summary |
| Ready for Next Day | View Summary, Start Next Day |

State text is player-facing — `"Day complete — start the next day when ready"`,
never `READY_FOR_NEXT_DAY`. Asserted by test.

### End-of-day summary (`scripts/UI/end_of_day_summary.gd`)

Modal, listens to `summary_available`, so it **opens by itself** when the day
ends. Dims and blocks input behind it, pauses the simulation, reads the frozen
record only. One reused instance — opening twice refreshes rather than stacking.
Reopenable from the control bar and F10. `Continue` → `READY_FOR_NEXT_DAY`,
`Start Next Day` → `PREPARING`.

Shows financial, customer (with loss-reason breakdown), operations and day
context sections; zero-value loss reasons are hidden rather than padding the
panel.

---

## 3. Two real bugs the loop test caught

**`close_early()` froze the tavern in CLOSING.** The manual state floor pinned
it there until the *schedule* independently reached closing time — for an early
close, most of a day away. Manual closing now honours
`closing_grace_minutes` and finishes on its own.

**`trading_day` was derived from the world day.** A session runs 18:00 → 01:30
and crosses midnight, so the world day increments *during* service. Ending at
02:00 and starting at 17:00 the same calendar day produced no day change at all.
`trading_day` is now its own counter, incremented exactly once in
`advance_to_next_day()`.

---

## 4. Unique customers vs transactions — **Complete**

| Counter | Meaning |
|---|---|
| `customers_entered` | Distinct arrivals |
| `customers_served` | **Unique** customers who bought at least one drink |
| `transactions_completed` | Successful sales |
| `drinks_sold` | Units moved |

Uniqueness uses `Customer.get_stable_customer_id()` (instance-based, valid
whether or not diagnostics are running — `runtime_customer_id` is `-1` without a
report manager). A customer buying three rounds is now 1 served, 3 transactions.
`average_spend` is per customer; `average_transaction` is per sale.

### Tips — **Partial, documented**

Tips still have no first-class mechanic. `payment_multiplier` is a
per-customer-type *price* multiplier. I record base price as the sale and any
surplus as a tip, documented at the call site. You flagged this as needing a
decision — it is a two-line change in `_on_customer_paid_for_drink` if you want
tips to read zero until a real mechanic exists.

---

## 5. Test results — all suites passing

| Suite | Result |
|---|---|
| `phase_4a_loop_test` (new) | **22/22** |
| `phase_4a_integration_test` | 18/18 |
| `phase_4_daily_cycle_test` | 27/27 |
| `management_menu_test` | 6/6 |

The loop test presses buttons only. It never calls `Tavern.end_day()`,
`advance_to_next_day()` or any lifecycle method directly, and never touches
F10. It verifies button availability in four states, that disabled buttons do
nothing, the full Preparation → … → Next Day loop, automatic summary opening,
five rapid End Day presses producing one summary, five rapid Start Next Day
presses advancing exactly one day, and money surviving the transition.

No parser or runtime errors.

---

## 6. Manual test steps

1. **Run.** Bar at top reads `Day 1  17:00  Preparing to open`. Only `Open Tavern` enabled; hover the others for reasons.
2. **Press `Open Tavern`.** State → `Open for business`. Customers begin arriving.
3. **Serve a few** — prepare drinks, let staff deliver.
4. **Press `Last Orders`.** New arrivals stop; seated customers continue.
5. **Press `Close Tavern`.** State → `Closing`, then `Closed` after 30 game minutes.
6. **Press `End Day`.** The **summary opens by itself**. Check income and sales-by-item are non-zero and name real drinks.
7. **Press `End Day` again** (reopen summary first): figures must not change.
8. **Press `Continue`.** State → `Day complete — start the next day when ready`.
9. **Press `Start Next Day`.** Back to `Day 2  17:00  Preparing to open`.
10. **Check money and stock persisted**; daily totals are zero again.

---

## 7. Genuinely deferred — **not done**

Stated plainly rather than claimed:

- **§8 preparation guidance** — no assessment service. **Deferred.**
- **§9 modifier targets** — `CUSTOMER_TYPE_WEIGHT`, `CUSTOMER_GROUP_SIZE`, `CUSTOMER_STAY_DURATION`. No `tags` on `CustomerType`. **Deferred.**
- **§10 diagnostic export wiring** — `build_report_section()` still unconsumed by the exporters. **Deferred.**
- **§11 health checks** — not implemented. **Deferred.**
- **§12 F10 additions** — existing controls retained and the bar opens the panel; the new modifier/health entries are **not** added.
- **Groups** — no multi-customer group system exists, so `groups_served` / `groups_lost` stay zero. Not applicable rather than broken.

By your §15 checklist: the player-facing loop items are met; preparation
guidance, modifier targets, diagnostics and health checks are not.
