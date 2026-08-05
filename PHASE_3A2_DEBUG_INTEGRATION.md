# Phase 3A.2 — Debug, Integration and Cleanup Pass

Scope was triaged against the two reports. The four confirmed, player-visible
defects were fixed at their source and verified at runtime. The remaining brief
items are recorded honestly below as **not done**, with what was found.

**General navigation and avoidance were not modified.** No change was made to
`NavigationAgent2D` configuration, navigation maps, avoidance, pathfinding,
stuck detection, navigation recovery, movement speed, arrival tolerances,
obstacle generation or route selection. The bar-side fix is an
interaction-target change only: it alters *which point a worker walks to*, not
how it gets there.

---

## 1. Confirmed bugs fixed

### #3 — Bartender performed serving work (root cause, not symptom)

Two independent holes, both closed:

1. **`StaffMember._take_task()` never checked capabilities.** `select_best_task()` filtered by capability, but it is not the only route to a claim — carried-item reassignment, recovery and developer tools all reach a claim directly.
2. **`CarriedItemRecovery._plan_reassign()` hard-coded `SERVE_DRINK`** and never consulted the worker's role. A bartender holding a prepared drink was handed a customer-delivery task. This was the exact route by which the bartender completed two serves.

Fixed by enforcing at the **chokepoint**: `TavernTaskService.claim()` now refuses
any task whose required capabilities the worker does not hold, and records a
`capability_violation` issue carrying worker ID, archetype, capabilities, task
ID, task type, required capabilities, carried item and assignment route.
`_take_task()` checks on the near side and names the route.
`_get_reassignable_tasks()` replaces the hard-coded lookup and considers every
implemented task type the worker is actually allowed to perform.

The check **fails closed**: a worker that cannot report its capabilities is
refused, not trusted.

### #2 — Bartender used the wrong side of the bar

Implemented as action-specific access points, scene-driven:

```text
ServiceSlots/SlotN                 the logical slot - one ItemSlot, one stack
  ├── DepositPoint    (0, -30)     north, behind the counter
  └── CollectionPoint (0,  22)     south, customer side
```

`BarCounter.get_slot_access_position(slot_index, SlotAccess)` returns the right
point, falls back to the slot marker with a one-time `push_warning` if a point
is missing, and `has_complete_access_points()` lets the integrity check report a
half-configured counter.

`PrepareDrinkExecutor` deposits via `SlotAccess.DEPOSIT`; `ServeDrinkExecutor`
collects via `SlotAccess.COLLECT`; `CarriedItemRecovery` picks the side from the
worker's own capabilities rather than from the item.

Reservation is unchanged and still applies to the **logical slot** — the access
points carry no ownership of their own, so deposit and collection cannot create
two claims on one item.

Measured: deposit y=140 (north of the counter body, which spans y 151.75–178.25),
collection y=192 (south). 52 px apart, correct sides.

### #6 — Stock alerts named the wrong speaker

`Comms.find_speaker()` returned whichever staff member the group yielded first,
which is why every alert was attributed to `tavern_hand_01` — a worker with no
ability to do anything about an empty barrel.

`find_speaker_for_capability()` now prefers an **enabled** worker whose role
covers the relevant capability, falls back to any available speaker, then to a
neutral station voice (`speaker_id = "station"`, name taken from the source
node). Disabled or paused workers are skipped. Stock alerts ask for
`REFILL_STATIONS`.

Verified: the alert speaker is now `bartender_02`, not `tavern_hand_01`.

### #1 — `M` menu did not update stock

Root cause confirmed: the menu subscribed to `money_changed`,
`statistic_changed` and `time_changed` — **nothing inventory-related**. Its
stock page was built only when the Stock button was pressed and was never
rebuilt on reopen or on any stock mutation.

Now:

- `open_menu()` calls `_connect_stock_sources()` then `refresh_all()`, so reopening can never show a stale value.
- Subscribes to the authoritative sources: every station's `stock_changed` and `stock_state_changed`, `StockStorage.contents_changed`, and `OrderManager.order_submitted` / `order_delivered` / `delivery_partially_received`.
- `_connect_once()` guards every connection, so reopening or a runtime-added station cannot double-connect.
- Refreshes are coalesced with `call_deferred`, so a delivery, a refill and a preparation landing in one frame rebuild the list once. **The menu never polls.**
- `get_stock_snapshot()` returns the raw authoritative values behind the display, for the debug comparison the brief asked for.

