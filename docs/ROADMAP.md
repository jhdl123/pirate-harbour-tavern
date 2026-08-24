# Roadmap

Working roadmap. Nothing is complete until implemented **and** verified.
Reconciled against `825add8`; items already built have been removed rather than
carried forward as aspiration.

## The strategic gap

The simulation is deep; the game is thin. Service quality is measured in detail
and currently has **no consequence** — no reputation, no progression, no
end-of-day spend, and one day does not differ from the next. Closing that loop
is worth more than any additional system.

## Priority 0 — Make the day loop matter

The progression spine. Largely unbuilt, but most of the plumbing exists.

- **Reputation** — one value moved by events already emitted (drinks served,
  patience departures, group outcomes). *Not implemented.*
- **Reputation → demand** — register a `Modifier` against spawn weight.
  `Modifiers` exists with a target registry and stacking and **nothing currently
  registers anything**; `TavernDemandController` already consumes modifiers.
- **End-of-day spend** — extend the existing `EndOfDaySummary` modal with a
  small set of purchasable upgrades. *Not implemented.*
- **Recurring costs** — wages or rent so money has somewhere to go.
  *Not implemented.*

Target: day 5 should feel different from day 1 — busier, richer, one upgrade
bought. That is the point at which this becomes a game worth showing someone.

## Priority 1 — Stabilise what exists

Before more features:

- `DeliverGroupKegExecutor` validity check (worker stranded holding a keg).
- Task cancellation rate (24–35%).
- Group activity participation at 0.0%.
- Behind-bar walkable strip too narrow for staff to hold position (level fix).
- Call `record_stock_event()` from delivery and withdrawal so the diagnostic
  stock log stops being empty.

## Priority 2 — Customer visits

Multiple drinks per visit; clearer departure logic; more varied visit lengths;
making existing customer identity and social depth **visible** to the player.

## Priority 3 — Staff

Hiring and progression; utilisation display; player overrides. Roles, claiming,
capabilities and executors already exist.

## Priority 4 — Stock and supply

Shortage consequences; more suppliers; delivery timing choices. Storage,
purchasing, warnings, restocking and physical display already exist.

## Priority 5 — Activities and tavern life

Gambling; entertainment; environmental interaction; special customer
opportunities. The activity framework exists and is data-driven.

## Priority 6 — Reputation depth and customer identity

Visit history, repeat customers, relationships, VIPs, special requests.
`CustomerIdentity` exists as a foundation.

## Priority 7 — Progression depth

Decoration, capacity, equipment, new drink tiers, reputation milestones.

## Priority 8 — World and harbour simulation

Ports, ships, captains, merchants, factions, trade, weather, world events.

## Future concepts

Smuggling, dynamic trade, port reputation, faction relationships, notable
visitors, harbour intelligence. **Ideas, not commitments** — they are promoted
into the roadmap explicitly or not at all.

## Roadmap rule

Do not jump to a lower priority because its architecture is interesting. Finish
the playable management loop before adding another large foundation.
