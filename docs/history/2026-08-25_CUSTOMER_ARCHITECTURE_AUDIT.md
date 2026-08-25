# Customer Architecture Audit — Phase B Stage 1

Read-only audit. No code, resource or scene changes were made in this pass.
Base commit `235b7ac` (working tree confirmed clean, `main`, matching brief).

## Method

Read `CustomerBrain.think()`, `ActivityRegistry`, `ActivityDefinition`,
`ActivityCondition`, `ActivityBehaviour` and `CustomerNeeds` directly. The
identity/preference layer, the awareness/destination/group layer, and
`customer.gd` plus every condition and behaviour script were each read in full
by a dedicated pass; findings below are sourced from that reading, not
inferred from names. `tests/darts_score_probe.tscn` was run fresh (120
samples, this session, this commit) rather than relying only on the brief's
numbers — see "Fresh probe run" below. Two `.tres` resources
(`visit_tavern_activity.tres`, `relax_at_seat.tres`) were opened directly to
get exact condition counts rather than estimating them.

### Fresh probe run (2026-08-25, this session)

```
samples=120
DARTS AVAILABILITY: eligible 409, on cooldown 10, condition-blocked 835
WHEN ELIGIBLE: would win 65 (15.9%); beaten by order_drink 114, relax_at_seat 208, socialise_at_seat 22
mean darts score 10.06, mean gap to winner 5.75
MEAN SCORE WHEN ELIGIBLE: order_drink 22.23, socialise_at_seat 12.31, relax_at_seat 11.80,
  visit_tavern_activity 10.06, drink 8.00, leave -11.50
relax contributions: base 7.50, visit_time +2.49, satisfaction +2.14, thirst -1.54 -> 11.74
darts contributions: base 8.50, visit_time 0.00, distance +0.61, satisfaction +1.25,
  thirst -0.56, group_cohesion -0.70 -> 10.11
ACTUAL OCCUPANCY (529 activity-entries): order_drink 298, drink 111, relax_at_seat 37,
  leave 60, socialise_at_seat 23, visit_tavern_activity 0
```

Same direction as the brief's numbers, same noisy-count/stable-mean pattern
called out in the work order: eligibility ~32.6% here vs 37.2% in the brief,
win-when-eligible 15.9% here vs 9.8%/22% across the brief's two runs — noisy,
as expected. The contribution breakdown is nearly identical to the brief's
(relax visit-time +2.49 vs +2.72, darts visit-time 0.00 both runs, group
cohesion -0.70 vs -0.58). One new data point: across 529 recorded
activity-entries in this run, `visit_tavern_activity` occupancy was **0**, not
just low — darts was chosen zero times in this sample. This does not
contradict the brief's 1.2%; it is consistent with a rate that low landing on
zero in a shorter run, exactly the "occupancy counts in the tens are noise"
warning in `PHASE_B_BRIEF.md`. Treated as confirmation, not a stronger claim.

## Verdict table

