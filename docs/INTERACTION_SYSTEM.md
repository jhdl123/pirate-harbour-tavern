# Interaction System

## Design goal

Every interactive object in the tavern answers the same three questions:

```text
Am I worth offering to this actor right now?
What could this actor do to me?
Do this specific thing.
```

The interaction framework asks those questions. It never answers them. All
gameplay stays inside the object, using the systems that object already owns —
`ItemTransferService` for the bar counter, drink creation for a station,
serving logic for a customer.

The framework is responsible for exactly five things:

```text
detecting nearby interactables
deciding which one is selected
highlighting the selected one
displaying the interaction prompt
executing the requested action
```

It is responsible for nothing else. In particular it holds no gameplay state,
knows no object types, and never touches an item.

---

## Class map

```text
systems/interaction/

InteractionDetector       Area2D on the actor. Detection only.
    └── "who is within reach"

InteractionSelector       Node on the actor. The brain.
    ├── scoring and stickiness
    ├── TAB cycling
    ├── highlight lifecycle
    └── prompt signals
        │
        └── InteractionSelectionRules   Resource: weights and tuning

Interactable              Area2D on the object. The whole public surface.
    ├── delegates to a provider (the object's root node)
    ├── legacy fallback for objects with only interact()
    └── drives the highlight
        │
        └── InteractionHighlight        Node: reusable default highlight

InteractionAction         What one possible action is called, and whether it
                          is currently possible.
InteractionRequest        Who is asking, from where, for what.

InteractionPromptUI       Control on the HUD. The ONE prompt in the game.
InteractionInput          InputMap -> key label, so "[E]" follows rebinding.
```

Nothing in that list imports anything from `scripts/Interactables/`,
`scripts/Entities/` or `systems/inventory/`. The dependency arrow only ever
points from gameplay towards the framework.

---

## Interaction flow

The full path from a key press to an item moving:

```text
Player presses E
    │
    ▼
player.gd  _process()
    ├── blocked while ActionRunner is running
    └── try_interact()
        │
        ▼
InteractionSelector.perform_primary()
    ├── is anything selected?
    ├── selected.get_primary_action(request)      <- freshly built, every time
    ├── is that action available?
    └── selected.perform(request)                 <- carries action.id + data
        │
        ▼
Interactable.perform()
    ├── provider has perform_interaction()?  -> call it
    └── provider only has interact()?        -> call that (legacy path)
        │
        ▼
BarCounter.perform_interaction(request)
    ├── reads request.data.slot_index          <- the slot the prompt named
    ├── reads request.get_actor_carrier()
    └── ItemTransferService.transfer(...)      <- unchanged item system
        │
        ▼
ItemContainer.slot_changed
    └── BarCounter._on_service_slot_changed()
        ├── refreshes the slot sprite
        └── interactable.notify_state_changed()
            │
            ▼
InteractionSelector re-reads the action  ->  prompt updates immediately
```

Two things are worth noticing about that path.

**The player never learns what it touched.** It converts a key press into
"run the primary action" and hands that to the selector. Adding kegs, crafting
stations or NPCs never touches `player.gd`.

**The selector never learns what an action means.** It moves an opaque
`action.id` and `action.data` from the object that offered them back to the
same object. The bar counter puts a slot index in `data` and gets that exact
slot index back, so the slot the prompt described is guaranteed to be the slot
that receives the item.

---

## The provider protocol

An object opts into the framework by putting an `Interactable` (an `Area2D`) in
its scene and implementing some of these methods on its root node. There is no
base class to inherit and every method is optional.

```gdscript
## Player-facing object name. Falls back to Interactable.display_name.
func get_interaction_display_name() -> String

## Where the interaction happens, in world space. Used for distance scoring
## and for anchoring the prompt. Defaults to the Interactable's position.
## Objects with several interaction points return the nearest one.
func get_interaction_point(from_position: Vector2) -> Vector2

## Cheap early-out. An object with no available actions is skipped anyway, so
## only implement this when the check is cheaper than listing actions.
func can_interact(request: InteractionRequest) -> bool

## Everything this actor could do right now. Build fresh each call.
func get_interaction_actions(
    request: InteractionRequest
) -> Array[InteractionAction]

## Run the action named by request.action_id.
## Return true if something actually happened.
func perform_interaction(request: InteractionRequest) -> bool

## Custom highlight. Called repeatedly while selected, so it MUST be
## idempotent. Omit it to get the InteractionHighlight node behaviour.
func set_interaction_highlighted(
    enabled: bool,
    request: InteractionRequest
) -> void
```

