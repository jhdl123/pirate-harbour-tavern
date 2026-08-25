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

## 18. Changing decisions

When a decision changes: update this file, update the affected system docs,
explain why it changed, implement, and commit documentation with implementation
where practical.

## 19. Customer decisions are two-stage

A customer decides **what it currently wants**, then **which available thing
serves that want**. Activities do not all compete in one flat utility pool.

Why: measured at `235b7ac`, `relax_at_seat` beat darts in 321 of 528 samples
where darts was eligible. In a flat contest sitting still is a legitimate
winner over doing something, and no weight fixes that — it only changes which
activity wins the same contest. See `CUSTOMER_MODEL.md`.

## 20. Needs are demands, not happiness

A need expresses what would currently be valuable to a customer. Low `social`
does not mean unhappy; it means company is not worth much right now. Mood and
satisfaction are separate and already exist — do not merge them.

**All needs are normalised 0.0–1.0.** Raw-valued needs have caused two
multi-session bugs: `wealth` as a raw coin count made leaving impossible, and
`remaining_visit_minutes` as raw minutes gives a customer +2.75 for sitting
down. Raw quantities are exposed as context values, never as needs.

## 21. Activities declare what they satisfy

Conditions read needs; activities advertise what they give back. Adding an
activity — cards, gambling, food, a musician — should be one activity resource,
one behaviour and a destination. No new condition resources, no re-balancing of
existing activities, no brain changes. This is the acceptance test for the
customer model, not an aspiration.

## 22. Groups bias members, they do not dictate

A crew is more likely to socialise or play together, and any member can still
peel off for their own reasons. Group context is a scoring input, never a
separate code path.

## 23. Lingering is the default

Staying is normal; a customer does not justify not leaving. Departure is a
decision that becomes gradually more likely under time, money, satisfaction,
group departure and closing. The visit timer is a backstop, not the mechanism.

## 24. Most customers do ordinary things

Explicitly rejected: a tavern where everyone is always doing an activity. In a
real tavern most time is drinking and talking and darts is occasional. A
theme-park result is a worse outcome than the current one, not a better one.

## 25. Inspection UI reads a snapshot

`Customer → CustomerInspectionData → CustomerInspectorUI`. The UI never reads
customer internals, needs, the brain or the registry directly. Same rule and
same failure mode as §3's `StockedDisplay`. This exists so the decision
architecture can change again without touching UI.
