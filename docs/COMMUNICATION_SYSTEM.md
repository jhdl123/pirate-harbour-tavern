# Communication System

Phase 3A. The tavern's single way of telling the player something.

---

## 1. Why this is a framework and not a low-stock popup

The obvious way to warn the player that grog is running out is a label on the
grog station. Then ale needs one. Then deliveries. Then a customer complaint,
a trader arriving, a tutorial hint, a staff member with something to say — and
by then there are eight unrelated popup systems, none of which know about each
other, and the screen is a mess nobody can turn off.

So the low-stock warning was built as the *first user* of a general framework
rather than as a feature. Adding "a trader has arrived" later is a few lines,
not a new UI.

---

## 2. Separation of concerns

This is the rule that keeps it clean:

```text
Drink stations own the facts.
The communication system owns the message lifecycle and how it looks.
```

A `DrinksStation` knows how many servings it has and whether that counts as
low. It does **not** know what a toast is, what severity means, or whether a
staff member is available to say it.

```text
station stock changes
  -> station evaluates its own state (with hysteresis)
  -> emits stock_state_changed(previous, current)
  -> StockAlertCoordinator hears it
  -> queries authoritative storage for replacement stock
  -> asks Comms to raise / escalate / resolve one alert
  -> toast, persistent alert, speech bubble, history
```

The Tavern Hand never scans stations. Stations never look for staff.

---

## 3. The pieces

| File | Role |
| --- | --- |
| `systems/communication/comm_message.gd` | The message data model |
| `systems/communication/communication_config.gd` | Resource: durations, caps, colours |
| `systems/communication/communication_service.gd` | The service. Autoloaded as `Comms` |
| `systems/communication/stock_alert_coordinator.gd` | Turns stock states into alerts |
| `systems/communication/ui/communication_ui.gd` | Toasts, alert panel, speaker panel, history |
| `systems/staff/staff_speech_bubble.gd` | The short line above a worker's head |

---

## 4. Three kinds of message

| Type | Lifetime | Example |
| --- | --- | --- |
| `NOTIFICATION` | Brief, non-blocking, auto-dismisses | "Delivery arrived" |
| `ALERT` | Persists until resolved or acknowledged | "Grog is running low" |
| `SPEAKER` | Attributed to somebody, may carry choices | Tavern Hand saying something |

**Severity:** `INFO`, `LOW`, `WARNING`, `CRITICAL`.

**Category:** `STAFF`, `CUSTOMER`, `STOCK`, `DELIVERY`, `VISITOR`, `EVENT`,
`SYSTEM`, `TUTORIAL`.

Severity drives colour through the config resource, not through hard-coded
values in gameplay code.

---

## 5. Alert lifecycle and why it does not spam

```text
INACTIVE -> TRIGGERED -> DISPLAYED -> ACKNOWLEDGED -> RESOLVED
```

Four separate mechanisms keep it quiet:

**Hysteresis, on the station.** The warning triggers when servings fall to the
low threshold. It does not reset when they climb back to the same number — it
resets only above a higher threshold. Without this, hovering at the boundary
produces an alert every time somebody buys a drink.

Defaults: trigger at 4 servings, empty at 0, reset above 8.

**Deduplication keys.** Every message carries one. Posting a message whose key
already has a live alert *updates that alert* instead of creating a second.
`deduplication_count` records how many times it happened.

**Escalation, not accumulation.** When a station goes from low to empty, the
existing alert's severity and text change:

```text
WARNING:  Grog is running low - 4 servings remain.
              becomes
CRITICAL: Grog has run out.
```

One alert, escalated. Not two alerts. Escalations are recorded on the message
so the history shows what happened.

**Automatic resolution.** An alert can carry an `auto_resolve` condition that
the service polls. Refill the station and the warning clears itself — you do
not have to dismiss it, and it cannot be left stale. If the station later runs
low again, that is a new lifecycle.

---

## 6. Stock-aware detail

A warning that just says "low on grog" makes you go and look. These messages
query the authoritative `StockStorage` and tell you what you actually need to
know:

