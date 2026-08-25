# Learning Log

## Project setup

Completed:

- Created the Godot project and main scene.
- Created a structured folder layout.
- Configured input actions.
- Set up Git version control.
- Established reusable scenes for player, customers, tables, chairs, door and drink stations.

## Concepts learned

### Scenes and nodes

- A scene is a reusable node tree.
- Packed scenes can be instantiated for customers and furniture.
- Exported node/resource references make dependencies visible in the Inspector.

### Signals

- Signals allow systems to react without tightly coupling scripts.
- Customer payments are forwarded to `EconomyManager`.
- The HUD listens to `money_changed` rather than polling or editing money.
- `ActionRunner` reports action start, progress, completion and cancellation.

### Resources and data-driven design

- A custom Godot `Resource` can define reusable gameplay data.
- `DrinkDefinition` stores price, timing, visuals and break behaviour.
- `CustomerType` stores movement, patience, spawning and preferences.
- `CleaningTask` stores a task's visuals, complication and action reference.
- `ActionDefinition` stores generic action duration and input behaviour.
- Changing a `.tres` resource can rebalance gameplay without changing scripts.

### Composition

- Domain-specific resources can contain generic resources.
- `CleaningTask` contains an `ActionDefinition` rather than inheriting all action behaviour.
- `Chair` contains a `CleanableComponent`.
- `Player` contains an `ActionRunner`, an `ItemCarrier` and an `InventoryComponent`.
- `ItemSlot` contains an `ItemSlotRules` resource rather than hard-coding filters,
  so one slot script serves hands, bar slots, crates and backpacks.

### Data over enums

- An enum is a hard-coded list, so adding a value always means editing a script.
- `ItemDefinition.tags` is an `Array[StringName]` on a resource, so a brand-new
  item group can be typed into the Inspector with no code change.
- The old `ItemCategory` enum was removed for exactly this reason.

### Avoiding item duplication and loss

- Reference types are shared, so two slots holding the same `ItemStack` object
  would silently duplicate items.
- `ItemSlot` copies anything put in and copies anything handed out, so a stack
  always has exactly one owner.
- `ItemTransferService` validates the whole transaction before mutating either
  side, and never empties the source before the destination is confirmed.
- Signals connected with a lambda capture `self` by strong reference. A
  `RefCounted` object owning a child that stores such a connection creates a
  reference cycle that never frees. `ItemContainer` uses a bound method callable
  instead.

### Managers and ownership

- A system should have one clear owner for important state.
- `EconomyManager` owns money.
- The chair/cleanable component owns cleaning state.
- The player's action runner owns active timed-action progress.
- UI displays state but does not own it.

### Compatibility migrations

- Large architectural changes are safer when migrated in stages.
- Temporary compatibility fields can keep the game playable while references are moved.
- Once all consumers use the new system, obsolete timers, variables and methods can be removed.

## Current understanding checks

- To change a drink's value, edit `Base Sell Price` on its `DrinkDefinition` resource.
- To let a new kind of item into the backpack, edit `Rejected Tags` on the
  player's `InventoryComponent`, not the inventory script.
- To find out why a transfer failed, read the returned `ItemTransferResult`.
- To change cleaning time, edit `Duration Seconds` on the linked `ActionDefinition`.
- To change broken-glass probability/cost, edit the empty-glass `CleaningTask`.
- To change a customer type's speed or patience, edit its `CustomerType` resource.
- To change global spawning or navigation, edit the `GameConfig` resource.
- Scripts should not directly modify the economy balance outside `EconomyManager`.

### Interaction framework

- Duplicated logic hides in "who decides". Before the framework, the player
  decided what it was interacting with *and* the bar counter decided the same
  thing independently, so the two could disagree.
- Splitting detection from selection was worth it. Reach became a physics
  question answered by a collision shape; "which one do we mean" became a pure
  data question that is easy to reason about and change.
- Duck-typed optional methods beat a base class here. An object implements only
  what it needs, and the drinks station ignoring four of the six protocol
  methods is a feature, not an oversight.
