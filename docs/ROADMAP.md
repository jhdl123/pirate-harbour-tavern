# Roadmap

Working roadmap. Nothing is complete until implemented **and verified**.

This roadmap describes the current development priority, not the complete
long-term vision. The long-term vision remains in `PLAN.md`.

## Strategic goal

The simulation foundation is becoming increasingly deep, but the player needs
to be able to perceive, understand and influence that simulation.

The immediate goal is therefore to close the gap between:

**simulation → player perception → player decision → meaningful consequence**

The next development stages should prioritise player experience and a
convincing living tavern before adding large new world systems.

---

# Priority 0 — UI/UX Foundation

**Current focus.**

The customer AI and activity foundations have recently been substantially
developed. Before adding another major gameplay layer, consolidate how the
player sees, understands and interacts with those systems.

## In-world interaction

- Minimal `[E] Action` prompts.
- Closest interactable selected automatically.
- Mouse hover overrides automatic targeting.
- Tab can cycle nearby targets.
- Subtle target highlighting.
- One obvious action executes immediately.
- Multiple actions open a contextual action panel.
- Mouse + keyboard interaction.
- Forgiving proximity-based interaction.

## Hover information

- World-anchored hover summaries.
- Context-sensitive information depending on target type.
- Short summaries rather than full information panels.
- Customer hover information respects player knowledge.
- Hover should remain visually unobtrusive.

## Customer inspection

- Customer contextual interaction panel.
- Inspect action.
- Paused character dossier.
- Enlarged actual customer representation.
- Progressive/knowledge-gated information.
- Descriptive relationship information.
- Meaningful history where available.
- Current status where useful.
- Hidden undiscovered information.
- Shared dossier presentation regardless of entry point.

The exact information/knowledge rules remain deferred to the later information
system design.

## Customer ledger foundation

- Physical office ledger as an in-world interactable.
- `[E] Examine Ledger` opens directly.
- Ledger provides access to known/discovered customer records.
- Ledger uses the same customer dossier as in-world inspection.

The exact rules for who appears in the ledger remain deferred.

## General UI

- Minimal persistent HUD.
- Unified day/time/money presentation.
- Contextual notifications.
- World-first state communication.
- Consistent menus and modal stack.
- Consistent Esc/Close navigation.
- Contextual tooltips.
- Custom themed cursor.
- Scrollable lists with contextual scrollbars.
- Consistent button states.
- Contextual confirmation for consequential actions.
- Readability/accessibility principles built into UI implementation.

## Management UI

- Same visual language as in-world UI.
- More information-dense than gameplay UI.
- Categorised management navigation.
- Do not expose future systems before they exist.
- Preserve existing management/debug functionality while improving usability.

## Debug UI

Debug tools remain developer-facing but should be easier to operate and
visually coherent.

Do not remove useful diagnostics simply to make the UI cleaner.

---

# Priority 1 — Living Tavern Behaviour

Once the UI foundation is in place, return to the central gameplay problem:

**Make the tavern feel like a place where people spend time.**

Customers should have reasons to remain after their immediate service need is
met.

## Immediate behaviour

- Validate the recently updated customer AI in normal gameplay.
- Confirm customers enter, navigate, sit, order, drink and leave naturally.
- Confirm customers do not simply cycle through the tavern.
- Confirm groups behave coherently.
- Confirm customers can linger without becoming stuck.
- Observe how often customers choose activities versus ordinary drinking,
  talking and relaxing.

## Activities

Start with a small number of meaningful activities rather than building a large
activity catalogue.

Likely first candidates:

- Darts.
- Socialising/conversation.

Then evaluate further activities based on what they add to the tavern rather
than simply adding variety.

Potential future activities include:

- Cards.
- Dice/gambling.
- Eating.
- Music/entertainment.
- Watching events.
- Environmental interactions.
- Special customer opportunities.

Activities should remain data-driven and plug into the existing activity
framework.

## Tavern-life goal

The target is not "every customer is doing something."

The target is a believable distribution:

**drink → talk → drink → occasionally play darts → talk → perhaps order again →
eventually leave**

Customers should create emergent situations and reasons for the player to pay
attention.

---

# Priority 2 — Complete the Daily Gameplay Loop

The player should be able to play through multiple days without developer
intervention.

