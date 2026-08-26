# Game Design — Pirate Harbour Tavern

Intended experience and design principles. For what is actually built, see
`CURRENT_STATE.md`. For durable implementation/design decisions, see
`DECISIONS.md`. For the long-term vision behind these principles, see
`PLAN.md`.

## Vision

A tavern management simulation set in a pirate/Caribbean port. It should feel
like running a real tavern, not operating a fast-food service line. Customers
spend meaningful time in the tavern and create a living environment around the
player.

The tavern itself is the primary interface to the game world. The player should
learn about, manage and influence the tavern by being physically present in it,
rather than interacting primarily through abstract menus.

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

Customer identity should become increasingly meaningful over time. The player
should gradually recognise returning customers and learn things about them,
rather than being given complete information about every simulated character.

## Tavern life

Reasons to stay: drinking, conversation, gambling, relaxing, entertainment,
environmental interaction, meeting particular people, events, and later
smuggling and trading opportunities.

Activities should create consequences, not exist as decoration.

Most customers should still spend ordinary time drinking, talking and relaxing.
The goal is a believable tavern, not a theme park where every customer is
constantly performing an activity.

## Management pillars

Service · Customers · Staff · Stock · Cleaning and maintenance · Economy ·
Reputation · Expansion and decor · Progression · Events · Harbour/world
simulation · Trading, smuggling and risk.

## UI and interaction philosophy

The UI should support the tavern rather than compete with it.

### World-first communication

The tavern world should communicate state wherever possible. A dirty table,
waiting customer, active dart game or staff task should be understandable from
the world itself before the player needs to read a notification.

UI should reinforce information that is difficult to perceive rather than
constantly restating everything happening in the simulation.

### Minimal persistent HUD

The normal gameplay HUD should remain deliberately restrained.

Persistent information should primarily be limited to information that is
constantly useful during tavern management, such as:

- Current day
- Current time
- Money
- Important active status where genuinely necessary

Other information should appear contextually.

### Hybrid interaction

Interaction should be simple when the action is obvious and become more
expressive when there are meaningful choices.

A single available action executes immediately.

Multiple available actions open a contextual action panel.

Interaction prompts should be compact and consistent rather than large
instructional overlays.

### Targeting

The closest interactable is the default target.

Mouse hover can override the automatic target, and Tab can cycle through nearby
interactables.

The system should remain forgiving. Interaction should not require pixel-perfect
positioning or strict facing/line-of-sight rules.

### Hover information

Hover information is a glance layer.

It should provide a short contextual summary of the thing being targeted rather
than exposing its complete information.

Hover summaries should be world-anchored, concise and visually unobtrusive.

### Customer knowledge

Customer information represents what the player knows, not what the simulation
knows.

The player should not automatically receive complete NPC data simply because it
exists internally.

Customer information is progressively discovered through gameplay. The exact
sources of information will be designed later as part of the information
system.

Unknown information should normally be hidden rather than represented by
question marks or locked RPG-style fields.

### Customer inspection

Customers can be inspected through the normal interaction system.

The intended flow is:

Hover → contextual summary

`[E]` → immediate action or contextual interaction panel

Inspect → full customer dossier

Deep inspection pauses the simulation so the player can read and consider the
information without the tavern continuing to operate behind the UI.

The dossier should use an enlarged representation of the customer's actual
in-game character rather than requiring separate portrait artwork.

The dossier should feel like a character record with some journal-like
qualities rather than a conventional RPG stat sheet.

It may eventually contain:

- Identity
- Known description
- Relationship to the tavern/player
- Known preferences
- Known connections
- Meaningful history
- Current status when relevant
- Rumours and information learned through the information system

Undiscovered information should not be shown.

Player-written notes are deliberately not a near-term feature.

### Customer ledger

The office should eventually contain a physical customer ledger.

The ledger is an in-world object, not simply another abstract HUD menu.

The intended flow is:

Office → `[E] Examine Ledger` → ledger opens → customer entry → shared
character dossier

The ledger and in-world customer inspection should use the same underlying
dossier presentation rather than creating two different customer-information
interfaces.

The exact rules determining who appears in the ledger are intentionally left to
the future information-system design.