| Component | Verdict | Justification | Evidence |
|---|---|---|---|
| `CustomerBrain.think()` selection loop | **MODIFY** | Single flat pool: `for definition in registry.definitions: ... if score > best_score`. Everything needed for stage 3 (gate, score, cooldown, commitment, weighted-band selection, mandatory exemption, diagnostics) already lives here and is reusable as-is; only a motivation-selection pre-step and a filter-by-motivation clause are missing. | `customer_brain.gd:229-343` read directly; fresh probe confirms the flat-pool symptom (darts wins 15.9% of eligible samples, 0/529 occupancy). |
| `ActivityRegistry` | **KEEP** | Plain array + id lookup, no scoring logic of its own. Two-stage needs a way to ask "which definitions serve motivation X" — that can be a filter on `definitions` at the `think()` call site, or one small added query method mirroring `get_available()`; the registry's storage/lookup shape does not need to change. | `activity_registry.gd` read in full — 126 lines, no coupling to scoring order. |
| `ActivityDefinition` | **MODIFY** | Needs one new additive field — a declared "what this satisfies" table (need id -> amount) — to drive both motivation-stage filtering and the inversion `DECISIONS.md` §21 asks for. `base_utility`/`conditions`/`get_utility()` contract is otherwise sound and reusable at stage 3 unchanged. | `activity_definition.gd:107-118` (`get_utility`) unchanged-compatible; no `satisfies`-shaped field exists today (confirmed by full file read). |
| `ActivityCondition` (base) | **KEEP** | Generic gate+score contract is exactly what stage 3 still needs per-candidate; nothing here assumes a flat pool. | `activity_condition.gd` read in full, 56 lines. |
| `NeedThresholdCondition` | **KEEP** | Generic need gate/score, need-id-agnostic; works the same whether the candidate pool is flat or motivation-filtered. | Confirmed via targeted read (fork report). |
| `ProbabilityCondition` | **KEEP** | Pure noise injection (`randf() * score_weight`), orthogonal to pool structure. | Confirmed via targeted read. |
| `DestinationAvailableCondition` | **KEEP** | Hard gate on `DestinationBroker.has_available()`, unaffected by scoring-stage changes. | Confirmed via targeted read. |
| `DomainFlagCondition` | **KEEP** | Generic bool-flag gate/score (this is what implements the group-cohesion penalty correctly as a bias, not a gate — `gates=false`, `score_bonus=-5.0`). | `group_not_drinking_scoring.tres` read directly; fresh probe shows -0.70 mean contribution, consistent. |
| `RepeatDecayCondition` | **MODIFY (low priority)** | Reads raw repeat counters (`relax_count`/`darts_count`/`socialise_count`) through the same `get_need()`/`set_need()` API as true 0-1 needs — a milder instance of the same raw-value-in-needs pattern DECISIONS §20 names as a defect, though it does not distort the flat pool the way `remaining_visit_minutes` does (it decays a fixed ceiling, not a cross-activity comparison). | `repeat_decay_condition.gd` read; `customer_needs.gd:112-121,326-345` shows these counters going through `set_need`/`get_need` unclamped-to-1 (excluded from the 0-1 clamp branch). |
| `EndOfVisitPressureCondition` | **MODIFY (low priority)** | Score-only, reads `remaining_visit_minutes` directly (raw need_id, default). Appropriate *use* (departure pressure should scale with time left) but sits on the same raw field flagged for fix in item 2 below; becomes correct automatically once that field is reclassified as a context value with a normalised companion. | `end_of_visit_pressure_condition.gd` read; confirms it reads whatever need_id is configured without scale awareness. |
| `PreviousActivityAffinityCondition` | **KEEP** | Flat bonus keyed on `last_activity_id` membership; no coupling to pool structure. | Confirmed via targeted read. |
| `NearestPointDistanceCondition` | **KEEP** | Distance-falloff scoring against `DestinationBroker.get_candidates()`, scaled by `travel_willingness` (already 0-1). Explains the measured "distance bonus averages +0.39/+0.61 of a possible 4.0" finding structurally — falloff radius vs. `DartsPoint` placement is a level/tuning fact, not an architecture defect. | Confirmed via targeted read; positions per brief, not re-derived this pass. |
| `DeterministicEntryOnlyCondition` | **KEEP** | Deliberately always-false hard gate, used correctly to keep `return_to_seat` out of normal `think()` selection while still reachable via `enter_activity()`. | Confirmed via targeted read and probe log lines (`rejected 'return_to_seat': deterministic-entry-only activity` appears on every sample). |
| `CanAffordDrinkCondition` | **KEEP** | Reads `needs.wealth` as a context/domain value for a mandatory gate (can this customer afford anything), not as a scored "need" competing in the pool — the correct existing exception the raw-wealth lesson already produced. | Confirmed via targeted read. |
| `ActivityBehaviour` (base) | **KEEP** | `on_enter`/`tick`/`on_exit` contract is sound and activity-agnostic; no change needed for two-stage. | `activity_behaviour.gd` read in full. |
| `drink_behaviour` / `leave_behaviour` / `order_drink_behaviour` | **KEEP** | Mandatory-lifecycle bookkeeping only (`is_mandatory=true`, exempt from cooldown/commitment); these sit outside the leisure motivation contest by design already and need no change for stage 3. | `activity_definition.gd:223-229` (`is_mandatory`); behaviours confirmed as thin pass-throughs to `Customer` methods, no need writes. |
| `relax_at_seat_behaviour` | **MODIFY** | On completion it writes **zero** need deltas — only increments the raw `relax_count` repeat counter. It currently satisfies nothing declaratively; its entire competitive strength is `base_utility` (7.50) plus the raw-minutes visit-time term (+2.49 mean). This is the direct mechanical cause of relax dominating darts. | Confirmed: `Customer._on_relax_finished()` (per targeted read) only calls `needs.adjust(&"relax_count", 1.0)`. Fresh probe's relax contribution breakdown has no non-zero term besides base/visit_time/satisfaction/thirst — none of which is something relaxing itself produced. |
| `socialise_at_seat_behaviour` | **MODIFY (light)** | Already writes real need deltas on completion (mood +0.1/+0.05, engagement +0.25) — closest existing thing to "advertises what it satisfies" — but the deltas live as ad hoc export fields on the behaviour resource, not a declared table read by a motivation stage. Fold into the new `satisfies` field rather than rebuilding. | Confirmed via targeted read of `socialise_at_seat_behaviour.gd` and its exported effect fields. |
| `visit_tavern_activity_behaviour` (darts) | **KEEP mechanic / MODIFY declaration** | The partner co-op mechanic (`max_participants=2`, `find_nearby_activity_partner()`, 220px search) is a working, correctly-scoped piece of exactly the group/partner behaviour the target model wants — keep as-is. Its need effects live on `TavernActivityPoint` (mood/engagement/intoxication/wealth, `darts_count`) — same ad hoc-per-resource pattern as socialise, needs folding into a declared table, not rebuilding. | Confirmed via targeted read; `visit_tavern_activity.tres` read directly (`max_participants=2`). |
| `return_to_seat_behaviour` / `wander_behaviour` | **KEEP** | Deterministic pipeline step and deliberate always-available fallback respectively; neither participates in the motivation contest in a way that needs restructuring. | Confirmed via targeted read. |
| `CustomerNeeds` | **MODIFY** | Two separate defects. (1) Raw-valued fields exposed through the same API as true needs: `wealth` (int), `remaining_visit_minutes`/`visit_duration_minutes` (raw minutes — the measured +2.72/+2.49 mean relax bonus), `relax_count`/`socialise_count`/`darts_count`/`drinks_consumed` (raw counts). (2) Of `CUSTOMER_MODEL.md`'s target 4 needs, only `thirst` is actually implemented as a fluctuating 0-1 need. `social` has no dynamic need field at all — only `social_tendency`, a **static personality trait** copied in at spawn and never adjusted by (in)activity. `entertainment` and `relaxation` **do not exist as fields at all** — `entertainment_interest` is a static personality trait, and there is no relaxation-need field; `relax_count` is a bare repeat counter, not a satisfaction level. This is "absent," not "present but weak." | `customer_needs.gd` read in full — field list at lines 31-152, clamp exemption list at 322-329. Cross-checked against `CUSTOMER_MODEL.md` §2's named set (thirst, social, entertainment, relaxation). |
| `CustomerIdentity` (structure) | **KEEP** | Type + personality + visit intent + per-customer social memory is exactly the target model's Identity layer and is fully functional (92 assertions in `customer_identity_test`). | Confirmed via targeted read; matches `docs/CURRENT_STATE.md`'s "Verified" status. |
| `CustomerIdentity.get_activity_bias()` (application point) | **MODIFY** | Mechanism itself (`visit_intent.activity_score_offsets[activity_id]`, flat float, default 0.0) is sound and reusable unchanged — it can keep biasing the stage-3 score of an already-motivation-filtered candidate exactly as it does today. What needs to change is *when* it's read: today it's summed straight into the one flat pool at `customer_brain.gd:267`; under two-stage it still gets called from inside the (now filtered) loop, so this is a call-site change, not a rewrite of the method. `customer_identity_test.gd` exercises `get_activity_bias()` directly against fixed activity ids (e.g. `visit_tavern_activity`) and will keep passing unchanged. | `customer_identity.gd` + `visit_intent_config.gd` read directly; `customer_brain.gd:266-267` read directly; `customer_identity_test.gd:436-440` read (asserts merchant vs pirate bias differ for `visit_tavern_activity`). |
| `VisitIntentConfig` (9 intents) | **KEEP core / MODIFY application** | The 9 intents (`celebration`, `entertainment`, `group_drinking`, `heavy_drinking`, `passing_time`, `quick_drink`, `quiet_meeting`, `social_visit`, `waiting_for_someone`), each with duration/drink-count/disposition-offset shape, map well onto `CUSTOMER_MODEL.md` §1's "visit purpose" — this is present, not absent. What's missing: intents currently express bias only as per-activity-id score offsets, with no way to say "this visit leans toward the entertainment motivation" independent of which specific activity exists yet. A parallel motivation-weight (or reuse of the existing offsets at the new stage-2 motivation-selection step) is additive, not a redesign of the resource. | `visit_intent_config.gd` + `visit_intent_registry.gd` read directly; 9 `.tres` files confirmed under `Data/customer_ai/visit_intents/`. |
| `Personality` | **KEEP** | `create_visit_profile()` genuinely does duplicate-and-jitter as the brief states: duplicates the Resource, jitters 13 named 0-1 traits by `±trait_variance`, jitters 6 named multipliers proportionally (floor 0.05), all through a caller-supplied RNG for determinism. Per-visit variation is present and functioning, not missing. | `personality.gd` read directly, confirmed method body and both name lists. |
| `CustomerType` | **KEEP** | 69 of its own `@export` fields plus composed `Personality` (~19) and per-entry `DrinkPreference` (~4 each) reach the brief's "~98 fields" scale. Weighted-preference resolution (`get_valid_drink_preferences`, `find_preference_for`, `get_orderable_drinks`) with legacy fallback already implements the data-driven preferences model the target architecture wants. Several fields (`customer_category`, `priority_level`, information-system block) are confirmed unused placeholders, not defects — they're explicitly reserved, matching `CUSTOMER_MODEL.md`'s "leave room for, don't build" instruction for `information`. | `customer_type.gd` read directly, field count grepped. |
| `DrinkPreference` | **KEEP** | Pure preference/format data (`drink`, `weight`, `preferred_format_ids`, `typical_servings`); orthogonal to needs/motivation, no change needed. | `drink_preference.gd` read directly. |
| `SocialCompatibility` | **KEEP** | Entirely about which customers get along/approach/avoid/partner (tag/group/history/disposition scoring, `would_approach`/`would_avoid`/`find_best_partner`) — the mechanism a talking/social activity would use to pick a partner, not a need or motivation concept itself. Already functional and used by `socialise_at_seat`'s partner search. | `social_compatibility.gd` read directly (all-static, 301 lines). |
| `SocialPresenceService` (conversation pairing) | **KEEP as a standalone feature** | Runs a genuine 2-second wall-clock proximity/pairing tick (`_process`, deliberately real-time not `WorldTime`-scaled), forms and expires conversations, uses `SocialCompatibility` and per-customer social memory correctly. This slice works and should not be touched. | `social_presence_service.gd` read directly, `_process`/`_form_new_conversations`/`_expire_finished` confirmed. |
| `SocialPresenceService` as "Awareness" (`CUSTOMER_MODEL.md` §3) | **MODIFY (extend)** | Confirmed genuinely absent for the activity-attraction role: no method exposes "who is near X" or "is activity Y already in use" to any caller, and grepping every `CustomerBrain`/`ActivityCondition` file finds zero callers into this service. `DestinationBroker` structurally can't fill the gap either — occupied `Reservable`s are filtered out *before* scoring, never surfaced as a positive signal. This is `CUSTOMER_MODEL.md`'s own claim ("the one layer that genuinely does not exist") confirmed by code reading, not assumed from the name. New, but small: an occupancy/proximity query plus one new condition, reusing this service's or `DestinationBroker`'s existing distance math rather than new infrastructure — matches the brief's "keep it cheap" instruction. | Grep across `systems/customer_ai/` for calls into `SocialPresenceService` from scoring code: none found. `destination_broker.gd` read directly — `has_available`/`reserve_nearest` only ever see free reservables. |
| `DestinationBroker` | **KEEP** | Correctly scoped to its actual job (nearest free slot); the awareness gap above needs an *additional* query path, not a change to reservation logic itself. | `destination_broker.gd` read in full, 70 lines. |
| `Reservable` | **KEEP** | Correct single-holder capacity primitive with a timeout safety net and a `transfer_to()` group-handoff path already built for exactly the group-to-member handoff pattern this model needs. Occupancy visibility for awareness is better answered by enumerating `DestinationBroker.get_candidates()` than by changing this class. | `reservable.gd` read in full, 278 lines. |
| `GroupManager._offer_leisure_activity()` | **KEEP** | Confirmed by direct reading (`group_manager.gd:1479-1535`) to gate only (drinking-state check, away-capacity cap, chance roll, idle-member pick) and then call `_ask_member_brain()` (`:1541-1555`), which literally does `brain.call(&"think")` — the same competitive scoring a solo customer runs, unmodified. `DECISIONS.md` §22's "bias, not dictate" claim is accurate for the live path. A legacy dictate-fallback (`_start_leisure_activity`) exists but only runs when no brain is configured — an unconfigured-test-harness compatibility path, not the live one. | `group_manager.gd:1479-1555` read directly by targeted pass. |
| `CustomerGroup`'s interaction with member decisions | **KEEP** | Group cohesion enters scoring as a plain `DomainFlagCondition` (`group_not_drinking_scoring.tres`, `score_bonus=-5.0`, `gates=false`) attached to darts like any other condition — a bias, not a separate code path, exactly matching §22. | `group_not_drinking_scoring.tres` read directly; fresh probe confirms -0.70 mean contribution, non-gating (darts is still eligible 409/1254 samples with the flag sometimes true). |
| `Customer`'s state machine | **KEEP** | A genuinely separate, denser physical/navigation-phase state machine (17 states: `ENTERING`...`GROUP_INSIDE_STAGING`) layered *under* `CustomerBrain.State`'s 5 abstract states — not a duplicate or a conflicting second brain. This is the class doc comment's own stated design ("generic states only" at the brain level; physical phase belongs to the actor) working as intended. | Confirmed via targeted read of `customer.gd`'s `State` enum and its 8 `.think()` call sites, all genuine completion callbacks. |
| `Customer.get_activity_flags()` (domain flags) | **KEEP** | 14 bool flags (`is_seated`, `has_ordered_drink`, `group_is_drinking`, etc.) feeding `DomainFlagCondition` generically; no restructuring needed for two-stage. | Confirmed via targeted read, `customer.gd:2720-2789`. |
| `Customer.get_diagnostics_snapshot()` | **MODIFY** | Already returns money/thirst/mood/intoxication/visit-time/drinks/engagement/partner-ids — real data, not placeholder. Missing for the inspector: `patience`/`energy` (exist on `CustomerNeeds`, simply not copied onto the snapshot — cheap), motivation (does not exist anywhere yet — must be built by item 1 below, then surfaced), and candidate-scores/rejection-reasons/execution-outcome, which **already exist** as `DecisionRecord` fields populated by `CustomerBrain._report_decision()`, but only when `report_manager` is configured and export is enabled — i.e. gated behind diagnostic-export mode, not available for a live hover. This is exactly the "collected, computed, then discarded before reaching any surface" pattern `CUSTOMER_INSPECTOR.md` names. | `customer.gd:2796-2822` read directly; `customer_brain.gd:715-789` (`_report_decision`) read directly, confirms candidate scores/contributions/rejections are already computed and only need an always-on per-customer cache, not new instrumentation. |

