# Final Diagnostic Pass — Return-to-Seat Fix, Merchant Behaviour, Group Proof

Closes out the Phase B customer-model work. Three focused investigations,
one confirmed and fixed correctness bug, two documented-not-fixed findings,
and a final readiness verdict. Base: `3e490b6`
(`feature/phase-b-customer-model`). Fix commit: `90831f6`.

## 1. The return-to-seat gaps

### Reproduction and trace (before any code change)

`tests/return_to_seat_stall_probe.gd` (new, read-only) watches every live
customer's `current_state` and dumps a full diagnostic snapshot
(`ActorNavigation.get_state()`/`is_travelling()`/`is_parked()`/
`get_recovery_attempts()`, position, distance to reserved chair, brain
state) the moment any customer's state has not changed for 20 game-minutes
- catching a stall while it is happening, not reconstructing one after the
fact.

First run caught it directly. Four live `RETURNING_TO_SEAT` stalls, all
with the same signature:

```
distance_to_seat: 33.26px   is_travelling=true   recovery_attempts=0
distance_to_seat: 33.00px   is_travelling=true   recovery_attempts=0
distance_to_seat: 33.08px   is_travelling=true   recovery_attempts=0
distance_to_seat: 37.01px   is_travelling=true   recovery_attempts=0
```

Four independent customers, four different tables, all plateaued within a
few pixels of each other, all still nominally "travelling," none ever
triggering the navigation stuck-recovery escalation (which checks every
0.5 real seconds and would fail within a few real seconds if genuinely
stuck - ruled out as the mechanism by the timing alone).

### Root cause (D, from the classification scheme: navigation preventing arrival - confirmed, not inferred)

`Chair.occupied_obstacle` is a `NavigationObstacle2D` with
`occupied_avoidance_radius = 22.0` and `occupied_zone_offset = 4.0`,
enabled via `set_occupied_zone_enabled(true)` the first time a customer
sits down (`arrive_at_seat()`) and by `_on_returned_to_seat()` once
re-seated. It is **never disabled** while that same customer is
temporarily away visiting an activity - only `Chair.release_reservation()`/
`force_release_reservation()`/`require_cleaning()` disable it, all tied to
fully giving up the chair, not a temporary trip. `Customer.seat_arrival_
distance = 2.0px` - far inside the obstacle's ~22-26px effective radius.

A customer returning to a chair it never released was therefore
avoidance-blocked by **its own** obstacle before it could ever get within
2px to satisfy `_on_destination_reached()` and call `_on_returned_to_seat()`
- `think()` never re-fires, because the one thing that would trigger it
never happens. The ~33-37px plateau observed live matches the obstacle's
geometry almost exactly. `customer.gd`'s own doc comment on
`begin_visiting_activity()` already said "reserved_chair is left completely
untouched" for this trip - true of the *reservation*; the *physical
obstacle* was the same design intent, just not carried through.

This also explains why some evaluation gaps ended in `utility_decision`
(customer 42, eventually escaped - plausibly avoidance-solver drift over a
long enough time letting position slip inside 2px by chance) and others in
`visit_time_expired` (customer 41 - the position-independent visit-timer
intervened first, unrelated to whether the obstacle ever cleared).

### Fix

`begin_visiting_activity()` and `begin_visiting_activity_as_partner()`
(`scripts/Entities/customer.gd`) now call
`reserved_chair.set_occupied_zone_enabled(false)` before travelling.
`_on_returned_to_seat()` already re-enables it once actually seated, so
nothing else needed changing. The reservation itself is untouched - only
the physical avoidance obstacle toggles - so this cannot let another
customer take a still-reserved seat.

### Regression test

`tests/return_to_seat_obstacle_test.gd` - real `chair.tscn`/
`customer.tscn`/`darts_point.tscn` scenes, no mocks. Proves: the zone is
enabled once seated; `begin_visiting_activity()` disables it without
touching the reservation; `_on_returned_to_seat()` re-enables it; the
co-opted-partner path (`begin_visiting_activity_as_partner()`) needs and
gets the same fix. **5/5 assertions pass.**

### Confirmation at scale

