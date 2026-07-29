# Cleanup Report — Pirate Harbour Tavern

## Methodology, and an important honesty note

This pass was a **static code and data audit**: every `.gd` script, every relevant
`.tscn`/`.tres` file, and the autoload/signal wiring in `project.godot` were
read and traced by hand, following each system from its entry point (an input
action, a scheduled world-time event, a signal) through to its effects.

**I do not have the Godot editor available in the environment this cleanup was
done in.** I could not launch the project, click through menus, or watch the
customer loop run. Where the brief asked for interactive playtesting (serving
drinks, refilling stations, opening menus, skipping days), what I actually did
instead was trace the code path a button press or scheduled event would take
and check it against the stated requirement. That is a real form of testing —
it caught a genuine stock-duplication bug a casual playthrough might not have
surfaced for several in-game days — but it is not a substitute for you running
the game yourself. `TEST_CHECKLIST.md` is written with this distinction
explicit: every item is marked either "traced in code, needs your play-test to
confirm" or left as an open question.

Given the size of the project (~75 GDScript files, 1000+ files including
assets), this pass concentrated on the systems most likely to hide real bugs —
the economy/order/delivery chain, the pause system, the item transfer service,
and the Bar Management UI — and did a lighter verification pass (checked for
the specific anti-patterns called out in the brief: per-frame recalculation,
unbounded growth, unthrottled repathing) on the navigation and interaction
frameworks, which were already extensively documented in-code from earlier
development and did not show the same problems.

---

## Bugs found and fixed

### 1. Order duplication after a partial delivery

**Problem.** If a delivery arrived while storage was full or nearly full, any
quantity that didn't fit was supposed to stay pending and complete later when
space freed up. Instead, the *next* time deliveries were processed, the order
would attempt to deliver its **full original quantity again** — potentially
creating more stock than was ever ordered or paid for.

**Cause.** `OrderManager.process_due_orders()` and `complete_all_deliveries()`
iterated `pending_orders.duplicate(true)` — a **deep** duplicate. In GDScript,
`Dictionary` is a reference type, so `pending_orders` is really an array of
shared references. A deep duplicate hands `_deliver_order()` a fully
disconnected copy of each order dictionary. When a delivery was only
partially received, the line that recorded "5 of these 10 are already
delivered" was written onto that disconnected copy and then discarded — the
real dictionary sitting in `pending_orders` never learned that anything had
been delivered at all. The next time the order came due, it started again
from the full original quantity.

**Fix.** Changed both loops to `pending_orders.duplicate()` (shallow). A
shallow duplicate copies the array's structure but keeps the same dictionary
references inside it, so mutations during delivery apply to the real pending
order, and the loop can still safely `erase()` from the live array mid-iteration.

**How it was verified.** Traced the flow by hand: submit an order → let it
fall due with storage already full → confirm (by reading `_deliver_order`)
that `remaining_quantity` is now written to the same dictionary object stored
in `pending_orders` → confirm a second `process_due_orders()` call reads that
updated value instead of the original. This is exactly the "fill storage
before a delivery arrives" edge case called out in the brief's testing
section, and it's flagged in `TEST_CHECKLIST.md` for you to confirm live.

---

### 2. Bar Management menu's Overview and Progression pages were non-functional

**Problem.** The M-menu Overview page always showed the hard-coded text
`"Day 1 — 08:00"`, `"£0"`, `"0"` customers and `"0 occupied / 0 available / 0
total"` seats, regardless of actual game state. The Progression page's five
labels (customers served, days operated, money earned, peak customers,
milestone progress) were present in the scene but were never written to by
any script at all — they permanently showed their placeholder design-time
text.

**Cause.** `GameManager` had no `class_name`, so nothing else in the project
could hold a *typed* reference to it — `BarManagementMenu` could only accept
it as a generic `Node`, which meant it had no safe way to ask "how many
customers are active" or "how many seats are occupied" without reaching past
its own encapsulation. Rather than do that, `refresh_overview()` had
apparently been stubbed out with placeholder text and never finished, and the
Progression page was never wired up to `StatisticsTracker` at all (it wasn't
even passed to the menu in the scene).

**Fix.**
- Gave `GameManager` a `class_name` and added four read-only query methods:
  `get_active_customer_count()`, `get_total_seat_count()`,
  `get_occupied_seat_count()`, `get_available_seat_count()`.
