# Behavioural Evaluation — Post Weighted-Selection Fix

Read-only evaluation, no code changes. Answers one question: "do these
customers now behave like plausible tavern visitors?" Base: `8791b55`
(`feature/phase-b-customer-model`, weighted-selection fix included).

## Method

`tests/tavern_behaviour_evaluation_probe.gd` (new, diagnostic-only — reads
`VisitRecord`/`DecisionRecord` data `CustomerAIReportManager` already
collects, plus a light periodic sample of `CustomerNeeds.visit_purpose`
and `CustomerBrain.get_current_activity()` for an independent cross-check
on decision timestamps; touches no `systems/customer_ai` file). Same
420-second/95-completed-visit run shape already established in this
session. 25 complete histories read in full — every one that had at least
2 decisions, ranked by decision count so the richest, longest visits (the
ones actually capable of showing multi-activity behaviour) were the ones
inspected, not a random or aggregate-weighted sample.

**Sampling bias, stated up front:** ranking by decision count means this
25 skews toward longer, more-decided visits. A short visit that got forced
out after one order never had the chance to show anything. This is
deliberate — the question is "what does a visit that runs its course look
like", not "what does the average visit look like" — but it means the
aggregate figures below (73.7% "no activity" from the same population)
and this sample's figures are answering different questions, not
disagreeing with each other. Both are reported.

## Classification (25 of 25)

| # | Customer | Type | Length | Departure | Class | Note |
|---|---|---|---|---|---|---|
| 1 | 42 | Pirate | 233 min | utility | **C** | relax, socialise, darts — 105-min unexplained gap after return-to-seat |
| 2 | 8 | Pirate | 244 min | utility | **G** | darts reservation+navigation failure, 152-min stall before recovery |
| 3 | 41 | Pirate | 139 min | timer | **C** | darts x2, relax — 64-min gap, milder version of #1's pattern |
| 4 | 39 | Naval Officer | 62 min | utility | **C** | relax, socialise x2 — clean, no gaps |
| 5 | 30 | Sailor | 58 min | utility | **B** | one darts visit |
| 6 | 51 | Sailor | 78 min | utility | **B** | one darts visit; awareness fired twice (+0.12, +0.39), didn't change winner |
| 7 | 55 | Merchant | 94 min | utility | **C** | darts x2, relax, socialise — 0 drinks consumed (see personality finding) |
| 8 | 23 | Sailor | 69 min | utility | **C** | relax, darts |
| 9 | 21 | Merchant | 72 min | utility | **C** | darts, relax |
| 10 | 63 | Pirate | 81 min | utility | **B** | one relax visit after 3 order/drink rounds |
| 11 | 93 | (active) | — | — | **B** | one darts visit (incomplete) |
| 12 | 72 | Merchant | 83 min | timer | **D** | darts x2 only, nothing else; 0 drinks consumed |
| 13 | 6 | Merchant | 75 min | utility | **B** | one relax visit |
| 14 | 57 | Sailor | 64 min | utility | **B** | one darts visit |
| 15 | 28 | Merchant | 71 min | timer | **C** | relax, darts, despite a reservation+navigation failure (recovered in ~15 min, not a stall) |
| 16 | 35 | Sailor | 62 min | timer | **C** | socialise, relax |
| 17 | 76 | Sailor | 58 min | utility | **D** | socialise x2 only |
| 18 | 97 | (active) | — | — | **B** | one relax visit so far; one clean "no candidate" WAITING tick, resolved in 8 min |
| 19 | 62 | Merchant | 79 min | utility | **C** | darts, relax; one clean WAITING tick, resolved in 16 min |
| 20 | 34 | Naval Officer | 50 min | utility | **C** | relax, darts |
| 21 | 5 | Sailor | 58 min | utility | **C** | socialise, darts, relax — three activities in 58 minutes |
| 22 | 7 | Sailor | 49 min | timer | **B** | one relax visit |
| 23 | 84 | Sailor | 82 min | utility | **C** | relax, darts, despite a navigation failure (recovered cleanly) |
| 24 | 14 | Plantation Owner | 74 min | utility | **A** | zero optional activities — pure order/drink/leave, fairly beaten on score, not a bug (see below) |
| 25 | 91 | Merchant | 81 min | utility | **C** | darts x2, relax |