- Actions as data rather than method calls is what makes future context menus,
  verb wheels and mouse input cheap. The menu renders strings and passes opaque
  ids back; it never learns an object type.
- A legacy fallback let two objects join the system with zero script changes.
  Migration does not have to be all at once to be real.
- Anything called every tick must be idempotent. `set_interaction_highlighted`
  is called repeatedly on purpose, so the bar counter can move its slot
  highlight, which means it has to early-return when nothing changed.
- Prompts should ask the system that owns the rules. The bar counter asks
  `ItemTransferService.can_transfer()` instead of re-deriving whether a place
  will succeed, so the prompt cannot lie.

## Current understanding checks (interaction)

- To make a new object interactive, add an `Interactable` area and implement
  `get_interaction_actions()` and `perform_interaction()` on its root node.
- To change selection feel, edit `default_selection_rules.tres`, not a script.
- To make one object win ties, raise `Interaction Priority` on its
  `Interactable` node.
- To change what a prompt says, return a different `InteractionAction`. Never
  add a label to a world object.
- To find the actor inside an interactable, read the `InteractionRequest`.
  Never search the scene tree for the player.

### Actor navigation

- Most of the "stuttering AI" was not a pathfinding problem. Setting a
  destination awaited two physics frames with movement stopped, so every state
  change cost a visible pause, and stuck recovery made it worse by pausing
  again before retrying.
- Turning a system off to make a special case work is a smell. Avoidance was
  disabled for the walk into a seat and for the walk out of the door - the two
  moments actors were most likely to be near each other.
- Smoothing belongs in two places, not one. Smoothing the steering direction
  fixes path-corner flips; ramping velocity fixes everything else, including
  bugs in future controllers.
- One writer for one piece of state. Velocity had four writers plus an engine
  callback, which is why "why did it stop" had no single answer.
- An arrival needs a slowing curve, not a smaller stop distance. Reducing the
  threshold makes overshoot worse, not better.
- Off-mesh destinations are normal, not errors. A seat is inside furniture, so
  the path can only reach the edge; measuring how far the projection moved the
  target turns a special case into a general final-approach radius.
- Recovery should escalate. A sidestep costs no pathfinding and clears most
  jams, which are two actors refusing to pass each other rather than a bad
  route.
- A reservation needs two stages and an expiry. One stage lets two actors reach
  the same chair; no expiry means one lost actor costs a seat permanently.
- Resources are shared. Writing per-actor tuning onto a profile edits the asset
  every actor is using, so profiles are duplicated on ready.

## Current understanding checks (navigation)

- To make an actor walk somewhere, call `move_to` with a `NavigationDestination`
  and listen for `destination_reached`.
- To change how an actor accelerates or stops, edit its `ActorMovementProfile`.
- To make customers step aside for staff, raise the staff
  `avoidance_priority`; nothing else changes.
- To stop an actor being shoved while it is seated, call `park()`.
- To make anything claimable by one actor, add a `Reservable` child.
- To let actors walk up to a new object, add `ApproachPoint` markers to it.

### World time and simulation

- A clock is the easy half. The hard half is "call me at this world time",
  because without it every future system quietly reinvents a timer, which is
  exactly what a shared framework exists to prevent.
- Signals and scheduling solve different problems. Signals are for reacting to
  now and may be collapsed for performance; a booking must never be missed.
  Being explicit about which is which stopped both from being compromised.
- Skipping time correctly means stepping, not jumping. Firing a day's events
  after the clock has already reached the end would have them all see the wrong
  world.
- The autoload should be the driver, not the model. Keeping `WorldClock` a plain
  object made it testable, serialisable and duplicable, at no cost.
- Store one number, derive the rest. Day, hour and minute held separately can
  disagree; derived from a single minute count they cannot.
- Two levels of pause is a feature, not a mess — as long as the debug view shows
  both, because a hidden second flag is how "why is it frozen" bugs start.
- Save enums by stable string id, not by integer. Inserting a state later must
  not silently change what an old save means.
- A `Callable` cannot be serialised, and pretending otherwise would be worse
  than the honest pattern: restore the time, let each system re-book itself.

## Current understanding checks (time and simulation)

