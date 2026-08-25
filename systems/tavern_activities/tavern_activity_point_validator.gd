class_name TavernActivityPointValidator
extends RefCounted

## Finds a [TavernActivityPoint] whose slots cannot be resolved back to it.
##
## [b]Why this exists.[/b] `VisitTavernActivityBehaviour.on_enter()` needs to
## resolve a reserved [Reservable] back to the [TavernActivityPoint] that
## owns it. `a6e8993` moved darts' `Reservable` one nesting level deeper
## (child of a new [TavernActivitySlot] rather than direct child of the
## point) without updating that resolution, so every darts selection was
## silently abandoned from that commit until this one - a computed failure
## signal (`abandon_activity_visit()`) that existed and reached nowhere for
## days. See `docs/history/2026-08-25_CUSTOMER_ARCHITECTURE_AUDIT.md` and
## `CURRENT_STATE.md`'s Known issues.
##
## Mirrors [NavigationValidator]: static, read-only, groups rather than a
## recursive tree walk (every [TavernActivityPoint] registers itself into
## [code]&"tavern_activity_points"[/code] in [method TavernActivityPoint.
## _ready]). Catches the same class of bug again, for any future point-based
## activity, the moment the scene loads rather than after days of silent
## failure.


## Every point whose slots cannot resolve back to it. Each entry has
## [code]point_path[/code], [code]slot_name[/code] and [code]reason[/code].
static func find_unresolvable_slots(tree: SceneTree) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []

	if tree == null:
		return problems

	for node: Node in tree.get_nodes_in_group(&"tavern_activity_points"):
		var point: TavernActivityPoint = node as TavernActivityPoint

		if point == null:
			continue

		if point.slots.is_empty():
			problems.append({
				"point_path": String(point.get_path()),
				"slot_name": "",
				"reason": "no TavernActivitySlot children and no legacy "
					+ "bare Reservable to synthesize one from",
			})
			continue

		for slot: TavernActivitySlot in point.slots:
			if slot.reservable == null:
				problems.append({
					"point_path": String(point.get_path()),
					"slot_name": (
						String(slot.name) if slot.is_inside_tree() else "(synthesized)"
					),
					"reason": "slot has no Reservable",
				})
				continue

			if slot.point != point:
				problems.append({
					"point_path": String(point.get_path()),
					"slot_name": (
						String(slot.name) if slot.is_inside_tree() else "(synthesized)"
					),
					"reason": (
						"slot.point does not resolve back to this point - "
						+ "the exact failure that made darts unplayable "
						+ "from a6e8993 to this fix"
					),
				})

	return problems
