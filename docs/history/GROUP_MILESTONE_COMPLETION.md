# Group milestone completion — delivery clearance, order icon, Captain, roles

## Root cause

The staff report settled this one. `deliver_group_keg`: 11 created, 11 claimed, **5 completed, 6 cancelled** — every cancellation `group_left_before_delivery`, with 8–25 world minutes of work invested each time. The tavern hand was claiming the task, collecting the keg, walking over, and then standing there until the group's patience expired.

Two faults, not one:

**The ring never opened.** Members held their drinking slots for the whole delivery. The middle is empty, but their avoidance radii close the gaps between them, so there was no path in and nowhere to set the keg down.

**The worker was aimed at the keg point itself.** `_step_towards_group()` used `get_serving_position()` as its destination, so even with room the worker was trying to stand exactly where the keg needed to go.

## New files

| File | What it is |
|---|---|
| `resources/CustomerTypes/captain.tres` | The Captain customer type. `customer_category = &"captain"`, `spawn_weight = 0.0` so it never arrives alone. |
| `Data/customer_ai/personalities/captain.tres` | Higher wealth, generosity, tolerance and visit length. |
| `tests/group_milestone_test.{gd,tscn}` | 43 assertions covering this pass. |

## Changed files

`customer_group.gd`, `group_manager.gd`, `group_place.gd`, `group_spawner.gd`, `customer_group_definition.gd`, `customer.gd`, `deliver_group_keg_executor.gd`, `staff_capabilities.gd`, `Data/staff/tavern_hand.tres`, `Data/staff/tasks/deliver_group_keg.tres`, the five `Data/groups/*.tres`, `scenes/main/main.tscn`.

## Each change

**Delivery clearance.** Three new states — `CLEARING_DELIVERY_SPACE`, `DELIVERY_IN_PROGRESS`, `REFORMING` — appended to the enum so every existing integer keeps its value. On collection the group widens its own ring: each member steps outward along **its own radius**, so the formation keeps its shape and nobody crosses anybody else's path going out or coming back. Temporary positions live in `_delivery_slot_by_member`; the drinking slots are never written to, which is what lets the group put everybody back exactly where they were.

Clearance is bounded three ways: 70% of members is enough (`minimum_cleared_fraction`), a member that cannot walk gets one refresh then a safe placement, and `delivery_clearance_timeout` proceeds regardless. One member wedged behind a bench cannot block every delivery the group will ever receive.

**Delivery approach point.** `GroupPlace.get_delivery_approach_position()` sorts the members by angle around the centre and takes the middle of the widest angular gap — the clearest side to walk in from — projected onto the navigation map. The executor waits at the approach until `is_ready_for_keg_placement()` is true, so the keg never lands inside a closed ring.

**Order icon.** Reuses the leader's existing `OrderIcon` sprite. There is no second UI system: the group asks its leader to show the icon it already owns. Visible across `WAITING_TO_ORDER` through `DELIVERY_IN_PROGRESS`; hidden with a recorded reason on delivery, failure, departure or cleanup. `get_icon_leader()` promotes a replacement and moves the icon if the leader is lost mid-order.

**Captain.** `CAPTAIN_IF_PRESENT` leader rule, and `captain_chance` on the group definition — rolled once per party before anybody spawns, so a group is either Captain-and-crew or it is not, never half of one. The Captain is member zero, so it leads the way in and lands in the slot the formation already gives the first arrival. Defaults: pirate crew 0.35, captain and companions 1.0, merchant party 0.2, dock workers 0.15, sailor pair 0.1. Captaincy is detected by `customer_category`, never by display name, so renaming the resource cannot silently turn every Captain into a sailor.

**Role restriction.** A dedicated `deliver_group_kegs` capability rather than reusing `serve_drinks`: a keg is heavy floor work, and the bartender staying behind the bar is a role boundary rather than an accident of which task types happen to exist. Tavern Hand has it; Bartender does not. No name checks anywhere.

## Two bugs the tests caught

Both would have read as fine in review.

`NavigationServer2D.map_get_closest_point()` returns **the origin** when a map has no regions. The first version of the projection collapsed entire formations onto (0, 0). Both projection helpers now detect that and keep the raw geometric answer.

The executor oscillated. It asked "am I at the approach?" before "am I close enough to place?", so once it stepped inward it walked straight back out to the approach, forever. Reordered, with one bounded inward step.

## Test results

| Suite | Result | Baseline |
|---|---|---|
| `group_milestone_test` (new) | **43 / 0** | — |
| `group_parity_test` | 49 / 0 | 49 / 0 |
| `group_loop_test` | 38 / 0 | 38 / 0 |
| `group_stress_test` | 8 / 0 | 8 / 0 |
| `beverage_framework_test` | 49 / 0 | 49 / 0 |
| `beverage_ordering_test` | 18 / 0 | 18 / 0 |
| `phase_3a2_integration_test` | 16 / 0 | 16 / 0 |
| `phase_4a_integration_test` | 18 / 0 | 18 / 0 |
| `group_framework_test` | 47 / 2 | 47 / 2 |
| `group_keg_loop_test` | 28/4 then 27/5 | 27 / 5 |

The bartender/tavern-hand check goes through `TaskBoard.claim()` itself, not a comparison of two `.tres` files — `claim()` is the chokepoint the real game uses, and it is the thing worth testing.

## Limitations

**`group_keg_loop_test` is timing-sensitive.** Two consecutive runs of the same build gave 28/4 and 27/5. The 27/5 run had exactly the baseline's failure set. Treat its absolute number as noise and the failure *set* as the signal.

**Members are stubs in the new suite.** They implement exactly the member API the group calls, so a method disappearing from `Customer` fails an assertion — but the walking itself is not exercised. The clearance geometry is verified; whether a real `Customer` can always physically reach its stepped-back position on the real navmesh is not.

**`main.tscn` was not soak-tested with mixed Captain and ordinary groups.** The 10-group soak in the new suite uses stubs. Captain wiring in the scene is verified by import, not by watching one arrive.

**The §8 balance summary is not aggregated.** Every per-group field is recorded, but nothing yet rolls them into Captain-vs-ordinary success rates, average clearance/reform time, or keg tasks by staff role.

**`placement_range` is a plain variable on the executor**, not an export — it wants moving to the task definition when that resource is next touched.