### Rules of thumb

**Build actions fresh, never cache them.** An action describes the world as it
is this instant. Caching one guarantees a prompt that lies.

**Let the existing systems answer "is this possible".** The bar counter asks
`ItemTransferService.can_transfer()` rather than re-deriving the rules, so the
prompt can never disagree with what the transfer will actually do, and refusal
text comes from `ItemTransferResult.get_message()`. Do the same with any
system that already knows the answer.

**Call `notify_state_changed()` after anything that changes what the player
could do.** An item placed, a state transition, stock running out. Without it
the prompt still updates, but on the next polling tick rather than instantly.

**Return `false` from `perform_interaction()` when nothing happened.** The
selector uses it to decide whether to emit `interaction_performed`.

---

## Target selection

### Scoring

Selection is deliberately simple and additive:

```text
score = distance_weight * (1 - distance / distance_falloff)
      + priority_weight * interaction_priority
      + sticky_bonus                              (current selection only)
```

Highest score wins. Distance is measured to the object's
`get_interaction_point()`, not its origin — which is why standing at the left
end of the bar scores against the left-hand service slot rather than the middle
of the counter.

Facing direction is intentionally absent. When you want it, it becomes one more
weighted term in `_score_candidate()` and nothing else in the framework
changes.

### Anti-flicker

Two objects at almost identical distances would otherwise swap selection every
frame as the player shuffles. Two things prevent it:

- **Sticky bonus.** The current selection gets a score bonus, so a rival has to
  be clearly better, not marginally better.
- **Update interval.** Selection is re-evaluated on a fixed tick rather than
  every frame, so sub-pixel movement noise cannot decide anything.

### Validity

A candidate is only considered if it is in range, enabled, passes
`can_interact()`, and returns at least one action. When the current selection
stops meeting that bar, the next-best valid target is chosen automatically on
the same tick.

Freed nodes are pruned defensively in `InteractionDetector.get_candidates()`
rather than relying on `area_exited` — a customer that is served and removed can
be gone before physics reports the exit.

### Cycling (TAB)

`cycle_next()` sorts the valid candidates by score and moves to the next one,
wrapping around. Every press advances by one.

Cycling then sets a **manual hold**, without which automatic re-scoring would
snap the selection straight back to the nearest object on the next tick. The
hold is released when any of these happen:

```text
the selected object stops being valid
manual_hold_seconds elapse                (default 5s)
the actor moves manual_release_distance   (default 80px)
```

Walking away is a clear signal that the player has moved on, so automatic
selection resumes without needing another key press.

---

## The shared prompt

There is exactly one prompt node, in the HUD:

```text
Main
└── UI (CanvasLayer)
    ├── MoneyLabel
    ├── TimeLabel
    └── InteractionPrompt        <- InteractionPromptUI
        └── PromptLabel
```

World objects carry no labels. The bar counter's old `InteractionLabel` has been
deleted, and nothing else has ever had one.

The prompt finds its selector through the `interaction_selector` group rather
than a `NodePath`, so the HUD needs no reference into the player scene and
nothing breaks when the player is spawned rather than placed in the scene.

Text is assembled as:

```text
"[" + key + "] " + verb + " " + subject
```

The key comes from `InteractionInput`, which reads the `InputMap`. Rebinding
the interact key — in project settings today, in an options menu later —
updates every prompt in the game with no further work.

Unavailable actions are shown greyed, with the reason appended when there is
one:

```text
[E] Place Ale                      available
[E] Empty slot                     unavailable, no reason given
[E] Place Ale (There is no room)   unavailable, with reason
```

`AnchorMode` switches between following the target's interaction point and a
fixed screen position. Following is the default because it matches how the bar
counter's label used to read.

---

## Creating a new interactable

### The minimum

A barrel the player can take a plank from:

**1. Scene**

```text
Barrel (StaticBody2D)          <- barrel.gd
├── Sprite2D
├── CollisionShape2D
├── InteractionArea (Area2D)   <- systems/interaction/interactable.gd
│   └── CollisionShape2D           group: "interactable"
└── InteractionHighlight       <- systems/interaction/interaction_highlight.gd
                                   target_paths: [../Sprite2D]
```

**2. Script**

