# Durable Decisions

Decisions that should not be re-litigated unless new evidence justifies change.
Each says what was decided and, where it matters, why.

## 1. Git is the source of truth

The repository is authoritative for current implementation. Chat is for
exploration; durable conclusions belong in repository documentation.

## 2. Data-driven architecture

Balance and reusable definitions are Resources or configuration — customer
types, drinks, activities, actions, containers, serving formats, suppliers,
global config. Adding a drink or a container should not require new branches in
behaviour scripts.

## 3. One authoritative owner

Verified owners as of `825add8`:

| State | Owner |
|---|---|
| Money | `EconomyManager` |
| World time | `WorldTime` autoload |
| Simulation state | `Simulation` autoload |
| Day lifecycle | `Tavern` autoload |
| Staff work | `TaskBoard` autoload |
| Communication | `Comms` autoload |
| Stacking modifiers | `Modifiers` autoload |
| Item movement | `ItemTransferService` |
| Beverage stock | `BeverageStorage` instances |
| Station → stock mapping | `StationStockPlan` |

`StockedDisplay` is a **view** of storage, never an inventory. Two readings of
one quantity is the specific failure mode this rule exists to prevent — it has
occurred twice on this project, once in the game and once inside the diagnostic
system itself.

## 4. Customer AI uses activities

Customer behaviour moves toward activity/utility-driven selection rather than a
growing state machine. New behaviours use the existing activity framework.

## 5. Customers have meaningful visits

Not order → drink → leave. Visit duration emerges from state, needs, activities
and service, not a blunt timer.

## 6. Chairs belong to the broader visit

A chair stays reserved for the customer's visit rather than being released after
one drink.

## 7. Staff reuse player gameplay APIs

Staff perform real actions through authoritative systems rather than setting
outcomes directly.

## 8. World time uses the authoritative time system

World progression uses `WorldTime`, not ad-hoc timers.

## 9. Navigation uses the reusable framework

Never disable navigation or avoidance to fix congestion or arrival problems.
Approach points are resolved by `NavigationService.project_to_mesh_from()`,
which finds a point that is *interior* (holdable under avoidance) and
*reachable*, not merely on the mesh. Biasing an approach toward the approaching
actor is specifically forbidden: it makes the answer depend on where the worker
stands and once sent the bartender to the wrong side of his own bar.

## 10. Interaction is generic

The player hard-codes no knowledge of interactables. The framework selects an
action; the target performs the domain work.

**Consequence:** one interactable currently offers one action, so a station
serves one drink. Multi-drink stations need a secondary-action UI first.

## 11. Item movement is centralised

Use `ItemTransferService`; do not mutate slots or containers directly.

## 12. Diagnostics precede balance claims

Before changing behaviour, check stock, staffing, run duration, sample size,
spawn count, prerequisites, assertion count and instrumentation. If repeated
tuning has little effect, instrument instead.

## 13. Small changes before rewrites

Prefer narrow fixes that preserve the architecture. A redesign must be justified
by the design requirement, not by the code being interesting.

## 14. Tavern feel takes priority

The game should feel like a tavern simulation even where an arcade-style
implementation would be simpler.

## 15. Design and implementation are separate stages

ChatGPT for design and second opinions; Claude Code for repository work; the
repository documentation is the bridge. See `AI_WORKFLOW.md`.

## 16. Ale is retired but retained

Small Beer replaced Ale as an active poured drink. Ale resources are kept
because the group keg chain still references them. Do not delete them; do not
reintroduce Ale to customer menus.

## 17. Diagnostics observe, never re-implement

The diagnostic layer queries authoritative systems and reports what they hold.
No diagnostic-only quantities, drink mappings or order mappings. A validator
that can only ever report PASS is indistinguishable from one that cannot fail —
`diagnostic_export_probe` therefore injects real faults and asserts they are
caught.

## 19. Cross-activity influence is soft-scored data, not a state machine

A customer's next choice can be nudged by what they just finished (e.g.
drink → socialise) through a scoring condition reading
`ActivityContext.last_activity_id`, not a hard sequence or a ban. This keeps
`CustomerBrain.think()`'s competitive-scoring model as the one decision
mechanism customers ever use — adding influence never means adding a special
case to it.

## 20. Multi-participant activities reuse the reservation framework

An activity needing more than one participant (Darts: 1–2) gets a second
`TavernActivitySlot` on its `TavernActivityPoint` and an
`ActivityDefinition.max_participants` value, not a new coordination
mechanism. A future card table or gambling activity is the same pattern with
a different participant count and its own slots. Deliberately excluded: a
waiting/matchmaking system — no partner nearby at decision time means
playing solo, not waiting.

## 21. Changing decisions

When a decision changes: update this file, update the affected system docs,
explain why it changed, implement, and commit documentation with implementation
where practical.
