# Customer Inspector

A hover/select inspection panel over customers. Built now as a development
instrument; it is the foundation the later information UI grows from.

Adopted 2026-08-25 alongside `CUSTOMER_MODEL.md`.

## Why build it now

Two returns from one piece of work.

**As a debugging instrument.** The customer model cannot be tuned by watching
the game and guessing. "Why is that man sitting down?" is currently answerable
only by writing a headless probe. It should be answerable by hovering over him.

**As the information UI foundation.** The eventual game needs the player to look
at a room and decide who is worth their attention. That is the same panel with a
different disclosure rule.

There is also a pattern this fixes. Diagnostic data has been *collected,
computed, and then discarded before reaching any surface* at least four times on
this project — staff utilisation, departure reasons, task cancellation reasons,
activity score contributions were all already being calculated and never shown.
`Customer.get_diagnostics_snapshot()` and
`ActivityDefinition.get_utility_breakdown()` already return most of what this
panel needs. This is mostly a rendering job, not an instrumentation job.

## Architecture rule (non-negotiable)

```
Customer  →  CustomerInspectionData  →  CustomerInspectorUI
```

The UI **never** reads customer internals, needs, the brain, or the activity
registry directly. The customer produces an immutable snapshot; the UI renders
it.

This exists so the decision architecture can be rewritten again — and it will
be — without touching UI. It is the same rule as `StockedDisplay` being a view
over storage rather than an inventory (`DECISIONS.md` §3), and the same failure
mode it prevents.

## Disclosure tiers

One panel, two rules for what it may contain.

### Developer tier — this pass

Everything. Gated behind the existing debug-build check, alongside F10.

```
Name · customer type · current state · current activity
Visit purpose · visit elapsed / expected
Needs (all, 0–1)
Current motivation (stage 2 winner)
Candidate activities with scores, and why rejected candidates were rejected
Group membership and role
Money · drinks consumed · intoxication · mood
```

The candidate list is the most valuable part. This is the difference between:

```
tavern_activity_started = 8
```

and:

```
Sailor12 — Drinking
  motivation: ENTERTAINMENT
  darts        14.2   selected
  socialise    11.8
  relax         8.4
  → reservation FAILED: destination unavailable
```

The second tells you where the problem is. The first does not.

**Reservation and execution outcomes must appear here**, not only selection.
Selection succeeding and execution failing look identical from a count.

### Player tier — later, not this pass

Progressive disclosure driven by what the player has learned about that
customer. Build the tier mechanism now; leave it showing only type, state and
activity.

```
Captain Elias
Pirate Captain
Drinking with crew

Known to you:
  Frequent visitor
```

## Non-goals

- No permanently visible bars over customers' heads.
- No happiness meter. Needs are demands, not satisfaction — see
  `CUSTOMER_MODEL.md` §2.
- No editing customer state from the panel.
- No new data sources. If the panel wants a number, it is exposed on the
  snapshot by the system that already owns it. Diagnostics observe, never
  re-implement (`DECISIONS.md` §17).

## Interaction

Hover to inspect is the target. If the existing interaction framework makes
select-to-inspect substantially cheaper, take that and note the deviation —
customers are already interactables and the framework should not be bypassed
for this (`DECISIONS.md` §10).
