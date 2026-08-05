# Group Drinks — Configuration Guide

How to add drinks groups can order, and control which kind of group orders
what. Everything here is a resource edit; none of it needs a script change.

**Current scope: kegs and casks only.** Groups order drinks that pour straight
out of a station — pitchers, table casks, firkins. Mixed drinks, recipes and
ingredients are switched off deliberately (see *Turning mixed drinks on* at the
bottom).

---

## The three things that must agree

A group can only order a drink when all three line up. Most "why won't they
order it?" problems are one of these missing:

```
1  DRINK      lists a shared serving format
2  FORMAT     accepts the drink's tags, and fits the group size
3  STATION    has the capability to fill that vessel, and has the measures
```

The diagnostics panel (F7 → Stations) reports the third one directly — it lists
what each station *cannot* serve and why.

---

## Adding a drink groups can order

Say you want groups to order Cider by the pitcher.

**1. The drink must list the shared format.**
`Data/beverage/drinks/cider.tres` → `serving_format_ids` must include
`pitcher`. Cider already lists `mug`, `tankard`, `pitcher`, so nothing to do.

**2. The format must accept the drink's tags.**
`Data/beverage/serving_formats/pitcher.tres` → `valid_drink_tags` is
`[beer, ale, cider]`. Cider is tagged `cider`, so it passes.

If it did not, you would add the drink's tag to `valid_drink_tags` — that is
what I did to let a tankard hold rum.

**3. A station must be able to pour it.**
The station needs:
- `service_content_id` matching the drink's `content_id` (`cider`)
- the `draw_from_cask` capability (the drink requires it)
- the **fill capability for that vessel** — see the table below

| Shared vessel | Capability the station needs |
|---|---|
| Pitcher | `fill_pitcher` |
| Punch Bowl | `fill_shared_bowl` |
| Table Cask, Firkin, Kilderkin | `fill_shared_cask` |

This is derived from the container's *category*, so a new shared format
inherits the right requirement automatically.

**4. Stock.** The station's cask needs at least `measures_per_serving` in it —
24 for a pitcher, 48 for a table cask.

---

## Configuring stations

Station wiring lives in **one node**, not on each station instance:
`BeverageSceneSetup` in the scene.

Leave `stations` empty and every station in the `drink_stations` group gets
`default_cask_capabilities`, which is currently:

```
draw_from_cask, fill_pitcher, fill_shared_cask
```

That means a station you duplicate works immediately with no configuration.

To give one station different capabilities, add a `StationSetup` entry:

| Field | Meaning |
|---|---|
| `station_name` | node name, e.g. `Grog_station` |
| `capabilities` | overrides the defaults for this station |
| `service_container_id` | which cask it serves from (default `service_cask`, 96 measures) |
| `content_id` | the liquid, if not the drink's own `content_id` |
| `starting_measures` | fallback stock for this station |

**To stop groups ordering shared casks at a station**, remove
`fill_shared_cask` from its capabilities. It will still pour individual drinks.

---

## Controlling which groups order what

Each archetype in `Data/groups/` decides its own taste. The fields that matter:

| Field | Effect |
|---|---|
| `shared_order_chance` | 0.0–1.0. How often the group shares rather than ordering individually. Pirate Crew is 0.9; Merchant Party is 0.25. |
| `preferred_serving_tags` | The steering wheel. Every drink carrying one of these tags gets **×2.5** weight; every format listing it gets **×1.5**. |
| `minimum_shared_portions` | Stops small groups ordering huge vessels. |
| `maximum_shared_portions` | Stops large groups ordering tiny ones. |
| `maximum_orders_per_visit` | Hard cap on reordering. |
| `reorder_chance` | 0.0–1.0 per empty serving. |

**Worked example — making Dock Workers drink cider.**
Open `Data/groups/dock_workers.tres`, add `cider` to `preferred_serving_tags`.
Cider is now 2.5× more likely for them than its base popularity. No other group
is affected.

**Worked example — stopping pairs ordering big casks.**
`sailor_pair.tres` has `maximum_shared_portions = 6`. A table cask is 8
portions, so it is already excluded. Lower it to 4 and pitchers (4 portions)
become the largest they will take.

**Two independent guards on size.** The group's `minimum_shared_portions` /
`maximum_shared_portions`, *and* the format's own `minimum_group_size`. A
firkin declares `minimum_group_size = 6`, which is why two customers can never
order one regardless of archetype settings.

---

## Adding a new group archetype

Copy any file in `Data/groups/` and edit:

- `group_id` — stable, never rename once saved
- `minimum_size` / `maximum_size`
- `size_weights` — e.g. `{3: 3.0, 4: 2.0, 5: 1.0}` makes threes commonest.
  Leave empty for uniform.
- `spawn_weight` — relative chance against other archetypes; 0 disables
- `place_preference` — `PREFER_SEATED`, `PREFER_STANDING`, `NO_PREFERENCE`
- `standing_allowed` — false means they leave rather than stand
- `preferred_serving_tags` — as above

Nothing needs registering. The framework does not depend on any specific
archetype existing.

---

## Where the numbers live

| To change | Edit |
|---|---|
| Pitcher/cask portion counts | `Data/beverage/serving_formats/*.tres` → `portion_count` |
| Measures a serving costs | same file → `measures_per_serving` |
| Shared-drink prices | drink's `base_sell_price` × format's `price_modifier` |
| Which groups like which drinks | `Data/groups/*.tres` → `preferred_serving_tags` |
| Station capacity | `Data/beverage/containers/service_cask.tres` → `maximum_capacity` |
| Formation spacing | `GroupStandingArea.formation_radius` on the area node |
| Reorder behaviour | `Data/groups/*.tres` → `reorder_chance`, `maximum_orders_per_visit` |

---

## Temporary fallback — remove later

`BeverageSceneSetup.grant_starting_stock` fills every station with 96 measures
on startup.

**This is scaffolding.** Deliveries do not yet top up *service* stock — only
bulk cellar storage — so without it every station starts dry and no group could
ever be served. Turn it off once the delivery chain reaches service containers.

Also still outstanding, and related:
- No staff task fills a service cask from cellar bulk; use the F7 panel's
  "Fill every service container from bulk" for now.
- Shared servings appear at the group's serving point without a staff member
  physically carrying them.

---

## Turning mixed drinks on

When the preparation task is connected to staff, set
`GroupOrderService.allow_prepared_drinks = true`.

That single flag lets Rum Punch, Coffee and Drinking Chocolate back into group
ordering — the recipes, ingredients and punch bowls are already authored and
validated. The only reason they are excluded now is that nothing prepares them.
