# Phase B — Customer Model

Work order. Read `CUSTOMER_MODEL.md` and `CUSTOMER_INSPECTOR.md` first; this is
the plan for getting there, not the design.

Base commit: `235b7ac`.

## Goal

The next playtest should feel different. Not measurably different — *visibly*
different, watching the room for five minutes without opening a report.

Deliberately aggressive scope. This is one pass: audit, then implement, then
inspector, then measure. Not four sessions.

## Stage 1 — Read-only audit

**Do not modify code in this stage.** Output only
`docs/history/2026-08-25_CUSTOMER_ARCHITECTURE_AUDIT.md`.

Map every part of the current customer implementation against the target model
and give each a verdict: **KEEP / MODIFY / REPLACE**, with a one-line
justification.

### Audit guardrails

These exist because this project has repeatedly reached wrong conclusions in
exactly these ways.

**Map by function, not by name.** Much of the target model already exists under
different vocabulary. The audit will over-report REPLACE if it looks for the
words. Known examples — verify each rather than assuming:

| Target concept | Likely existing implementation |
|---|---|
| Visit purpose | `VisitIntentConfig` (9 intents) + `CustomerIdentity.get_activity_bias()`, applied inside `think()` |
| Per-visit variation | `Personality.create_visit_profile()` (duplicate-and-jitter) |
| Preferences | `CustomerType` (~98 fields), `DrinkPreference`, `SocialCompatibility` |
| Group bias | `GroupManager._offer_leisure_activity()` already delegates to the member's own brain |
| Needs | `CustomerNeeds` — check which values are normalised and which are raw |
| Activity execution | `ActivityBehaviour` + `DestinationBroker` + `Reservable` |
| Awareness | `SocialPresenceService` only, and only proximity |

**Justify every REPLACE with live measurement.** Static source reading has
produced the wrong answer on this project at least three times, and each time
the correct answer came from running the scene. If a component is proposed for
replacement because it does not work, show the run that says so.

**Distinguish "absent" from "present but too weak to observe."** These need
different fixes and the second is more common here than it looks.

**Report the score-contest structure explicitly.** Whether the flat pool can be
made two-stage inside `CustomerBrain.think()` and `ActivityRegistry`, or whether
those need replacing, is the single most important line in the audit.

### Evidence you already have

Measured at `235b7ac`, do not re-derive:

- darts eligible 37.2% of samples, occupies 1.2% of customer time
- darts beaten by `relax_at_seat` 321 / `order_drink` 117 / `socialise` 38 of
  528 eligible samples; would win 52; on cooldown only 20
- mean when eligible: `order_drink` 20.76, `socialise` 12.51, `relax` 12.43,
  darts 10.20, `drink` 8.00, `leave` −9.62
- relax mean contributions: base 7.50, visit_time **+2.72**, satisfaction +2.17,
  thirst −1.34 → 12.25
- darts mean contributions: base 8.50, visit_time **0.00**, distance +0.39,
  satisfaction +1.28, thirst −0.45, group cohesion −0.58 → 9.99
- `relax_visit_time_scoring` uses `score_weight = 0.05` on
  `remaining_visit_minutes`, a **raw minute count**, not a 0–1 need
- both `DartsPoint` nodes are at (82,452) and (156,452); tables are at (448,319)
  and (696,317), so the 600px distance falloff barely reaches table 2
- `is_committed()` in `customer_brain.gd` is never called — commitment does not
  gate `think()`

`tests/darts_score_probe.tscn` (included) reproduces all of the above. It is the
before/after instrument for this pass — run it at the start and at the end.

### Stop point

Present the verdict split (roughly what % keep / modify / replace) and the
implementation plan **before** starting Stage 2. If the audit finds the model
needs a larger rewrite than expected, say so rather than proceeding quietly.

## Stage 2 — Implementation

Build to `CUSTOMER_MODEL.md`. Priority order if the pass has to be cut short:

1. **Two-stage decision.** Motivation, then activity within that motivation.
   This is the change that makes darts stop competing with sitting down.
2. **Needs normalised 0–1 and audited.** Any raw-valued need is a defect. Fix
   `relax_visit_time_scoring` regardless of what else happens — it distorts
   every measurement taken after it, including this pass's own before/after.
3. **Activities declare what they satisfy.** The inversion. Validate against the
   extension test in `CUSTOMER_MODEL.md` §5.
4. **Lingering as default, departure as decision.**
5. **Awareness / opportunities.** Scope this last and keep it cheap — proximity
   plus "is this activity already in use" is enough to start.

Preserve: navigation, reservations, activity execution, destination broking,
groups, `SocialPresenceService`, personality, customer types, the weighted
selection among near-equal candidates, and the data-driven resource approach.

## Stage 3 — Inspector

Per `CUSTOMER_INSPECTOR.md`. Developer tier, full disclosure, snapshot layer
between customer and UI.

This is not optional polish — it is how the balancing pass after this one gets
done without writing another probe.

## Stage 4 — Measure

Required in the final report, before and after, from comparable runs:

| Metric | At `235b7ac` |
|---|---|
| tavern activities / customers | 8 / 60 |
| relax / socialise activities | 26 / 8 |
| darts eligible → occupancy | 37.2% → 1.2% |
| chose-to-leave vs visit-time-ended | 13 vs 30 |
| realised visit length (median / max) | 65.0 / 218.0 |
| solo service rate | 53.3% |
| group activity participation | 33.3% (6 groups — noisy) |
| `order_drink` share of customer time | ~28–35% |

Plus the distribution question: how many customers did **no** activity at all?
That number should stay substantial. A tavern where everyone plays darts is a
worse result than the current one — see `CUSTOMER_MODEL.md` non-goals.

### Measurement traps on this project

- Group-level effects need **~14 groups minimum**. A 4-minute probe sees 4–8 and
  cannot detect them. This has produced a false "it didn't work" twice.
- Check stock and staffing before reading any service metric as an AI problem.
  Two consecutive unattended runs each starved a different player-supplied input.
- Service rate varies strongly with run length; compare like with like.
- Occupancy counts in the tens are noise. Eligibility percentages are stable
  enough to reason from in a single run; occupancy is not.
- `tests/service_latency_probe.tscn` overwrites `debug/latest/`. Restore with
  `git checkout -- debug/` afterwards.

## Definition of done

- Audit document committed with per-component verdicts.
- Two-stage decision implemented; darts occupancy materially up from 1.2%
  **without** the theme-park failure mode.
- Adding a hypothetical new activity demonstrated as resources only.
- Inspector shows needs, motivation, candidates, scores, rejections and
  execution outcome on hover.
- Before/after table above, from comparable runs.
- `CURRENT_STATE.md`, `DECISIONS.md`, `CUSTOMER_AI_SYSTEM.md` and `TEST_MAP.md`
  updated to match what was actually built.
- Regressions checked against the baselines in `CLAUDE.md`.

## What not to do

- Do not tune darts' weights as the fix. That is the flat-pool problem wearing a
  different number.
- Do not add new activities.
- Do not build rumours, dialogue, named characters or relationships.
- Do not build a visible needs UI in the game.
- Do not treat the existing framework as disposable — most of it is the
  execution layer the new model runs on.