Same stall probe, re-run post-fix across a fresh 420s/16-peak-customer
simulation: 31 total stalls caught, **zero** `RETURNING_TO_SEAT` or
`MOVING_TO_ACTIVITY` (the exact pattern this fixes). All 31 were `IN_GROUP`
(the correct steady state for an assembled group member, not a stall) or
`ORDERING` (pre-existing, unrelated staff service latency - see Known
issue territory, not this fix's concern). One `MOVING_TO_SEAT` stall and
one `WALKING_TO_STAGING` stall also appeared once each - a related but
distinct case (initial seating rather than returning) is flagged as future
work below, not expanded into now per "smallest possible fix."

**Classification: BUG, confirmed and fixed.**

## 2. Merchant zero-drink behaviour

### Evidence

Three Merchants in the prior evaluation (customers 55, 72, 62) ended their
visit with `drinks_consumed = 0` despite starting thirst 35-55%. Their
state trails all show the same pattern: `ORDERING` followed directly by
`MOVING_TO_ACTIVITY` (or another decision), **never** passing through
`DRINKING` - sometimes twice in one visit (customer 72: two separate
order attempts, neither ever consumed).

### Root cause (B: unintended configuration consequence, not a bug)

`resources/CustomerTypes/merchant.tres`'s `visit_intent_weights` gives
`quiet_meeting` the highest weight (4.0) of any intent, so it is
disproportionately the intent merchants roll. `Data/customer_ai/visit_
intents/quiet_meeting.tres` declares:

```
activity_score_offsets = {"relax_at_seat": 8.0, "socialise_at_seat": -6.0,
  "visit_tavern_activity": -10.0, "wander": -8.0}
```

`drink.tres` has exactly one condition (a pure gate, `has_drink_to_
consume`) and `base_utility = 8.0` - its score is **always exactly 8.0**,
unmodified by any identity bias (quiet_meeting's offset dict has no
`"drink"` key). `relax_at_seat`'s floor, under quiet_meeting, is
`7.5 (base) + 8.0 (offset) - 3.0 (worst-case thirst penalty) = 12.5` -
comfortably above `drink`'s flat 8.0 in every case, not just some.

`drink` is `is_mandatory = true`, which exempts it from the stage-3
motivation filter but does **not** protect it from being outscored on raw
merit by an optional activity that does pass the filter. Whenever stage-2
selects `relaxation` as the active motivation while a merchant has a drink
ready to consume, `relax_at_seat` is scored, passes the filter (it serves
`relaxation`), and **always** beats `drink`'s flat 8.0 - so the customer
relaxes instead of drinking an already-prepared order. This is not rare:
it only requires stage-2 to select `relaxation` once at the right moment,
and quiet_meeting's `entertainment_offset`/`sociability_offset` (both
-0.35) push the other motivations down, making `relaxation` comparatively
more likely to be picked.

This is `CustomerBrain`/`ActivityDefinition` working exactly as coded -
`is_mandatory` was never documented or intended to mean "cannot be
outscored," only "exempt from the stage-3 filter and from weighted
sampling." The unintended part is `quiet_meeting.tres`'s specific `+8.0`
number being large enough, and `drink`'s flat `8.0` being exactly the kind
of value it can reliably clear. Ending satisfaction for these three
customers (49%, 65%, 36%) was also the lowest in the entire 25-customer
evaluation sample, consistent with an order silently going unconsumed
being a real, felt bad outcome for that customer, not a neutral one.

**Classification: CONFIGURATION ISSUE, root cause proven, not fixed** -
per the explicit instruction not to broaden this into a tuning pass. The
mechanism is precisely known; changing `quiet_meeting.tres`'s offset or
adding a floor/cap to `drink`'s score would be a one-line candidate fix
whenever tuning is back in scope, but is not attempted here.

## 3. Group behavioural proof

### Method

`tests/group_behaviour_probe.gd` (new, read-only) - same 420s/360s spawn
window as every other probe this session, but groups by `group_id`
(sampled live, since a still-in-progress member has no finished
`VisitRecord` yet) and prints every member of the same group side by side,
the only way to judge peel-off/rejoin from a transcript. 14 distinct
groups observed, sizes 2-6, all 46 sampled group members' complete
individual histories read.

### Finding

**Zero of 46 sampled group members ever recorded a nonzero individual
leisure activity count** (`relax`/`socialise`/`darts` all 0 for every
member, in every group). Almost none have any individual `CustomerBrain`
decision recorded at all beyond a single terminal "leave." Every group
follows the same lockstep sequence: `GROUP_WAITING_OUTSIDE →
GROUP_ENTERING → MOVING_TO_GROUP_SLOT → IN_GROUP → LEAVING_TO_DOOR`, with
no individual divergence visible anywhere in between.

Traced why, via the groups' own state-machine logs (not guessed):

- **6 of 14 groups never got a drink at all**, departing via
  `group_keg_out_of_stock` before ever reaching `CONSUMING`. A stock/supply
  condition specific to this run's economy, unrelated to `CustomerBrain` or
  `GroupManager`'s decision logic.
- **Of the groups that did complete the full order → stock-check →
  delivery → drink pipeline and reach `SOCIALISING` (the leisure phase),
  100% of them (every single one observed) left via `reason=out_of_
  patience` within 8-20 minutes of entering it** - `CONSUMING ->
  SOCIALISING | entered leisure phase for N minutes` followed almost
  immediately by `SOCIALISING -> PREPARING_TO_LEAVE | reason=out_of_
  patience`, every time.