```gdscript
class_name Barrel
extends StaticBody2D

@export var stored_item: ItemDefinition

@onready var interactable: Interactable = $InteractionArea

var storage: ItemContainer


func get_interaction_display_name() -> String:
    return "Barrel"


func get_interaction_actions(
    request: InteractionRequest
) -> Array[InteractionAction]:
    var actions: Array[InteractionAction] = []

    var carrier: ItemCarrier = request.get_actor_carrier()
    var slot: ItemSlot = storage.get_slot(0)

    if carrier == null or slot == null or slot.is_empty():
        return actions

    actions.append(
        InteractionAction.create(
            &"take",
            "Take",
            slot.get_definition().display_name
        )
    )

    return actions


func perform_interaction(
    request: InteractionRequest
) -> bool:
    var carrier: ItemCarrier = request.get_actor_carrier()

    if carrier == null:
        return false

    var result: ItemTransferResult = carrier.take_from(
        storage.get_slot(0)
    )

    if result.is_success():
        interactable.notify_state_changed()

    return result.is_success()
```

That is the whole integration. No change to the player, the selector, the
prompt, or any input handling.

### Several interaction points on one object

Study `scripts/Interactables/bar_counter.gd`. It is one interactable made of
three service slots, and it needs all three of the optional hooks:

- `get_interaction_point()` returns the nearest slot, so scoring, highlight and
  prompt all agree on the same spot.
- `set_interaction_highlighted()` is called every selection tick, which is what
  lets the slot highlight walk along the counter as the player moves.
- Actions carry `{"slot_index": i}` in `data`, so the slot named by the prompt
  is the slot that receives the item.

Storage shelves, kegs and multi-seat tables will all want this shape.

---

## Migration status

| Object        | State                                      |
| ------------- | ------------------------------------------ |
| Bar Counter   | Migrated. Full protocol, custom highlight.  |
| Drinks Station| Migrated. Minimal protocol.                |
| Chair         | Legacy fallback. Highlight + prompt only.   |
| Customer      | Legacy fallback. Highlight + prompt only.   |
| Storage, NPCs | Do not exist yet.                          |

### The legacy fallback

`Interactable` will work with an object that has none of the protocol methods
but does have `interact(player)`. It synthesises a single primary action from
two exported properties and calls `interact()` when the action runs:

```text
fallback_verb              "Clean up", "Serve"
fallback_includes_subject  whether the object's name follows the verb
```

That is how Chair and Customer are selectable, highlighted and prompted with
**zero changes to `chair.gd` or `customer.gd`**. Their gameplay is untouched.

### Migrating a legacy object later

Chair is the clearest example. Today `chair.gd` has:

```gdscript
func interact(player: Node) -> void:
    if not cleanable.can_start_cleaning():
        return
    ...
    cleanable.start_cleaning(player_action_runner)
```

Migrating it means splitting that into a question and an answer:

```gdscript
func get_interaction_actions(
    request: InteractionRequest
) -> Array[InteractionAction]:
    var actions: Array[InteractionAction] = []

    if not cleanable.has_cleaning_task():
        return actions

    var action: InteractionAction = InteractionAction.create(
        &"clean",
        "Clean up",
        cleanable.current_task.display_name
    )

    if not cleanable.can_start_cleaning():
        action.as_unavailable("already cleaning")

    actions.append(action)

    return actions


func perform_interaction(request: InteractionRequest) -> bool:
    # exactly the body of the old interact(), returning a bool
```

Then delete `fallback_verb` and `fallback_includes_subject` from the scene, and
delete `interact()`. Nothing else changes. Customer follows the same shape:
its `State.ORDERING` check and its `ordered_drink` comparison become the
availability test, which also fixes the current cosmetic wart where a customer
shows "[E] Serve Customer" before they have ordered.

---

## Future expansion

### Multiple actions

The architecture already supports it; only the input wiring is missing.

`InteractionAction.Kind` has `PRIMARY`, `SECONDARY` and `CONTEXT`. Objects may
already return several actions of any kind — `get_actions()` returns all of
them, and `get_primary_action()` simply filters for the best available
`PRIMARY`. Nothing reads the others yet.

Whichever route you eventually choose, the object code does not change:

**Keyboard shortcut.** Add `player_secondary_interact` to the input map, add
`perform_secondary()` to the selector as a copy of `perform_primary()` filtered
on `Kind.SECONDARY`, and one line in `player.gd`. Roughly 20 lines total.

