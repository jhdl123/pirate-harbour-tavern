# Current State

Verified implementation status. **This is a summary, not a substitute for the
code.** When it disagrees with the repository, the repository is right — fix
this file.

Reconciled against `feature/darts-multiplayer-and-activity-affinity` at
`526e2fa` (2026-08-25). `main` is currently at `235b7ac` — 5 commits behind
this branch; see `CHANGELOG.md` for what has not merged yet.

Repository: `jhdl123/pirate-harbour-tavern` · Godot **4.7.1**

## Status key

| Marker | Meaning |
|---|---|
| **Verified** | implemented and demonstrated by a passing test or diagnostic run |
| **Built, lightly tested** | implemented, works in play, no dedicated coverage |
| **Foundation** | classes and data exist; not yet gameplay the player experiences |
| **Partial** | some paths work, known gaps listed |
| **Planned** | agreed, not started |

## Core loop

**Verified for solo customers.** Spawning, entrance, navigation, seating and
reservation, ordering, waiting, drink delivery, drinking, payment, departure
and cleaning all run unattended for a full simulated day. A fresh 3-day
diagnostic run (`debug/archive/2026-08-24-2023/`, commit `d51e6c8`) reports
Drinks/Stations/Ordering/Delivery/Storage/Restocking/Bar/Customers/Staff all
PASS and all orderable drinks passing the full service chain - the same
result the prior baseline (`debug/archive/2026-08-19-1514/`, commit
`10dbfff`, 2 game days) showed, so the solo-customer core loop survived the
undocumented Phase A customer AI change (see the Customer AI section below)
intact. **Groups did not** - that same fresh run FAILs on group success; see
the Groups section.

Breakage handling exists (`CleaningTask`, break-chance on `DrinkDefinition`) —
**built, lightly tested**.

## Systems

### Items and inventory — Verified
`ItemDefinition`, `DrinkDefinition` (extends it), `ItemStack`, `ItemSlot`,
`ItemContainer`, `ItemCarrier`, `ItemTransferService`, `ItemRegistry`,
`ItemTags`. Covered by `item_system_tests`.

### Interaction — Verified
Generic detection, scoring with stickiness, highlighting, prompts and action
execution via `Interactable` + `InteractionMenu`. **Known limit:** an
interactable returns exactly one action and there is no secondary-action UI, so
a station can only ever offer one drink. This is why bottle service stations are
children of their shelves.

### Navigation — Verified
`ActorNavigation`, movement profiles, arrival and recovery, RVO avoidance with
stable per-actor passing bias, `NavigationService`, `NavigationValidator`,
reservations. A startup navigation scan runs in debug builds.
Covered by `navigation_stress_test`, `reachability_probe`, `nav_probe`.

### Time and simulation — Verified
`WorldTime` and `Simulation` autoloads; day counter, scaling, pause,
scheduling. `Tavern` owns the day lifecycle; `TavernSchedule` and
`DemandProfile` drive arrivals.

### Customer AI — Verified (behaviour), Partial (perception)
`CustomerNeeds`, `CustomerBrain`, `ActivityDefinition`/`ActivityCondition`,
`ActivityRegistry`, `CustomerIdentity`, `Personality`, `VisitIntentConfig`,
`SocialCompatibility`. Covered by `customer_identity_test` (92 assertions).
**Gap:** much of this depth is not visible to the player.

### Groups — Verified
`CustomerGroup`, `GroupManager`, `GroupOrderService`, `GroupKegStockService`,
`DeliverGroupKegExecutor`, shared table cask ordering, leader-pays payment.
The 66–83% group success figure is stale: a fresh 3-day run at commit
`d51e6c8` (2026-08-24, `debug/archive/2026-08-24-2023/`) measured 37.5% at
the game's own maximum player speed (4x). Speed matters a lot here — the
same scenario at an unsupported 8x (no player can select this;
`GameTimeConfig.available_speed_multipliers` tops out at 4.0) measured
27–35%, because `WorldTime.set_speed()` only scales the world clock, not
staff movement or `ActionDefinition` durations, so world-clock deadlines
outrun real-time-paced service the higher the speed goes. True 1x-speed
group success is still unmeasured; re-run before trusting any single number
here.
**`DeliverGroupKegExecutor` bug status unclear:** the code currently reads
`_find_group()` every step and fails the task with `group_no_longer_waiting`
if the group is gone, recovering the carried keg through the normal
carried-item policy - this looks like it already handles the "group left
mid-delivery" case the known-bug note below describes, and the file hasn't
changed since 2026-08-06. Neither confirmed fixed (no live repro attempted)
nor confirmed still broken - the note is kept until one or the other is
demonstrated.