## Split

37 rows: **25 KEEP (67.6%) / 12 MODIFY (32.4%) / 0 REPLACE (0%)**.

No component earns REPLACE. The execution layer — conditions, behaviours,
destination broking, reservations, groups, identity, personality, preferences
— is sound and does what `docs/CURRENT_STATE.md` already says it does. The
MODIFY list clusters tightly around exactly the three things
`PHASE_B_BRIEF.md` and `DECISIONS.md` §19-21 already named: the flat pool
(`think()`, `ActivityRegistry`'s consumption pattern), the raw-need defect
family (`CustomerNeeds`, two of its scoring conditions), and the missing
"advertise what you satisfy" inversion (`ActivityDefinition` plus two
behaviours/one point resource). Nothing outside that cluster needs to move.

## The most important question

**Two-stage is buildable inside the existing `CustomerBrain.think()` and
`ActivityRegistry` — MODIFY, not REPLACE.**

The current loop, verbatim from `customer_brain.gd:229-260`:

```gdscript
for definition: ActivityDefinition in registry.definitions:
    if definition == null:
        continue
    if not definition.is_available(context):
        ... continue
    if is_on_cooldown(definition, context.world_minutes):
        ... continue
    var score: float = definition.get_utility(context)
    if identity != null:
        score += identity.get_activity_bias(definition.activity_id)
    ...
    if score > best_score:
        best_score = score
        best = definition
```

Every mechanism stage 3 of the target model needs is already here: iterate
candidates, hard-gate on conditions, score, apply identity bias, track the
best, then weighted-select among near-top candidates
(`_select_weighted()`, unchanged). Two-stage requires two additive changes,
neither of which touches this shape:

1. A motivation-selection step computed once per `think()` call, before this
   loop, from `needs` + `identity.personality` + `identity.visit_intent` +
   group context (all already available on `context`/`identity` — nothing new
   to plumb in). This can be a small new function, not a new class hierarchy.
2. One filter clause inside the existing `for` loop —
   `if not definition.satisfies(chosen_motivation): continue` — reading the
   new declarative field `ActivityDefinition` needs anyway for item 3 of the
   Stage 2 priority list. Everything after that line (`is_available`,
   `get_utility`, cooldown, commitment, weighted selection, diagnostics
   recording) is untouched.

`ActivityRegistry` needs nothing structural — it is a flat store today and
can stay one; "which activities serve this motivation" is a filter applied at
the call site (or one small added query method mirroring the existing
`get_available()`), not a reorganisation of storage. A separate "should this
visit continue" pre-check (linger vs leave) is also addable as its own small
step before motivation selection; much of its substance already exists as
the mandatory out-of-money leave check at `think()`'s top
(`customer_brain.gd:189-202`) and `leave`'s own scoring conditions — this
needs consolidating into one explicit stage-1 decision, not new machinery.

This is a scope-shrinking finding, not a scope-growing one, **with one
qualification stated plainly below.**

## Needs: normalised vs raw

**Normalised 0.0-1.0** (confirmed by `customer_needs.gd`'s clamp branch,
lines 316-330): `mood`, `patience`, `energy`, `intoxication`, `thirst`,
`social_tendency`, `engagement`.

**Raw** (excluded from the clamp branch, or typed as `int`):
- `wealth` — raw currency (`int`). Known defect per DECISIONS §20 (broke
  leaving in Phase A part 5).
- `remaining_visit_minutes` / `visit_duration_minutes` — raw world minutes.
  This is the measured relax-dominance cause (+2.49 to +2.72 mean, this
  session's and the brief's runs respectively).
- `relax_count`, `socialise_count`, `darts_count` — raw repeat counts.
- `drinks_consumed` — raw count.

All five raw fields are reached through the exact same `get_need()`/
`set_need()` API as the seven normalised ones, which is itself part of the
defect: nothing in the type system or the API distinguishes a need from a
context value, so a new condition author has no signal that
`remaining_visit_minutes` behaves differently from `thirst`.

**Beyond the raw-value question, a bigger gap**: of `CUSTOMER_MODEL.md` §2's
target 4 needs (`thirst`, `social`, `entertainment`, `relaxation`), only
`thirst` is implemented as an actual fluctuating 0-1 need. `social` has no
need field — only the static personality trait `social_tendency`, seeded once
and never adjusted by isolation or company. `entertainment` and `relaxation`
have **no field at all** — `entertainment_interest` is a static trait, and
`relax_count` is a bare counter, not a level. This is genuinely absent, not
present-but-weak, and it is larger than "audit the raw values" implies — see
the qualification below.

## Extension test (`CUSTOMER_MODEL.md` §5)

Counted directly from the `.tres` resources, not estimated:

- `visit_tavern_activity.tres` (darts): **12** condition resources attached
  (`is_settled`, `free_to_leave_seat`, `visit_activity_availability`,
  `visit_activity_min_time_remaining`, `visit_activity_distance_scoring`,
  `darts_repeat_decay`, `visit_activity_satisfaction_scoring`,
  `visit_activity_thirst_scoring`, `decision_variance`,
  `group_has_away_capacity`, `group_not_drinking_scoring`,
  `after_socialise_darts_affinity`).
- `relax_at_seat.tres`: **9** condition resources attached.

Today, adding one new leisure activity (cards, a musician) means: 1
`ActivityDefinition`, 1 behaviour (new or shared), 1 destination setup, **and
somewhere between 8-12 hand-authored `ActivityCondition` resources**, each
tuned against the same flat pool every existing activity already competes in
— plus open-ended rebalancing risk to every other activity's `base_utility`
so the new one neither dominates nor never wins. That is 12-16+ files/edits
for one activity, fails the target's "one resource, one behaviour, one
destination, no new conditions, no rebalancing" test outright, and confirms
`DECISIONS.md` §21's inversion (activities declaring what they satisfy,
scored against a per-motivation candidate set) is the actual fix — a
motivation-filtered candidate set needs far fewer, more generic conditions
per activity because it is no longer defending its score against activities
serving an unrelated need.