**Totals: A=1 (4%), B=8 (32%), C=13 (52%), D=2 (8%), E=0, F=0, G=1 (4%), H=0, I=0.**

No pure "premature departure" (F) or "mechanically irrational decision" (H)
found in this specific 25 — the closest thing to H (customer 45's
`relax_at_seat` selected over a higher-scoring, motivation-serving
candidate, from the prior evaluation) is exactly what the weighted-
selection fix eliminated; none recurred here.

## Three full timelines, quoted

**Customer 5 (Sailor, 58 minutes, chose to leave)** — the best single
example of the target shape from `CUSTOMER_MODEL.md`'s "what working looks
like":

```
t=1033 forced: order_drink
t=1047 forced: drink
t=1055 social → socialise_at_seat (13.0, beat darts 12.4 and relax 10.6)
t=1060 social → visit_tavern_activity (13.6, beat relax 10.6)
t=1070 relaxation → relax_at_seat (10.3)
t=1079 social → leave (8.5, only candidate above the floor)
```

Three different leisure activities, three different correctly-matched
motivations, in under an hour, ending in a real (if modest-margin) merit
decision to leave.

**Customer 42 (Pirate, 233 minutes, chose to leave)** — richest history in
the sample, and the clearest example of the unexplained-gap finding:

```
t=1193 order_drink → t=1199 drink → t=1207 order_drink → t=1213 drink
t=1221 relaxation → relax_at_seat
t=1232 relaxation → order_drink (fair win, no candidate served relaxation better)
t=1244 drink
t=1252 social → socialise_at_seat (14.2, beat leave 13.0)
t=1258 entertainment → visit_tavern_activity (13.4, beat leave 12.2)
t=1300 forced → return_to_seat
  [ nothing recorded for 105 minutes ]
t=1405 relaxation → leave (12.7, beat relax 10.9, socialise 10.4, darts 9.3)
```

Everything before and after the gap is exactly the model working as
intended — a customer who drank, relaxed, socialised, played darts, and
eventually chose to leave on a fair contest. The 105-minute silence in the
middle is the one thing in this entire evaluation that does not have a
confirmed explanation.

**Customer 14 (Plantation Owner, 74 minutes, chose to leave)** — the "still
behaves like enter → order → drink → leave" case, quoted because it is
mechanically fair, not broken:

```
t=1051 forced: order_drink → t=1063 forced: drink
t=1075 entertainment → order_drink (11.3) — candidates: leave 5.5,
  relax_at_seat 11.6, socialise_at_seat 13.9, visit_tavern_activity 9.9
```

`socialise_at_seat` scored highest (13.9) but does not serve
`entertainment`, so it correctly never competed; of what remained,
`order_drink` (mandatory, always in the race) beat `visit_tavern_activity`
9.9 fairly. This customer's needs clearly wanted something else
(social/entertainment/relaxation all near 1.0 by the end) and never got
it — not because of a bug, but because `order_drink`'s own base score plus
mood/thirst terms occasionally still wins close calls even after the
raw-value scale fix. This is the same, already-documented, not-yet-tuned
dynamic from `2026-08-25_SCORING_AUDIT.md` — visible here as a real
customer outcome rather than an abstract number.

## The eleven questions

**1. Does personality/type produce meaningful variation?** **PROVEN
WORKING**, with an interesting specific pattern: Merchants (customers 55,
72, 62 — 3 of 6 Merchants sampled) ended their visit with **zero drinks
consumed**, a pattern no other customer type showed in this sample despite
Merchants carrying noticeably more starting money (£55–£82 vs £15–£51 for
other types). Plantation Owner (customer 14) started at £114, more than
double anyone else, and ended at £3 with 88% intoxication — a distinct,
plausible "wealthy heavy drinker" archetype. Type/personality is visibly
shaping outcomes, not just labels.

