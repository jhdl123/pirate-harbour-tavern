# Customer Group Framework — Architecture Review

Reviewed against the current workspace (Beverage Framework build).

---

## 1. The constraint that shapes this job

**The tavern has 8 seats.** Two tables (`table1`, `table2`), four chairs each.

That is the whole seating capacity. It means:

- A group of 5+ can **never** be seated, at any time, regardless of occupancy.
- Two groups of 4 fill the tavern completely.
- Solo customers compete for the same 8 chairs.

So standing areas are not a fallback in this build — for anything above a
foursome they are the **only** path, and for realistic occupancy they will
carry most group visits. The brief anticipates this ("particularly important
because the current tavern has limited tables and seating"), but it is worth
being explicit: the seated path will be the rarer one until the bar is
redesigned.

This also means the acceptance test "fill all tables and spawn another group"
is reached almost immediately, which is convenient for testing.

## 2. Spawning is gated on seat availability

`GameManager.spawn_customer()` returns early:

```
var assigned_chair := find_best_available_chair()
if assigned_chair == null:
    record_arrival_rejection(&"no_seating")
    return
```

A customer is never created unless a chair is free. Standing visits require
this to be restructured so place selection happens *after* the decision to
admit a visit, not before. This is the single most invasive change in the
update, and it sits in the middle of the existing solo-customer path — so it
has to be done without disturbing that path.

## 3. What can be reused directly

| System | Verdict |
|---|---|
| `Reservable` / `ReservationService` | **Reuse.** Reserve → occupy → release with holder tracking, tags and expiry recovery. Atomic multi-seat booking is a loop over `reserve()` with rollback on any failure — no new reservation system needed. |
| `Table` | **Extend.** Already groups its chairs and exposes `get_available_chairs()` / `get_available_seat_count()`. The natural home for "can this table seat my whole group?". |
| `SharedServing` | **Already ready.** It has `group_id`, and `is_consumer_eligible()` checks it *first*, falling back to table proximity only when empty. That hook was added in the last phase for exactly this. It needs no changes once customers carry a group id. |
| `ServingFormatDefinition` | **Already ready.** `is_shared`, `portion_count`, `minimum_group_size`, `maximum_group_size`, `requires_table`, `allows_standing_area`, `creates_group_anchor` are all authored and validated. Group order selection reads them as-is. |
| `VesselPool` | **Reuse.** Reserve/release already conserves counts, and `SharedServing` returns its vessel exactly once through a guard. |
| `PreparationService` | **Reuse the service, build the task.** See section 5. |
| Navigation / avoidance | **Reuse untouched.** Formation slots become ordinary navigation targets. |
| `TavernActivityPoint` | **Pattern to copy.** A `GroupStandingArea` is the same shape — an authored node with a `Reservable`, markers and a capacity — so it should follow the same conventions rather than inventing new ones. |

## 4. What does not exist yet

- No group concept anywhere. `ModifierTargets.CUSTOMER_GROUP_SIZE` remains a
  declared, unread constant.
- Customers have no `group_id`. `SharedServing.is_consumer_eligible()` calls
  `consumer.get(&"group_id")`, which currently returns null for every customer,
  so it always falls through to the proximity branch.
- No standing areas, no formation logic.
- No group-level order representation. `Customer.ordered_drink` is a single
  `DrinkDefinition` with no serving format and no group association.

## 5. Dependency: the beverage integration is not finished

This brief requires "staff delivering a shared serving" and the full punch bowl
path. That depends on work flagged as outstanding at the end of the last phase
and still outstanding now:

- **`PreparationService` is not referenced by any staff task.** Confirmed by
  search: it appears only inside `systems/beverage/` and the tests. The
  executors are `clean_seat`, `prepare_drink`, `refill_station`, `serve_drink` —
  `prepare_drink` predates the framework and still works off
  `station.served_drink`.
- **Customer orders carry no serving-format id.**
- **Nothing delivers a shared serving into the world.** `SharedServing` can be
  created and consumed from, but no staff path produces one.

So a meaningful part of this update is finishing the previous one. That is
fine — the brief says to connect the two — but it means the "group" work and
the "beverage integration" work are not separable, and the estimate should
reflect both.

## 6. Proposed architecture

```
CustomerGroupDefinition   resource: what kind of party this is
        │
CustomerGroup             runtime controller, one per visit
        │                 owns the group state machine
        ├── members[]  →  Customer nodes, each with group_id
        ├── leader     →  one member, replaceable
        ├── place      →  GroupPlace (seated: Table + chairs
        │                            standing: GroupStandingArea)
        ├── order      →  GroupOrder (drink id + serving format id)
        └── serving    →  SharedServing (existing, unchanged)

GroupRegistry             autoload-style roster of active groups
GroupStandingArea         authored scene node: centre, entry, serving point,
                          formation radius, capacity, Reservable
GroupFormation            pure function: centre + count + layout → slots
```

**Division of responsibility.** The group controller makes group-level
decisions — where to sit, what to order, when to leave. It never drives a
member's movement frame by frame; it assigns a destination and the customer's
existing navigation and state machine do the rest. That keeps the group layer
thin and stops it becoming a second customer AI.

**Place abstraction.** Seated and standing visits differ in how a place is
found and reserved, not in what a place *provides* — a centre, per-member
positions, a serving point, and a release. Wrapping both behind one `GroupPlace`
interface is what keeps the state machine from branching on place type at every
step.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Breaking the solo customer path in `spawn_customer()` | Group spawning becomes a separate entry point; the solo path keeps its early-return unchanged. |
| Half-reserved seats | Atomic reserve-all-or-none with rollback, tested directly. |
| Two members taking the last portion | `SharedServing.take_portion()` is already single-threaded and guarded; the test asserts it. |
| Formation jitter | Slots assigned once on arrival and held; no per-frame recompute. |
| Groups permanently holding a place | Every failure state routes to departure; a watchdog releases reservations. |
| Standing areas blocking staff | Areas are authored nodes placed away from service points, with a documented radius. |
