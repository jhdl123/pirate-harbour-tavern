# Customer Identity and Behaviour Foundation

## What changed and why

Customers looked scripted for three specific reasons, all now addressed:

1. **`CustomerBrain.think()` was a pure argmax** (`if score > best_score`).
   Identical inputs gave an identical activity every time, so every sailor
   in the room walked the same sequence in the same order.
2. **Personality was per-type, not per-customer.** `CustomerNeeds.seed_from()`
   read the type's shared `Personality` resource directly, so every sailor
   spawned with byte-identical traits.
3. **Nothing paced activities.** No cooldowns, no commitment floor, no
   duration variance, so repeats came back instantly and everyone finished
   together.

## Architecture

The existing state machine still owns execution and safe transitions.
Mandatory lifecycle work — entering, ordering, being served, drinking,
paying, leaving — is marked `is_mandatory` on its `ActivityDefinition` and is
**exempt from every new pacing and sampling rule**. A cooldown can never
block a customer from ordering; a commitment floor can never keep one
relaxing while their group leaves; weighted selection never samples `leave`
away in favour of something more fun.

Optional behaviour is what the new layer touches.

## Adding another customer type

1. Duplicate a `.tres` in `resources/CustomerTypes/`.
2. Set `type_id` to a new stable string — never rely on array order.
3. Point `personality` at a `Personality` in `Data/customer_ai/personalities/`.
4. Fill `visit_intent_weights` with intent ids and weights.
5. Add it to the spawner's `customer_types` array in `main.tscn`.

No code changes. `enabled = false` keeps a half-balanced type out of play.

## Adding another visit intention

1. Duplicate a `.tres` in `Data/customer_ai/visit_intents/`.
2. Set `intent_id`, then the multipliers and offsets.
3. `activity_score_offsets` is a plain Dictionary keyed by `activity_id` —
   unknown keys are ignored, so an activity with no entry scores exactly as
   it does today.
4. Add it to `Data/customer_ai/visit_intent_registry.tres`.
5. Weight it on whichever types should roll it.

## How a future information system consumes this

`CustomerBehaviourEvents` is an autoload emitting fourteen neutral signals.
Payloads are stable ids and values only — never node references — so a
listener can queue an event and process it after the customer has gone, and
a payload can be serialised into a save unchanged.

Nothing emits rumours, secrets or intelligence. The events exist so that
when the information system is built, every moment it would care about has
already happened somewhere it can hear it. `CustomerType` also carries
descriptive `information_domains`, `knowledge_tags`, `conversation_topics`,
`discretion_tendency`, `credibility_tendency`, `observant_tendency` and
`secrecy_tendency` — all inert today.

## Testing in Godot

`godot --headless res://tests/customer_identity_test.tscn` — 69 assertions.

In-editor: set `CustomerBrain.verbose_scoring` for per-candidate logging, or
`deterministic_decisions` to reproduce a run exactly. Pass a non-zero
`identity_seed` to `Customer.configure()` for reproducible traits.

## Known limitations

See the session notes — social compatibility scoring, developer menu
controls and the aggregate behaviour report are specified but not yet built.

## Activity integration matrix (brief section 9)

Every existing activity, audited. Nothing was removed.

| Activity | Owner | Mandatory | Commit | Target | Max | Cooldown |
|---|---|---|---|---|---|---|
| `order_drink` | individual | yes | — | — | — | — |
| `drink` | individual | yes | — | — | — | — |
| `leave` | individual | yes | — | — | — | — |
| `relax_at_seat` | individual | no | 3 | 8 | 20 | 6 |
| `socialise_at_seat` | individual | no | 4 | 10 | 25 | 8 |
| `visit_tavern_activity` | individual | no | 5 | 14 | 30 | 20 |
| `wander` | individual | no | 2 | 5 | 12 | 12 |
| `return_to_seat` | individual | no | — | — | — | — |

All values are world minutes.

**Eligibility and reservations** are unchanged — each activity's authored
`conditions` array still gates it, and `destination_tag` still drives
`DestinationBroker` reservation. The new layer only adds a cooldown check
before scoring and a commitment check before re-deciding.

**Interruption**: mandatory activities interrupt anything. Closing, group
departure, an invalidated reservation and `force_activity()` all bypass both
commitment and cooldown, because a pacing rule must never be able to strand
a customer mid-service.

**Fallback**: when no candidate clears the score floor, the weighted pass
returns null and the existing argmax result stands. When nothing is eligible
at all, the brain enters `WAITING` exactly as before.

**`return_to_seat` is unpaced deliberately.** It's a follow-up to
`visit_tavern_activity`, not a choice — giving it a cooldown could strand a
customer away from their chair.

### Not migrated

Group leisure still selects at group level and has the member execute it
(the deviation from 4 August). Rerouting it through `CustomerBrain` would
need new conditions and behaviours for group context, so the old behaviour
is preserved intact rather than half-migrated. This is the first task of the
next pass.

## Developer controls

`F9` toggles the panel, then: `F11` cycle type, `F12` force-spawn,
`K` deterministic mode, `L` verbose scoring, `P` print a live profile,
`O` export the behaviour report, `U` mixed-type stress test.

Force-spawning sets `GameManager.forced_customer_type` and lets the ordinary
spawn path run — a diagnostic spawn that bypasses the real path tests the
diagnostic, not the game.

## Balancing

Three numbers in `CustomerBehaviourReport` measure "do customers look
scripted": `repeat_action_percentage`, `most_common_sequence_percentage` and
`average_distinct_activities_per_visit`. Tune `CustomerBrain.selection_band`,
activity cooldowns and intent offsets against those.