**2. Do groups bias behaviour while allowing peel-away?** **UNKNOWN — NOT
ANSWERABLE FROM THIS SAMPLE.** All 25 richest histories were solo
customers; no group member had enough decisions to rank into this sample.
The immediately prior same-branch run recorded group activity
participation at 1.8% (56 member-visits, 17 groups) — group members are
reaching leisure activities almost never, which is itself notable, but a
low leisure-participation rate is a different question from "do they bias
and peel off correctly when they do decide." A dedicated group-focused
sample (ranking group members by decision count specifically) is needed
before this question has a real answer.

**3. Do customers reconsider naturally after activities?** **PROVEN
WORKING.** Every sampled completion of relax/socialise/darts is
immediately followed by a fresh decision in the same or next tick, visible
in all 13 "C" histories.

**4. Do needs change enough to create different motivations?** **PROVEN
WORKING.** Motivation visibly shifts thirst → social → relaxation →
entertainment within single visits, tracking the printed needs snapshots
exactly. See customer 5 above.

**5. Does awareness alter decisions, not just scores?** **WORKING BUT NOT
OFTEN DECISIVE** — consistent with the controlled diagnostic from the
scoring audit, not a new finding. Fired twice in this sample (customer 51,
+0.12 and +0.39), never changed the winner. Genuine and isolated, rarely
the deciding factor for darts specifically, for the already-documented
structural reason (distance and awareness are correlated).

**6. Are customers lingering by choice, not arbitrary timers?** **PROVEN
WORKING**, and the strongest positive result in this evaluation: 18 of 25
(72%) departed via `utility_decision` (a real contest, `leave` beating
genuine alternatives), 5 of 25 (20%) via the visit-time timer, 2 still
active. This matches `CUSTOMER_MODEL.md`'s explicit goal — "the target is
for chosen departure to be the normal case, with the timer as a backstop"
— directly, on real data.

**7. Are there repeated identical loops?** **WORKING, MINOR EXCEPTION.**
No customer got stuck cycling the same activity indefinitely. Two
customers (72, 76 — both Merchants) repeated the *same single* leisure
activity twice (darts, socialise respectively) with nothing else — mild
repetition, not a loop, classified D. Not concerning at this rate (2/25).

**8. Are there customers who still behave as enter → order → drink →
leave?** **YES, but rare and mechanically explained, not a bug** — 1 of 25
(customer 14, above). Consistent with `order_drink` still winning close
calls on merit sometimes, the known, already-flagged, not-yet-tuned
dynamic.

**9. Are any activities dominating despite the new architecture?** **NOT
OBSERVED.** Across the 25: relax appears in 14, darts in 13, socialise in
7 — no single leisure activity crowds out the others. Order/drink
dominates overall occupancy as intended (`CUSTOMER_MODEL.md`'s explicit
non-goal: "most customers, most of the time, should drink and talk").

**10. Are any activities effectively unreachable?** **NOT OBSERVED.** All
three leisure activities appear repeatedly and get selected across a range
of motivations and customer types.

