# Phase B Verification Pass

Follow-up to `2026-08-25_CUSTOMER_ARCHITECTURE_AUDIT.md` and the Stage 2-4
implementation it led to (commits `ac6f52d` through `2d3ff82` on
`feature/phase-b-customer-model`). That implementation pass fixed a real
bug (darts occupancy was zero due to a slot-parent-resolution defect dated
to `a6e8993`, see `CURRENT_STATE.md`'s Known issues) and made `leave`
genuinely merit-based at stage 1. This pass re-verifies the ten
requirements `docs/CUSTOMER_MODEL.md` sets, against the current code, with
fresh measurement rather than carried-forward numbers.

Base for this pass: `2d3ff82`. Changes made: `6b51832`, `6641eaf`,
`059f1ff` on the same branch.

## Method

Each of the ten requirements was checked by reading the current
implementation directly, not by recalling the audit's findings — the audit
predates the slot-bug fix and the needs inversion, so several of its
numbers no longer apply. Two fresh instrumented runs were used as
evidence: `darts_score_probe.tscn` (240 game-seconds, motivation-gated
scoring) and `phase_b_measurement_probe.tscn` (240 game-seconds, real
diagnostic export, plus five complete individual customer decision
histories pulled from `CustomerAIReportManager._decisions_by_customer` -
data that was already being recorded every run and simply never read).

## Item-by-item

**1. Decision model hierarchy.** Confirmed unchanged and correct.
`CustomerBrain.think()` still runs stage 1 (terminal activity vs the true
unfiltered best, tracked via `is_terminal` not a hard-coded id) before
stage 2 (`_select_motivation()`) before stage 3 (motivation-filtered
scoring), with weighted selection among near-equal candidates preserved
and mandatory activities exempt from it. No changes needed.

**2. Needs as demand values, decoupled from decision count.** Fixed this
pass. `CustomerNeeds.update_motivational_needs()` previously bumped
`social`/`entertainment`/`relaxation` by a flat amount every time
`think()` happened to run, so a customer whose brain was polled more often
(e.g. mid-conversation interruptions) had needs rise faster for no
in-fiction reason. It now takes `current_world_minutes` and rises on a
genuine asymptotic time curve, the same shape `remaining_visit_minutes`
already used. One decision no longer equals one need increase.

**3. Activities declare what they satisfy (extension test).** Fixed this
pass. `ActivityDefinition.satisfies` was already the filter `CustomerBrain`
reads for stage 3, but two of three leisure activities still wrote their
completion-time need delta from a *second*, hand-authored number:
`SocialiseAtSeatBehaviour.social_gain` and `TavernActivityPoint
.entertainment_effect`/`.social_effect`. Both fields are removed; both
paths now read `satisfies` directly, matching what `RelaxAtSeatBehaviour`
already did. `satisfies` is now the single place a need/activity
relationship is declared, both for filtering and for the actual write-back
- the two-readings-of-one-fact problem `DECISIONS.md` §17 warns about no
longer exists here. Two remaining `== &"leave"` comparisons in
`CustomerBrain.think()` were replaced with the `is_terminal` flag.

**4. Awareness (minimal, reusable).** Fixed and proven this pass.
`NearbyActivityInUseCondition` existed already but its "which reservables
of this tag are occupied" query was embedded inside the one condition
class - not reusable by anything else, despite the brief asking for a
*foundation*. Extracted to `DestinationBroker.get_occupied()`, mirroring
the existing `has_available()`. Proof: `awareness_contribution` in
`darts_score_probe`'s contribution breakdown went from **0.00 across 478
samples** (previous, contaminated measurement) to **0.02 mean across 820
samples** in a clean run this pass - small on average because it is zero
whenever nobody is already there, exactly as designed, but genuinely
nonzero and traceable to specific samples where it fires.

**5. Groups bias, do not dictate.** Confirmed unchanged and correct.
`GroupManager._ask_member_brain()` calling `brain.think()` is still the
live path for every member with a configured brain; the old list-driven
`_start_leisure_activity()` dictate path only runs when a member has no
brain (test-harness scenes only). A member's own needs, personality and
awareness reach the decision as scoring inputs, not as a separate group
choice.

**6. Lingering as default.** Confirmed sound, `is_committed()` now wired
in (was previously computed and never read - see item 2 of the prior
implementation pass). Darts is not artificially dominant: in this pass's
`darts_score_probe` occupancy tally, `order_drink` + `drink` account for
388 of 513 recorded activity-entries against 16 for darts - drinking
dominates, matching `CUSTOMER_MODEL.md`'s explicit non-goal ("most
customers, most of the time, should drink and talk").

**7. Customer Inspector.** Field list re-checked against
`CUSTOMER_INSPECTOR.md`'s exact developer-tier list - everything was
already present except the visit history, which is added this pass.
`Customer._visit_history` (small, in-order, appended from all three
activity-completion handlers) feeds
`CustomerInspectionData.visit_history`, rendered in `to_display_text()`.
Deliberately not `VisitRecord.recent_activity_history` - that field is
only populated while `CustomerAIReportManager.is_export_enabled()` is
true, so it is empty for ordinary debug-build play; the inspector needs to
work any time in a debug build.

**8. Diagnostic traceability.** Confirmed the infrastructure already
existed and already satisfies the requirement -
`CustomerBrain`/`CustomerAIReportManager` were already recording a full
`DecisionRecord` per decision (needs at that moment, motivation, every
scored candidate, selected, rejection reasons, execution outcome) and
retaining up to 200 per customer (`_decisions_by_customer`), unconditional
on export mode being active for the *current* inspection (only gated on
`diagnostics_config.export_enabled`, which is on by default in
`main.tscn`). This data was being collected and never read except through
the live inspector's single most-recent decision. `phase_b_measurement_
probe.tscn` now dumps the five longest visits' complete decision
sequences, reusing this existing data rather than adding a second tracking
mechanism. `TavernActivityPointValidator`'s startup scan remains in place,
unchanged.

**9. Do-not-add-yet list.** Respected. No food, gambling, cards, new
activities, information/rumour/dialogue/relationship content, or
player-facing disclosure was added. `NearbyActivityInUseCondition` remains
generic by `tags: Array[StringName]`, not darts-specific, but is only
instantiated once (darts) since nothing else is tagged yet.

**10. Proof before tuning.** Done this pass - see Findings below. This is
the one item with a genuine, evidenced open question rather than a clean
confirmation.

## Findings from the controlled run

Full report: `phase_b_measurement_probe.tscn`, 240 game-seconds, 42
completed visits.

```
departure - chose to leave: 4   visit time ended: 8   out of patience: 0   other forced: 30
realised visit length - median: 67.0 min   max: 143.0 min
NO ACTIVITY AT ALL (relax + socialise + tavern all zero): 33 / 42  (78.6%)
ACTIVITY STARTS PER CUSTOMER: 16 starts / 42 completed visits = 0.38 per customer
GROUPS: group activity participation 6.7% (2 / 30 member-visits)
```

**The good news, visible only in the individual histories, not the
table.** Five complete decision sequences were read start to finish (not
sampled). Two of five show genuinely non-monotonous, believable visits:
customer 2 (90 minutes) goes order → drink → relax → socialise → relax →
socialise → darts → (idle tick) → return-to-seat → leave-by-timer;
customer 6 (90 minutes) goes order → drink → order → drink → relax →
(idle tick) → darts → relax → **leave**, where the leave decision beat
darts on score (8.2 vs nothing better available) rather than winning by
exemption. Customer 1's eventual leave at minute 143 beat
`visit_tavern_activity` 14.1 to 11.9 - a real, close, merit-based contest,
not the "leave wins because its rivals were filtered out" pattern the
audit found and Stage 2 item 4 fixed. This is what stage 1/2/3, the
`satisfies` inversion and awareness were supposed to produce, and in these
traces they do.

**The open question.** The aggregate "no activity at all" figure (78.6%)
is essentially unchanged from what the withdrawn 78.5% figure looked like
before the slot-bug fix, the leave fix, the needs inversion and the
time-decoupling all landed - despite all four of those being real,
verified fixes. The individual histories show why: `order_drink` is
`is_mandatory = true`, which correctly exempts it from the stage-3
motivation filter (a customer must be able to reorder regardless of what
they currently "want" most) - but its own score is not primarily
thirst-driven. `order_money_scoring.tres` reads raw `wealth` at
`score_weight = 0.25` (uncapped - `£40` alone is worth +10, more than
thirst's entire range) and `order_visit_time_scoring.tres` reads raw
`remaining_visit_minutes` at `score_weight = 0.06` (uncapped - two hours
left is worth +7.2), while `order_thirst_scoring.tres` caps at
`score_weight = 6.0` against the normalised `thirst` (range 0-6 total).
Several traced decisions show this directly: customer 1 at minute 1095,
`thirst=0.02`, still picks `order_drink` at score 18.4 over
`visit_tavern_activity` at 13.7; customer 5 at minute 1091, `thirst=0.17`,
picks `order_drink` at 21.1 over `socialise_at_seat` at 16.9. A customer
with money and time left keeps re-winning the reorder contest almost
independent of whether they are actually thirsty, which crowds out
leisure activities even in the ticks where motivation has correctly
identified entertainment/relaxation/social as maxed out.

This is the same *class* of bug `DECISIONS.md` §20 already names twice -
raw wealth as a scoring input broke the leave decision; raw
`remaining_visit_minutes` distorted relax and was deleted outright in the
prior pass. This is a third instance, in `order_drink`, which predates
Phase B and sits outside its four target needs (thirst/social/
entertainment/relaxation) - it was never touched by this pass's condition
sweep because it is not one of the activities Phase B's `satisfies`
inversion covers.

**Not fixed in this pass.** Per the explicit instruction not to move into
broad tuning until the foundation is demonstrated: this is reported, not
corrected. The decision architecture, needs model, satisfies inversion and
awareness layer are all now verified working as designed - the individual
histories prove it for the customers that reach leisure activities at all.
What is still suppressing how *many* customers reach that point is
`order_drink`'s own scoring composition, not the Phase B systems this pass
covers. The natural next step, when tuning work is in scope, is the same
treatment `relax_visit_time_scoring` already got: normalise or cap
`order_money_scoring`/`order_visit_time_scoring` rather than reading the
raw context values directly, then re-run this same measurement to confirm
the "no activity" figure actually moves.

## What is proven vs still provisional

**Proven, with evidence, this pass:** two-stage decision hierarchy intact;
needs genuinely demand-shaped and time-driven, not decision-count-driven;
`satisfies` is the single source of truth for all three leisure
activities' need effects; awareness fires and is a reusable query, not
one-off logic; groups bias rather than dictate; `is_committed()` is live;
the inspector's field list is complete; per-customer diagnostic trace data
was already complete and is now actually surfaced; leave is a genuine
merit-based contest, not a default win; darts occupancy is non-zero and
customers who reach leisure activities show believable, non-scripted
variety across a full visit.

**Still provisional:** the tavern-wide *rate* at which customers reach any
leisure activity at all. The architecture works; something outside this
pass's scope (order_drink's own raw-value scoring) is the currently
dominant reason most customers don't exercise it. `CUSTOMER_MODEL.md`'s
"what working looks like" scene (a sailor joins darts, a crewmate stays,
someone starts a second drink) is demonstrated in miniature in 2 of 5
sampled full visits - not yet the tavern-wide norm.