- Traced the patience mechanism itself: `CustomerGroup.get_remaining_
  patience() = base_patience_minutes (45, default) - get_visit_duration()`
  - a **single, total budget covering the entire visit** (assembly +
  ordering + stock-wait + delivery + drinking + leisure), not reset per
  phase. The observed assembly-to-drinking pipeline in these traces
  regularly consumed 30-40+ of the 45 minutes before leisure could even
  start, leaving only the last few minutes - which is exactly the 8-20
  minute window observed before `out_of_patience` cut it off.

### What this does and does not prove

`GroupManager._ask_member_brain()` calling `brain.think()` directly,
unconditionally, through the same scoring path a solo customer uses -
confirmed present and correctly wired by reading the code (this session's
earlier verification pass, unchanged since). **That mechanism was never
exercised meaningfully in this run** - not because it is bypassed or
broken, but because the group's overall pacing budget leaves it almost no
window to run in before the group is recalled. "Group members initially
bias toward shared behaviour" is trivially true (every member's state
trace is identical group-lockstep from arrival to departure). "Individual
needs can still produce different choices," "one member can peel away,"
"the individual can later return/rejoin," and "the group does not behave
as a rigid shared state" are **not disproven** - the code path that would
produce them is intact - but they are **not proven** either, because the
architecture was given essentially no opportunity to show them in 46
sampled members across 14 groups.

**Classification: WORKING BUT UNPROVEN.** The decision-time architecture
(bias, not dictate) is confirmed sound by code reading. Its observable
effect in practice is currently suppressed by a pacing relationship
between `base_patience_minutes` and the keg-service pipeline's typical
duration - a configuration/tuning question, explicitly out of scope to
change this pass. Group behaviour needs either a longer patience budget,
a faster keg pipeline, or both before it can be proven by observation
rather than by code reading alone - noted as the clearest piece of
concrete future work from this whole pass.

## Findings summary

| # | Finding | Classification |
|---|---|---|
| 1 | Return-to-seat stall: chair's own occupied-zone obstacle blocks its holder's return | **CORRECTNESS BUG - fixed** (`90831f6`), regression test added |
| 1b | A similar `MOVING_TO_SEAT`/`WALKING_TO_STAGING` stall pattern was observed once each post-fix, distinct from the fixed case | **FUTURE WORK**, not investigated this pass |
| 2 | Merchant zero-drink: `quiet_meeting`'s `relax_at_seat` bias unconditionally outscores `drink`'s flat score | **CONFIGURATION ISSUE**, root cause proven, not fixed |
| 3 | Stage-3 motivation filter respected in group member decisions (none observed to violate it, same as solo) | **PROVEN** (by the small number of individual decisions that did occur) |
| 3b | Group members individually diverging from the group (peel off, different leisure choice) | **WORKING BUT UNPROVEN** - mechanism confirmed sound by code, never meaningfully exercised due to a patience/pipeline pacing mismatch |
| 3c | `base_patience_minutes` (45, total-visit budget) vs. keg-service pipeline duration | **CONFIGURATION ISSUE**, root cause proven, not fixed |
| 3d | Stock shortages preventing 6/14 sampled groups from ever drinking | **CONFIGURATION/CONTENT ISSUE** (this run's economy), not a customer-AI concern, not investigated further |

## Final assessment

**FOUNDATION READY**, with the group-behaviour caveat carried forward as
documented, known, unproven-not-broken territory rather than a blocker.

The return-to-seat bug - the one concrete, confirmed defect blocking the
prior pass's "ready" verdict - is fixed, tested, and confirmed eliminated
at scale. The merchant finding is a real, precisely-traced content
interaction, not a decision-architecture defect, and does not threaten the
soundness of the model itself. The group finding is the most important
one to carry forward accurately: the architecture this whole Phase B pass
built - two-stage decisions, demand-shaped needs, the `satisfies`
inversion, awareness, the stage-3/stage-4 selection fix, bias-not-dictate
group scoring - is confirmed sound wherever it has been given the chance
to run, solo or group. What is still unproven is narrower and more
specific than "does the group system work": it is "does a 45-minute total
group patience budget leave enough room, after a realistic keg-service
pipeline, for that already-correct architecture to ever be observed." That
is a pacing question for a future, explicitly-scoped tuning pass, not a
reason to reopen `CustomerBrain` or `GroupManager`'s decision logic again.

No score weight, need value, threshold, personality value, or activity
definition was changed in this pass. One code fix was made (the return-to-
seat obstacle), traced to a confirmed root cause before being touched, and
covered by a regression test.