### Staff and tasks — Verified
`TaskBoard` autoload, `TavernTask`, `StaffMember`, `StaffCapabilities`,
executors, viability scoring, carried-item recovery with bounded attempts and a
terminal give-up. Two roles: Tavern Hand (serve, clean, deliver group kegs) and
Bartender (prepare, deposit, refill).
**Open concern:** the 24–35% task cancellation figure is stale for the same
reason as group success above - the same fresh run measured 48.9% at 4x
speed (was 90%+ at the unsupported 8x tested first). Re-measure at 1x before
treating either number as current.

### Customer AI — visit duration and departure (Phase A, undocumented until now)
Customer types can carry a per-type visit-duration band
(`CustomerType.visit_duration_minimum_minutes` / `_maximum_minutes`, 0 means
"use the global range") so a quick-pint type and an all-night type are
distinct populations rather than one stretched curve. A "leave decision
window" (`CustomerAIBalanceConfig.leave_decision_window_minutes`, default 30)
schedules one extra `think()` before the hard visit timer, giving the
customer a real chance to choose to leave rather than always being timed out.
Patience no longer ejects a customer on one slow serve: it takes
`abandoned_orders_before_leaving` (default 3) misses before the departure
reason becomes `&"repeated_neglect"` (`&"patience_expired"` is no longer
ever assigned). This shipped in commit `4923617` without a commit-message
disclosure or a doc entry; two bugs were found and fixed against it this
pass (see Known issues).

### Customer AI — cross-activity affinity and two-participant darts (new)
`ActivityContext.last_activity_id` (stamped by `CustomerBrain._exit_current()`)
plus `PreviousActivityAffinityCondition` let an activity's own `.tres` data
declare a soft bonus off whatever the customer just finished, without any
new branching in `CustomerBrain`. Wired for drink→socialise, darts→drink,
and darts↔socialise. `ActivityDefinition` gained `min_participants`/
`max_participants` (default 1/1); Darts is 1/2. `TavernActivityPoint` now
discovers `TavernActivitySlot` children instead of assuming exactly one
`Reservable`, so `darts_point.tscn` offers two independently-reservable
slots. `VisitTavernActivityBehaviour` makes one synchronous attempt (no
waiting/timeout) to co-opt a nearby available customer as a second
participant via the new `Customer.find_nearby_activity_partner()`; each
participant reserves, plays, and returns to its own decision point
independently, so e.g. one choosing to order a drink afterward while the
other socialises is the ordinary result of two separate `Customer` nodes,
not new coordination code. Group members reach this the same way solo
customers do (`GroupManager._ask_member_brain()` already calls the same
`think()`) with no `GroupManager`/`CustomerGroup` changes needed.

Found and fixed along the way: `return_to_seat.tres` had zero conditions
despite its own doc comment saying it should only ever be entered directly,
so a customer with no other viable option could have normal `think()`
scoring pick it while already at its own chair - an instant "return" that
re-triggers `think()` immediately, printing as a burst of repeated
`Chosen: return_to_seat` rather than a hang. Now gated by
`DeterministicEntryOnlyCondition`, which is always false and safe because
`enter_activity()`/`force_activity()` never check availability.

`CustomerBehaviourPanel` (F9) and `StockDevPanel` (F10) gained a real
customer picker (previously always "customer index 0", by their own
explicit comments) - every existing action (print profile, verbose
scoring, force-to-socialise, force-to-darts) now targets whichever customer
is selected. `DecisionRecord` gained `activity_partner_customer_id`,
mirroring the existing `social_partner_customer_id` field.

Not covered by an automated test this pass - several attempts at a
dedicated solo/two-player darts test were made and found three of the real
bugs above, but the test itself remained too environmentally fragile
(customer-type visit-duration variance, `--fixed-fps` timing races on
transient states) to land reliably in the time available; the mechanism is
exercised by `tests/group_parity_test.gd`'s existing (unchanged, still
passing) `_test_leisure_darts_and_return()` via the legacy stub path, and
by the full regression suite (`customer_identity_test`,
`group_and_recovery_probe`, `report_fields_test`, `diagnostic_export_probe`,
`behaviour_mix_probe` all pass unchanged), but solo/two-player darts and
post-match divergence have not been proven end-to-end by an automated test.