- To make something happen at a fixed time daily, call
  `WorldTime.schedule_daily(hour, minute, callback, tag)`.
- To make something take world time, call `WorldTime.schedule_in(minutes, ...)`
  instead of creating a `Timer`.
- To decide whether a system should update, call `Simulation.is_running()`,
  `accepts_input()` or `updates_actors()`.
- To change how long a day feels, edit `game_minutes_per_real_second`.
- To change what a state permits, edit `default_state_rules.tres`, not a script.
- To show a time anywhere, use `TimeFormatter`.

## Next learning focus

Build the first real consumer of the time framework — tavern opening hours —
which is two `schedule_daily` calls and a flag the customer spawner reads. It is
the cheapest honest test of whether the scheduler is genuinely reusable or only
looks it, and it exercises pausing, speed changes and skipped time in one go.

---

# Durable Development Lessons

Everything above is Godot and engine learning from building the project.
Everything below is process and debugging lessons — added when a discovery is
likely to save future time. Add an entry when a diagnosis turns out to have been
wrong in a way that could recur.

## Evidence

**One short simulation is not evidence of an AI fault.** Run length, customer
count, staffing, stock and sample size all move the metrics. Establish
prerequisites before judging behaviour.

**Stock and staffing are confounds.** Several "customer AI is broken" reports
turned out to be an empty storeroom or a single worker.

**Instrument before tuning twice.** If a change produces no meaningful movement
two attempts running, stop turning the dial and measure the state or transition
directly.

## Tests

**A test can report `0 failed` while running a fraction of its assertions.** A
script error mid-run silently skips the rest. Watch the assertion **count**.

**Verify a suspected test-side break against a clean checkout first.** Test
fixtures build their own miniature tavern and can legitimately need updating —
but assuming that without checking has cost two cycles.

**Compare the failure set, not the count.** `group_keg_loop_test` is flaky
between 27/5, 28/4 and 29/3 on identical builds.

## Static reading versus running

**Static file reading has given the wrong answer repeatedly on this project.**
Run the scene. Three separate navigation hypotheses derived from reading the
files were disproved by a probe measuring the live navmesh.

**`--check-only --script` gives false errors for `class_name` files.** Only
`--headless --editor --quit` is authoritative for compilation.

**`--headless --editor --quit` does not import textures.** `--headless --import`
does. Run it first on a fresh clone.

## Navigation

**"On the navmesh" is not "can stand here".** `map_get_closest_point()` returns
a point on the polygon *edge* for anything outside it. An actor cannot hold a
boundary point — avoidance nudges it off, arrival never satisfies, and the
executor reissues the same move forever.

**Never bias an approach point toward the approaching actor.** It makes the
answer depend on where the worker happens to be, and sent the bartender to the
customer side of his own bar.

**An isolated walkable pocket looks identical to open floor** through a closest-
point query. Check reachability, not just walkability.

**Navigation map readiness must be established before interpreting results.** An
empty or unready map is not a customer AI fault, and returns the origin rather
than failing.

## Architecture

**Two readings of one quantity is the recurring failure mode.** It has happened
in the game (storeroom display versus storage) and inside the diagnostic system
itself (stock report versus chain validator). One owner, everything else
observes.

**Changing a resource's shape means auditing its UI consumers.** The supplier
resource tested perfectly while the Order Ledger panel crashed, because the menu
still read a field that filled-container entries do not have.

**A silent default is worse than a missing value.** The reusable station scene
shipped a grog refill item, so any station that forgot to override it asked
staff for a grog barrel — a well-formed task, existing stock, successful
transfer, and completely wrong. Prefer nothing over a plausible default.

**Verifying a node exists is not verifying it is wired.** A missing reference is
a silent null.

