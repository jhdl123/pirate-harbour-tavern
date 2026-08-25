# Customer Model — intended architecture

The design target for customer behaviour. `CURRENT_STATE.md` says what is
built; this says what it is being built *toward*. Where the two disagree, this
file is the intent and the code is the fact.

Adopted 2026-08-25. Supersedes nothing — it is the layer *above* the existing
activity framework, not a replacement for it.

## Why this document exists

The activity/utility framework works. The behaviour it produces does not read
as a tavern. Measured at `235b7ac`:

- `visit_tavern_activity` (darts) is **eligible in 37% of customer-samples** and
  occupies **1.2% of customer time**. It is not gated out — it loses.
- Of 528 samples where darts was eligible it would have won 52 times. It was
  beaten by `relax_at_seat` **321 times**.
- Mean scores when eligible: `order_drink` 20.8, `socialise_at_seat` 12.5,
  `relax_at_seat` 12.4, **darts 10.2**, `drink` 8.0, `leave` −9.6.
- `order_drink` occupies ~28–35% of all visible customer time.

The specific cause is structural, not numerical. Every activity competes in one
flat pool, so **sitting still is a legitimate winner over doing something**. No
weight on darts fixes that; it only moves which activity wins the same flat
contest. `relax_at_seat` also carries `score_weight = 0.05` against
`remaining_visit_minutes` — a raw minute count — so a customer with 55 minutes
left gets +2.75 *for sitting down*. Having time to spare makes doing nothing
more attractive and does nothing for darts.

## The target model

```
CUSTOMER
├── Identity      type, personality, preferences, (later) relationships
├── Visit         why they came, expected length, spending, group
├── Needs         thirst, social, entertainment, relaxation, (later) hunger, information
├── Awareness     who is nearby, what is free, what is already happening
└── Decision      motivation first, then the activity that serves it
```

Activities sit at the **bottom** of this, not at the top. They are how a visit
continues, not what a customer is.

### 1. Visit purpose

A customer arrives with a reason and a rough shape of visit — not an itinerary.
"An evening out" and "a quick drink after work" are different visits, and the
difference should be visible in the room.

Much of this already exists (`VisitIntentConfig`, nine intents, applied through
`CustomerIdentity.get_activity_bias()` inside `think()`). The audit must
establish whether it is missing, or present and too weak to observe.

### 2. Needs

Needs express **what would currently be valuable to this customer**. They are
not happiness, not satisfaction, and not a score of how the visit is going.

- `Social` low does not mean miserable. It means social contact is not currently
  worth much to them.
- `Thirst` high does not mean unhappy. It means a drink is worth a lot.

Mood/satisfaction is a separate thing and already exists. Do not merge them.

**Every need is normalised 0.0–1.0.** This is a hard rule. Raw-valued needs have
caused two separate multi-session bugs on this project (`wealth` as a raw coin
count broke the leave decision; `remaining_visit_minutes` as raw minutes is
currently distorting relax). Anything raw is exposed as a *context value*, never
as a need.

Initial set: `thirst`, `social`, `entertainment`, `relaxation`. `hunger`,
`information` and `gambling` are reserved names for later — do not implement
them now, but do not design a shape that excludes them.

### 3. Awareness

The customer perceives the room, not just itself: who is nearby, which
activities are free, what is already happening.

This is the one layer that genuinely does not exist. `SocialPresenceService` is
the closest thing and it is a 2-second proximity tick. Scope it carefully; it is
the expensive piece.

The behaviour it must eventually enable: *someone is already playing darts*
raises the value of joining. A tavern where activity attracts activity clusters
naturally; a tavern where each customer decides in isolation does not.

### 4. Two-stage decision

This is the central change.

```
think()
  │
  ├─ 1. Should this visit continue?          (linger vs leave)
  │
  ├─ 2. What do I currently want?            (pick a motivation from needs,
  │                                           weighted by personality, visit
  │                                           purpose, group, awareness)
  │
  └─ 3. What available thing serves that?    (score only the activities that
                                              satisfy the chosen motivation)
```

Darts then competes with *other entertainment*, not with sitting down. Leaving
is decided as its own question, not as an activity that has to out-score
ordering a drink.

Randomness stays — the existing weighted selection among near-equal candidates
is correct and should be preserved at stage 3. Customers must not become
predictable.

### 5. Activities advertise what they satisfy

Today conditions **read** needs; nothing declares what an activity **gives
back**. That inversion is why each new activity needs 8–11 hand-authored
condition resources and a re-balance against everything else.

Target shape (illustrative, not a schema):

```
darts       entertainment +0.8   social +0.4
talking     social +0.9          (later: information +0.5)
drinking    thirst +0.8          social +0.2   entertainment +0.1
relaxing    relaxation +0.9
```

**The extension test for this whole pass:** adding a new activity — cards,
gambling, eating, a musician — should be one activity resource declaring what it
satisfies, one behaviour, and a destination. No new condition resources, no
re-balancing of existing activities, no code changes to the brain. If the audit
concludes the model does not meet that test, it has not gone far enough.

### 6. Groups bias, they do not dictate

A crew is more likely to socialise or play darts together, but a member can peel
off. If one gets hungry once food exists, they go and eat and come back.

Group context is a scoring input at stage 2 and stage 3, not a separate code
path. This is already the stated design (`GroupManager._offer_leisure_activity()`
asks the member's own brain) — preserve it.

### 7. Lingering is the default

Staying is normal. A customer should not have to justify not leaving.

```
Arrival → Settling → Active visit ⇄ (drink · talk · activity · sit) → Winding down → Departure
```

Departure becomes gradually more likely under time, money, satisfaction,
intoxication, group departure and closing. It is a decision, not a timer
expiring. Part 5 moved this from 4/69 to 13/60 chosen departures; the target is
for chosen departure to be the *normal* case, with the timer as a backstop.

## What "working" looks like

Watch the tavern for five minutes and see something like: a sailor arrives and
sits; two who came together talk; a merchant sits near them; one sailor finishes
his drink and joins the darts; his crewmate stays at the table; someone starts a
second drink; someone leaves; a new group arrives.

And crucially — **you should not be able to predict what happens next.**

## Non-goals

Stated explicitly because each has been proposed and rejected:

- **No theme park.** Most customers, most of the time, should drink and talk.
  Darts is occasional. A tavern where everyone is always doing an activity is a
  worse failure than the current one.
- **No Sims-style needs/happiness UI in the shipped game.** Needs are internal
  simulation state. See `CUSTOMER_INSPECTOR.md` for what is exposed and when.
- **No scheduled itineraries.** No customer holds a plan of what they will do at
  19:15. Behaviour emerges from state plus environment plus controlled
  randomness. Long-horizon planning makes NPCs harder for a player to read, not
  easier.
- **No named characters, rumours, dialogue, relationships or information
  content in this pass.** The model must not *exclude* them; it must not
  implement them.
- **No new activities in this pass.** Darts is the test case. One activity
  proven visible is worth more than five that are not.

## How the information layer plugs in later

This is the reason the model matters. An information system needs customers who
stay long enough to be noticed, chosen between, and approached. `enter → order →
drink → leave` leaves it nowhere to live.

The hooks it will need, which this model should leave room for and not build:
`information` as a need; talking as an activity that satisfies it; awareness
carrying "who is here and what do I know about them"; and the inspector
exposing progressively more as the player learns more.