```text
Tavern Hand:
"The grog barrel is nearly empty."

Grog Station: 3 servings remaining
Replacement stock: 1 barrel in storage
```

```text
Tavern Hand:
"We are nearly out of ale, and there are no replacement kegs."

Ale Station: 2 servings remaining
Replacement stock: none
```

The second is more severe, because it needs an order rather than a walk to the
cellar.

Storage totals are read live through `ItemContainer.get_total_quantity()`.
There is **no notification-owned copy of the inventory**, so the numbers cannot
drift.

---

## 7. Staff as the speaker

Where a staff member is available, an alert is attributed to them: their name
on the message, and a short speech bubble above their head.

Two things this deliberately does **not** do:

- It does not make the worker abandon a job and walk to the player before the
  warning can exist. The warning is reliable even if the worker is across the
  room, mid-serve, or unreachable.
- It does not use a blocking dialogue panel for a routine stock warning. A
  speech bubble plus a persistent alert is right; a modal that interrupts play
  is not.

If there is no staff member, or all staff are paused, the alert is raised by
the tavern itself with no speaker. The system never depends on a worker
existing.

---

## 8. The UI layers

| Layer | Behaviour |
| --- | --- |
| Toasts | Brief, queued, capped on screen at once, auto-dismiss |
| Persistent alerts | Unresolved management conditions, severity-coloured, acknowledgeable, expandable for detail |
| Speaker panel | Name + message + acknowledge, ready for choices |
| History | Recent notifications, alerts, speaker messages and resolutions |

Routine staff task completions do **not** toast by default. That is controlled
by `notify_on_completion` on each `TavernTaskDefinition`, and it is off. A toast
for every drink delivered is noise, and hiding real messages behind noise is
exactly what this framework exists to prevent.

---

## 9. How to post something

Notification:

```gdscript
Comms.notify(
    "Delivery arrived",
    "Two barrels of grog were delivered.",
    CommMessage.Category.DELIVERY
)
```

Persistent alert with deduplication and automatic resolution:

```gdscript
Comms.raise_alert(
    "Grog running low",
    "Only 3 servings remain.",
    CommMessage.Category.STOCK,
    CommMessage.Severity.WARNING,
    "stock:%d" % station.get_instance_id(),
    func() -> bool:
        return station.get_stock_state() == DrinksStation.StockState.OK
)
```

Speaker message:

```gdscript
Comms.say(staff_member, "We are nearly out of ale.")
```

Full control is available through `Comms.post(message)` with a `CommMessage`
built by hand.

---

## 10. How to add a dialogue choice later

The model already carries it. A `CommMessage` has a `choices` array of
dictionaries, and the service has `select_choice()`, which emits
`choice_selected(message, choice_id)`. `StaffMember.handle_message_choice()`
is the receiving end on the worker.

So a future branching conversation needs:

1. Choices populated on the message.
2. Buttons rendered in the speaker panel (the panel already reserves space).
3. A handler that reacts to `choice_selected`.

What it does **not** need is a change to the message model, the service, or the
staff member. Phase 3A deliberately stops short of a branching narrative
editor, but nothing here has to be rewritten to add one.

---

## 11. Configuration

`Data/communication/communication_config.tres`:

- toast count on screen, default duration, queue cap
- maximum visible alerts, auto-resolve poll interval, re-create cooldown
- speaker message duration, whether choices pause the game
- history size
- one colour per severity

Stock thresholds are per-station exports on each `DrinksStation`, because they
depend on that station's capacity.

---

## 12. Current limitations

- The speaker panel renders a message and an acknowledgement. Choices are
  modelled and routed but not yet drawn as buttons.
- Portraits are on the model and not yet displayed.
- Pending deliveries are not counted in the replacement-stock figure. Adding it
  means reading `OrderManager.get_pending_orders()`; it was left out because it
  would have widened the phase.
- Sound is a hook, not an implementation.
- The UI is functional rather than styled. It is readable at 1280×720 and stays
  out of the play area, but it is not final art.
