# Phase 2B.1 Change Report — Diagnostic Completion & Developer Tools

## Summary

Found and fixed the actual cause of the empty `completed_visits`/
`active_visits`/`decisions_by_customer_id`/`issues` fields: a scene-wiring
bug in `main.tscn`, not a logic error in the reporting code itself (see
"Root cause" below). With that fixed, the full report now populates
correctly. Also added three more of the brief's example anomaly checks,
two new F10 developer-panel buttons ("Serve all waiting drinks", "Clean all
tables"), and grouped the panel's now-larger button list under section
headers. No gameplay systems or customer activities were touched.

## Root cause

`CustomerAIReportManager`'s `diagnostics_config` export (a `Resource`, not
a `Node`) was incorrectly listed in the scene node's `node_paths` array,
which is exclusively for properties Godot resolves as NodePath-to-Node
references after the tree builds. The property's actual assigned value was
an `ExtResource`, not a `NodePath` - so Godot's deferred resolution step
never correctly applied it, and `diagnostics_config` stayed `null` at
runtime regardless of what `Data/customer_ai/diagnostics_config.tres`
said. Every report field gated behind `is_export_enabled()` (which checks
`diagnostics_config != null`) was therefore always empty; the session
summary's own counters still worked because those are incremented
unconditionally, by design, so basic totals remain available even with
detailed export off. One-line scene fix; see `CUSTOMER_AI_SYSTEM.md`'s
Phase 2B.1 section for the full explanation.

Also flipped `Data/customer_ai/diagnostics_config.tres`'s `export_enabled`
default to `true` (console logging stays off by default) - with the wiring
bug fixed, leaving this `false` by default would have made a next playtest
look like the fix hadn't worked, since nothing would populate until someone
found and flipped that setting.

## Files supplied

### New files

None. This pass fixed a wiring bug and extended existing files - it did
not need any new scripts or resources.

### Modified files (replace your copy with the supplied one)

| File | Destination |
|---|---|
| Main scene (the actual fix) | `res://scenes/main/main.tscn` |
| Diagnostics config default | `res://Data/customer_ai/diagnostics_config.tres` |
| Customer (new anomaly checks, `force_serve_now()`) | `res://scripts/Entities/customer.gd` |
| Stock dev panel (two new buttons, grouping) | `res://scripts/UI/stock_dev_panel.gd` |
| Customer AI architecture doc | `res://docs/CUSTOMER_AI_SYSTEM.md` |

## Files to remove

None.

## Installation guide

1. Copy the five files above into your project at the paths shown,
   overwriting the existing copies.
2. Open the project in Godot 4.7.1 and let it re-import.
3. Confirm no parser errors in the Output panel.
4. Play for 10-20 minutes with a few tables active, then press **F10** →
   **"Export Customer AI report."**
5. Open the resulting file from `user://customer_ai_reports/` (see the
   Windows path in `docs/CUSTOMER_AI_SYSTEM.md`) and confirm
   `completed_visits`, `decisions_by_customer_id` and (if anything actually
   went wrong) `issues` are now populated.

## New developer menu actions

- **Serve all waiting drinks** - instantly serves every active customer
  currently waiting for one, reusing the same validated serving logic
  `interact()` uses (chair hand-off, state change, scheduling, satisfaction
  gain, diagnostics, the `drink` activity's bookkeeping transition) minus
  only the player/carried-item check, which has no equivalent for a
  keyboard shortcut.
- **Clean all tables** - instantly resolves every chair's pending cleaning
  task via the existing `CleanableComponent`, the same component a real
  cleaning action already completes through. Occupied chairs are naturally
  unaffected, since a cleaning task only ever exists after a customer's
  reservation has already been released.

The panel is now grouped under **Customer AI** / **Simulation** /
**Stock & Economy** headers. Every existing button kept its exact prior
behaviour - only labels were added.

## Test procedure

1. Play normally for several minutes with diagnostics export on (now the
   default) and a few customers completing full visits.
2. Press F10 → "Export Customer AI report."
3. Open the JSON file and confirm: `completed_visits` has one entry per
   customer who left, each with real spawn/departure times, money, thirst,
   satisfaction and intoxication values (not placeholders); `active_visits`
   lists anyone still in the tavern at export time; `decisions_by_customer_id`
   has an entry per customer with a capped history of real decisions,
   including forced ones (`was_forced: true`, e.g. patience or visit-time
   expiry) distinguished from normal utility choices; `issues` is empty if
   nothing unusual happened during the session.
4. Press F10 → "Serve all waiting drinks" while at least one customer is
   mid-order; confirm they proceed to drink, pay, and continue their normal
   post-drink decision exactly as if the player had served them.
5. Dirty a few chairs (let some visits complete normally), then press
   "Clean all tables" and confirm they become available for new customers
   immediately, while any currently-occupied chair is untouched.
6. Confirm the project still loads with no parser errors and no missing
   resources.

## Known limitations

Three of the brief's example issue types - a chair lost unexpectedly, a
customer remaining active after visit-time expiry, and an activity timeout
- are not implemented. Each would require either continuous polling
(which this system deliberately avoids) or detecting the absence of an
expected event, which none of the current event-driven hooks can do
reliably. Implementing a plausible-looking check for these without a
reliable signal to hang it on would risk exactly the kind of fabricated
diagnostic the brief explicitly warns against - see
`docs/CUSTOMER_AI_SYSTEM.md`'s Phase 2B.1 section for the full reasoning.