### Beverage, stock and delivery — Verified
`BeverageRegistry`, `ContainerDefinition`, `ServingFormatDefinition`,
`StorageProfileDefinition`, `FilledContainer`, `BeverageStorage`,
`StationStockPlan`, `StockedDisplay`, `OrderManager`, `SupplierDefinition` /
`OrderCatalogueEntry`. Order → delivery → authoritative storage → visible
storeroom prop → staff withdrawal → station is demonstrated end to end by
`restock_chain_probe` and `delivery_storeroom_probe`.

Three poured drinks (Grog, Cider, Small Beer) and four bottled (Madeira, Port
Wine, Canary Wine, Brandy). Ale is retired from normal service but **kept
deliberately** — the group keg chain and its resources still reference it.

### Communication — Verified
`Comms` autoload; toasts, alerts, speaker messages, stock alerts derived from
authoritative configuration.

### Economy — Built, lightly tested
`EconomyManager` owns money. Payment, stock purchase and daily statistics work.
No wages, rent or recurring costs.

### Daily cycle — Built, lightly tested
`DailyStatistics`, `DailyStatisticsRecorder`, `DailyControlBar`,
`EndOfDaySummary` modal. Records per-day counters, sales, income and stock used.

### Diagnostics — Verified
`CustomerAIReportManager`, `StaffReportManager`, `DiagnosticRunExporter`,
`ServiceChainValidator`. F10 → Export Diagnostic Run writes `debug/latest/` and
a timestamped archive, each stamped with the Git commit. Covered by
`diagnostic_export_probe`, which includes fault injection.

### Modifiers — Foundation
`Modifiers` autoload with target registry and stacking. **Nothing currently
registers a modifier.** Its own comment anticipates weather, reputation and
upgrades. This is the plumbing a progression system would use.

## Not implemented

Reputation · progression and upgrades · wages, rent or recurring costs ·
gambling · entertainment · smuggling and trading · harbour/world simulation ·
factions · weather · save/load.

## Known issues

1. `DeliverGroupKegExecutor` validity-check status unclear — see the Groups
   section above. Not confirmed broken, not confirmed fixed.
2. Task cancellation and group success are both worse at the game's own
   maximum speed (4x) than the stale 24–35% / 66–83% figures on record, and
   unmeasured at 1x. See the Groups and Staff sections above.
3. Most drink stations resolve their approach point to the customer side,
   because the walkable strip behind them is ~8px — narrower than the ~12px an
   actor needs to hold position. A level fix, not a code fix.
4. `record_stock_event()` is wired but nothing calls it, so the stock event log
   in diagnostics is always empty.
5. Sprite gaps: bottled drinks use an 8×16 bottle when full but a 16×16 wine mug
   when empty or broken; Cider, Small Beer and Ale share one mug sprite. Both
   need art, not code.
6. Group activity participation reading 0.0% is likely already stale: commit
   `a6b6b38` (2026-08-19, before the commit this file was last reconciled
   against) fixed both causes its own comments describe
   (`allow_activities_while_drinking` now defaults `true`;
   `is_settled` now includes `IN_GROUP`). Never re-measured -
   `activity_participation_rate_percent` isn't printed in any exported
   report file (checked `drinks_report.txt`, `customer_report.txt`,
   `system_diagnostics.txt`, `staff_report.txt` on a fresh run), so
   confirming this needs either reading the exporter's in-memory dictionary
   directly or adding it to a report.
7. `grog` and `kill_devil` are two `DrinkDefinition`s sharing one content id —
   unreconciled duplication.
8. Pre-existing GDScript warnings (shadowed names, integer division, unused
   `order_placed` signal). See the editor log.

`docs/history/KNOWN_ISSUES.md` holds a longer, older static-audit list from
an early cleanup pass; parts of it are now stale.

## Diagnostic lessons that keep recurring

Apparent AI faults have repeatedly turned out to be insufficient stock,
inadequate staffing, short runs, too few groups, task churn, or missing
instrumentation. Establish prerequisites and sample size before judging
behaviour.