**A parent-walk assumption breaks the moment a nesting level is inserted, and
nothing announces it.** `a6e8993` ("Add cross-activity affinity and a two-slot
darts model") moved darts' `Reservable` one level deeper - direct child of
`TavernActivityPoint` to child of a new `TavernActivitySlot` - so the
existing `reservable.get_parent() as TavernActivityPoint` cast in
`VisitTavernActivityBehaviour.on_enter()` always returned null afterward.
Every darts selection was abandoned in the same instant it was entered,
silently, from that commit forward on `main` - independent of Phase B, which
only exposed it by finally making darts win selection often enough to hit
the path. The fourth time on this project a computed failure signal
(`abandon_activity_visit("reserved_destination_not_a_activity_point")`) was
discarded before reaching any surface - see `CURRENT_STATE.md`'s Known
issues and DECISIONS.md §17's "diagnostics observe, never re-implement" for
the pattern this keeps producing. Fix: an explicit back-reference
(`TavernActivitySlot.point`, set by the owner) instead of a parent-walk that
assumes a fixed nesting depth. Where a node relationship matters, prefer a
reference set by the one class that knows it over a lookup that infers it.

**A recurring bug class survives a fix that only touches the instance found,
not the pattern.** Raw, unbounded values used directly as scoring inputs
have now broken customer decisions three separate times on this project:
`wealth` (raw coin count) broke the leave decision; `remaining_visit_minutes`
(raw minutes) distorted relax against darts and was fixed by deleting the
condition outright; `order_drink`'s money/visit-time scoring
(`2026-08-25_PHASE_B_VERIFICATION_PASS.md`) does the same thing a third
time, undiscovered until a full individual-customer-history read (not an
aggregate) made the pattern visible - a customer at `thirst=0.02` still
winning the reorder contest at score 18.4. Each fix so far treated the
symptom (this one condition, this one activity) rather than searching for
the same shape elsewhere. When a raw-context-value defect is found and
fixed, the right next step is grepping every `NeedThresholdCondition` with
`value_is_context = true` for the same missing normalisation, not just
closing the one instance found.

**A filter enforced when computing the winner is not automatically enforced
on the pool a later step samples from.** `CustomerBrain.think()`'s stage-3
motivation filter correctly excludes a non-serving candidate from ever
becoming `best`/`best_score` - but the weighted-selection call right after
it (`_select_weighted(eligible_for_report, best_score)`) was handed the
*unfiltered* `eligible_for_report` list, not the filtered set `best` came
from. A candidate the filter had already correctly rejected could still be
resampled back in, purely because its raw score happened to sit within
`selection_band` of whatever the filtered competition produced - three
confirmed cases in one 20-history read
(`2026-08-25_SCORING_AUDIT.md` §7). Two lists that are *supposed* to be the
same population but are built at different points in a function, one
before a filter and one after, will silently diverge the moment a third
step (weighted selection, added later than the filter) reads the wrong
one - the same shape as the two-readings-of-one-quantity lesson above, just
with a filtered/unfiltered list instead of two separate value sources.

**An aggregate metric can stay flat while the mechanism underneath it is
completely different.** "No activity at all: 78.6%" measured after this
pass's real fixes (slot-bug, leave-stage-1, needs inversion, time-
decoupling) landed is numerically almost identical to the pre-fix 78.5%
figure - which could easily read as "nothing changed, the fixes didn't
work." Reading five complete individual decision histories instead of the
aggregate showed the opposite: the fixes worked exactly as designed
(genuine non-monotonous relax/socialise/darts sequences, leave winning on
merit), and a *different*, previously-invisible cause (`order_drink`'s own
scoring) is independently holding the aggregate flat. An unchanged
aggregate is not evidence a fix did nothing; it can also mean two effects
of similar size are now cancelling where only one existed before.

## Godot file handling

**Godot re-saves `[sub_resource]` blocks without `script_class`.** A regex
matching on `script_class` silently misses previously written blocks and
duplicates them.

**Preserve the original `uid` line when rewriting a `.tres`.** Inventing one
breaks every reference to it.

**Anchoring a scripted edit on a common line hits the wrong node.** A property
assignment landed on `BarManagementMenu` instead of `StockDevPanel` because both
contained the same line. Anchor on something unique.

## Git

**Never use `git stash` as the only protection for uncommitted work.** It
silently shelved a full session's changes on this project.

**Diff the developer's commits before delivering.** Ship only what has not
already landed, rebased onto their HEAD.