Target loop:

**Opening → Service → Closing → End-of-day → Next day**

Complete/verify:

- Opening state.
- Customer arrival period.
- Active service.
- Closing.
- End-of-day summary.
- Daily income.
- Tips.
- Sales.
- Customers served/lost.
- Breakages.
- Stock usage.
- Daily results.
- Next-day transition.
- Developer lifecycle/debug controls.

The goal is to make one complete day feel like a meaningful unit of play.

---

# Priority 3 — Make the Tavern Economy Matter

The existing economy needs consequences.

## Reputation

- Establish a player-facing reputation value.
- Connect service/customer outcomes to reputation.
- Use reputation to influence demand.

## Money

- End-of-day spending.
- Recurring costs such as wages/rent.
- Purchasable upgrades.
- Meaningful financial decisions.

## Target

By around day 5, the player should be able to feel that the tavern is different
from day 1:

- More customers.
- More money.
- More responsibilities.
- At least one meaningful improvement.
- Consequences from previous performance.

---

# Priority 4 — Staff and Tavern Operations

The staff foundation already exists, so the next step is making it meaningful
to the player.

- Hiring.
- Staff progression.
- Utilisation display.
- Player overrides.
- Task priorities.
- Staff capability differences.
- Better task/alert presentation.
- Bartender serving/restocking behaviour.
- Cleaning workload.
- Delegation decisions.

The goal is to move the player away from personally performing every repetitive
task.

---

# Priority 5 — Stock and Supply

Existing stock/storage/purchasing foundations should become meaningful through
choices and consequences.

- Shortage consequences.
- Supplier differences.
- Delivery timing.
- Purchasing decisions.
- Restocking choices.
- Better warnings.
- Physical stock presentation.
- Costs and supply risk.

---

# Priority 6 — Customer Identity and Relationships

Once the basic tavern loop is enjoyable, deepen customers into persistent
characters.

- Named customers.
- Recognition.
- Repeat visits.
- Visit history.
- Preferences.
- Relationships.
- Groups and crews.
- Notable/VIP customers.
- Special requests.
- Customer-specific events.

This phase builds on the customer dossier and knowledge-aware UI established
earlier.

---

# Priority 7 — Information and Intelligence

Review and design the information system deliberately before implementation.

Potential information sources:

- Direct conversations.
- Observation.
- Repeat visits.
- Customer interactions.
- Other customers.
- Rumours.
- Staff observations.
- Events.
- Reports.
- Harbour/world information.

Potential outputs:

- Customer knowledge.
- Rumours.
- Relationships.
- Faction information.
- Harbour reports.
- Opportunities.
- Risks.

The exact rules should be designed as a separate system rather than being
implicitly defined by the UI.

---

# Priority 8 — Progression Depth

Once the core loop and economy work:

- Decoration.
- Tavern capacity.
- Equipment.
- New drink tiers.
- New facilities.
- Reputation milestones.
- Staff progression.
- Activity improvements.
- Tavern specialisation.

Progression should change how the tavern operates, not simply increase numbers.

---

# Priority 9 — World and Harbour Simulation

Build the larger world simulation once the tavern can meaningfully consume its
information.

Potential systems:

- Ports.
- Ships.
- Captains.
- Merchants.
- Factions.
- Trade.
- Weather.
- Travel.
- World events.

The tavern remains the player's primary interface with this world.

---

# Future Concepts

Ideas rather than current commitments:

- Smuggling.
- Dynamic trade.
- Port reputation.
- Faction relationships.
- Notable visitors.
- Harbour intelligence.
- Political influence.
- Larger world events.

These should only be promoted into the active roadmap when the existing gameplay
loop demonstrates a need for them.

---

# Roadmap Rules

1. **Finish the playable loop before adding another large foundation.**
2. **Prefer player-visible improvements over invisible simulation depth.**
3. **Use existing data-driven frameworks rather than hard-coded special cases.**
4. **Validate behaviour in the actual game, not only through code inspection.**
5. **Do not add activities simply to increase the activity count.**
6. **Do not expose future systems through placeholder UI.**
7. **Design major systems before implementing them.**
8. **Keep the tavern itself as the player's primary interface to the world.**
9. **When the simulation becomes deeper than the player can perceive, improve
   communication before adding more simulation.**
