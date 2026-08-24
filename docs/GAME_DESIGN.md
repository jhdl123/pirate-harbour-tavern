# Game Design — Pirate Harbour Tavern

Intended experience and design principles. For what is actually built, see
`CURRENT_STATE.md`.

## Vision

A tavern management simulation set in a pirate/Caribbean port. It should feel
like running a real tavern, not operating a fast-food service line. Customers
spend meaningful time in the tavern and create a living environment around the
player.

## Core rhythm

Open → attract customers → observe needs → serve and manage → maintain → earn →
respond to problems → improve → close → review → prepare for the next day.

Customers should not appear, order one drink and disappear.

## Customer philosophy

Customers are individuals, not anonymous orders. The design supports different
types and personalities, drink preferences, patience and service expectations,
spending power, social behaviour, activities beyond drinking, longer and repeat
visits, recognisable identity, groups, and eventually reputation, relationships
and notable/VIP customers.

Customer behaviour is data-driven through the activity framework rather than a
growing monolithic state machine.

## Tavern life

Reasons to stay: drinking, conversation, gambling, relaxing, entertainment,
environmental interaction, meeting particular people, events, and later
smuggling and trading opportunities.

Activities should create consequences, not exist as decoration.

## Management pillars

Service · Customers · Staff · Stock · Cleaning and maintenance · Economy ·
Reputation · Expansion and decor · Progression · Events · Harbour/world
simulation · Trading, smuggling and risk.

## Design principles

**Taverns are social spaces.** Time spent in the room is the point; emergent
situations come from customers staying.

**Management becomes about attention.** The player should not perform every task
forever. The challenge becomes deciding what deserves attention and what to
delegate.

**Presence versus reach.** The player cannot be everywhere. Staff, layout,
visibility, customer importance and alerts create meaningful choices.

**Data-driven balance.** Customer types, drinks, activities, prices and timing
live in Resources and configuration, not in behaviour scripts.

**Systems compose.** New mechanics reuse the existing reservation, navigation,
interaction, action, time, task, item, communication, economy and activity
systems rather than adding isolated implementations.

**Communicate state.** The player should understand what needs attention, what a
customer wants, what staff are doing, why something failed, and how the tavern
is performing.

## Visual direction

3/4 top-down pixel art; classic RPG / tavern-management feel; warm wooden
palette; fixed upper-left lighting; modular characters and props; readable
silhouettes. Character identity comes from silhouette, clothing, hats, beards,
colour and UI identity rather than tiny facial detail.

## Avoid

- Turning the game into a queue-optimisation puzzle.
- Adding mechanics because they are technically easy.
- Hard-coding balance into behaviour scripts.
- Duplicating player and staff systems.
- Customers vanishing immediately after service.
- Customers that are effectively identical.
- Broad statistical claims from short simulations.
- Building large systems before the gameplay need is demonstrated.

## Current design tension (honest note)

The simulation is considerably deeper than the player can currently perceive or
influence. There is no reputation, no progression and no end-of-day spend, so
service quality has no consequence and one day does not differ from the next.
Closing that gap is the stated Priority 0 in `ROADMAP.md`.
