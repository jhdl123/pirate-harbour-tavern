# Systematic Scoring/Utility Audit

Follow-up to `2026-08-25_PHASE_B_VERIFICATION_PASS.md`, which traced the
`order_drink` occupancy-suppression finding to raw `wealth`/
`remaining_visit_minutes` fed directly into `NeedThresholdCondition.score()`.
That pass fixed only the two conditions it had already measured as broken.
This one is the systematic version: every scoring path `CustomerBrain` and
`ActivityDefinition` use, read in full, not just the ones already known to be
wrong.

Base: `25ac4dd`. Changes from this audit: `c30f467` (scoring contract),
`2c5f55d` (awareness diagnostic).

## Method

Read all 11 `ActivityCondition` subclasses (every scoring mechanism that
exists in the project) and all 46 condition resources under
`Data/customer_ai/conditions/`, extracting `need_id`, `value_is_context`,
`score_weight`, `gates` and `threshold` for each. Cross-referenced every
context-value `need_id` against `CustomerNeeds.get_context_value()`'s match
statement to confirm its real raw range, and against
`CustomerAIBalanceConfig` for a defensible, already-documented normalisation
range rather than an invented one. Also read `CustomerIdentity`'s bias
system and `SocialCompatibility` (used for partner-finding, not activity
scoring) to confirm they are not raw-value scoring paths of the same kind.

## 1. Every scoring input, tabulated

Condition classes that never touch a raw value are listed once, not
per-resource: `PreviousActivityAffinityCondition` (boolean trigger, flat
bonus), `ProbabilityCondition` (bounded `[0, score_weight]`),
`DomainFlagCondition` (boolean trigger, flat `score_bonus`, never a raw
scalar), and the three gate-only conditions with no `score()` method at all
(`CanAffordDrinkCondition`, `DestinationAvailableCondition`,
`DeterministicEntryOnlyCondition`). None of these can produce an unbounded
contribution by construction - excluded from the table below, not
overlooked.

