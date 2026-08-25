# Weighted Selection Motivation-Filter Fix

Follow-up to `2026-08-25_SCORING_AUDIT.md` §7's headline finding: reading 20
complete individual customer histories (not aggregates) surfaced 3 cases
where `CustomerBrain` selected an activity that did not serve the active
motivation. This is that fix, isolated from the scoring-scale audit and
from any tuning, exactly as instructed.

Base: `98809d5`. Fix commit: see this pass's single commit on
`feature/phase-b-customer-model`. Not merged to `main`.

## 1. Reproduction, before touching any code

`tests/weighted_selection_regression_test.gd` (new). Forces `_select_
motivation()`'s weighted pick to `social` deterministically (only `social`
has nonzero weight in the needs profile, so every other key contributes
nothing to the running total - no need to touch `deterministic_decisions`,
which would also have disabled `_select_weighted()` itself). Positions
`relax_at_seat` (`satisfies = {"relaxation": 0.3}`, does not serve `social`)
to score close enough to the real winners (`socialise_at_seat`/
`visit_tavern_activity`, both of which do serve `social`) to land inside
`selection_band`.

Run against the pre-fix code, 150 trials: **74 violations (49.3%)** -
`relax_at_seat` selected under motivation `social` in essentially every
other trial, despite `socialise_at_seat` scoring higher every single time
and being the one that actually serves the motivation. Sample:

```
[VIOLATION] trial 0: motivation=social selected=relax_at_seat candidates=[
  {"activity_id": "leave", "score": 8.79},
  {"activity_id": "relax_at_seat", "score": 11.14},
  {"activity_id": "socialise_at_seat", "score": 11.26}]
```

## 2. Exactly where the filtered candidate set is lost

`CustomerBrain.think()` builds two things during its scoring loop:

- `best`/`best_score` - updated only for a candidate that survives both the
  `is_terminal` skip and the stage-3 motivation filter
  (`not definition.is_mandatory and not definition.serves_motivation(motivation)`
  -> `continue`).
- `eligible_for_report` - appended for *every* available, non-cooldown
  candidate, **before** either of those two `continue` statements run. This
  is intentional and correct for its actual purpose: CUSTOMER_INSPECTOR.md
  asks for a rejected candidate's score to be visible, not just the
  winner's.

The weighted-selection call,

```gdscript
if best != null and not best.is_mandatory:
    var sampled: ActivityDefinition = _select_weighted(
        eligible_for_report, best_score
    )
```

was handed `eligible_for_report` - the unfiltered list - using the
*filtered* `best_score` as its threshold pivot. Any candidate in that list
scoring within `selection_band` of `best_score` was eligible to be sampled,
regardless of whether it had ever been allowed to compete for `best` in the
first place.

## 3. Confirmed: the selector receives the wrong list; it does not reach for a broader one itself

Read `_select_weighted()` (`customer_brain.gd:1061`) in full. It takes
`eligible: Array[Dictionary]` and `best_score: float`, filters by
`selection_band`/`minimum_selection_score` and by
`ActivityDefinition.is_mandatory` (looked up generically through
`registry.get_definition()`), and returns a weighted-random pick. It does
not read `CustomerBrain.motivation`, does not call `serves_motivation()`,
and does not touch any list other than the one it is given. The defect is
entirely at the call site, not inside the selector.

## 4. The fix

One new list, populated at the one point a candidate has survived both the
`is_terminal` skip and the stage-3 filter - the same point `best`/
`best_score` are updated:

```gdscript
stage3_survivors.append({
    "activity_id": String(definition.activity_id),
    "score": score,
})

if score > best_score:
    best_score = score
    best = definition
```

And the call site now passes it instead:

```gdscript
var sampled: ActivityDefinition = _select_weighted(
    stage3_survivors, best_score
)
```

`eligible_for_report` is untouched and still feeds every report/inspector
path exactly as before (`_report_decision()`, `_print_decision_block()`,
`CustomerBehaviourEvents.emit_decision_evaluated()`). `_select_weighted()`
itself was not changed - it remains exactly as generic as it already was,
per the architectural requirement: it still knows nothing about
motivations, needs, groups, or any specific activity, only about scores,
a threshold, and `is_mandatory`. The fix is a pure data-flow correction:
give the selector the population it was always supposed to receive.

## 5. Isolated regression result

Same test, same 150 trials, against the fixed code: **0 violations.**

```
150 trials, motivation=social in 150, relax_at_seat eligible-for-report in
at least one: true, violations: 0
=== RESULT: 3 passed, 0 failed ===
```

The "relax_at_seat eligible-for-report in at least one: true" assertion
confirms the scenario is still well-formed after the fix - the excluded
candidate is still visible in `eligible_for_report` (correct, diagnostics
must not lose it), it simply can no longer be selected.

