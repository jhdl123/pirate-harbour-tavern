# Architecture Overview — Pirate Harbour Tavern

This describes the major systems as they exist after this cleanup pass, and
how they connect. It reflects the actual code, not an aspirational design.

## Layering

```
Autoloads (global, singleton)
  Simulation      - authoritative "is the game running" state
  WorldTime       - the one game clock, scheduling, save-ready
  InteractionMenu - owns exactly one open context menu, and its pause

Systems (systems/) - reusable frameworks, no gameplay-specific knowledge
  navigation/   interaction/   inventory/   items/   actions/
  reservation/  economy/       orders/      stock/   time/
  simulation/   statistics/    ui/

Gameplay (scripts/) - the actual tavern, built from the systems above
  Managers/   (GameManager, GameConfig)
  Entities/   (Player, Customer)
  Interactables/ (Chair, Table, DrinksStation, StockStorage's script lives in
                  systems/stock, but the furniture scripts for Bar, Ledger,
                  Chair, Table, CustomerDoor live here)
  Components/ (CleanableComponent, ItemCarrier, InventoryComponent, PatienceBar)
  UI/         (HUD, BarManagementMenu, StockDevPanel, StorageInventoryMenu)
```

The dependency direction is meant to run downward only: gameplay scripts
depend on systems, systems never depend on gameplay scripts. `DrinksStation`
knows about `ItemTransferService`; `ItemTransferService` has never heard of a
drinks station.

---

## Simulation (`systems/simulation/`)

`Simulation` (autoload, `simulation_controller.gd`) is the single authoritative
answer to "is the game running right now". It holds one current state
(`LOADING`, `PLAYING`, `PAUSED`, `FAST_FORWARD`, and room for future
`DIALOGUE`/`CUTSCENE`) plus a **stack** of suspended states.

```
push_state(PAUSED)   -> suspends current state, becomes PAUSED
pop_state()          -> restores whatever was suspended
pause() / resume()   -> convenience wrappers over the above
```

The stack is what makes nested pausing safe: if the M menu pushes `PAUSED`
and then the player somehow opens a second pausing surface, closing the first
one only pops back to whatever was actually underneath it — it can never
resume the game while something else still needs it paused. See
`PAUSE-SYSTEM AUDIT` below for how each menu actually uses this.