| Input | Raw scale | Expected score scale | Normalisation | Cap/clamp | Sign | Weight | Should be a need? |
|---|---|---|---|---|---|---|---|
| `thirst` | 0.0-1.0 (already a need) | 0.0-1.0 | none needed | inherent (need is 0-1) | +/- per resource | 6.0 (order) / -3.0 (relax) / -1.5 (socialise) / -1.0 (darts) / -2.0 (leave) | Already is |
| `mood` | 0.0-1.0 (already a need) | 0.0-1.0 | none needed | inherent | +/- per resource | 4.0 (order) / 2.5 (relax) / 2.0 (socialise) / 1.5 (darts) / -5.0 (leave) | Already is |
| `intoxication` | 0.0-1.0 (already a need) | 0.0-1.0 | none needed | inherent | +/- per resource | -8.0 (order gate) / 1.5 (relax) / 1.0 (socialise) / 5.0 (leave) | Already is |
| `wealth` | int, unbounded in principle, £15-£45 typical starting range (`CustomerAIBalanceConfig`), observed £4-£62 mid-visit this session | should behave like a bounded influence, not dominate | **was: none** -> now `context_scale = 45.0` (`maximum_starting_money`) | **was: none** -> now clamped to `[0,1]` before weighting | + (order: more money -> more likely to reorder) / - (leave: more money -> less likely to leave) | 0.25 (order) / -0.3 (leave) | No - correctly a context value; the defect was the missing scale, not the raw/need classification |
| `remaining_visit_minutes` | float, 0 to ~90 authored (`maximum_visit_duration_minutes`), observed up to 218 with personality multipliers | should behave like a bounded influence | **was: none** on 3 of 5 uses -> now `context_scale = 90.0` on all 3; `EndOfVisitPressureCondition` and `visit_activity_min_time_remaining`'s gate-only use were already safe | **was: none** on order/leave/socialise -> now clamped; distance-style squared ramp already clamped on end-of-visit pressure | + (order, socialise) / - (leave) | 0.06 (order) / -0.1 (leave) / 0.03 (socialise) / 8.0 max (end-of-visit pressure, already safe) / 0.0 (gate-only, already safe) | No - correctly a context value; same fix as wealth |
| `drinks_consumed` | float count, 0 to `absolute_maximum_drinks_per_visit` (5) | small bounded influence | **was: none** -> now `context_scale = 5.0` | **was: none, but self-limiting today** since the drink-limit config keeps the raw value small -> now explicit | + (leave: more drinks -> more inclined to leave) | 1.2 | No - correctly a context value; was fragile (only safe because of a *different* system's cap) rather than actually fixed |
| `relax_count` / `socialise_count` / `darts_count` | float count, unbounded in principle, typically 0-3 per visit | diminishing-returns multiplier | exponential decay (`(1-decay_per_repeat)^repeats`), self-bounding by construction | inherent - converges toward 0, never past `-reference_utility` | - only (erodes, never boosts) | `decay_per_repeat` 0.15 default, `reference_utility` 6.0 | No - `RepeatDecayCondition`'s formula is the correct pattern; already safe, no change needed |
| distance (nearest free point) | pixels, 0 to map size | bounded bonus | `clampf(1 - distance/falloff, 0, 1)` then `* maximum_bonus` | explicit, already correct | + only | `maximum_bonus` 4.0 (darts distance) | N/A - not a need, already correctly normalised; the reference pattern every context-value condition should have followed |
| distance (nearest occupied point, awareness) | pixels, 0 to map size | bounded bonus | same clamp-then-scale pattern | explicit, already correct | + only | `maximum_bonus` 2.0 (darts awareness) | N/A - already correct, see item 4 below for its interaction with the distance condition above |
| `patience`, `energy`, `social`, `entertainment`, `relaxation` | 0.0-1.0 (already needs) | 0.0-1.0 | none needed | inherent | context-dependent | not currently read by any `NeedThresholdCondition` resource (`patience`/`energy` unused in scoring; `social`/`entertainment`/`relaxation` gate stage-3 motivation selection, not scored by a condition directly) | Already is |
| `group_cohesion_multiplier` (`VisitIntentConfig`) | 0.0-2.0, authored | n/a | n/a | n/a | n/a | n/a | **Not a scoring defect - dead code.** Declared and authored on all 9 `VisitIntentConfig` resources; grepped the entire `systems/` tree and nothing reads it. Not wired to anything, contributes nothing today. Flagged for whoever picks up group-cohesion work next, not fixed here - fixing it would be adding new behaviour, not correcting a scale defect. |
| `activity_score_offsets` / `motivation_weight_offsets` (`CustomerIdentity`/`VisitIntentConfig`) | designer-authored float, no `@export_range` bound | small bias, same order of magnitude as a condition's own contribution | none - static per-intent data, not derived from live customer state | none enforced, but not a live-state defect - an author picking an absurd number is a content-authoring risk, not the raw-value-scoring bug class this audit targets | either | designer's choice per intent | No - correctly not a need; low risk since it never reads a runtime quantity, only a hand-set table |
| `SocialCompatibility.score()` | n/a (already computed as a bounded score, not read as a raw value by any condition) | -1.0 to 1.0 | `clampf(total, -1.0, 1.0)` plus every sub-term already capped (`MAXIMUM_TAG_SCORE`, etc.) | explicit, already correct | both | n/a | N/A - not part of `ActivityDefinition` scoring at all (used for partner-finding only); included here as the *other* reference example of the contract done right |

## 2. The scoring contract

Fixed in `c30f467`. `NeedThresholdCondition` gains `context_scale: float`
(default `0.0` = unchanged legacy behaviour): when `value_is_context` is true
and `context_scale > 0.0`, the raw distance-from-`threshold` is clamped to a
`0.0-1.0` fraction of `context_scale` before `score_weight` is applied -
exactly the pattern `NearestPointDistanceCondition`/
`EndOfVisitPressureCondition` already used by hand for their own raw inputs.
`score_weight` now means the same thing in both the need case and the
context case: the contribution at full distance, not an unbounded per-unit
multiplier. This is deliberately **not** a global 0-1 normalisation of every
raw value in the project (per the brief: "do not globally normalise
everything... the important requirement is that the intended scale is
explicit and controlled") - `wealth` stays an `int`, `remaining_visit_minutes`
stays a raw minute count everywhere else in the codebase (display, gates,
`RepeatDecayCondition`'s exponential, distance falloffs); only the one place
that was silently multiplying an unbounded quantity by an arbitrary weight
gained an explicit, authored scale.

Every `score_weight` value in the six affected resources was left exactly as
authored - only what unit it is multiplied against changed. The resulting
behaviour change (order/leave/socialise's money and visit-time contributions
shrinking from double-digit swings to sub-single-digit ones) is the honest
consequence of the fix, not a tuning target chosen to hit a number.

## 3. Duplicate sources of truth

Re-confirmed clean. `CustomerBrain.think()` has zero hard-coded
`activity_id` comparisons (`grep` returned nothing); the only activity-
specific string anywhere in the brain is `force_activity(&"leave", &
"out_of_money")`, judged a business rule (running out of money always means
leave) rather than an extensibility concern. Every leisure behaviour
(`RelaxAtSeatBehaviour`, `SocialiseAtSeatBehaviour`,
`VisitTavernActivityBehaviour` via `Customer._on_activity_use_finished()`)
reads its completion-time need effect from `ActivityDefinition.satisfies`
alone - no stray gain fields remain (swept `systems/customer_ai/activities/
behaviours/` for `_gain\s*=\s*[0-9]` and found only the local variables that
already read from `satisfies`).

**Hypothetical `EatActivity` extension test, reasoned through rather than
built** (per the brief: use it as the test case, do not implement it):

- Serving an activity to an *existing* motivation (say, a second
  entertainment-need activity - a card table) needs exactly what
  `CUSTOMER_MODEL.md` §5 promises: one `ActivityDefinition.tres` declaring
  `satisfies = {"entertainment": X}`, one behaviour reading that dictionary
  the same way the three existing leisure behaviours do, one destination.
  Zero `CustomerBrain` changes. This is what this session's own darts/
  relax/socialise work already proves empirically, not just in theory.
- Serving a genuinely **new** need - `hunger`, which `EatActivity` would
  actually need - does **not** pass the same test today, and
  `CUSTOMER_MODEL.md` never claimed it would (§2 lists `hunger` as a
  "reserved name for later," not a zero-cost addition). The real touch
  points, traced precisely: a new `var hunger: float` field plus a `&
  "hunger"` case in both `CustomerNeeds.get_need()` and `.set_need()`'s
  match statements; a new `&"hunger": needs.hunger` key in
  `CustomerBrain._select_motivation()`'s weights dictionary (currently
  hard-coded to exactly four keys - thirst/social/entertainment/
  relaxation); and a new field on `CustomerInspectionData` plus a
  populate line in `Customer.get_inspection_data()` for the inspector to
  show it. Three real code changes, all outside `ActivityDefinition`/
  `ActivityCondition` itself, none of them a `CustomerBrain` change *about
  a specific activity* - the brain still never learns what "Eat" is, only
  that a fourth motivation now exists. This is the accurate boundary of
  the extension test: new activity within an existing need = free; new
  need = three small, known, generic touch points, never activity-specific
  ones.

## 4. Awareness proof

See `tests/awareness_diagnostic_test.gd` (commit `2c5f55d`) and its own
class doc comment for the full result. Summary: the occupancy signal is
real, exactly attributable, and isolated from every other contribution
(Part 1, 8/8 assertions pass). It measurably participates in a real
decision - raises darts' own score whenever someone is already there (Part
2) - but did not flip the winner against `socialise_at_seat` in the tested
near-tie case, because `NearestPointDistanceCondition` (falloff 600px, max
+4.0) and `NearbyActivityInUseCondition` (falloff 300px, max +2.0) are both
driven by the same physical distance, and distance's own floor wherever
awareness is still nonzero (>= 2.0) already matches awareness's ceiling.
Awareness is proven working, not proven dominant - an honest distinction
worth keeping, not a defect to fix in this pass (the brief explicitly asked
for "one behavioural diagnostic," not a rebalance of two conditions that
were each independently reasonable when authored).

## 5. Customer Inspector

Re-checked against `CUSTOMER_INSPECTOR.md`'s exact developer-tier field
list - unchanged since `2026-08-25_PHASE_B_VERIFICATION_PASS.md` added
`visit_history`. All required fields present: needs, motivation, candidates
with scores and rejection reasons, selected activity, execution outcome,
group, current activity/state, visit history. No changes made this pass.

## 6. What this pass did not do

No `score_weight` was changed. No new activity was added. No condition was
deleted or added beyond the one new opt-in field on `NeedThresholdCondition`
itself. `group_cohesion_multiplier`'s dead-code gap is reported, not wired
up - implementing group cohesion's actual effect would be new behaviour,
which is out of scope for a scaling-defect audit.

## 7. Controlled proof: 20 complete individual customer histories

`phase_b_measurement_probe.tscn`, widened to a 420-second run (70 completed
visits, up from 240s/42) and to print the top 20 customers by decision
count rather than 5, so the sample is large enough to classify rather than
just spot-check. Every one of the 20 was read start to finish, not
sampled - full transcript in this run's output, decision-by-decision needs,
motivation, candidates and selection for each.

### Aggregate (context only - the classification below is the actual answer)

```
completed visits: 70 | chose to leave: 16 | visit time ended: 9 | other forced: 45
realised visit length - median: 62.5 min, max: 221.0 min
NO ACTIVITY AT ALL: 57/70 (81.4%)  |  group activity participation: 0.0% (0/45)
```

The aggregate looks unmoved, or worse, than the previous pass's 78.6%. The
classification below is why an aggregate alone is the wrong instrument -
see the headline finding.

### Classification (20 of 20, ranked by decision count)

| # | Customer | Decisions | Length | Departure | Class |
|---|---|---|---|---|---|
| 1 | 27 | 10 | 219 min | visit time ended | **C** - relax, socialise, darts x2 |
| 2 | 4 | 9 | 87 min | visit time ended | **C** - socialise, darts (contains anomaly, see below) |
| 3 | 28 | 9 | 124 min | chose to leave | **D** - order/drink loop around one socialise |
| 4 | 1 | 8 | 128 min | visit time ended | **C** - darts (contains a flagged anomaly, see below) |
| 5 | 64 | 8 | 83 min | chose to leave | **D** - relax twice, nothing else |
| 6 | 45 | 8 | 89 min | chose to leave | **C** - relax, darts (contains anomaly, see below) |
| 7 | 35 | 7 | 91 min | visit time ended | **C** - socialise, darts |
| 8 | 36 | 7 | 171 min | chose to leave | **C** - darts, socialise, darts again |
| 9 | 49 | 7 | 102 min | chose to leave | **D** - order/drink loop, no leisure activity reached |
| 10 | 3 | 7 | 174 min | chose to leave | **B** - one darts visit |
| 11 | 18 | 6 | 55 min | chose to leave | **C** - socialise, darts, relax, all in 55 minutes |
| 12 | 19 | 6 | 55 min | chose to leave | **D** - order/drink loop only |
| 13 | 17 | 6 | 221 min | chose to leave | **B** - one darts visit in a 221-minute visit (noted) |
| 14 | 2 | 6 | 70 min | chose to leave | **C** - darts, relax |
| 15 | 7 | 5 | 83 min | chose to leave | **C** - relax, socialise |
| 16 | 15 | 4 | 54 min | visit time ended | **B** - one darts visit |
| 17 | 8 | 4 | 76 min | chose to leave | **A** - drink then leave, no optional activity |
| 18 | 20 | 3 | 42 min | visit time ended | **F** - timed out having only ordered and drunk |
| 19 | 34 | 2 | 37 min | visit time ended | **F** - timed out before the ordered drink was even consumed |
| 20 | 39 | 2 | 39 min | chose to leave | **F** - chose to leave before the ordered drink arrived |

**Totals: A=1, B=3, C=9, D=4, E=0, F=3, G=0 confirmed, H=3 confirmed
instances (see headline finding).**

Read as a whole, not as a percentage: 9 of 20 (45%) are genuine
multi-activity visits with a believable, non-monotonous shape - relax then
socialise then darts, or darts twice with a return to seat in between, at
lengths from 55 to 219 minutes. 3 more have exactly one optional activity
in an otherwise ordinary drink-led visit. This is a materially different
picture than "81.4% did no activity" suggests - the 81.4% figure counts
*all 70* completed visits, most of which are short (many under 60 minutes,
several ending on `visit_time_expired` after only 2-4 decisions), not just
the customers who stayed long enough to plausibly do anything. The 20
longest, most-decided visits - the ones actually testing whether the model
produces a believable evening rather than a fast checkout - are
multi-activity or single-activity in 12 of 20 cases (60%), pure order/drink
loops in 4 (20%), and abrupt/thin in 4 (20%, `F`, all under 45 minutes).

### Headline finding: weighted selection leaks past the stage-3 motivation filter

Not a scoring-scale defect (item 1's subject) - a decision-correctness one,
found only by reading full histories rather than aggregates, exactly the
failure mode item 7 asked to be checked for.

`CustomerBrain.think()` computes `best`/`best_score` only from candidates
that pass the stage-3 motivation filter (`is_mandatory` or
`serves_motivation(motivation)` - see `customer_brain.gd`'s stage-3 block).
But the weighted-selection call immediately after,

```gdscript
if best != null and not best.is_mandatory:
    var sampled: ActivityDefinition = _select_weighted(
        eligible_for_report, best_score
    )
```

passes `eligible_for_report` - populated *before* the motivation filter's
`continue`, so it contains every available candidate regardless of whether
it serves the chosen motivation - not the filtered set. `_select_weighted()`
(customer_brain.gd:1040) samples anything within `selection_band` of
`best_score`, with no re-check of `is_mandatory`/`serves_motivation` against
the motivation that produced `best_score` in the first place. A candidate
that was correctly excluded from ever *becoming* `best` can still be
resurrected into the pool `best` is then replaced with, purely because its
raw score happens to sit close enough to whatever score the filtered
competition produced.

Reproduced 3 times in this run's 20 sampled histories, all with the
motivation and every candidate's `satisfies` printed alongside the
selection so the mismatch is directly verifiable from the transcript:

- Customer 27, t=1170: motivation `social`, selected `relax_at_seat`
  (score 10.1). `relax_at_seat.satisfies = {"relaxation": 0.3}` - does not
  serve `social`. `socialise_at_seat` (13.0) and `visit_tavern_activity`
  (11.1), both of which do serve `social`, were available and scored
  higher.
- Customer 4, t=1077: motivation `entertainment`, selected
  `socialise_at_seat` (12.2). `socialise_at_seat.satisfies =
  {"social": 0.25}` - does not serve `entertainment`. `visit_tavern_
  activity` (9.5, serves `entertainment`) was available and eligible, just
  scored lower - `socialise_at_seat` should not have been a candidate for
  `entertainment` at all, regardless of its score relative to darts.
- Customer 45, t=1338: motivation `entertainment`, selected `relax_at_seat`
  (9.8), while `socialise_at_seat` (14.2, does not serve `entertainment`
  either, so also should have been excluded) and `visit_tavern_activity`
  (11.4, correctly serves `entertainment`) were both available and both
  scored higher.

Likely fix, not implemented this pass: build the weighted-selection pool
from only the candidates that survived the stage-3 filter (the same set
`best`/`best_score` were computed from), not from `eligible_for_report`.
`eligible_for_report` should keep including everything for the inspector/
diagnostics use it already serves (showing a rejected candidate's score is
exactly the value CUSTOMER_INSPECTOR.md asks for) - only the *selection*
pool needs narrowing, not the *reporting* one.

**Not fixed in this pass.** This is a new, unplanned finding from the
controlled proof itself, not one of the raw-value-scaling defects the audit
set out to find, and fixing it changes decision outcomes across the whole
customer population, not just leisure activities - exactly the kind of
change that needs its own isolated before/after measurement rather than
being folded into this pass silently. Flagged for a decision on next steps
rather than fixed on the spot.

### Secondary observation, not confirmed as a defect

Customer 1 selects `drink` twice in a row (t=1126, t=1134) with `thirst`
unchanged at `1.00` between them - the drink activity completing without
apparently reducing thirst. `execution_outcome` was empty on every recorded
decision in this transcript, so nothing surfaced as a visible failure, but
an activity completing without its expected effect landing is worth a
dedicated trace before being called either a bug or an artifact of staff
service timing in this particular run. Noted, not diagnosed - flagging
because CUSTOMER_INSPECTOR.md specifically asks for failed executions to be
visible, and this may be a case where one is not currently visible enough.
