# Groups Re-enabled

Automatic groups are enabled again without replacing the stable solo spawn loop.

## Integration changes

- Tavern-open, navigation-ready and population checks now run before a group attempt.
- A group is rejected before any nodes are created when its minimum size cannot fit.
- Random group size is capped to the currently available customer population slots.
- Only one group may use the entry corridor at a time. A scheduled arrival falls back to a solo customer while the corridor is busy.
- Group members now retain a reference to their owning group controller.
- Entry watchdogs were increased to 30 real seconds to avoid killing a valid large group while it files through the doorway.
- Automatic group arrivals are enabled in `main.tscn`.

## Expected behaviour

With the default weights, most arrivals remain solo and roughly one in five eligible arrivals attempts to be a group. A failed or unsuitable group attempt should produce a solo visitor instead of losing the arrival or blocking later spawns.
