# Phase 4A — Corrective Completion Pass

## The audit finding, stated plainly

Your review was correct. Audit of the attached ZIP:

```
grep -rn 'Tavern.stats' --include=*.gd .
```

returned **eleven hits: six F10 test buttons and five test-file lines. Zero
production gameplay.** The `DailyStatistics` model was complete, well tested in
isolation, and never called by the game. My previous report called Stage 2
"Complete". That was wrong, and the distinction it missed — a recording method
existing versus an authoritative event reaching it — is exactly the one that
matters.

A second inconsistency I had introduced: `TavernLifecycle._day_metrics` was a
*second* per-day store running alongside `DailyStatistics`. Two places to look,
two places to forget to reset. Now one.

---

## 1. Completion table

| Feature | Production integration point | Automated test | Status |
|---|---|---|---|
| Sales income | `Customer.customer_paid_for_drink` → `GameManager` relay → recorder | `TRADE` (income 15 from 3 real sales) | **Done** |
| Sales / income by item | Same, now carrying `ordered_drink.item_id` | `TRADE` (`{"grog": 3}`, no placeholder) | **Done** |
| Drinks sold | Same event | `TRADE` | **Done** |
| Customers served | Same event (unit: **one paid drink transaction**) | `TRADE`, `DOUBLE` | **Done** |
| Customers entered | `GameManager.customer_spawned` | `TRADE` (9 entered) | **Done** |
| Customers lost + reasons | `Customer.customer_departed(reason, was_served)` | `FLOW` | **Done** |
| Cleanup departures excluded | `departure_reason = day_ended_cleanup` | `FLOW` | **Done** |
| Stock used / by item | `DrinksStation.serving_consumed` (new) | `TRADE` (`{"grog": 5.0}`) | **Done** |
| Breakages | `CleanableComponent.complication_triggered` | — | **Wired, untested** |
| Deliveries | `OrderManager.order_delivered` | — | **Wired, untested** |
| Arrivals rejected | `GameManager.arrival_rejected` (new) | — | **Wired, untested** |
| Peak occupancy | Recorder, on spawn/departure | `TRADE` (peak 8) | **Done** |
| Peak waiting customers | `GameManager.get_waiting_customer_count()` (new) | — | **Wired, untested** |
| Staff tasks completed | `TaskBoard.task_completed` | — | **Wired, untested** |
| Tips | **No source exists** — see below | — | **Documented, not invented** |
| `READY_FOR_NEXT_DAY` | `acknowledge_summary()` | `FLOW` | **Done** |
| Groups served / lost | No group system exists yet | — | **Not applicable** |

### The proof

The integration test **never calls `Tavern.stats.record*()`**. It opens the
tavern, keeps the bar stocked as a player would, and lets real staff serve real
customers. Result:

```
[PASS] TRADE: 3 real paid transactions recorded.
[PASS] TRADE: Income 15 recorded from real payments.
[PASS] TRADE: Sales by item: { "grog": 3 }
[PASS] TRADE: Stock used by item: { "grog": 5.0 }
[PASS] DOUBLE: 3 sale events == 3 served; no duplication.
```

**`stock_used = 5` against `sold = 3` is the important line.** Two servings were
poured and never sold. If stock usage were inferred from sales it would read 3.
It comes from stock actually leaving a station, which is what you asked for.

---

## 2. Architecture

One node — `DailyStatisticsRecorder` — owns **every** subscription. Sprinkling
`Tavern.stats.record(...)` through ten gameplay files would have fixed the
symptom and made "is anything recorded twice?" unanswerable without reading all
ten. Now it is a question about one file.

**Duplicate prevention:** `_connect_once()` keyed by instance id + signal name;
a per-frame payment counter that the test asserts never exceeds one; and a test
comparing sale events against the served count.

**New signals added** (each the single authoritative point for its event):

```text
Customer.customer_paid_for_drink(amount, item_id, base_price)
Customer.customer_departed(customer, reason, was_served)
DrinksStation.serving_consumed(item_id, quantity)
GameManager.arrival_rejected(reason)
GameManager.customer_paid_for_drink / customer_departed   (relays)
```

`Customer.customer_paid` is untouched, so existing listeners still work.

### Tips

**Tips do not exist in this build.** `payment_multiplier` is a per-customer-type
*price* multiplier, not a gratuity. Rather than invent a figure I record the
base price as the sale and any surplus above it as a tip, documented at the call
site as a design decision to revisit. If you would rather tips read zero until a
real tipping mechanic exists, that is a two-line change in
`_on_customer_paid_for_drink`.

### Customers served

Defined as **one paid drink transaction**, not one visit — a customer ordering
twice is served twice, which makes average spend mean what it looks like.
Distinct visitors are `customers_entered`.

---

## 3. State flow

```text
CLOSED --end_day()--> END_OF_DAY --acknowledge_summary()--> READY_FOR_NEXT_DAY
                                                                  |
                                                    advance_to_next_day()
                                                                  v
                                                              PREPARING
```

`READY_FOR_NEXT_DAY` is now genuinely entered and required:
`can_start_next_day()` is false until the summary is acknowledged.
`advance_to_next_day()` acknowledges implicitly if called directly, so a caller
that skips the screen still works.

---

## 4. Test results

| Suite | Result |
|---|---|
| `phase_4a_integration_test` (new) | **18/18** |
| `phase_4_daily_cycle_test` | 27/27 |
| `management_menu_test` | 6/6 |

Project imports with no parser errors.

---

## 5. Genuinely deferred — not started

I fixed the criticism you raised and stopped. These remain **not done**:

- **§3 modifier targets** — `CUSTOMER_TYPE_WEIGHT`, `CUSTOMER_GROUP_SIZE`, `CUSTOMER_STAY_DURATION`. No `tags` field was added to `CustomerType`. Stage 4 is **not complete**.
- **§4 preparation assessment service** — not built.
- **§5 end-of-day summary screen** — no player-facing screen. The frozen record is reachable only via F10. **The end-of-day flow is not complete by your stated criterion.**
- **§7 diagnostic export wiring** — `build_report_section()` still unconsumed. **Diagnostics are not complete by your stated criterion.**
- **§8 health checks** — not implemented.
- **§10 F10 additions** — only "recent authoritative events" added, plus clearer TEST labelling on injection buttons and an acknowledge-summary action.

---

## 6. What I would do next

1. **Summary screen** — the frozen record is complete and node-free; this is UI over existing data, and it is what makes the loop player-facing.
2. **`tags` on `CustomerType`** — unblocks all three modifier targets together.
3. **Diagnostic wiring and health checks** — the data exists; both need consumers.
