# Group formation and shared-order integration fix

## Root cause

Seated group members were handed to `Customer.arrive_at_seat()`, which continued
through the normal solo-customer AI path. Each member therefore selected and
placed an individual order while `GroupManager` was also running the group's
shared-order state machine. The shared keg/cask framework existed, but this
handoff prevented it from owning the visit cleanly.

## Changes

- Group members now wait outside in a compact two-column formation with safe
  28 px centre spacing, rather than appearing as a long line.
- Entry remains controlled one member at a time to protect the doorway.
- Seated members enter `IN_GROUP` when they reach their reserved chair and do
  not start solo ordering, patience, visit-time or utility behaviour.
- `CustomerGroup.are_members_in_position()` now requires every member to have
  reached its place and entered `IN_GROUP`; ordering no longer starts when only
  60% of the party has arrived.
- `GroupManager.shared_orders_only` defaults to true. The implemented shared
  keg/cask/pitcher path is used for group visits; the incomplete individual
  fallback is bypassed.

## Current behaviour

Once the whole party is settled, GroupManager waits `minutes_before_ordering`
(default 2 world minutes), selects an available shared drink and serving format,
reserves stock, creates the shared serving at the table/standing area, takes one
payment, and lets members consume portions in staggered turns.