**Context menu / verb wheel.** Call `selector.get_selected().get_actions()` on
open, build a button per action, grey out the unavailable ones using
`is_available` and `unavailable_reason`, and on click call
`interactable.perform(request)` with the chosen action's `id` and `data`. The
menu needs no knowledge of any object type — it renders `get_label()` strings
and passes opaque ids back.

**Verb-first (Monkey Island).** Pick a verb, then filter each candidate's
actions by `id` when scoring, so only objects offering that verb are
selectable. Add a `required_action_id` field to `InteractionSelectionRules`
and one filter line in `_get_valid_candidates()`.

The reason all three are cheap is that actions are data, not method calls.

### Mouse interaction

The framework is already split at the right seam. `InteractionSelector` only
needs a source of "which interactable does the actor mean" — today that comes
from scoring the detector's candidates.

Add a `SelectionSource` enum, or an exported `use_pointer_selection` flag, and
in `_update_selection()` branch to a pointer path that does a
`PhysicsPointQueryParameters2D` at `get_global_mouse_position()` and picks the
topmost `Interactable`. Everything downstream — highlight, prompt, `perform()`,
every object's protocol implementation — is unchanged, because none of it knows
how the selection was made.

Hover prompts come free: the prompt UI already reacts to
`selection_changed`/`prompt_changed` rather than to input.

Click-to-act is then `perform_primary()` on mouse down, and right-click opens
the context menu described above.

### Reachability

Mouse selection will want a "too far away" state. Add a `maximum_range` check
in `_score_candidate()` and mark the action unavailable rather than dropping
the candidate, so the player sees why. The `is_available` /
`unavailable_reason` fields already exist for exactly this.

### Staff

`InteractionSelector` takes an `actor` and an `InteractionSelectionRules`
resource. A bartender NPC gets the same two components with different weights
and drives them from AI instead of input — `perform_primary()` is a plain
method call. Objects need no changes: they duck-type the actor for
`get_item_carrier()` and `get_action_runner()`, never for "is this the player".

---

## Tuning

`Data/interaction/default_selection_rules.tres`, assigned on the player's
`InteractionSelector`.

| Property                  | Default | Effect                                    |
| ------------------------- | ------- | ----------------------------------------- |
| `distance_weight`         | 1.0     | How much closeness matters                |
| `distance_falloff`        | 160.0   | Distance at which closeness reaches zero  |
| `priority_weight`         | 0.15    | How much `interaction_priority` matters   |
| `sticky_bonus`            | 0.12    | Anti-flicker margin                       |
| `selection_interval`      | 0.05    | Seconds between re-evaluations            |
| `manual_hold_seconds`     | 5.0     | How long TAB survives re-scoring          |
| `manual_release_distance` | 80.0    | How far you may walk before TAB releases  |

`distance_falloff` only normalises the score — it is not a reachability limit.
Range is decided by the detector's collision shape, which is where it belongs.

Per-object, on the `Interactable` node:

| Property                    | Effect                                     |
| --------------------------- | ------------------------------------------ |
| `display_name`              | Name used when the provider supplies none  |
| `interaction_priority`      | Tie-breaker. Customer 2, Chair 1, rest 0.   |
| `is_interaction_enabled`    | Turn the object off without removing it    |
| `provider_path`             | Override the default "my parent" provider  |
| `highlight_path`            | Override the default highlight search      |

Keep priorities small and meaningful. Nothing should be so high that the player
cannot reach past it.

---

## Input

| Action                | Key       | Purpose                          |
| --------------------- | --------- | -------------------------------- |
| `player_interact`     | E, Enter  | Run the primary action           |
| `player_cycle_target` | Tab       | Select the next object in range  |

Both are exported properties on `player.gd`
(`primary_interaction_action`, `cycle_target_action`), so rebinding to a
different action name needs no code change.

Interaction input is ignored while `ActionRunner` is running, but selection
keeps updating, so the highlight and prompt stay on screen during a timed
action such as cleaning.

---

## Gotchas

**`set_interaction_highlighted()` is called every tick.** It must be
idempotent. The bar counter early-returns when the highlighted slot has not
changed.

**Do not put a prompt in a world object.** There is one prompt. If it needs to
say something new, that is a new `InteractionAction`, not a new label.

**Do not reach for the player from inside an object.** The old bar counter did
`get_tree().get_first_node_in_group("player")` in `_process` and that is gone.
The actor arrives in the `InteractionRequest`.

**The `interactable` group is still populated** — `Interactable` adds itself on
ready — but nothing in the framework searches by group any more. It remains
useful for debug tooling and level scripts.
