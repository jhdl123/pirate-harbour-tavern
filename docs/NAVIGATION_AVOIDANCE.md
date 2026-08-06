# Navigation and Collision Avoidance

## What was actually wrong

Measured against the live navmesh in `main.tscn`, not read from files. Three
plausible causes were **disproved**:

- **Static geometry is fine.** All eight static colliders are correctly
  carved out of the navmesh. Furniture is parsed in — `Environment` is the
  only `navigation_geometry` group member, but `source_geometry_mode = 1`
  means *groups with children*, and all furniture is parented under it.
- **Seat spacing is fine.** 62–96px between seats, far above the avoidance
  floor.
- **The seat-approach dead band is already fixed.** `_final_approach_radius`
  is a sum of the three tolerances, not a `maxf()`. Seated groups complete
  the full loop; they have simply never been re-enabled.

What was actually wrong:

1. **Both navigation profiles were empty files.** Every value was a code
   default, so a bartender carrying a keg steered identically to a drunk
   sailor.
2. **Godot's RVO avoidance is symmetric.** Two actors meeting head-on
   compute mirror-image evasions, both step the same way, and shuffle. This
   cannot be tuned away — it needs a deliberate asymmetry.
3. **`parked_avoidance_priority` was 1.0.** In Godot's solver, higher means
   "everyone else moves around me", so seated customers actively shoved
   approaching actors. This is why staff carrying kegs got pushed off their
   delivery approach.
4. **`chairRight` on both tables sat 3px off the navmesh.** Every other seat
   was exactly 0.

## What changed

### Organic movement

Three stable per-actor values, set once at spawn and never changed:

| Value | Effect |
|---|---|
| `_passing_side` | which way this actor steps when blocked |
| `_lateral_offset` | how far off the path centreline it walks |
| `_speed_multiplier` | how fast it walks relative to everyone else |

Varying these per frame would produce noise rather than character — an actor
that picks a new side every frame *is* the mirror dance.

Customers seed all three from their `CustomerIdentity` seed, so a
deterministic run reproduces how they move as well as how they behave, and
`personality.restlessness` shifts the speed distribution.

The lateral offset fades out as the destination nears and is suppressed
entirely during final approach — the last few pixels need to land precisely
on a seat, not beside it.

### Symmetry breaking

`_apply_passing_bias()` nudges the solver's safe velocity toward the actor's
preferred side, but **only while the solver is actively deflecting it**
(`side_bias_engage_dot`). In open space it costs nothing. Applied to the
safe velocity rather than the desired one, so avoidance still owns the
manoeuvre — this only decides which way round the obstruction it goes.

### Yielding

`parked_yield_priority` (0.30 customers / 0.45 staff) now sits **below**
travelling priority. A parked actor holds position through its physics body;
it does not need avoidance priority to do that, and having it actively hurt.

`working_priority` (0.90 staff) lets a staff member on a task outrank a
customer milling about.

### Profiles

Both authored and differentiated. Staff hold a tighter line, walk at more
uniform speeds, repath more readily and outrank customers. Customers drift
more and vary more.

## Tuning

| Symptom | Knob |
|---|---|
| Actors walk in single file | raise `lateral_path_offset` |
| Actors shuffle head-on | raise `passing_side_bias` |
| Actors curve oddly in open floor | raise `side_bias_engage_dot` |
| Crowd looks mechanical | raise `speed_variation` |
| Staff can't get through | raise `working_priority` |

## Verifying

    godot --headless res://tests/navigation_stress_test.tscn   # 25 assertions
    godot --headless res://tests/nav_probe.tscn                # collider/navmesh report

`NavigationValidator.report(tree)` logs any seat, formation slot or service
point sitting off the navmesh. Worth calling once after the mesh bakes, so a
level edit that strands a destination is reported the first time the scene
runs rather than the first time an actor tries to reach it.

## Still outstanding

- Seated groups remain switched off via `standing_places_only`. Pairs
  complete the full loop; groups of four lose two members to patience and
  skip `CLEARING_DELIVERY_SPACE`. That is group logic, not navigation.
- `NavigationValidator` is not yet called from the navigation region — it is
  available and tested, but nothing invokes it automatically.
