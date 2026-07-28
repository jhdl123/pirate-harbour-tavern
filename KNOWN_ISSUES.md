# Known Issues — Pirate Harbour Tavern

This list is honest about what this cleanup pass could and couldn't confirm.
See `CLEANUP_REPORT.md` for the methodology note: this was a static code
audit, not an interactive playtest, because the Godot editor itself isn't
available in the environment this pass was done in. Nothing below is hidden
or downplayed to make the pass look more complete than it was.

---

## 1. Everything below "traced in code" in `TEST_CHECKLIST.md` needs a real playtest

**Symptoms.** None observed — this is a methodology gap, not a bug report.

**Likely cause.** N/A.

**Severity.** Process risk, not a functional bug. The specific bug this pass
did find (order duplication, see `CLEANUP_REPORT.md` bug 1) was caught by
tracing code, which shows tracing works — but it can't catch everything an
actual play session would (timing feel, visual glitches, input edge cases
that only show up with real key-repeat behaviour, frame-rate-dependent
issues).

**Suggested next step.** Work through `TEST_CHECKLIST.md` in the editor.
Anything that fails is worth a follow-up bug report with the exact repro
steps.

---

## 2. `StockDevPanel`'s shipping guard is coarse and unconfirmed against a real export

**Symptoms.** None observed directly.

**Likely cause.** The fix added in this pass (`OS.is_debug_build()`) is the
standard Godot idiom for "don't run this in a release export," and matches
Godot's own documented semantics. But it was verified by reading Godot's
documentation, not by actually producing a release export template and
confirming the panel is absent — that step needs the editor.

**Severity.** Low. Worst case if the guard doesn't behave as documented: the
dev panel would still be reachable via F10 in a shipped build, which is a
QA/exposure concern, not a data-loss or crash risk.

**Suggested next step.** Do a release export and confirm F10 does nothing.

---

## 3. `docs/CONFIGURATION_GUIDE.md` (the project's own internal doc, not this
   deliverable) predates the stock/order/delivery system

**Symptoms.** The existing `docs/CONFIGURATION_GUIDE.md` (613 lines) has no
mention of `OrderManager`, `SupplierDefinition`, `DrinksStation` or
`StockStorage` at all.

**Likely cause.** That document was written before the stock, storage,
ledger and delivery systems existed, and was never updated when they were
added.

**Severity.** Low-to-medium. Not a functional bug, but it means the project's
own internal configuration reference is now misleading by omission for
anyone editing stock/economy balance who doesn't know to look elsewhere. The
root-level `CONFIGURATION_GUIDE.md` produced by this cleanup pass **does**
cover these systems fully, so nothing is actually undocumented — it's just
in two places with different coverage.

**Suggested next step.** Fold the stock/order/delivery sections from the new
root `CONFIGURATION_GUIDE.md` into `docs/CONFIGURATION_GUIDE.md`, or retire
one of the two documents, so there's a single source of truth.

---

## 4. Pre-existing uncommitted changes in the working tree

**Symptoms.** `git status` shows several files modified relative to the last
commit that this cleanup pass did not touch: `scripts/Interactables/drinks_station.gd`,
`scenes/furniture/drinks_station.tscn`, `project.godot`, and several
`Data/**.tres` resource files.

**Likely cause.** Normal in-progress work from before this project was
handed over for cleanup — nothing about it looks accidental or broken, it
simply predates this pass.

**Severity.** None identified — flagged purely so it isn't mistaken for
something this cleanup introduced. This pass left all of it alone, per the
brief's instruction not to redesign working systems.

**Suggested next step.** Review and commit (or discard) that pre-existing
diff on your own schedule; it's unrelated to this cleanup.

---

## 5. No automated regression tests beyond `tests/item_system_tests.gd`

**Symptoms.** N/A — this is a coverage gap, not a bug.

**Likely cause.** The project has one manual test scene covering the item
system. Nothing automated covers orders, deliveries, the pause stack, or the
customer state machine.

**Severity.** Low for a project this size, but worth naming since the brief
asks for reliability and future expandability. The order-duplication bug
found in this pass (`CLEANUP_REPORT.md` bug 1) is exactly the kind of thing
an automated test (submit an order, fill storage, advance time twice, assert
quantity delivered) would have caught immediately and would prevent from
regressing.

**Suggested next step.** Consider extending `tests/item_system_tests.gd`'s
pattern to `OrderManager` once the order/delivery system's shape stabilises
further.

---

## 6. Areas this pass did not deeply re-verify at the code level

Listed for completeness, not because anything specific was found wrong:

- `scenes/furniture/table.tscn`, `chair.tscn`, `customer.tscn` node structure
  (checked the scripts that drive them; did not diff every node property).
- `HUD` (`scripts/UI/hud.gd`) — read for context, not audited line-by-line.
- `NavigationDebugger` (`scripts/Debug/navigation_debugger.gd`) — a debug
  visualisation tool; not exercised.
- Full multi-customer stress behaviour (many customers, many tables at once)
  — the per-customer logic was traced and looks correct, but only a live
  playtest can confirm behaviour under load.