Every system that could plausibly pause asks `Simulation.is_running()` /
`accepts_input()` / `updates_actors()` rather than keeping its own flag or
touching `get_tree().paused` directly (engine pause is opt-in only, off by
default, via `mirror_to_engine_pause`, because it would freeze UI and tweens
too, which this kind of game doesn't want).

## World Time (`systems/time/`)

`WorldTime` (autoload, `world_time.gd`) is the single game clock. It owns:

- `WorldClock` — day/hour/minute/scale state.
- `GameTimeConfig` — a Resource holding every tunable time value (see
  `CONFIGURATION_GUIDE.md`).
- `TimeScheduler` — lets any system book a callback for a future world time
  (`schedule_in`, `schedule_at`, `schedule_daily`, `schedule_repeating`)
  instead of rolling its own `Timer`. `GameManager`'s customer spawning and
  `OrderManager`'s delivery processing both use this, which is why they
  correctly pause, fast-forward and survive a 24-hour skip without special
  cases.

`WorldTime` subscribes to `Simulation.state_changed` and stops advancing
when the simulation isn't running, so time and pause are consistent by
construction rather than by every consumer remembering to check twice.

## Navigation (`systems/navigation/`)

`ActorNavigation` wraps a `NavigationAgent2D` and owns repathing, arrival,
stuck detection and recovery (sidestep → forced repath → give up and report
failure) for **any** actor, not just customers — `Customer` is presently the
only user, but nothing in the framework mentions customers, tables or
drinks. Repathing is throttled by `minimum_repath_interval` on the actor's
`ActorNavigationProfile`, and destination changes only trigger a new path
request once they've moved further than `destination_move_repath_distance` —
both are there specifically to stop the "repath every frame" performance trap
called out in the brief.

`ActorMovement` turns the agent's desired velocity into actual movement,
smoothing direction changes so actors don't twitch.

`ReservationService` / `Reservable` is the generic claim system. A `Chair`
has a `Reservable` component; so could a future workstation or queue slot.
Reservation is two-stage (`reserve` → `occupy`) specifically so "on the way to
a seat" and "sitting in it" are different states — a customer who is deleted
mid-walk releases a *reservation*, not an occupied seat.

## Interaction (`systems/interaction/`)

`InteractionDetector` finds nearby `Interactable`s. `InteractionSelector` is
the only place that scores them (distance + priority + a sticky bonus for
whatever's already selected) and decides what's currently "meant". It knows
nothing about bars, drinks or customers — it asks each candidate what it
offers via `can_interact()` / `get_actions()` and hands the chosen action back.
A manually-cycled target (Tab) holds its place for a configurable time or
until the actor moves too far, so cycling doesn't get immediately overridden
by scoring.

`Interactable` is a thin wrapper node most world objects attach: it forwards
to the object's own script via duck-typing (`can_interact`, `get_actions`,
`perform_interaction` if present; sensible defaults otherwise), so the
selector, detector and highlight system need zero special-casing per object
type.

## Items and Inventory (`systems/items/`, `systems/inventory/`)

`ItemDefinition` is the base resource for anything that can exist in a slot —
`DrinkDefinition extends ItemDefinition`, so a drink *is* its own item
definition (one resource per drink), not a separate concept bolted on.

`ItemRegistry` maps stable `item_id`s back to `ItemDefinition` resources —
the one place that can answer "which definition is `grog`?" for save/load and
startup validation. See `CLEANUP_REPORT.md` bug 4 for how this cleanup
connected it up; it was previously an orphaned, fully-populated `.tres` that
nothing loaded.

`ItemSlot` / `ItemStack` / `ItemContainer` are the storage primitives.
`ItemTransferService` is the **only** place items move between slots — a
static, stateless service used by the player's carried-item interactions,
drink stations, storage and (eventually) staff AI. Every transfer is fully
validated before anything is mutated, and a failed transfer leaves both sides
completely unchanged — see its own doc comment for the full safety contract.
This was read start to finish during the cleanup and found to already be
correct, including the swap-rollback path.

`ItemCarrier` / `InventoryComponent` give an actor (currently only the
player) a slot to carry one thing.

## Economy (`systems/economy/`)

`EconomyManager` is a plain node (one instance under `Managers/`), not an
autoload — it's small enough, and single-instance enough, that a `class_name`
+ exported reference does the job without adding another global. It owns the
money total and emits `money_changed` / `money_added` / `money_spent` /
`transaction_failed` for anything that wants to react (the HUD, the Bar
Management overview).

## Orders and Deliveries (`systems/orders/`, `systems/stock/`)

`OrderManager` owns pending and delivered orders as plain `Dictionary`
records (a `class_name`-free data shape rather than a Resource, since orders
are transient, per-session state, not authored content). `SupplierDefinition`
+ `OrderCatalogueEntry` are the data-driven catalogue a `OrderLedger` reads
from. Delivery timing is intentionally a single project-wide
`default_delivery_minutes` on `OrderManager` — see `CLEANUP_REPORT.md` bug 3
for why `SupplierDefinition` no longer pretends to have its own delivery
delay.

`StockStorage` wraps an `ItemContainer` configured to accept the
`drink_stock` tag, and exposes `add_item()` (used both by delivery completion
and the dev panel) and `deposit_carried()` / `take_one()` for the player's
storage menu.

## Drink Stations (`scripts/Interactables/drinks_station.gd`)

Each station is fully data-driven: `served_drink`, `refill_item`,
`maximum_servings`, `starting_servings`, `servings_per_refill_item`, plus
visuals and a segmented stock indicator. It owns a one-slot `ItemContainer`
as its "output", and uses `ItemTransferService` for every hand-off — a
serving is only ever consumed after `ItemTransferService` confirms the
carrier actually received it, so a full-inventory failure or a rejected
transfer never silently loses stock.

## Management UI (`scripts/UI/`)

`BarManagementMenu` (M key) is read-only: an Overview page (money, active
customers, seats, drinks served today), a Progression page (lifetime
statistics and a milestone line), and a dynamically-added Stock page (storage
contents, station levels, pending deliveries). As of this cleanup it reads
real state from `GameManager`, `EconomyManager`, `StatisticsTracker` and
`WorldTime` instead of static placeholder text — see `CLEANUP_REPORT.md`
bug 2. It manages its own pause (`Simulation.push_state`/`pop_state`)
independently of `InteractionMenuController`, because it's opened by a
keybind rather than by walking up to a world object — the two pause paths
converge on the same `Simulation` stack, so they compose safely.

`InteractionMenuController` (autoload) is the shared home for every
*context* menu opened by walking up to something — the Supply Ledger and
Storage both use it via `InteractionMenu.open_menu(scene, context)`. It owns
exactly one open menu at a time, its pausing, and restoring whatever
simulation state was interrupted.

`StockDevPanel` (F10) is deliberately dumb: every button calls a real system
method (`EconomyManager.add_money`, `WorldTime.advance_minutes`,
`OrderManager.complete_next_delivery`, `DrinksStation.fill_stock`/`empty_stock`,
`StockStorage.add_item` via the `ItemRegistry`) rather than keeping any
separate debug-only state, so what you test with it is exactly the real game
system.

## Developer Tools

`StockDevPanel` (F10) now checks `OS.is_debug_build()` before building its UI
or responding to input at all, so it cannot appear in an exported release
build (see `CLEANUP_REPORT.md` bug 6). `SimulationDebugPanel` (F1–F4) is
intentionally not gated the same way — the project's `README.md` documents
F1–F4 as normal, shipped controls (pause, speed, skip-hour), not a developer-only
surface, so gating it would remove a feature rather than hide a debug tool.
See `KNOWN_ISSUES.md` for the caveat that this guard could not be confirmed
against a real release export in this environment.

---

## How a customer flows through the systems

```
WorldTime.schedule_in()         GameManager.spawn_customer()
        |                               |
        v                               v
customer_spawn event  ---------> assigns Table/Chair via Reservable
                                        |
                                        v
                          Customer.actor_navigation moves to staging,
                          then the seat (ActorNavigation + ActorMovement)
                                        |
                                        v
                          Chair.begin_use() promotes reserve -> occupy
                                        |
                                        v
                          Customer orders -> DrinksStation.perform_interaction
                          serves via ItemTransferService -> customer carries
                                        |
                                        v
                          Customer drinks -> _on_drink_finished()
                          emits customer_paid -> GameManager -> EconomyManager
                          Chair.require_cleaning() -> CleanableComponent
                                        |
                                        v
                          Customer.finish_customer() emits customer_finished
                          -> GameManager removes from active_customers,
                             clears the table reservation, queue_free()s
```

Every arrow in this chain is a signal or a typed method call, never a poll —
which is why the whole loop stops cleanly when `Simulation` pauses and speeds
up cleanly when `WorldTime` fast-forwards.
