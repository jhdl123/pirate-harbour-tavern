# Customer AI System

A foundation, not a finished AI: today's customers still spawn, sit, order
one drink, drink it, pay and leave - exactly as before this system existed.
What changed is *how* that sequence is decided and represented, so a much
deeper simulation can be built on top of it without redesigning anything
here. See `CUSTOMER_AI_CLEANUP_REPORT.md` (or the chat history, if that file
does not exist in your copy) for exactly which lines of `Customer` moved
where and why each move was judged safe.

## Folder structure

```text
systems/customer_ai/
  personality.gd            Personality - shared, authored traits per CustomerType
  customer_needs.gd          CustomerNeeds - one customer's live, changing state
  activity_registry.gd       ActivityRegistry - every ActivityDefinition, id-indexed
  destination_broker.gd      DestinationBroker - tag -> real Reservable, tavern-wide
  customer_brain.gd          CustomerBrain - the think/choose/reserve/perform loop

  activities/
    activity_context.gd      ActivityContext - the parameter object everything below shares
    activity_condition.gd    ActivityCondition - base class for pluggable rules
    activity_behaviour.gd    ActivityBehaviour - base class for "what happens"
    activity_definition.gd   ActivityDefinition - one activity's data

    conditions/
      need_threshold_condition.gd     gate/score against one CustomerNeeds value
      probability_condition.gd        soft random scoring nudge, never gates
      destination_available_condition.gd  gate on DestinationBroker availability
      domain_flag_condition.gd        gate on an actor-supplied boolean flag

    behaviours/
      order_drink_behaviour.gd  the seated customer's order-and-wait sequence
      drink_behaviour.gd        bookkeeping for the drinking phase
      leave_behaviour.gd        starts the walk to the door
      wander_behaviour.gd       intentionally does nothing - the fallback

Data/customer_ai/
  personalities/       Personality .tres instances (one per CustomerType, optional)
  conditions/           shared ActivityCondition .tres instances
  behaviours/           shared ActivityBehaviour .tres instances
  activities/           ActivityDefinition .tres instances (order_drink, drink, leave, wander)
  activity_registry.tres   the one registry GameManager points at
```

## Class responsibilities

- **`Personality`** - authored, shared, never mutated. One per `CustomerType`.
  Seeds a customer's starting `CustomerNeeds` at spawn; after that the two
  are independent.
- **`CustomerNeeds`** - one customer's own, private, constantly-changing
  state: mood, wealth, patience, energy, intoxication, social tendency,
  remaining visit time, visit purpose, preferred drinks, favourite
  activities, a relationships stub and a reputation stub. A plain
  `RefCounted`, never a shared `Resource` - see its own doc comment for why.
- **`ActivityContext`** - one small object bundling everything a condition
  or behaviour needs (the actor, its needs, its position, actor-supplied
  domain flags, and the activity currently being evaluated). Built fresh
  every think cycle; mirrors `InteractionRequest` from the interaction
  framework.
- **`ActivityCondition`** - one reusable, composable rule. `is_satisfied()`
  is a hard gate; `score()` is a soft preference added into the activity's
  utility. Four concrete conditions exist; a bespoke one is still just a new
  subclass.
- **`ActivityBehaviour`** - what actually happens while an activity runs
  (`on_enter`/`tick`/`on_exit`). Stateless and shareable - two customers
  running "Leave" at once share the same `LeaveBehaviour` instance.
- **`ActivityDefinition`** - one registered activity: identity, scoring
  (`base_utility` + `conditions`), which `Reservable` tag it needs (if any),
  and which `ActivityBehaviour` runs it.
- **`ActivityRegistry`** - every `ActivityDefinition`, id-indexed, with the
  same shape and validation pattern as `ItemRegistry`.
- **`DestinationBroker`** - resolves a destination tag to a real `Reservable`
  anywhere in the tree, built entirely on the existing `Reservable`/
  `ReservationService` framework (see "Destinations" below).
- **`CustomerBrain`** - runs the loop for one actor. Generic `State` enum
  only (`THINKING`, `NAVIGATING`, `PERFORMING_ACTIVITY`, `WAITING`,
  `LEAVING`) - never a state per activity.

## How the AI thinks

```text
think()
  |
  v
build an ActivityContext (actor, needs, position, domain flags)
  |
  v
ActivityRegistry.get_available(context)   <- every ActivityDefinition whose
  |                                          conditions.is_satisfied() all pass
  v
score each candidate: base_utility + sum(condition.score())
  |
  v
highest score wins
  |
  v
destination_tag empty?  --no--> DestinationBroker.reserve_nearest()
  |  yes                              |
  v                                   v
behaviour.on_enter(context)  <---  reservation secured
```

`CustomerBrain.think()` is the full Evaluate -> Choose -> Reserve -> Perform
pass, called at a genuine decision point. `CustomerBrain.enter_activity(id)`
is a direct transition that skips scoring entirely - used for the two
places in today's loop that have no real branch yet (a freshly seated
customer always wants to order; being served always leads to drinking).
Both still run through the same reserve/`on_enter`/`on_exit` machinery, so a
future activity reached either way is equally capable.

**Event-driven, not polled.** There is no per-frame ticking anywhere in this
system today. `Customer` calls `think()` or `enter_activity()` at real
moments - seated, served, finished drinking, patience expired - the same
way `WorldTime`'s scheduler and `ActionRunner` are event-driven rather than
polling. See "Performance considerations" below.

## Activity lifecycle