## Inspector gap

Most of what `CUSTOMER_INSPECTOR.md`'s developer tier wants is **already
computed**, confirming its own claim that this is "mostly a rendering job."
Specifically:

- Needs: `thirst`/`mood`/`intoxication` are already on
  `get_diagnostics_snapshot()`. `patience`/`energy` exist on `CustomerNeeds`
  but are not copied onto the snapshot — a one-line addition each.
- Candidate activities with scores, and rejection reasons: **already fully
  computed** in `CustomerBrain.think()` (`eligible_for_report`,
  `rejected_for_report`, `contributions_for_report`) and packaged into
  `DecisionRecord` by `_report_decision()` — but only when `report_manager`
  is set and `is_export_enabled()` is true, i.e. gated behind diagnostic
  export mode, and stored in an aggregate history rather than "this
  customer's current decision, right now." The inspector needs a bridge —
  `CustomerBrain` caching its own last decision unconditionally (not gated
  on export) — not new score/rejection computation.
- Reservation/execution outcomes: already reported via
  `report_manager.record_activity_failure()` /
  `report_issue()` at `customer_brain.gd:519-527`, same export-gating issue.
- Group membership/role: available through existing group/customer
  references; not separately verified this pass but no evidence of absence.
- **Genuinely missing, not just unsurfaced**: motivation (stage 2's winner)
  does not exist anywhere in the codebase yet — it is new work created by
  implementing item 1 above, not a pre-existing value to expose.

## Which tests constrain or break

- `customer_identity_test.gd` (92 assertions) exercises `get_activity_bias()`
  directly against fixed activity ids including `visit_tavern_activity`
  (lines 436-440) and calls `CustomerBrain._select_weighted()` with synthetic
  score dictionaries (lines 291-333, 514, 549). Both are compatible with
  two-stage **if** `get_activity_bias()` and `_select_weighted()` keep their
  current signatures and are simply invoked from inside a filtered loop
  rather than the full one — confirmed unbroken by design, not just assumed.
- `leave_decision_probe.gd` calls `ActivityDefinition.get_utility()` /
  `get_utility_breakdown()` directly per definition — same compatibility
  condition; no hard assertion found coupling it to "every activity is always
  scored."
- `darts_score_probe.gd` itself — the brief's own before/after instrument —
  computes eligibility by walking `registry.definitions` directly, bypassing
  `CustomerBrain`. After motivation-gating exists, "eligible" as this probe
  currently defines it (condition-satisfied only) will no longer be the same
  thing as "actually competing in the pool `think()` uses." The probe will
  keep running and printing numbers, but its output will need a second
  column (motivation-gate pass/fail) to remain the correct before/after
  instrument rather than silently changing what it measures.
- Group tests (`group_framework_test`, `group_keg_loop_test`,
  `group_live_test`) — `GroupManager._offer_leisure_activity()` delegates
  unchanged to `CustomerBrain.think()`; since two-stage changes what `think()`
  returns, any group-activity-participation numbers these tests assert or log
  will shift as a direct, expected consequence, not because group code
  itself needs to change. Re-baseline after Stage 2, don't treat a shift here
  as a regression without checking the cause first.
- `phase_a_audit_probe` / `phase_a_gate_audit` — diagnostic dumps with no
  PASS/FAIL text by design; unaffected either way.
- `phase_4a_integration_test`'s known payment flakiness is unrelated to any
  of this and untouched.

## Implementation plan (Stage 2 priority order)

1. **Two-stage decision.** Add `ActivityDefinition.satisfies:
   Dictionary[StringName, float]` (need id -> amount). Add one motivation-
   selection step in `CustomerBrain.think()` before the existing loop,
   reading `needs` + `identity.personality`/`visit_intent` + group context.
   Add the one filter line inside the existing loop. Consolidate the
   existing out-of-money forced-leave check and `leave`'s own scoring into
   one explicit "should this visit continue" stage-1 step. **Risk: medium** —
   this is the most central function in the system and the one with the most
   test surface (`customer_identity_test`, `leave_decision_probe`,
   `darts_score_probe`, all group tests indirectly), but the change itself is
   additive/filtering, not a rewrite of the scoring contract.

2. **Needs normalised and audited.** Fix `relax_visit_time_scoring.tres`
   first, regardless of sequencing elsewhere — it distorts every measurement
   taken after it, including this pass's own. Reclassify `wealth`,
   `remaining_visit_minutes`/`visit_duration_minutes`, and the three repeat
   counters as context values with a type-level or naming distinction from
   real needs, not just a documentation note. **Then** add real `social`,
   `entertainment` and `relaxation` needs — fields that actually rise when
   unmet and fall when an activity satisfies them — since the audit found
   these absent, not weak. **Risk: medium-high** — the raw-value fix is
   small and mechanical; designing rise/decay curves for three needs that
   did not exist before is real new design work the brief's "audit the
   values" framing understates. Flagging this now rather than discovering it
   mid-Stage-2.

3. **Activities declare what they satisfy.** Populate the new `satisfies`
   field for all 8 activities; move `relax_at_seat`'s (currently zero) and
   `socialise_at_seat`'s/darts' (currently ad hoc, resource-specific) need
   effects into behaviour completion writing against the declared table
   consistently. Prune each leisure activity's condition set down once
   motivation-filtering means it is no longer defending its score against
   the whole flat pool — validate directly against the extension test by
   counting resources for one hypothetical new activity before/after.
   **Risk: medium** — touches every existing leisure activity's tuning, but
   mechanically straightforward once items 1-2 land.

4. **Lingering as default, departure as decision.** Mostly already working
   (13/60 chosen-vs-timed-out per `CURRENT_STATE.md`). Wire up or remove the
   currently-dead `is_committed()` (confirmed never called). Re-tune leave's
   pressure curve once items 1-3 change what it's competing against.
   **Risk: low.**

5. **Awareness/opportunities.** Add one cheap occupancy/proximity query
   (reusing `SocialPresenceService`'s or `DestinationBroker`'s existing
   distance math — do not build parallel infrastructure) and one new
   condition type feeding "someone's already here" into the entertainment/
   social motivation's scoring. Scope strictly to what the brief asks for
   (proximity + in-use), nothing more. **Risk: low-medium** — mainly a
   scope-discipline risk, not a technical one.

## Stop point

Verdict split: **67.6% KEEP / 32.4% MODIFY / 0% REPLACE.** The two-stage
change is confirmed buildable inside the existing `CustomerBrain.think()` and
`ActivityRegistry` — no replacement of core architecture is required.

**One qualification, stated plainly as the brief asks**: the scope is not
smaller than the brief assumed on the *decision-loop* side, but it is
**larger than "audit the raw values" implies on the needs side**. Item 2
above is not a bug-fix pass — three of the four target needs
(`social`, `entertainment`, `relaxation`) do not exist as need fields at all
and require actual design (what raises them, what decays them, what
satisfies them), not just reclassifying an existing raw field. This should
be sized accordingly before Stage 2 starts, not discovered partway through
it.

Stopping here per the brief. Awaiting direction before Stage 2.