### Menus and management

Management menus should use the same visual language as the in-world UI while
being more information-dense.

The management interface should grow through a small number of categorised
sections rather than becoming one large flat list.

Future systems should not be exposed in the UI before they exist.

Menus should behave as a consistent modal stack:

- Esc goes back one level.
- Close buttons perform the same navigation.
- The simulation remains paused throughout a deep management interaction.
- Closing the top-level modal returns to gameplay.

### Notifications and alerts

The world communicates normal state first.

UI notifications provide supporting information when something is easy to miss
or useful to confirm.

Routine actions should normally communicate through contextual feedback and
world-state changes rather than generating a notification every time.

Notifications can have different persistence:

- Brief feedback for routine events.
- Longer-lived alerts for unresolved problems.
- Stronger presentation for genuinely important events.

### Visual consistency

UI should use a coherent visual language throughout the game.

The same principles should apply to interaction prompts, hover summaries,
contextual menus, customer dossiers, management screens, notifications,
tooltips and debug tools.

The visual language should fit the pirate tavern and existing pixel-art
direction without becoming excessively decorative.

### Readability and accessibility

Readability is a design requirement, not a later polish task.

The UI should favour:

- Clear text hierarchy
- Sufficient contrast
- Readable text sizes
- Consistent terminology
- Icons supported by text where appropriate
- Important information not relying on colour alone
- Sensible scaling opportunities

Accessibility should be considered while UI systems are created rather than
retrofit after the entire interface has been built.

## Management attention

The player should not perform every task forever. The challenge becomes deciding
what deserves attention and what to delegate.

UI should help the player understand:

- What needs attention
- Why it needs attention
- What staff are doing
- What customers want
- What has gone wrong
- What the tavern is earning
- What decisions are available

The UI should inform decision-making without turning the game into a dashboard
where the player spends more time reading panels than watching the tavern.

## Design principles

**Taverns are social spaces.** Time spent in the room is the point; emergent
situations come from customers staying.

**The world is the primary interface.** Menus and notifications support what the
player sees rather than replacing it.

**Management becomes about attention.** The player should not perform every task
forever. The challenge becomes deciding what deserves attention and what to
delegate.

**Presence versus reach.** The player cannot be everywhere. Staff, layout,
visibility, customer importance and alerts create meaningful choices.

**Player knowledge is distinct from simulation knowledge.** The simulation may
know more than the player. UI should respect that distinction.

**Data-driven balance.** Customer types, drinks, activities, prices and timing
live in Resources and configuration, not in behaviour scripts.

**Systems compose.** New mechanics reuse the existing reservation, navigation,
interaction, action, time, task, item, communication, economy and activity
systems rather than adding isolated implementations.

**Communicate state.** The player should understand what needs attention, what a
customer wants, what staff are doing, why something failed, and how the tavern
is performing.

**Prefer contextual UI.** Information should appear when useful rather than
remaining permanently visible.

## Visual direction

3/4 top-down pixel art; classic RPG / tavern-management feel; warm wooden
palette; fixed upper-left lighting; modular characters and props; readable
silhouettes. Character identity comes from silhouette, clothing, hats, beards,
colour and UI identity rather than tiny facial detail.

The UI should complement this visual direction rather than imitate a generic
modern application.

## Avoid

- Turning the game into a queue-optimisation puzzle.
- Adding mechanics because they are technically easy.
- Hard-coding balance into behaviour scripts.
- Duplicating player and staff systems.
- Customers vanishing immediately after service.
- Customers that are effectively identical.
- Broad statistical claims from short simulations.
- Building large systems before the gameplay need is demonstrated.
- Filling the screen with permanent UI.
- Exposing simulation data the player has not discovered.
- Building speculative UI systems before the gameplay need is demonstrated.
- Making every interaction require a menu.
- Making every game event generate a notification.

## Current design tension

The simulation is considerably deeper than the player can currently perceive or
influence. The UI/interaction layer is therefore an important bridge between
existing simulation depth and the player's experience.

The immediate objective is not to expose every underlying system. It is to make
the existing game understandable, responsive and pleasant to interact with,
while establishing a foundation for the later customer-information,
relationship, reputation and world-information systems.