1. `ActivityRegistry.get_available()` filters every definition by
   `is_available()` (all conditions' `is_satisfied()`).
2. `CustomerBrain` scores the survivors and picks the highest.
3. If the chosen activity has a `destination_tag`, `DestinationBroker`
   reserves the nearest free match. Losing that race (another actor got
   there first) is treated the same as "no candidate" - `CustomerBrain`
   goes to `WAITING` rather than getting stuck.
4. `behaviour.on_enter(context)` runs once.
5. `behaviour.tick(context)` runs on whatever cadence that activity needs
   (most need none - see `ActivityBehaviour`'s doc comment).
6. Something calls `think()` or `enter_activity()` again (or
   `begin_leaving_permanently()`). `behaviour.on_exit(context, completed)`
   runs, the destination reservation (if any) releases, and the cycle
   repeats.

## Today's four activities, honestly

- **Order Drink** - real. Replaced the unconditional `choose_order()` call
  in `arrive_at_seat()`. Represents the *whole* order-through-serving arc,
  because the underlying mechanic (waiting for the player) has no natural
  sub-decision point yet.
- **Drink** - bookkeeping only. `Customer.interact()` still does 100% of the
  validation and serving mechanics, unchanged; this activity exists so the
  drinking phase is a real, queryable `ActivityDefinition` rather than an
  untracked engine state.
- **Leave** - real. Replaced the unconditional `begin_leaving()` calls after
  a drink finishes and after patience expires. Reliably wins today (see
  `leave.tres`'s `base_utility` versus `order_drink.tres`'s), but scores
  more attractively as mood drops - a low-mood customer is measurably closer
  to leaving without ordering at all, with zero code changes needed to make
  that the outcome for a grumpier `Personality`.
- **Wander** - inert filler. Guarantees `CustomerBrain` never has an empty
  candidate list; does nothing yet.

## Destinations

An activity names a destination only by tag - `&"seat"`, `&"bar"`,
`&"fireplace"` - never a node path. `Reservable._ready()` joins a group per
tag it carries (`Chair` already carries `&"seat"`), so `DestinationBroker`
finds every match tavern-wide with `get_nodes_in_group()` and hands the
search to `ReservationService`, which already does distance scoring and
safe claiming. **Adding a new destination type needs nothing here or in
`DestinationBroker`** - tag a `Reservable` with the new tag, and any
activity that asks for it finds it automatically.

## Adding a new customer type

1. Create a `CustomerType` `.tres` as before.
2. Optionally create a `Personality` `.tres` and assign it to the new
   type's `personality` field - see `Data/customer_ai/personalities/` for
   two examples with different baseline moods.
3. Nothing else. `CustomerNeeds.seed_from()` reads whatever `Personality`
   is assigned (or falls back to plain defaults if none is).

## Adding a new activity

Usually:

1. Create an `ActivityDefinition` `.tres` (`Data/customer_ai/activities/`).
2. Give it an `activity_id`, a `base_utility`, and whichever
   `ActivityCondition` `.tres` instances gate/score it - reuse
   `NeedThresholdCondition`, `ProbabilityCondition`,
   `DestinationAvailableCondition` or `DomainFlagCondition` from
   `Data/customer_ai/conditions/` wherever they fit; only create a new
   condition `.tres` for a genuinely new rule.
3. Point `destination_tag` at whatever `Reservable` tag it needs (or leave
   it empty).
4. Point `behaviour` at a shared or new `ActivityBehaviour`.
5. Add it to `activity_registry.tres`'s `definitions` array.

A genuinely bespoke activity needs one new `ActivityBehaviour` subclass
(`.gd`) - never a change to `ActivityDefinition`, `ActivityRegistry` or
`CustomerBrain`.

## Adding a new behaviour

Extend `ActivityBehaviour`, override whichever of `on_enter`/`tick`/
`on_exit` it needs, remembering it is shared across every customer running
that activity - no state on `self`. Anything per-customer belongs on
`ActivityContext.actor` or `.needs`.

## Adding future VIPs

Not implemented - the brief asks only to leave room. `CustomerType` already
has `customer_category`, `priority_level` and `importance_score` fields,
unread by anything today. The intended shape when this is built out:

- A VIP is still a `CustomerType` (or several), just with `customer_category`
  set to something like `&"merchant"` or `&"naval_officer"`.
- A dedicated `ActivityDefinition` or two, gated by a `DomainFlagCondition`
  on a new flag (e.g. `&"is_vip"`) that `Customer.get_activity_flags()`
  would need to start reporting.
- Unique dialogue and notification triggers most likely live outside this
  system entirely (a UI/notification layer reading `customer_category` when
  one spawns), not inside `ActivityBehaviour`.

## Future social simulation

Also not implemented. `CustomerNeeds.relationships` (an empty `Array[Node]`)
and `reputation` exist specifically so a future Relationship resource and a
"join a conversation"/"wait for a companion" activity have somewhere to
read and write without this file changing again.

## Extension points, summarised

| Want to... | Touch |
|---|---|
| Tune how attractive an activity is | The `.tres` - `base_utility`, conditions |
| Add a common-shape rule | A new `.tres` of an existing condition class |
| Add a genuinely new rule | New `ActivityCondition` subclass |
| Add a new thing to do | New `ActivityDefinition` `.tres` + registry entry |
| Add new customer-specific gating data | `Customer.get_activity_flags()` |
| Add a new destination type | Tag a `Reservable` - nothing else |
| Reuse this for a non-customer actor | Give it `CustomerNeeds`/its own needs class, a `get_activity_flags()`, and its own `ActivityRegistry` |

## Performance considerations

- **No per-frame polling.** `CustomerBrain` has no `_process()`. Every
  `think()`/`enter_activity()` call is triggered by an existing event
  (seated, served, drink finished, patience expired) - the same
  event-driven convention `WorldTime`'s scheduler already established.
- **`ActivityContext` is cheap.** A `RefCounted`, created fresh per think
  cycle and discarded - no pooling needed at today's customer counts.
- **`DestinationBroker` searches are O(reservables with that tag), not
  O(everything in the scene)** - `get_nodes_in_group()` only touches nodes
  actually tagged with the relevant destination.
- **`ActivityRegistry` builds its id lookup once** and reuses it
  (`_ensure_lookup()`/`rebuild()`), the same caching shape as `ItemRegistry`.
- **Conditions and behaviours are shared, not duplicated per customer** -
  unlike `ActorMovement`/`ActorNavigation` profiles, which *do* need private
  copies because they hold per-actor tuning. Nothing in `ActivityCondition`
  or `ActivityBehaviour` is per-actor state, so sharing is correct, not a
  shortcut.
- **Not yet load-tested with many simultaneous customers.** The `think()`
  call sites are all rare, discrete events per customer (a handful of times
  per visit), so this should scale the same way `OrderManager` does, but
  see `KNOWN_ISSUES.md`/`TEST_CHECKLIST.md` conventions from the last
  cleanup pass - this has been traced, not play-tested under load.

## Phase 2A — multi-activity visits

A visit is no longer always exactly Order → Drink → Leave. After a drink
finishes, `Customer._on_drink_finished()` now asks `CustomerBrain.think()`
to choose between three real, competing activities instead of assuming
Leave: **Relax at Seat**, **Order Drink** (again), or **Leave**.

**Chair lifecycle changed.** A chair is now reserved for the customer's
*entire* visit, not released after the first drink. `Customer.
release_reserved_chair()` is the single place a visit's reservation ends
(called from `begin_leaving()`, `finish_customer()`, and `_exit_tree()` as a
safety net for forced removal) - it marks the chair for cleaning if
`drinks_consumed_this_visit > 0`, or releases it plainly otherwise (a
customer who never got served shouldn't dirty a chair nothing was ever
placed on). `Chair.begin_use()` now accepts being called again while
already `IN_USE`, since a second drink reuses the same chair rather than a
fresh reservation.

**Order Drink can fire more than once.** The old `_order_attempted` flag
permanently blocked re-ordering; it's gone. The real gate is simply "not
currently mid-order" (`has_ordered_drink=false`, reused from `leave.tres`),
which naturally reopens once a drink finishes. A new
`under_drink_limit` domain flag (`Customer.drinks_consumed_this_visit <
GameConfig.maximum_drinks_per_visit`) additionally gates Order Drink and,
inverted, adds a scoring bonus to Leave once the limit is hit - see
`DomainFlagCondition`'s new `gates`/`score_bonus` fields, which let one
condition class either hard-gate or just nudge scoring without ever
disqualifying an activity.

**Relax at Seat** (`relax_at_seat.tres` / `RelaxAtSeatBehaviour`) is the new
activity: requires a reserved chair and no active order, schedules a
random-duration completion through `WorldTime` (never a per-frame count),
and calls `think()` again on completion - the same event-driven shape as
everything else in this system.

**A shared `decision_variance.tres`** (`ProbabilityCondition`) is attached
to Order Drink, Relax and Leave so their competition has visible variety
between customers rather than one activity mechanically always winning.

## Phase 2B — attributes, real decisions, and a diagnostic report

Phase 2A proved activities could chain. Phase 2B makes *why* one wins over
another mostly about the individual customer rather than mostly random
variance, and adds a structured report you can hand to someone else after a
playtest. No new activities - still just Order Drink, Relax at Seat, Leave.

### Runtime customer attributes

All new attributes live on `CustomerNeeds` (per-customer, never shared -
see its own doc comment) alongside the Phase 1 fields:

- `thirst` (0-1) - seeded from `CustomerAIBalanceConfig`'s starting-thirst
  range, reduced by `thirst_reduction_per_drink` each time a drink finishes.
- `mood` - this **is** "satisfaction". Phase 1 named it `mood`;
  Phase 2B's brief calls the same concept satisfaction. Renaming the field
  would have meant re-pointing every existing condition resource for no
  behavioural gain, so it stays `mood` in code - see `CustomerNeeds`'s class
  doc comment for the explicit bridge.
- `wealth` - "available money", already existed, now actually spent
  (`Customer._on_drink_finished()` deducts the payment amount the same
  instant `customer_paid` fires) and gated (`CanAffordDrinkCondition`).
- `intoxication` - already existed, now actually rises: each finished drink
  adds `DrinkDefinition.alcohol_strength * CustomerAIBalanceConfig.
  intoxication_gain_scale * (2.0 - Personality.temperance)`, so a more
  temperate customer's intoxication rises more slowly for the same drinks.
- `remaining_visit_minutes` / `visit_duration_minutes` - see "Visit
  duration" below for why these are not a per-frame or repeating-timer
  countdown.
- `drinks_consumed_this_visit` stays on `Customer` (a visit counter, not a
  need) - see Phase 2A's section above; unchanged this phase except that
  its limit now lives on `CustomerAIBalanceConfig` instead of `GameConfig`.

### Personality influence

`Personality` (shared, authored, per `CustomerType`) gained four
multipliers this phase, all applied once at spawn in `CustomerNeeds.
seed_from()`: `wealth_multiplier`, `drink_appetite` (scales Order Drink's
thirst-driven utility), `intoxication_tolerance`, `visit_duration_multiplier`.
The existing `temperance` trait now does real work too (intoxication
accumulation rate, above). None of this is a per-personality behaviour
script - every tendency the brief lists (patient/impatient, heavy/light
drinker, frugal/wealthy, relaxed/hurried) is a number on a `Personality`
`.tres`, not code. `sailor.tres`/`sailor_impatient.tres`'s existing
Personality resources already demonstrate this: nothing new needed for them
to also express a wealth/appetite/duration bias if you want to tune them
further.

### Visit duration - elapsed time, not a countdown

The brief explicitly asks to avoid a per-frame or per-customer repeating
countdown. `CustomerNeeds` doesn't tick anything: `start_visit_clock()`
(called once, in `Customer.arrive_at_seat()`) records the world-clock
minute the visit started; `update_remaining_visit_time()` (called by
`CustomerBrain._build_context()` - i.e. only when a decision is actually
being made) recomputes `remaining_visit_minutes` from plain subtraction.
The *mandatory* departure at zero is a single `WorldTime.schedule_in()`
booking made at the same moment (`Customer._visit_time_event`), mirroring
patience-expiry's existing pattern exactly - see
`Customer._on_visit_time_expired()`.

### Money

`CanAffordDrinkCondition` hard-gates Order Drink against the cheapest
drink this customer's `CustomerType` offers, computed from real
`DrinkDefinition.base_sell_price * Customer.payment_multiplier` - the exact
same formula `_on_drink_finished()` already used to compute payment, so
there is nothing to keep in sync. `Customer.choose_drink_from_customer_type()`
additionally narrows to affordable drinks when some (not all) of a type's
drinks are out of reach, so a customer who clears the gate never gets
assigned one they can't pay for.

### Satisfaction (mood)

Two triggers this phase, both amounts on `CustomerAIBalanceConfig`:
`satisfaction_gain_on_service` (successful serve, in `Customer.interact()`)
and `satisfaction_loss_on_patience_expiry` (in `Customer.
_on_patience_expired()`). `leave_mood_scoring.tres` (Phase 1, unchanged)
already made low mood pull toward Leave; `order_satisfaction_scoring.tres`
and `relax_satisfaction_scoring.tres` are new this phase and do the
opposite for Order Drink/Relax.

### Intoxication

Order Drink is hard-gated by `intoxication_order_gate.tres`
(`NeedThresholdCondition`, `AT_MOST` 0.75) - above that, Order Drink is not
a candidate at all, not just lower-scored. The same threshold also
contributes negative score below 0.75 (less attractive as it climbs), and
`leave_intoxication_scoring.tres` makes Leave more attractive as it rises.
Together, a customer above the threshold has no route back to ordering and
Leave reliably outscores Relax - a hard-gate-plus-scoring-bonus pair, the
same pattern Phase 2A's drink-limit safeguard already established.

### Thirst

Scores, never forces: `order_thirst_scoring.tres` (higher thirst -> higher
Order Drink utility), `relax_thirst_scoring.tres` and
`leave_thirst_scoring.tres` (lower thirst -> higher utility for both -
a non-thirsty customer has no pull toward ordering, which by itself makes
Relax/Leave relatively more attractive without needing to know about each
other).

### Utility scoring - the full condition list per activity

All new conditions are `NeedThresholdCondition` (or, for money, the new
`CanAffordDrinkCondition`) instances under `Data/customer_ai/conditions/` -
no new condition classes beyond `CanAffordDrinkCondition` were needed.

- **Order Drink**: `is_seated`, `not_currently_ordering`,
  `under_drink_limit`, `can_afford_drink`, `intoxication_order_gate`,
  `order_thirst_scoring`, `order_visit_time_scoring`, `order_money_scoring`,
  `order_satisfaction_scoring`, `decision_variance`.
- **Relax at Seat**: `is_seated`, `not_currently_ordering`,
  `relax_visit_time_scoring`, `relax_satisfaction_scoring`,
  `relax_thirst_scoring`, `relax_intoxication_scoring`, `decision_variance`.
- **Leave**: `not_currently_ordering`, `leave_mood_scoring` (Phase 1),
  `at_drink_limit_scoring` (Phase 2A), `leave_visit_time_scoring`,
  `leave_money_scoring`, `leave_intoxication_scoring`, `leave_thirst_scoring`,
  `decision_variance`.

`decision_variance` (`ProbabilityCondition`, unchanged from Phase 2A) is
kept deliberately small relative to the attribute-driven conditions above -
attributes dominate the outcome; the variance only breaks close ties.

### Mandatory departure rules

Exactly two events bypass normal utility competition entirely, both via
`CustomerBrain.force_activity(&"leave", reason)`: patience expiry (Phase 1,
unchanged) and visit-time expiry (new this phase). Intoxication and the
drink limit are **not** mandatory-departure events in this sense - they
work entirely through gating + scoring within normal `think()` competition,
which is deliberately how the brief's "Order Drink becomes ineligible...
Leave should win" pattern was designed from Phase 2A onward.

### Balancing resource locations

- `Data/customer_ai/balance_config.tres` (`CustomerAIBalanceConfig`) -
  starting money/thirst/satisfaction/visit-duration ranges, satisfaction
  change amounts, thirst reduction, intoxication gain scale, and the
  drink-per-visit limit (moved here from `GameConfig` this phase).
- `Data/customer_ai/diagnostics_config.tres` (`CustomerAIDiagnosticsConfig`)
  - console logging and JSON export switches and size limits (moved here
  from `GameConfig.show_customer_ai_debug_messages`).
- Per-activity scoring thresholds/weights stay on their own condition
  `.tres` files under `Data/customer_ai/conditions/`, the same as Phase 1/2A
  - see the class doc comment on `CustomerAIBalanceConfig` for why that
  split was kept rather than centralising literally everything.
- `Personality` `.tres` files under `Data/customer_ai/personalities/` -
  per-archetype multipliers/biases.
- `DrinkDefinition.alcohol_strength` - per-drink, on the drink's own
  `.tres` (`Data/items/drinks/`).

### Diagnostic report architecture

A dedicated, decoupled reporting stack under
`systems/customer_ai/diagnostics/`:

- **`CustomerAIDiagnosticsConfig`** (Resource) - the on/off switches.
- **`CustomerAIReportManager`** (Node, under `Managers/` in `main.tscn`,
  the same pattern as `EconomyManager`/`StatisticsTracker` - not an
  autoload) - the single collector. Every public method is safe to call
  regardless of whether export is enabled; see its own doc comment for why
  normal gameplay never depends on any of it.
- **`VisitRecord`/`DecisionRecord`/`IssueRecord`** (RefCounted data
  classes) - one visit, one decision, one anomaly, each with a
  `to_dictionary()`.

`Customer` and `CustomerBrain` both hold an optional `CustomerAIReportManager`
reference (wired through `configure()`/`CustomerBrain.report_manager`) and
call into it at the same points they already do their own bookkeeping -
there is no separate "reporting pass" that walks customers after the fact.
`CustomerBrain.think()`/`enter_activity()`/`force_activity()` all report
their own decisions; `Customer` reports spawn, orders, serves, payments,
relaxes, chair identity and departure.

### How to enable reporting

Open `Data/customer_ai/diagnostics_config.tres` in the Inspector (or edit
the `.tres` directly) and set:

- `console_debug_enabled = true` for the live console output (independent
  of JSON export).
- `export_enabled = true` for the JSON report to actually collect data.

Both default to `false`.

### How to generate a report

Press **F10** to open the developer panel (debug/editor builds only - see
`KNOWN_ISSUES.md`), then click **"Export Customer AI report."** This calls
`CustomerAIReportManager.finalize_and_write_report()` directly - the same
method you can call from anywhere else (a script, the remote debugger) if
you don't want the button. It works whether or not `export_enabled` was on
for the session; if it was off, the report is written but mostly empty,
since nothing was being recorded.

### Where Godot stores it on Windows

`user://customer_ai_reports/` resolves to:

```text
%APPDATA%\Godot\app_userdata\PirateHarbourTavern\customer_ai_reports\
```

(typically `C:\Users\<you>\AppData\Roaming\Godot\app_userdata\PirateHarbourTavern\customer_ai_reports\`)
- the same base folder the existing navigation-debug CSV already writes
  into, one level up.

### Report schema

```json
{
  "summary": {
    "report_format_version": 1,
    "phase_identifier": "Phase 2B",
    "session_start_unix": 0.0, "session_end_unix": 0.0,
    "real_session_duration_seconds": 0.0,
    "game_time_duration_minutes": 0.0,
    "maximum_active_customers_observed": 0,
    "customers_spawned": 0,
    "completed_visits": 0, "active_visits_at_report_time": 0,
    "total_drinks_ordered": 0, "total_drinks_served": 0,
    "total_drinks_consumed": 0, "total_payments": 0,
    "total_relax_activities": 0,
    "total_patience_departures": 0, "total_visit_time_departures": 0,
    "total_normal_utility_departures": 0, "total_forced_departures": 0,
    "total_failed_activity_starts": 0,
    "visits_truncated": false, "decisions_truncated": false
  },
  "completed_visits": [ /* VisitRecord.to_dictionary(), one per finished visit */ ],
  "active_visits": [ /* same shape, is_completed: false */ ],
  "decisions_by_customer_id": { "1": [ /* DecisionRecord.to_dictionary() */ ] },
  "issues": [ /* IssueRecord.to_dictionary() */ ]
}
```

Every `VisitRecord`/`DecisionRecord`/`IssueRecord` field is documented in
its own class file (`systems/customer_ai/diagnostics/*.gd`) - all ordinary
JSON-serialisable types (numbers, strings, bools, arrays, objects), openable
outside Godot.

### Report size controls

`CustomerAIDiagnosticsConfig.maximum_completed_visits_retained` (default
500, oldest dropped first) and `maximum_decisions_per_customer` (default
20, oldest dropped first per customer). Either limit being hit sets
`visits_truncated`/`decisions_truncated` to `true` in the summary, so a
truncated report is always self-declaring rather than silently incomplete.

### Known limitations

Deliberately not measured or invented this phase: navigation-recovery
counts (the field exists on `VisitRecord` but nothing currently increments
it - Phase 2B was not asked to add navigation instrumentation), reputation,
long-term memory, social/group activities, or anything resembling a full
economy simulation. `decision_variance`'s random contribution is real and
uncapped-by-design-choice small, not literally zero - see "Utility scoring"
above for why that is intentional rather than an oversight.

## Phase 2B.1 — diagnostic completion and developer tools

Phase 2B's report only ever produced non-empty `summary` totals -
`completed_visits`, `active_visits`, `decisions_by_customer_id` and
`issues` were always empty, regardless of `CustomerAIDiagnosticsConfig.
export_enabled`.

### The bug

`main.tscn`'s `CustomerAIReportManager` node listed `diagnostics_config` in
its `node_paths` array. `node_paths` is exclusively for properties Godot
resolves as a `NodePath` pointing at another node *after* the scene tree
finishes building - it does not apply to plain `Resource` exports, which
`diagnostics_config` (a `CustomerAIDiagnosticsConfig`) is. Because the
property was simultaneously assigned an `ExtResource` value and flagged for
NodePath resolution, the resource never actually reached
`CustomerAIReportManager.diagnostics_config` at runtime - it stayed `null`.
`is_export_enabled()` (`diagnostics_config != null and diagnostics_config.
export_enabled`) therefore always returned `false`, no matter what the
`.tres` file said. Session-summary totals still populated because those
counters are incremented unconditionally in `CustomerAIReportManager` (by
design, so basic totals are always available even with detailed export
off) - everything gated behind `is_export_enabled()` was not. The fix is a
one-line scene change: `diagnostics_config` is no longer listed in
`node_paths` on that node. No other node in `main.tscn` had the same
mistake - every other `node_paths` entry in the scene genuinely is a Node
reference.

### New anomaly detection

Three more of the brief's example issue types are now genuinely detected
(not just documented as future work), each reported through
`CustomerAIReportManager.report_issue()`:

- `duplicate_active_order` - `Customer.choose_order()` now checks whether
  an order was already active before choosing a new one. Normal AI gating
  should already prevent this, so seeing it in a report means the
  `not_currently_ordering` condition or a direct `enter_activity()` call
  path let something through it shouldn't have.
- `duplicate_drink_finished` - `Customer._on_drink_finished()` already had
  a guard for firing with no active order (a stale or duplicate scheduled
  event); it now also reports the anomaly instead of only logging a
  `push_error()`.
- `reservation_leak_precursor` - `Customer._exit_tree()` now checks whether
  the chair reservation was still held at the moment the customer was
  freed. Normal departure always releases it first via `begin_leaving()`/
  `finish_customer()`; seeing this issue means a customer was removed
  outside that path.

Three of the brief's other example issue types (`chair lost unexpectedly`,
`customer remained after visit expiry`, `activity timeout`) are
deliberately **not** implemented - each would need either continuous
polling (which this system's event-driven design avoids on principle) or
detecting the *absence* of an event, which cannot be done reliably from
inside the event-driven pieces that exist today. Recording a plausible-
looking but unreliable check for these would violate "do not fabricate
issues" more than simply not checking them.

### Developer menu additions

Two new F10 panel buttons, both calling into existing systems rather than
inventing new state:

- **"Serve all waiting drinks"** calls a new `Customer.force_serve_now()`
  on every active customer. `interact()`'s validated serving tail
  (chair hand-off, state change, scheduling, satisfaction gain, diagnostics,
  the `drink` activity bookkeeping transition) was extracted into a shared
  `_serve_drink()` so the dev button reuses the exact same logic as a real
  service - the only thing it skips is the player/carried-item check,
  which has no equivalent when there is no real player action. `force_serve_now()`
  re-checks `State.ORDERING` itself, so it is always safe to call on every
  active customer regardless of what each one is currently doing.
- **"Clean all tables"** iterates every seat `Reservable` (found the same
  way `DestinationBroker` already finds one - no new group invented) and
  calls the existing `CleanableComponent.clear_cleaning_task()` on any
  chair with a pending cleaning task. A chair's reservation is already
  released the moment it becomes dirty (`Chair.require_cleaning()` does
  that), so there is no reservation state left to fix here - only the
  visual/interaction cleanup, which `clear_cleaning_task()` already
  triggers via the same signal a real cleaning action completion would.
  A currently-occupied chair never has a pending cleaning task to begin
  with (cleaning only starts after departure), so occupied chairs are
  naturally unaffected without an extra guard.

The panel is now grouped under three headers - Customer AI, Simulation,
Stock & Economy - with every pre-existing button kept exactly where its
behaviour already put it; nothing was redesigned; the buttons were only
labelled visually.

## Phase 2B.2 — utility balancing and voluntary departures

Phase 2B.1's own diagnostic reports revealed the actual behaviour: almost
every completed visit ended via a forced departure (patience or visit-time
expiry), never a voluntary Leave. The cause was a real bug, not a tuning
gap.

### The bug: NeedThresholdCondition couldn't be scoring-only

`DomainFlagCondition` gained a `gates: bool` field back in Phase 2B so a
condition could contribute to scoring without ever disqualifying an
activity - `at_drink_limit_scoring.tres` already relied on this.
`NeedThresholdCondition` never got the same field: `is_satisfied()` always
enforced its `comparison`/`threshold` as a hard gate, with no way to opt
out. Several Phase 2B condition resources were written assuming
scoring-only behaviour the class didn't actually support - most damagingly
`leave_money_scoring.tres` (`AT_MOST` 0.0), which meant Leave's own
`is_satisfied()` required `wealth <= 0` to even be a candidate. Any
customer with money at all had Leave hard-gated out entirely, exactly
matching the reports' "almost no voluntary Leave" and forced-departure-only
pattern. `NeedThresholdCondition` now has the same `gates` field as
`DomainFlagCondition`; every condition resource meant to be scoring-only
now sets `gates = false` explicitly.

While fixing this, every scoring-only condition was also rewritten to use
`threshold = 0.0` uniformly (every need `NeedThresholdCondition` reads is
non-negative, so `distance = abs(value - 0) = value`, and the sign of
`score_weight` alone controls direction) rather than assuming an upper
bound like "visit duration never exceeds 90 minutes" - `Personality.
visit_duration_multiplier` can push a visit past whatever fixed maximum a
threshold-based-at-the-max approach assumed.

### 1-2. Leave is now always eligible; money influences instead of gates

Leave's only remaining hard gate is `not_currently_ordering` (unchanged
since Phase 2A). `leave_money_scoring.tres` now only scores
(`gates = false`, strengthened to `score_weight = -0.3`): high money
strongly suppresses Leave, shrinking toward zero as money runs out.

**Mandatory departure when broke**: `CustomerBrain.think()` now checks
this before normal competitive scoring, exactly like the existing
patience/visit-time forced paths, and calls
`force_activity(&"leave", &"out_of_money")` when `CustomerNeeds.wealth <=
0` and the customer has no active order and no drink to consume.
`Customer` listens for `CustomerBrain.activity_forced` generically
(`Customer._on_activity_forced()`) rather than needing to know this
specific reason exists, so a future forced-departure trigger needs no
change to `Customer` at all.

### 3. Satisfaction

`order_satisfaction_scoring.tres` and `relax_satisfaction_scoring.tres`
were strengthened (3.0 -> 4.0, 2.0 -> 2.5); `leave_mood_scoring.tres`
(Phase 1, now explicitly `gates = false`) strengthened -4.0 -> -5.0.

### 4. Relax has diminishing returns

New `RepeatDecayCondition` reads a numeric need that counts repeats
(`relax_count`, incremented in `Customer._on_relax_finished()`) and
returns a negative contribution that grows with each repeat:
`reference_utility * (decay_multiplier - 1.0)`, where
`decay_multiplier = (1 - decay_per_repeat) ^ count`. Configured on
`relax_repeat_decay.tres` (`decay_per_repeat = 0.15`,
`reference_utility = 6.0`) - a compounding curve (100%/85%/72%/61%/...)
rather than a hand-authored percentage table, and never gates: Relax
always remains possible, just increasingly unlikely to win.

### 5. Drinking moves customers toward leaving

New `leave_drinks_scoring.tres` adds a gradual pull toward Leave with
every completed drink, independent of the existing `at_drink_limit_scoring.tres`
bonus that only fires once the configured maximum is reached.
`drinks_consumed` mirrors `Customer.drinks_consumed_this_visit` onto
`CustomerNeeds` so it can be scored like any other need.

### 6. Visit duration influences gradually

`order_visit_time_scoring.tres`, `relax_visit_time_scoring.tres` and
`leave_visit_time_scoring.tres` all switched to the robust
`threshold = 0.0` pattern and no longer gate. The hard
`Customer._on_visit_time_expired()` scheduled departure is unchanged and
remains the safety net.

### 7. Wander disabled, not deleted

`Data/customer_ai/activity_registry.tres`'s `definitions` array no longer
includes `wander.tres`. `WanderBehaviour`, `wander.tres` and
`wander_chance.tres` are untouched on disk - re-enabling Wander later
means adding one line back to the registry.

### 8. No single factor dominates

Traced three representative scenarios by hand while tuning (a wealthy,
satisfied customer under the drink limit; the same customer relaxing past
the limit; a customer low on money and time at the limit) to confirm
Order Drink/Relax/Leave's ranking changes sensibly rather than one
activity mechanically winning regardless of state - see
`PHASE_2B2_CHANGE_REPORT.md` for the worked numbers.

### 9. Decision diagnostics: top score, second score, margin

`DecisionRecord` gained `top_score`, `second_score` and `margin`
(`top_score - second_score`), computed once in
`CustomerBrain._report_decision()` from the same `eligible_activities`
list already being recorded. The console block now also prints
`Margin: X.X`.

### 10. Balance resource locations

Every new/changed weight lives on its own condition `.tres` under
`Data/customer_ai/conditions/`, kept deliberately separate from
`CustomerAIBalanceConfig` (spawn-time ranges and need-change amounts, not
per-activity scoring weights).

### Known limitations

Numbers above were hand-traced for plausibility across representative
scenarios, not tuned against a large batch of real playtest sessions - see
`PHASE_2B2_CHANGE_REPORT.md`'s test procedure. No new customer activities
were added.

## Phase 2C — tavern activities, social behaviour, and reasons to stay

Three new activities (Socialise at Seat, Visit Tavern Activity, Return to
Seat), one new reusable world-object framework (`TavernActivityPoint`), and
one proof-of-concept instance of it (Darts). Wander stays disabled.

### Socialise at Seat

Stays at the chair; finds a partner via a plain Godot group
(`&"seated_customers"`, joined in `Customer.arrive_at_seat()`, left in
`release_reserved_chair()`) rather than a new discovery system.
`Customer.find_nearby_social_partner()` is the one search both the
`has_social_partner` eligibility flag and the behaviour's actual partner
pick use, so they can never disagree about whether a partner exists.
Eligibility is deliberately narrow: `Customer.is_available_for_social()`
is true only while `RELAXING` - a customer drinking, ordering, or leaving
is never interrupted, per the brief. One customer can start this without
the partner having chosen anything; the partner is only notified
(`notify_being_socialised_with()`, currently a debug-log call) and keeps
deciding independently.

**Visual**: reuses the existing `order_icon` sprite with a light blue tint
as a placeholder "in conversation" indicator (visible only during
`SOCIALISING`, reset afterwards) rather than adding a new scene node or
asset - see requirement 2's "no new finished artwork needed".

### TavernActivityPoint

A plain `Node2D` with a `Reservable` child (tagged with its own
`activity_id`, e.g. `&"darts"`) and a `UsePosition` marker - the exact same
reservation shape a `Chair` already uses, just for a temporary visit
instead of the whole stay. `enabled` is implemented by having a disabled
point reserve itself (`set_enabled(false)` calls `reservable.reserve(self)`)
rather than teaching `Reservable`/`DestinationBroker` a second "is this
actually available" concept - a disabled point is simply never free, which
both already handle correctly.

**Adding a future point** (a card table, a musician) needs: a new small
`.tscn` with this same three-node shape, a new `TavernActivityPoint` config
(no new script), and a new `ActivityDefinition` with
`destination_tag` set to the new tag and `behaviour` pointed at the
existing `VisitTavernActivityBehaviour` resource - the same one Darts
already uses. Nothing in `CustomerBrain`, `Customer`, or
`VisitTavernActivityBehaviour` itself needs to change; that is the whole
point of the framework.

### Darts (the proof-of-concept)

One `DartsPoint` instance (`scenes/furniture/darts_point.tscn`), placed
once in `main.tscn` at `Vector2(650, 450)` - **this position was chosen
without visual access to your room layout and may overlap furniture or
sit outside the walkable nav mesh; reposition it in the editor before
relying on it.** Everything else (reservation, travel, use, effects,
return) is entirely generic `TavernActivityPoint`/`VisitTavernActivityBehaviour`
machinery - Darts contributes no code of its own, only data
(`activity_id = &"darts"` and its config values).

### Chair retention while temporarily away

`Customer.reserved_chair` is never touched by
`begin_visiting_activity()`/`arrive_at_activity()`/`begin_returning_to_seat()`
- the whole point of Phase 2A/2B's "one chair for the whole visit" design
is that nothing needs to change here. `VisitRecord.kept_same_chair_for_visit`
stays accurate automatically, since it is only ever set false by
`CustomerAIReportManager.record_chair()` noticing a *different* chair id,
which never happens on a Darts trip.

### Return to Seat

A real, registered activity (so it shows up in decision history, not an
untracked engine state), entered only directly
(`CustomerBrain.enter_activity(&"return_to_seat")`) - never scored, empty
condition list, matching `drink.tres`'s existing shape exactly.

### Navigation failure recovery

`Customer._on_destination_failed()` gained two new branches:
`MOVING_TO_ACTIVITY` releases the activity reservation
(`CustomerBrain.abandon_current_activity()`, a new public wrapper around
the existing `_exit_current()`) and retries getting back to the chair
instead of treating the failure as a reason to leave the tavern.
`RETURNING_TO_SEAT` falls through to the existing generic
`handle_invalid_destination()` (which does lead to leaving) only if *that*
retry also fails - bounded to one retry rather than an unbounded loop. Both
branches report a diagnostic issue and increment a dedicated
`VisitRecord` failure counter. No new stuck-detection was built - the
existing `ActorNavigation` stuck-recovery already surfaces every failure
through this same callback, which is what "use the existing navigation
framework" asks for.

### Reasons to stay (engagement)

`CustomerNeeds.engagement`, raised by `TavernActivityPoint.engagement_effect`
and `SocialiseAtSeatBehaviour`'s configured gain, decayed a small
configurable fraction every time a decision is made
(`CustomerNeeds.decay_engagement()`, called from
`CustomerBrain._build_context()` - the same per-decision cadence
`remaining_visit_minutes` already refreshes on, not a new timer). Never
gates Leave - `leave_engagement_scoring.tres` only scores, and decays back
toward zero on its own, so it cannot indefinitely block a departure.

### Repetition and variety

`RepeatDecayCondition` (built in the balancing pass for Relax) is now also
used for Socialise (`socialise_count`) and Darts (`darts_count`) via their
own `.tres` instances with their own decay rate/reference utility - no new
condition class needed, the same compounding-decay pattern applies to any
repeat-counted need.

### End-of-visit pressure

`EndOfVisitPressureCondition` (new) contributes a squared-curve bonus to
Leave once `remaining_visit_minutes` drops inside a configurable window
(`leave_end_of_visit_pressure.tres`, default 12 minutes) - additive on top
of the existing linear `leave_visit_time_scoring.tres`, not a replacement.
The hard visit-expiry departure is completely unchanged and remains the
safety limit.

### Drink-limit preparation

`Personality.preferred_drink_count_multiplier` scales
`CustomerAIBalanceConfig.maximum_drinks_per_visit` to get each customer's
typical target; `Customer.get_effective_drink_limit()` is the one place
that computes and clamps it to the new hard
`absolute_maximum_drinks_per_visit` ceiling, and is now used everywhere the
limit is checked or reported (gating, debug output, `maximum_drinks_reached`).
No archetypes were added this phase - both existing personalities use
`1.0` (unchanged typical behaviour) until a future phase wants to
differentiate them.

### Utility contribution diagnostics

`ActivityCondition.contribution_label` (new field) plus
`ActivityDefinition.get_utility_breakdown()` (new method, separate from
`get_utility()` so normal scoring pays nothing extra). Every scoring
condition across every activity - not just Phase 2C's new ones - was
labelled, so a decision record's `utility_contributions` entry always
reconciles: `base_score` plus every labelled bucket sums to `final_score`
by construction (each bucket is populated from exactly the same
`condition.score()` calls the total already used). Only populated when
`CustomerAIDiagnosticsConfig.record_decision_history` is on, and only for
activities actually scored via `think()` - `enter_activity()`/
`force_activity()` transitions have no breakdown, since nothing was scored
for them (their `eligible_activities` is empty too, for the same reason).

### Decision report additions

`DecisionRecord` gained `selected_activity_point_id`,
`social_partner_customer_id`, `return_to_seat_required`, `engagement`, and
`recent_activity_history`, alongside the existing top/second/margin.
Populated *after* `_enter()` runs (a small reordering in `think()`), since
the activity-point/partner are only known once the activity has actually
been entered - reporting before would have left these fields wrong or
empty for exactly the decisions that matter most.

### Visit record additions

`VisitRecord` gained `socialise_count`, `tavern_activity_count`,
`darts_count`, `activity_reservation_failures`, `return_to_seat_failures`,
`maximum_engagement_reached`, `unique_activities_completed`, and
`recent_activity_history` (capped at 6 entries -
`CustomerAIReportManager.RECENT_ACTIVITY_HISTORY_LENGTH`). All are updated
incrementally on the same live record `record_departure()` already
finalises, so no new departure-time parameters were needed.

### Developer menu additions

Five new buttons under the existing Customer AI section: Export (unchanged),
**Enable/disable tavern activities** (calls each point's real
`set_enabled()`), **Force first customer to socialise**/**...to use darts**
(calls the new public `Customer.force_activity_for_testing()`, which goes
through the real `CustomerBrain.force_activity()`), **Release all activity
reservations** (unconditional `Reservable.release()`, a genuine developer
reset no normal path would call), **Show activity reservations** (prints
each Darts-tagged Reservable's holder). "Selected customer" does not exist
as a concept yet - both force buttons act on the first entry in
`GameManager.active_customers`, documented plainly in the button behaviour
rather than pretending to a selection UI that is not there.

### How to inspect reservations using F10

Press F10, then "Show activity reservations" - lists every tagged use
point and whether it is free or which customer currently holds it, read
directly from the live `Reservable` state (not a separate tracking
system, so it can never drift from what `DestinationBroker` itself would
find).

### Cross-activity affinity

`ActivityContext` gained `last_activity_id`, stamped by
`CustomerBrain._exit_current()` — the one choke point every exit path
(`think()`, `enter_activity()`, `force_activity()`,
`abandon_current_activity()`) already funnels through, so there is exactly
one place "what did this customer just finish" is tracked. A new condition
class, `PreviousActivityAffinityCondition`, scores a flat bonus when
`last_activity_id` matches one of its configured trigger ids and zero
otherwise - no decay curve needed, because the field only ever holds the
immediately-preceding activity, so the bonus stops applying the moment the
customer does anything else. Wired via ordinary `.tres` data onto existing
activities: drink → socialise, darts → drink, darts ↔ socialise. Adding
another pairing (e.g. socialise → a future card table) is another `.tres`
file, not a code change.

The one previously hard-coded per-activity branch this pass found -
`Customer._on_activity_use_finished()`'s
`if point.activity_id == &"darts": needs.adjust(&"darts_count", ...)` - was
generalised to `TavernActivityPoint.repeat_count_need_id`, so a future
activity's own repeat-decay need no longer requires its own `if` branch
here either.

### Known limitations, honestly

- **Capacity beyond 1 is now implemented, for Darts specifically.**
  `TavernActivityPoint` discovers `TavernActivitySlot` children (each its
  own `Reservable` + use position) instead of assuming exactly one;
  `ActivityDefinition.min_participants`/`max_participants` (default 1/1,
  Darts set to 1/2) tell `VisitTavernActivityBehaviour` whether to attempt
  co-opting a second participant via `Customer.find_nearby_activity_partner()`.
  A future multi-slot point (cards, a 4-seat table) reuses the same
  mechanism; only the framework's own generic min/max-participant support
  landed this pass, not a matchmaking/waiting system - a customer with no
  suitable partner nearby at the moment of choosing simply plays alone.
- **Cooldown is not enforced.** `TavernActivityPoint.cooldown_minutes` is
  recorded but nothing currently checks it after a point is released.
- **Darts' scene position is a placeholder guess**, not visually verified -
  see the Darts section above. The new second slot's marker position is
  the same kind of guess, not confirmed against the sprite in the editor.
- **"Selected customer" in the F10/F9 tools is now a real picker** (cycle
  key `I` in the F9 panel, a button in F10) rather than always "the first
  active customer" - every existing action (print profile, verbose
  scoring, force-to-socialise, force-to-darts) now targets whichever
  customer is selected.
- **No new stuck-detection was built** for the activity-visit states -
  intentionally, reusing the existing navigation framework's own recovery
  instead, per the brief's explicit instruction not to replace it.
- **Personality trait integration for Phase 2C is minimal**: `travel_willingness`
  and `preferred_drink_count_multiplier` are real and read; the longer list
  of future trait tags (gambler, competitive, musical, aggressive,
  information-seeking) is prepared as a free-form `Array[StringName]` on
  `Personality` (`future_trait_tags`) but not read by anything yet, per
  the brief's "do not implement new customer archetypes unless needed for
  testing".
- **No dedicated automated test for solo/two-player darts and post-match
  divergence.** Three attempts were made this pass; each found and fixed a
  real bug (off-navmesh teleport coordinates, eager GDScript argument
  evaluation, a scheduled-event race between forcing an activity and a
  customer's own pending completion timer), but the test itself stayed too
  environmentally fragile - customer-type visit-duration variance and
  `--fixed-fps` timing races on transient states - to land reliably in the
  time available, and was deleted rather than shipped unreliable. Coverage
  today is indirect: `group_parity_test.gd`'s existing legacy-stub darts
  case, plus the unchanged full regression suite. See `TASKS.md`.