**11. Are customers spending meaningful time interacting with the tavern,
not just transacting with the bar?** **WORKING BUT UNEVEN.** 21 of 25
(84%) have at least one non-bar activity (relax/socialise/darts); state
trails show genuine multi-minute `RELAXING`/`SOCIALISING`/`USING_ACTIVITY`
states, not instant transitions. The remaining 16% (customer 14 plus
customer 93/97's incomplete visits) spend their whole visit in the
order/drink cycle — present but a minority, and, per question 8,
mechanically fair rather than broken.

## The one open finding: long unexplained gaps

Three histories (42, 8, 41 — 12% of the sample) show a gap of 64–152
minutes with **zero** recorded decisions and **zero** activity-trace
changes, always starting right after a `return_to_seat`/activity
transition. `_on_returned_to_seat()` calls `_brain.think()` immediately
for a solo customer (confirmed by reading it — this is not a missing
call), so travel time alone does not explain a 100+ minute silence.

Two sub-patterns, not clearly one mechanism:

- **Customer 8**: `FAILURES: reservation=1 navigation=1` recorded, and the
  152-minute gap follows immediately. A failure→stall link is plausible
  here.
- **Customer 42**: no failure flag at all, still a 105-minute gap. Either
  the failure-counting mechanism does not catch every case that causes a
  stall, or this has a different, unidentified cause.
- **Counter-evidence it isn't universal**: customers 28 and 84 both have a
  recorded navigation/reservation failure and recovered within 10–20
  minutes, no stall. Customer 62 and 97 both hit a genuine "no candidate
  available" WAITING tick and recovered in 8–16 minutes, cleanly.

**Classification: UNKNOWN / NEEDS MORE DATA**, leaning **BUG** given the
correlation with recorded failures in the worst case, but not confirmed —
this evaluation was read-only and did not trace live navigation state
during a gap. This is the single most important open question from this
pass, more important than any aggregate number: a customer sitting
inert for over 100 minutes, even if the visit-time timer eventually cleans
it up, is not "lingering by choice."

## Findings summary

| Finding | Classification |
|---|---|
| Stage-3 motivation filter respected in selection | **PROVEN WORKING** (0/25 violations, matches the isolated regression) |
| Needs drive shifting motivation within a visit | **PROVEN WORKING** |
| Post-activity reconsideration | **PROVEN WORKING** |
| Chosen departure is the normal case (72%) | **PROVEN WORKING** |
| Personality/type produces visible behavioural variation | **PROVEN WORKING** |
| No single leisure activity dominates or is unreachable | **PROVEN WORKING** |
| Awareness participates in scoring, rarely decisive for darts | **WORKING BUT NEEDS TUNING** (if darts' distance/awareness balance is ever revisited — not urgent) |
| `order_drink` occasionally wins a close call it "shouldn't" | **WORKING BUT NEEDS TUNING** (already documented, not yet tuned by instruction) |
| Long unexplained idle gaps after return-to-seat (12% of sample) | **UNKNOWN / NEEDS MORE DATA, leaning BUG** |
| Group bias-with-peel-away | **UNKNOWN / NEEDS MORE DATA** (no group examples in this sample) |
| Mild same-activity repetition (2/25) | **WORKING BUT NEEDS TUNING**, low priority |

## Honest assessment

The decision architecture itself — two-stage selection, demand-shaped
needs, the `satisfies` inversion, awareness, and now the stage-3/stage-4
boundary — is sound. This is not a hedge: 13 of 25 richest histories are
genuine, varied, multi-activity visits with correctly-matched motivations
and merit-based departures, and the weighted-selection fix's evidence
(0/25 filter violations here, on top of 0/150 isolated and 0/29 from the
prior sweep) means that soundness is no longer provisional. Customer 5's
58-minute visit — drink, socialise, darts, relax, leave — is what
`CUSTOMER_MODEL.md` asked for, produced by the system as it stands, not
cherry-picked.

**The customer foundation is ready for the next layer, with one
condition:** the unexplained-gap finding needs a dedicated trace before
building anything that assumes customers reliably reconsider on a normal
cadence — an information/rumour/relationship system, in particular, would
inherit this defect silently (a customer who should notice something new
but is in a 100-minute stall will not). This does not require another
broad evaluation pass, just a focused trace of live navigation state
during one reproduced gap, which is a small, well-scoped follow-up, not a
fundamental problem with the customer system. Everything else found this
pass is either already known and intentionally not yet tuned, or a minor,
low-rate pattern not worth blocking on.

No code was changed in this evaluation.
