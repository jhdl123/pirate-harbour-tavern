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

## 26. Phase B implementation status (2026-08-25)

§19-25 are implemented, not just decided. Notes on how, for anyone
reconciling this file against the code:

- Two-stage decision lives inside the existing `CustomerBrain.think()` and
  `ActivityRegistry` exactly as the audit predicted - no replacement was
  needed. `ActivityDefinition.satisfies` (need id → amount) is the
  declarative field; a non-mandatory candidate whose `satisfies` does not
  serve the motivation `CustomerBrain._select_motivation()` chose is
  excluded before scoring. Mandatory activities and Wander (empty
  `satisfies`) are exempt, matching how they already bypassed cooldown/
  commitment.
- `CustomerNeeds.engagement` is retired. It is split into `social`/
  `entertainment`/`relaxation` (§20's remaining three named needs), each
  fed by the activity that already raised the old shared pool.
  **Corrected in the 2026-08-25 verification pass:** these three are now
  genuinely demand-shaped like `thirst` - motivation selection reads the
  need value directly, not `1.0 - value`. They rise on an asymptotic time
  curve (`CustomerNeeds.update_motivational_needs(current_world_minutes)`)
  and fall when the activity that serves them (via `satisfies`) completes.
  The rise is now driven by elapsed world time, not by how often
  `CustomerBrain.think()` happens to be called - see
  `2026-08-25_PHASE_B_VERIFICATION_PASS.md` item 2.
- Raw values (`wealth`, `remaining_visit_minutes`, `visit_duration_minutes`,
  the repeat counters) are no longer reachable through
  `CustomerNeeds.get_need()`/`set_need()` at all - a separate
  `get_context_value()`/`set_context_value()`/`adjust_context_value()` pair
  exists for them, and `NeedThresholdCondition` needs an explicit
  `value_is_context = true` to read one. Misconfiguring this now produces a
  loud warning instead of silently working, which is the type-level
  distinction this file's raw-value lesson always needed.
- `relax_visit_time_scoring.tres` is deleted outright, not reweighted - it
  scored a raw minute count directly and was the measured cause of relax
  beating darts. Isolated before/after: darts' "would win when eligible"
  went from 10.7% to 48.8% from this one change alone (`tests/
  darts_score_probe.tscn`, both runs this session).
- §10's "the framework should not be bypassed" is honoured with one
  documented deviation: the customer inspector uses select-to-inspect
  through the existing `Interactable`/`InteractionSelector` pipeline
  (customers already carry an `InteractionArea`), not true mouse hover.
  Hover would need a second, screen-space picking system the existing
  reach-based framework does not provide; select reuses 100% of it. Gated
  behind `OS.is_debug_build()`, same as the F10 panel.
- The `DecisionRecord` a hover/select panel needs (candidate scores,
  rejection reasons, motivation, execution outcome) is now cached
  unconditionally on `CustomerBrain` (`get_last_decision()`) rather than
  only existing when `report_manager.is_export_enabled()` - the aggregate
  export path is unchanged and still gated the same way.

**2026-08-25 verification pass** (`2026-08-25_PHASE_B_VERIFICATION_PASS.md`)
re-checked all ten `CUSTOMER_MODEL.md` requirements against the code
directly rather than trusting the numbers above, which predate the slot-
bug fix. `ActivityDefinition.satisfies` is now the *only* place a need/
activity relationship is declared - `SocialiseAtSeatBehaviour.social_gain`
and `TavernActivityPoint.entertainment_effect`/`.social_effect` (described
above) are removed; both paths read `satisfies` directly, same as relax
already did. `DestinationBroker.get_occupied()` extracts the awareness
layer's occupancy query so it is a reusable foundation method, not logic
embedded in one condition. The inspector gained a small always-on visit
history (`Customer._visit_history`), deliberately not reusing
`VisitRecord.recent_activity_history`, which only exists during an active
diagnostic export. One finding from this pass - `order_drink` scoring from
raw `wealth`/`remaining_visit_minutes` - was not fixed here; it was the
trigger for the systematic audit in §27, which fixed it along with every
other instance of the same defect rather than just this one.

## 27. Scoring inputs need an explicit, bounded scale, not just a raw/need label

`2026-08-25_SCORING_AUDIT.md`. §20 already established that a need must be
0.0-1.0 and a raw quantity must go through `get_context_value()` instead of
`get_need()`. That type-level split turned out not to be sufficient on its
own: `NeedThresholdCondition.score()` still multiplied `score_weight`
directly against whatever `get_context_value()` returned, with no cap -
correct for a genuine 0.0-1.0 need (where the formula is safe by
construction) but not for a raw context value, which can be arbitrarily
large. Found independently in six resources (`order_money_scoring`,
`order_visit_time_scoring`, `leave_money_scoring`,
`leave_visit_time_scoring`, `socialise_visit_time_scoring`,
`leave_drinks_scoring`), each authored separately, none of them checked
against the others.

**Decision:** a condition that scores a raw context value must declare an
explicit, bounded scale for it - `NeedThresholdCondition.context_scale`,
the raw distance that maps to a full 1.0 fraction before `score_weight` is
applied, mirroring the clamp-then-scale pattern `NearestPointDistance
Condition`/`EndOfVisitPressureCondition` already used by hand. Not a
blanket "normalise every raw value to 0-1 everywhere" rule - `wealth` and
`remaining_visit_minutes` stay raw everywhere else in the codebase (gates,
display, `RepeatDecayCondition`'s exponential, distance falloffs); only the
one place that turns a raw value into a *score contribution* needs the
scale to be explicit and authored, not implicit in whatever `score_weight`
a resource happened to pick.

Also decided: a candidate that fails `CustomerBrain`'s stage-3 motivation
filter must never re-enter the pool weighted selection samples from, even
if its raw score is close to the filtered winner's. Found by reading full
individual customer histories rather than aggregates (`_select_weighted()`
was sampling from `eligible_for_report`, populated before the motivation
filter runs) - see `2026-08-25_SCORING_AUDIT.md` §7's headline finding.
**Fixed** (`2026-08-25_WEIGHTED_SELECTION_FIX.md`): a second list,
`stage3_survivors`, is populated at the exact point a candidate passes both
the `is_terminal` skip and the stage-3 filter - the same population `best`/
`best_score` are drawn from - and `_select_weighted()` now reads that
instead of `eligible_for_report`. `_select_weighted()` itself is
unchanged - it was already a correctly generic selector; the defect was
entirely in what the call site handed it. Isolated regression: 74/150
violations before, 0/150 after
(`tests/weighted_selection_regression_test.gd`); a full post-fix
transcript sweep found 0/29 real selections violating the filter, down
from 3 confirmed instances before.