Verified: snapshot tracked a station live 20 → 17 and matched the station exactly.

---

## 2. Not done in this pass

Stated plainly rather than partially attempted:

- **#4 carried-item recovery frequency** — capability-blocked reassignment is now distinguished and recorded, which removes the bartender's 14 recoveries at source, but the recovery-plan retention and reservation work was not done.
- **#5 blocked refill tasks** — the two open refill tasks remain ordinary open work. No `BLOCKED_NO_STOCK` state was added.
- **#7 ordering lifecycle audit**, **#8 order-ID linkage**, **#9 delivery/payment consistency**, **#10 cleaning claim delay**, **#11 return-to-idle churn**, **#12 shared session metadata** — investigated only as far as the fixes above required.
- The **inventory conservation summary**, **task-board integrity scan** and **expanded report sections** were not added.
- The **general tidy pass** was not performed.

---

## 3. Files changed

**Modified (8)**

```text
systems/staff/tasks/tavern_task_service.gd   capability enforcement at claim;
                                             violation recording
systems/staff/staff_member.gd                capability gate on _take_task();
                                             can_perform_task();
                                             get_archetype_id()
systems/staff/carried_item_recovery.gd       capability-aware reassignment;
                                             role-appropriate bar side
systems/staff/executors/serve_drink_executor.gd    collects from the south side
systems/staff/executors/prepare_drink_executor.gd  deposits from the north side
systems/communication/communication_service.gd     find_speaker_for_capability()
systems/communication/stock_alert_coordinator.gd   refill-role speaker + neutral
                                                   station fallback
scripts/Interactables/bar_counter.gd         SlotAccess API, warnings, integrity
scripts/UI/bar_management_menu.gd            live stock, coalesced refresh,
                                             snapshot
scenes/furniture/bar_counter.tscn            Deposit/Collection markers per slot
tests/phase_3a_smoke_test.gd                 two stale invariants corrected
```

**Added (2)**

```text
tests/phase_3a2_integration_test.gd / .tscn   16-check verification suite
PHASE_3A2_DEBUG_INTEGRATION.md                this document
```

**No files need to be deleted.**

---

## 4. Behavioural changes

- A worker can no longer acquire work outside its role by **any** route; refusals are recorded rather than silent.
- The bartender approaches bar slots from behind the counter; the Tavern Hand from the customer side.
- Stock alerts are attributed to the role that can act on them, or to the station itself.
- The `M` menu reflects live stock and refreshes fully on every open.

---

## 5. New configuration and nodes

- `BarCounter.SlotAccess` enum (`DEPOSIT`, `COLLECT`).
- `DepositPoint` / `CollectionPoint` `Marker2D` children under each `ServiceSlots/SlotN`. Scene-driven, so a future serving hatch or island counter is a scene change.
- `TavernTaskService.ISSUE_CAPABILITY_VIOLATION` and `capability_violations` in the board summary.

---

## 6. Manual regression checklist

1. Open `M`, note stock, close, let the bartender pour, reopen — values differ.
2. Leave `M` open while a drink is prepared — station servings drop live.
3. Leave `M` open while a delivery lands — storage rises live.
4. Watch the bartender deposit: it should stay behind the bar.
5. Watch the Tavern Hand collect from the customer side.
6. Empty a station with no storage — the alert should name the Bartender.
7. Disable the Bartender, empty a station — the alert should name the station.
8. Confirm the bartender never delivers to a customer.

---

## 7. Known limitations

- Access-point offsets (−30 / +22) were derived from the counter's collision extents, not by eye. They are correct in headless pathing tests but may want nudging in the editor.
- The two open refill tasks from the original report will still appear as open work.
- Report phase identifiers remain inconsistent (`Phase 2B` / `Phase 3A`).
- Two assertions in `phase_3a_smoke_test.gd` were stale once a bartender existed; both were corrected, and the suite is green again at 34/34.
