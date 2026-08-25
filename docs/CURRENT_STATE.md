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
**Gap:** much of this depth is not visible to the player — narrowed by
Phase B's developer-tier inspector (below), still not player-facing.

### Customer AI — inspector (Phase B, developer tier)
`Customer.get_inspection_data() -> CustomerInspectionData`, rendered by
`CustomerInspectorUI` (`systems/customer_ai/inspection/`) — needs, current
motivation, candidate scores, rejection reasons, execution outcome, group
membership. `CustomerBrain.get_last_decision()`/`get_last_execution_outcome()`
are new, un-gated per-customer caches (populated regardless of
`report_manager`/export state). Reached via select (not hover — documented
deviation, `DECISIONS.md` §10/§26) through the existing `Interactable`
framework, one `&"inspect"` action, gated behind `OS.is_debug_build()`.
Group role is simplified to "member" (no leader/non-leader distinction yet —
`Customer` has no back-reference to its `CustomerGroup`).

### Customer AI — activity selection, Phase B two-stage decisions (2026-08-25)
The flat-pool problem measured at `235b7ac` (below, kept as history) is
addressed: `CustomerBrain.think()` now picks a motivation
(`thirst`/`social`/`entertainment`/`relaxation`) before scoring, and a
non-mandatory activity only competes when its `ActivityDefinition.satisfies`
serves that motivation. Full design in `CUSTOMER_MODEL.md`, implementation
detail in `docs/CUSTOMER_AI_SYSTEM.md`'s "Phase B" section, verdicts and plan
in `docs/history/2026-08-25_CUSTOMER_ARCHITECTURE_AUDIT.md`.

**Isolated before/after for the single most distorting fix** (deleting
`relax_visit_time_scoring.tres`, which scored a raw minute count directly -
`tests/darts_score_probe.tscn`, same commit, this one change only): darts'
"would be top scorer when eligible" went from 54/504 (10.7%) to 229/469
(48.8%).

**Full Stage 2 state** (`tests/darts_score_probe.tscn`, motivation-gated
pool): darts eligible-and-motivation-matched 257 samples, would be top
scorer in 184 of them (**71.6%**), beaten by `order_drink` 58,
`socialise_at_seat` 13, `leave` 2. `CustomerNeeds.engagement` is retired,
split into `social`/`entertainment`/`relaxation` fed by the activity that
used to raise the shared pool; raw values (`wealth`,
`remaining_visit_minutes`, repeat counters) are no longer reachable through
`get_need()`/`set_need()` at all, only through a separate
`get_context_value()` pair.

**Stage 4 table** (`tests/phase_b_measurement_probe.tscn`, 240s run, 65
completed visits, 10 distinct groups):

| Metric | At `235b7ac` | After (this run) |
|---|---|---|
| chose-to-leave vs visit-time-ended | 13 vs 30 | **16 vs 18** |
| realised visit length (median / max) | 65.0 / 218.0 | 52.0 / 99.0 |
| solo service rate | 53.3% | 71.7% |
| group activity participation | 33.3% (6 groups) | 8.6% (10 groups) |
| order_drink share of customer time | ~28–35% | 24.3% |
| did no activity at all (relax+socialise+darts) | not previously tracked | 51/65 (78.5%) |

Read with the brief's own measurement traps in mind: this run has 10 groups,
still under the ~14 needed for group-level numbers to stop being noisy, and
a 240s/65-visit sample is short enough that occupancy (as opposed to the
scoring-contest numbers above, which have much larger sample sizes) is not
reliable — darts' actual occupancy in this run's 2-second activity-time-share
sampling was 0, consistent with the "occupancy counts in the tens are noise"
warning rather than a contradiction of the scoring-contest result. The
chose-to-leave/visit-time-ended balance improving and group participation
dropping are both worth a longer confirming run before either is treated as
settled.

