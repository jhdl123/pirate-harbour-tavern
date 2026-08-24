# Current State

Verified implementation status. **This is a summary, not a substitute for the
code.** When it disagrees with the repository, the repository is right — fix
this file.

Reconciled against `main` at `825add8` (phase-a-part4-corrected).

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

**Verified.** Spawning, entrance, navigation, seating and reservation, ordering,
waiting, drink delivery, drinking, payment, departure and cleaning all run
unattended for a full simulated day. The most recent committed diagnostic run
(`debug/latest/`, commit `10dbfff`, 2 game days) reports every system PASS and
all orderable drinks passing the full service chain.

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
Recent runs show 66–83% group success.
**Known bug:** `DeliverGroupKegExecutor` has no validity check, so a worker
keeps a task whose group has left and stands holding the keg indefinitely.

### Staff and tasks — Verified
`TaskBoard` autoload, `TavernTask`, `StaffMember`, `StaffCapabilities`,
executors, viability scoring, carried-item recovery with bounded attempts and a
terminal give-up. Two roles: Tavern Hand (serve, clean, deliver group kegs) and
Bartender (prepare, deposit, refill).
**Open concern:** task cancellation ran 24–35% in recent runs.

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

1. `DeliverGroupKegExecutor` has no validity check — worker stranded holding a
   keg when its group leaves.
2. Task cancellation 24–35%.
3. Most drink stations resolve their approach point to the customer side,
   because the walkable strip behind them is ~8px — narrower than the ~12px an
   actor needs to hold position. A level fix, not a code fix.
4. `record_stock_event()` is wired but nothing calls it, so the stock event log
   in diagnostics is always empty.
5. Sprite gaps: bottled drinks use an 8×16 bottle when full but a 16×16 wine mug
   when empty or broken; Cider, Small Beer and Ale share one mug sprite. Both
   need art, not code.
6. Group activity participation reads 0.0%.
7. `grog` and `kill_devil` are two `DrinkDefinition`s sharing one content id —
   unreconciled duplication.
8. Pre-existing GDScript warnings (shadowed names, integer division, unused
   `order_placed` signal). See the editor log.

`KNOWN_ISSUES.md` in the repository root holds a longer, older static-audit list
from the Phase 3A cleanup pass; parts of it are now stale.

## Diagnostic lessons that keep recurring

Apparent AI faults have repeatedly turned out to be insufficient stock,
inadequate staffing, short runs, too few groups, task churn, or missing
instrumentation. Establish prerequisites and sample size before judging
behaviour.