## 6. Before/after from real individual histories, not just the isolated test

Re-ran `phase_b_measurement_probe.tscn` (same 420s/20-history
configuration as the audit) after the fix and grepped every recorded
`relax_at_seat`/`socialise_at_seat` selection against its motivation:

**Before** (`2026-08-25_SCORING_AUDIT.md` §7): 3 of ~40 scored selections
violated the filter - `relax_at_seat` chosen under `social`/`entertainment`,
`socialise_at_seat` chosen under `entertainment`.

**After:** 29 `relax_at_seat`/`socialise_at_seat` selections recorded across
the 20 sampled histories. **Zero violations** - every `relax_at_seat`
selection paired with motivation `relaxation` (which it serves), every
`socialise_at_seat` selection paired with motivation `social` (which it
serves).

One representative full trace, customer 49 (12 decisions, 179 minutes,
`utility_decision` departure) - order, drink, order, drink, `socialise_
at_seat` (motivation `social`), `relax_at_seat` (motivation `relaxation`,
correctly beating a *higher-scoring but non-serving* `visit_tavern_
activity=14.1` shown in the candidate list but not selected), `visit_
tavern_activity` (motivation `social`, which darts does serve), return,
order, drink, `socialise_at_seat` again, then `leave` at a decisive 20.6 -
four genuine leisure activities in one visit, each one correctly gated by
its own motivation, with the terminal `leave` decision entirely
independent of the stage-3 pool (see §8).

Aggregate, side effect not a target: activity starts per customer rose
from 0.33 to 0.49 and "no activity at all" fell from 81.4% to 73.7% between
the two 420s runs - the natural consequence of previously-eligible
candidates no longer being displaced by an incorrectly-resurrected
non-serving one, not the product of any weight or threshold change. Not
reported as proof of anything beyond this fix - two different 420s samples
of a stochastic simulation are not a controlled before/after on their own,
and no tuning was done to produce this number.

## 7. Remaining violations

None found. Swept the full post-fix 20-history transcript for the same
pattern (any non-mandatory, non-terminal selected activity whose
`satisfies` does not include its recorded motivation) - zero matches.

## 8. Confirmations requested

**Stage-1 leave remains independent.** Untouched by this fix by
construction, not merely by observation: `unfiltered_best`/
`unfiltered_best_score` are separate variables, populated during the same
scoring loop but *before* the `is_terminal` skip that also gates
`stage3_survivors`, and the stage-1 override
(`if unfiltered_best != null and unfiltered_best.is_terminal: best =
unfiltered_best`) never reads `stage3_survivors` or touches
`_select_weighted()` - `leave` is `is_mandatory = true`, so the weighted-
selection block is skipped entirely whenever leave wins at stage 1, exactly
as before. Customer 49's leave at 20.6 above is a real example of it
winning on merit, post-fix.

**Groups still bias without bypassing the filter.** No group-specific code
was added or touched. `GroupManager._ask_member_brain()` still calls
`brain.think()` directly and unconditionally; group context reaches scoring
only through `context.domain_flags` (`group_has_away_capacity`,
`group_is_drinking`), read while each candidate's `score` is computed,
*before* `stage3_survivors` is populated - a group member's candidates are
filtered by the exact same `serves_motivation()` check as a solo
customer's, automatically, because it is the same code path.

**Awareness still affects eligible candidates without bypassing the
filter.** `NearbyActivityInUseCondition`'s contribution is folded into
`score` via `definition.get_utility(context)` before stage-3 runs, so it
can change whether a candidate wins the *filtered* competition or how it
ranks within `stage3_survivors` - it cannot change whether a candidate
passes `serves_motivation()` in the first place. No interaction between
this fix and the awareness diagnostic (`tests/awareness_diagnostic_test.gd`,
still 8/8) was introduced or expected.

## 9. Does the decision pipeline now satisfy CUSTOMER_MODEL.md's stage 3/4?

For the specific boundary this fix addresses - "stage 4 selects only from
candidates stage 3 validated" - yes, confirmed by regression test (0/150),
by a full transcript sweep (0/29), and by code construction (`_select_
weighted()` never sees anything outside `stage3_survivors`). This was the
one place the pipeline violated its own stated architecture with a
by-construction guarantee now in place, not merely a should. The broader
question of whether the *whole* four-stage pipeline matches CUSTOMER_
MODEL.md §4 was already answered in `2026-08-25_PHASE_B_VERIFICATION_PASS.md`
item 1 (confirmed sound) and is unchanged by this pass.

## What this pass did not do

No `score_weight`, `ActivityDefinition`, need value, motivation threshold,
awareness condition, or group logic was changed. No attempt was made to
target a specific "activities per customer" figure - the aggregate
improvement in §6 is reported because it happened, not because it was
aimed for. `_select_weighted()` itself was not modified.
