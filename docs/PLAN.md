# Plan

Long-term vision and current direction, in one file because the second only
makes sense in light of the first. This is **context for architecture, not a
build specification** — see `CLAUDE.md`'s working rules and `GAME_DESIGN.md`'s
own scope note. Nothing below is a task list; `ROADMAP.md` is the task list,
and `TASKS.md` is the one active slice of it.

## How to read this document

- **This file** — why the game is being built this way, and what the world
  might eventually contain. Changes rarely.
- `GAME_DESIGN.md` — design principles for what's actually being built now
  and next. Changes occasionally.
- `ROADMAP.md` — prioritised, ordered work. Changes often.
- `TASKS.md` — the one active phase. Changes every session.
- `CURRENT_STATE.md` — what is actually implemented and verified. The
  repository remains the real source of truth; this is a summary of it.

## Core fantasy

Own and run a tavern in a dangerous, interconnected pirate-era Caribbean
world, and gradually turn that tavern into whatever kind of establishment the
player wants it to become. The player is not required to leave the tavern —
the wider world exists to give the tavern's people, goods and rumours
something to come from.

## The tavern as the player's interface to the world

A customer is not an anonymous order generator. They can be a sailor, a
merchant, a captain, a pirate, an informant, a local, a traveller — and can
carry more than money into the room: news, rumours, goods, requests,
relationships, conflicts. The tavern's composition (who drinks there, what
its reputation is) should eventually shape what information and opportunity
reach the player, because that asymmetry — **the world knows what is
happening; the player only knows what reaches the tavern** — is the
strongest single mechanic this project has to offer.

```text
World Simulation → event → information → NPC → tavern → conversation
    → player learns → player decides → tavern/economy/reputation changes
    → (potentially feeds back into the world)
```

That loop, not any individual system, is the long-term goal.

## Systemic pillars (long-term direction, not all current)

- **Customers as characters** — identity, personality, preferences, memory,
  recognisable regulars, eventually relationships and reputation with
  individuals. Foundation exists (`CustomerIdentity`, `Personality`); depth
  is future (`ROADMAP.md` Priority 6).
- **Groups** — crews, companions, merchant parties; arrive, sit, act and
  leave together, but members can diverge into different activities. Built
  and verified — see `GROUP_FRAMEWORK.md`.
- **Staff and delegation** — the player moves from doing everything to
  running the operation. Built — see `STAFF_TASK_SYSTEM.md`. Hiring and
  progression are future (`ROADMAP.md` Priority 3).
- **Economy** — beyond fixed prices: supply, scarcity, supplier
  relationships, cause-and-effect pricing. Storage, purchasing and
  restocking exist; shortage consequences and multiple suppliers are future
  (`ROADMAP.md` Priority 4).
- **Trade and smuggling** — the tavern as a commercial node, not a
  travelling-merchant minigame. Not started. Should interact with the
  economy and reputation systems rather than exist standalone, whenever it
  starts.
- **Gambling and activities** — extra reasons to stay, extra revenue, extra
  risk. The generic activity framework (data-driven, capable of more than
  one participant) is built and already proven twice — Socialise at Seat and
  Darts. A future card or dice table is the same framework with a different
  participant count and its own slots, not a new mechanism. See
  `CUSTOMER_AI_SYSTEM.md`.
- **Reputation** — not necessarily one number; potentially several
  dimensions (legitimate trade, gambling den, safe harbour for smugglers).
  Currently nothing registers a modifier yet, though `Modifiers` (the
  stacking-modifier autoload) exists specifically to be fed by this later.
  This is `ROADMAP.md` Priority 0 — the highest-priority unbuilt system,
  because service quality currently has no consequence.
- **Factions** — governments, merchants, pirates, criminal groups, each with
  their own interests, eventually shaped by the player's own activity mix.
  Not started; no architecture commitment made either way yet.
- **Information as a resource** — rumour → report → intelligence →
  knowledge, each with a source, reliability and age. Not started. A future
  information system most likely sits next to `Comms` rather than replacing
  it, but that is undecided until there is a concrete need to build against.
- **World/harbour simulation** — ports, ships, captains, weather, routes.
  Exists only as `ROADMAP.md` Priority 8 and "Future concepts" — deliberately
  the last thing to build, because it only pays off once it has somewhere to
  report into (the tavern).

## What this project is not

A restaurant simulator measured in service speed. A pure combat or trading
game. A world simulator that exists for its own complexity. A dialogue-only
narrative game. The tavern stays the immediate, played experience no matter
how deep the systems behind it grow.

## Guiding question

> Does this make the tavern feel more alive, make the player's decisions
> more meaningful, or strengthen the connection between the tavern and the
> wider world?

If a proposed system doesn't move one of those three, weigh its cost
carefully before adding it — see `GAME_DESIGN.md`'s "Avoid" list and
`CLAUDE.md`'s working rules 3–6.

## Architectural principles this vision depends on

None of the above should ever require rewriting the customer, staff or
economy core to add. That depends on principles already enforced in
`ARCHITECTURE.md` and `DECISIONS.md` — restated here only as the reason they
matter for the long game, not redefined:

- **Data-driven, configurable systems** — a new drink, activity, customer
  type or eventual commodity should be data, not a new branch in behaviour
  code (`DECISIONS.md` #2).
- **Modular, reusable behaviour over special cases** — new mechanics compose
  existing reservation, navigation, task, item and activity systems rather
  than duplicating them (`DECISIONS.md` #4, #7, #11).
- **Avoid unnecessary hard-coding** — a hard-coded `if activity_id == ...`
  branch is a signal something should have been exported data instead. The
  darts-to-two-participants work is the concrete recent example: see
  `ARCHITECTURE.md`'s "Customer AI and activities" section.
- **Extensibility without over-engineering** — build what the current phase
  needs; do not add configurability or participant slots for a case that
  does not exist yet (`DECISIONS.md` #13).
- **Separation of simulation and presentation** — the world can know things
  the player doesn't yet; UI observes gameplay state through signals and
  never owns it (`ARCHITECTURE.md`'s dependency rules).
- **Testable systems** — behaviour with a numeric claim needs a test or
  diagnostic behind it before it's trusted (`CLAUDE.md`'s verification
  levels).
- **Incremental development** — systems are built in the order the playable
  game currently needs them, not the order this document lists them in.

## Do not prematurely implement this document

The existence of a system here does not mean it should be implemented while
touching something else. When extending anything, ask: does the current
implementation need to be structured differently to avoid *blocking* one of
these future systems? If yes, make that structural allowance. If no, keep
the current implementation simple. An item is promoted from this document
into active work explicitly, in `ROADMAP.md` — never implicitly, because a
brief happened to mention it.