- Typed `BarManagementMenu`'s `game_manager` and `economy_manager` exports to
  `GameManager` and `EconomyManager`, and added a new `statistics_tracker`
  export, wired to the existing `StatisticsTracker` node in `main.tscn`.
- Rewrote `refresh_overview()` to read real data: `WorldTime.get_full_text()`,
  `EconomyManager.get_money()`, `GameManager`'s new seat/customer getters,
  and `StatisticsTracker.get_customers_served_today()`.
- Added `refresh_progression()`, wired to the five Progression-page labels
  that already existed in the scene but were never touched by code, plus a
  small purely-informational milestone helper (`Serve 25 customers — N / 25`)
  that reads `StatisticsTracker` and writes nothing back to it.
- Connected `EconomyManager.money_changed`, `StatisticsTracker.statistic_changed`
  and `WorldTime.time_changed` to a shared refresh handler so the menu stays
  live while open, instead of only being accurate at the instant it was
  opened.

**How it was verified.** Traced each new getter against `Table`/`Chair`'s
existing seat-state API to confirm occupied+available == total, and confirmed
every label in the scene file now has a corresponding write in the script
(previously five of them had none). Flagged in `TEST_CHECKLIST.md` for you to
confirm the numbers move as expected during play — spend money, serve a
customer, skip a day, and check the M menu updates.

---

### 3. Dead, misleading configuration field on `SupplierDefinition`