**"No activity at all staying substantial is the intended non-theme-park
result, not a shortfall"** (previous wording of this line) turned out to be
only half right. The slot-parent-resolution bug fixed later this pass meant
darts occupancy above was a false zero, not a measured one — see Known
issue 9. `docs/history/2026-08-25_PHASE_B_VERIFICATION_PASS.md` re-ran this
measurement after that fix plus the needs/awareness/leave-stage-1 work
landed: "no activity at all" is still 78.6% (33/42), essentially unchanged.
Reading five complete individual customer histories (not sampled — the full
decision sequence) shows the architecture genuinely works: 2 of 5 show
believable, non-monotonous relax/socialise/darts variety across a full
visit, and leave now wins on merit. What is suppressing the tavern-wide
*rate* is identified and traced: `order_drink` (outside Phase B's scope)
scores from raw `wealth`/`remaining_visit_minutes`, uncapped, alongside a
capped thirst term — the same raw-value defect class as the
`relax_visit_time_scoring` fix below, not yet applied to `order_drink`. Not
fixed this pass; see the verification pass doc for the full trace and why.

Extension test re-measured: a hypothetical new point-based leisure activity
needs one `ActivityDefinition.tres` and one `TavernActivityPoint` scene, zero
new condition resources - the four conditions every existing leisure
activity's baseline needs (`is_settled`, `not_transacting_at_bar`,
`visit_activity_availability`, `decision_variance`) are already shared,
reusable instances, and `VisitTavernActivityBehaviour.gd` already runs any
point-based activity generically. Darts needed 12 condition resources at
`235b7ac`; `relax_at_seat.tres` is down to 6 from 9 (two conditions -
the raw-minute one above, and one rewarding relax for already being
relaxed, backwards once `relaxation` became a demand-shaped motivation
input - were deleted, not reweighted).

#### History: the problem as measured at `235b7ac`, before Phase B

`visit_tavern_activity` (darts) was **eligible in 37.2% of customer-samples
and occupied 1.2% of customer time**. It was not gated out — it lost the
scoring contest. Of 528 samples where it was eligible it would have won 52;
it was beaten by `relax_at_seat` 321 times, `order_drink` 117 and
`socialise_at_seat` 38, and was on cooldown only 20. Mean score when
eligible: `order_drink` 20.76, `socialise_at_seat` 12.51, `relax_at_seat`
12.43, darts 10.20, `drink` 8.00, `leave` −9.62.

Mean contribution breakdown, relax 12.25 vs darts 9.99: darts started a
point ahead on base utility (8.50 vs 7.50) and still lost. The dominant term
was `relax_visit_time_scoring`, `score_weight = 0.05` against
`remaining_visit_minutes` — a **raw minute count, not a 0–1 need** — worth
+2.72 mean, against darts' visit-time condition which gated only and scored
0.00. This was the same raw-vs-normalised defect that broke the leave
decision with `wealth` in Phase A part 5; both are now fixed the same way
(see Phase B above).

Secondary: darts' distance bonus averaged +0.39 of a possible 4.0 — both
`DartsPoint` nodes are at (82,452)/(156,452) against tables at (448,319) and
(696,317), so the 600px falloff barely reaches table 2 (still true, not
addressed this pass — a level fix, not a code fix). Relax also had a
3-minute commitment floor and 6-minute cooldown against darts' 5 and 12.

Also confirmed: `is_committed()` in `customer_brain.gd` was never called, so
commitment did not gate `think()` — wired in as part of Phase B (see above).

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
9. **Darts was unplayable on `main` from `a6e8993` (2026-08-24) until fixed
   in this Phase B pass, independent of Phase B itself and independent of
   the flat-pool problem Phase B was built to address.** `a6e8993` came
   *after* `235b7ac` (confirmed by ancestry, not assumed) - the 37.2%
   eligible → 1.2% occupancy figures measured at `235b7ac` predate this bug
   entirely and reflect only the flat-pool scoring loss (darts losing to
   `relax_at_seat`), not this. `a6e8993` moved darts' `Reservable` one
   nesting level deeper (child of a new `TavernActivitySlot` rather than
   direct child of `TavernActivityPoint`, for the two-slot model), so
   `VisitTavernActivityBehaviour.on_enter()`'s `reservable.get_parent() as
   TavernActivityPoint` cast always returned null from that commit forward.
   Every darts selection was silently abandoned in the same instant it was
   entered (`abandon_activity_visit(
   "reserved_destination_not_a_activity_point")`). By the time Phase B
   started, darts was doubly broken: losing the scoring contest *and*
   unable to execute even on the rare win. Two-stage decisions (this pass)
   fixed the first; fixing the second was necessary to observe the first
   fix actually working. Nothing surfaced the execution failure because
   nothing reads `report_issue()` calls at startup or in normal play - the
   fourth time on this project a computed failure signal was discarded
   before reaching a surface, see `LEARNING_LOG.md`'s Architecture section.
   Fixed via an explicit `TavernActivitySlot.point` back-reference rather
   than a parent-walk; `darts_point.tscn` is the only scene using
   `TavernActivityPoint`, so nothing else carried the same defect.

`docs/history/KNOWN_ISSUES.md` holds a longer, older static-audit list from
an early cleanup pass; parts of it are now stale.

## Diagnostic lessons that keep recurring

Apparent AI faults have repeatedly turned out to be insufficient stock,
inadequate staffing, short runs, too few groups, task churn, or missing
instrumentation. Establish prerequisites and sample size before judging
behaviour.