**Problem.** `SupplierDefinition` exposed a "Delivery" category with a
`delivery_delay_days` slider (0–30 days) in the editor. It looked like the
obvious place to control how long a supplier takes to deliver. It did
nothing — no script anywhere read it. The actual delivery delay is (correctly,
per the brief's "keep delivery timing simple" instruction)
`OrderManager.default_delivery_minutes`, a single project-wide value.

**Cause.** Leftover from an earlier design iteration, before delivery timing
was centralized onto `OrderManager`. Nothing removed the now-unused field
from the resource.

**Fix.** Removed the field and updated the class doc comment to say plainly
that delivery timing lives on `OrderManager`, not per-supplier, and why (the
brief explicitly asked to keep this simple for now). No `.tres` file had a
non-default value set for it, so nothing else needed to change.

**How it was verified.** `grep`'d the whole project for the field name before
and after removal; the only remaining reference was the doc comment.

---

### 4. Orphaned `ItemRegistry` and hardcoded item paths in the dev panel

**Problem.** `Data/items/item_registry.tres` is a fully populated master list
of every item definition in the game — exactly the "item database" the brief
describes as an existing feature. Nothing loaded it. Meanwhile,
`StockDevPanel._add_test_stock()` looked up its two test items with
`load("res://Data/items/stock/grog_barrel.tres")` — a hardcoded path string,
which is exactly the kind of magic-string item identification the brief asks
to avoid, and which would silently break if that file were ever moved or
renamed.

**Fix.** Wired the existing `item_registry.tres` into `GameManager` (validated
once at startup via `ItemRegistry.validate_or_warn()`, so a duplicate or
malformed item id is caught immediately instead of surfacing later as a
mysterious null) and into `StockDevPanel`, which now looks items up by their
stable `item_id` (`&"grog_barrel"`, `&"ale_keg"`) instead of a file path.

**How it was verified.** Confirmed both ids exist in the registry and in the
`.tres` files themselves; confirmed `validate_or_warn()` reports duplicate ids
one warning per project by tracing its own logic (not something a UI action
can trigger directly — it's a startup check).

---

### 5. Excessive unconditional debug printing in `Chair`

**Problem.** Six `print()` calls in `chair.gd` (drink assigned, cleaning
required, cleaning started, task changed, complication, completed) fired on
every state change with no way to turn them off, unlike every other system in
the project, which gates its debug output behind `GameConfig.show_debug_messages`.
With several occupied tables this drowns the output panel during ordinary
play.

**Fix.** `Chair.configure()` now stores its `GameConfig` reference (it
already received one, just didn't keep it), and all six prints are gated
behind a new `_should_print_debug()` helper.

---

---

### 6. Developer stock panel had no shipping guard

**Problem.** The brief's developer-tool audit explicitly requires "developer
mode availability" to be configurable and dev tools to not "accidentally
appear in an exported production build unless intentionally enabled."
`StockDevPanel` (F10: money, time, stock and delivery test controls) built
its UI and responded to input unconditionally — it would be fully active in
an exported release build with no way to turn it off.

**Fix.** `StockDevPanel._ready()` now checks `OS.is_debug_build()` before
building its UI or responding to input at all; disabled in a release export,
active in the editor and in debug exports. `SimulationDebugPanel` (F1–F4:
pause, speed, skip-hour, time readout) was deliberately left alone — the
project's own `README.md` documents F1–F4 in its normal "Controls" table
alongside movement and interaction, not as a developer-only feature, so
disabling it in release builds would remove a feature the project already
treats as shipped, not gate a debug tool.

**How it was verified.** Traced `OS.is_debug_build()`'s documented semantics
(true in the editor and debug export templates, false in release export
templates) against Godot's own documentation. Could not actually produce a
release export to confirm in this environment — flagged in `TEST_CHECKLIST.md`
for you to confirm with a real export.

---

## Files added

- None (only edits and removals — see below).

## Files changed

- `systems/orders/order_manager.gd` — shallow-duplicate fix (see bug 1).
- `scripts/Managers/game_manager.gd` — `class_name`, seat/customer getters,
  `item_registry` export + startup validation (see bugs 2 and 4).
- `scripts/UI/bar_management_menu.gd` — real data wiring, live refresh (see
  bug 2).
- `scenes/main/main.tscn` — wired `StatisticsTracker` and the `ItemRegistry`
  resource into `GameManager` and `StockDevPanel`.
- `scripts/Entities/customer.gd` — added `class_name Customer`.
- `scripts/Interactables/chair.gd` — debug-print gating (see bug 5).
- `scripts/UI/stock_dev_panel.gd` — `ItemRegistry`-based lookups (see bug 4)
  and a debug-build guard (see bug 6).
- `systems/orders/supplier_definition.gd` — removed dead field (see bug 3).

## Files removed

- `scripts/main.gd` and `scripts/main.gd.uid` — an orphaned prototype script,
  not attached to any node in the current `main.tscn`, calling a
  `set_target()` method that no longer exists on `Customer` and referencing
  marker nodes (`CustomerSpawnPoint`, `CustomerTablePoint`) that don't exist
  in the current scene. Superseded entirely by `GameManager` + `CustomerDoor`.
- `scenes/furniture/table.tscn8647504531.tmp` — a Godot crash-recovery
  temp file.
- `INSTALL_INTERACTION_LEDGER.txt`, `INSTALL.txt`,
  `STOCK_DELIVERY_BUILD_README.md` — three near-duplicate "how to merge this
  patch" instruction files left over from earlier incremental delivery
  sessions, describing work (the interaction menu, the supply ledger, the
  stock/storage/delivery system) that is now already merged into the project.
  None were referenced from any script or scene.

## Behaviour changes

- The M-menu Overview and Progression pages now show real, live data instead
  of static placeholder text (bug 2). If you were relying on the placeholder
  text for anything (unlikely, but worth naming), that text is gone.
- `SupplierDefinition` no longer has a `delivery_delay_days` property. If any
  external tooling or a save file (none exist yet) referenced it, it will now
  be ignored rather than read.
- Dev-panel "Add 2 of each stock" now fails with a clear status message
  instead of silently loading the wrong file if the `ItemRegistry` reference
  or its entries are ever missing.

## A note on the repository's pre-existing state

The project's `.git` working tree already contained uncommitted changes to
several files I did not touch this session (`drinks_station.gd/tscn`,
several `Data/**.tres` files, `project.godot`) — this predates this cleanup
pass and appears to be normal in-progress work from before the project was
handed over. I'm calling it out so it isn't mistaken for something this
cleanup introduced; I left all of it alone.

## Areas deliberately left unchanged

- **Delivery timing model.** Kept intentionally simple (one project-wide
  `default_delivery_minutes`), per the brief's explicit instruction not to
  build supplier schedules, wagons or harbour arrival mechanics in this pass.
- **Navigation and interaction frameworks.** Read in depth for the specific
  anti-patterns called out in the brief (per-frame recalculation, unthrottled
  repathing, unbounded growth) and found to already implement throttled
  repathing, sticky selection and defensive null-checking correctly. Did not
  rewrite working, well-documented code for its own sake.
- **Save/load.** Not implemented, per the brief. The `ItemRegistry`,
  `SimulationController.to_dictionary()/apply_dictionary()` and
  `WorldTime.to_dictionary()/apply_dictionary()` groundwork already exists
  for when it is.

## Known remaining issues

See `KNOWN_ISSUES.md`.
