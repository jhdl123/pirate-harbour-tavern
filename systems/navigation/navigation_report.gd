class_name NavigationReport
extends RefCounted

## Aggregate navigation quality across every actor in the tavern.
##
## [b]Why this exists.[/b] The existing reports carry `navigation_failures: 0`
## and that has been read as "navigation is fine". It is not the same claim.
## A failure means the actor gave up entirely; an actor can grind against a
## doorway for six seconds, recover three times, and walk twice as far as it
## needed to, all while reporting zero failures. Nothing was measuring the
## difference between arriving and arriving well.
##
## The headline number is [b]path efficiency[/b] - distance actually walked
## divided by straight-line distance. ~1.0 is a clean line, ~1.2 is a
## sensible route round furniture, 2.0 means the actor walked twice as far as
## it needed to. Everything else in here explains an efficiency figure you do
## not like.
##
## [b]Slightly below 1.0 is normal and not a bug.[/b] An actor stops as soon
## as it is inside its arrival radius, so it never quite covers the full
## straight-line distance. On short hops - staff moving between bar slots -
## that gap is a real fraction of the journey, which is why staff typically
## read a little lower than customers. Only sustained values above
## [constant EFFICIENCY_CONCERN] mean the pathing is doing something silly.
##
## Read-only: this samples live actors and computes. It changes nothing.


## Path efficiency above which a journey is worth investigating.
const EFFICIENCY_CONCERN: float = 1.6

## Seconds of accumulated stalling that counts as a problem actor.
const STALL_CONCERN_SECONDS: float = 3.0


## Builds the report from every actor currently in the scene.
##
## Actors are found through the navigation groups they already register
## with, rather than a tree walk: `navigation_customers` and `tavern_staff`
## are the groups the actors themselves register with, so this cannot drift
## out of step with what is actually in the tavern.
static func build(tree: SceneTree) -> Dictionary:
	var actors: Array[Dictionary] = []

	_collect_group(tree, &"navigation_customers", "customer", actors)
	_collect_group(tree, &"tavern_staff", "staff", actors)

	return _summarise(actors)


static func _collect_group(
	tree: SceneTree,
	group: StringName,
	kind: String,
	out: Array[Dictionary]
) -> void:
	for node: Node in tree.get_nodes_in_group(group):
		var navigation: Variant = node.get(&"actor_navigation")

		if navigation == null:
			continue

		if not navigation.has_method("get_telemetry"):
			continue

		var entry: Dictionary = navigation.call("get_telemetry")

		entry["kind"] = kind

		out.append(entry)


static func _summarise(actors: Array[Dictionary]) -> Dictionary:
	var by_kind: Dictionary = {}
	var concerns: Array[Dictionary] = []

	var total_travelled: float = 0.0
	var total_direct: float = 0.0
	var total_stalled: float = 0.0
	var total_deflected: float = 0.0
	var total_recoveries: int = 0
	var total_sidesteps: int = 0
	var total_repaths: int = 0
	var total_completed: int = 0
	var total_failed: int = 0
	var worst_stall: float = 0.0
	var unseeded: int = 0

	var passing_sides: Dictionary = {}
	var speed_multipliers: Array[float] = []

	for actor: Dictionary in actors:
		var kind: String = String(actor["kind"])

		if not by_kind.has(kind):
			by_kind[kind] = {
				"actors": 0,
				"distance_travelled": 0.0,
				"direct_distance": 0.0,
				"stalled_seconds": 0.0,
				"deflected_seconds": 0.0,
				"recoveries": 0,
				"completed_journeys": 0,
				"failed_journeys": 0,
			}

		var bucket: Dictionary = by_kind[kind]

		bucket["actors"] = int(bucket["actors"]) + 1
		bucket["distance_travelled"] = (
			float(bucket["distance_travelled"])
			+ float(actor["distance_on_completed_journeys"])
		)
		bucket["direct_distance"] = (
			float(bucket["direct_distance"]) + float(actor["direct_distance"])
		)
		bucket["stalled_seconds"] = (
			float(bucket["stalled_seconds"]) + float(actor["stalled_seconds"])
		)
		bucket["deflected_seconds"] = (
			float(bucket["deflected_seconds"])
			+ float(actor["deflected_seconds"])
		)
		bucket["recoveries"] = (
			int(bucket["recoveries"]) + int(actor["recoveries"])
		)
		bucket["completed_journeys"] = (
			int(bucket["completed_journeys"])
			+ int(actor["completed_journeys"])
		)
		bucket["failed_journeys"] = (
			int(bucket["failed_journeys"]) + int(actor["failed_journeys"])
		)

		total_travelled += float(actor["distance_on_completed_journeys"])
		total_direct += float(actor["direct_distance"])
		total_stalled += float(actor["stalled_seconds"])
		total_deflected += float(actor["deflected_seconds"])
		total_recoveries += int(actor["recoveries"])
		total_sidesteps += int(actor["sidesteps"])
		total_repaths += int(actor["recovery_repaths"])
		total_completed += int(actor["completed_journeys"])
		total_failed += int(actor["failed_journeys"])
		worst_stall = maxf(worst_stall, float(actor["longest_stall_seconds"]))

		# Whether the organic movement values actually reached this actor.
		# An unseeded actor walks the old uniform way, and a report full of
		# them means the wiring never happened rather than that the tuning
		# is wrong.
		if not bool(actor["personal_movement_seeded"]):
			unseeded += 1
		else:
			passing_sides[actor["passing_side"]] = int(
				passing_sides.get(actor["passing_side"], 0)
			) + 1
			speed_multipliers.append(float(actor["speed_multiplier"]))

		if _is_concerning(actor):
			concerns.append(actor)

	for kind: String in by_kind:
		var bucket: Dictionary = by_kind[kind]
		var direct: float = float(bucket["direct_distance"])

		bucket["path_efficiency"] = (
			float(bucket["distance_travelled"]) / direct
			if direct > 0.0 else 0.0
		)

	var speed_spread: float = 0.0

	if speed_multipliers.size() > 1:
		var lowest: float = speed_multipliers[0]
		var highest: float = speed_multipliers[0]

		for value: float in speed_multipliers:
			lowest = minf(lowest, value)
			highest = maxf(highest, value)

		speed_spread = highest - lowest

	return {
		"actors_sampled": actors.size(),
		"by_kind": by_kind,
		"path_efficiency": (
			total_travelled / total_direct if total_direct > 0.0 else 0.0
		),
		"distance_travelled": total_travelled,
		"direct_distance": total_direct,
		"total_stalled_seconds": total_stalled,
		"longest_single_stall_seconds": worst_stall,
		"total_deflected_seconds": total_deflected,
		"total_recoveries": total_recoveries,
		"total_sidesteps": total_sidesteps,
		"total_recovery_repaths": total_repaths,
		"completed_journeys": total_completed,
		"failed_journeys": total_failed,
		"recoveries_per_journey": (
			float(total_recoveries) / float(total_completed)
			if total_completed > 0 else 0.0
		),
		"organic_movement": {
			"actors_seeded": actors.size() - unseeded,
			"actors_not_seeded": unseeded,
			"passing_side_distribution": passing_sides,
			"speed_multiplier_spread": speed_spread,
		},
		"actors_of_concern": concerns,
		"actors": actors,
	}


## An actor worth looking at: walking much further than necessary, or
## spending real time frozen.
static func _is_concerning(actor: Dictionary) -> bool:
	if float(actor["longest_stall_seconds"]) >= STALL_CONCERN_SECONDS:
		return true

	if int(actor["failed_journeys"]) > 0:
		return true

	if float(actor["direct_distance"]) < 200.0:
		# Too little travel for the ratio to mean anything yet.
		return false

	return float(actor["path_efficiency"]) >= EFFICIENCY_CONCERN


## Console summary. The three lines that matter are path efficiency,
## stalled seconds and recoveries per journey.
static func format_summary(report: Dictionary) -> String:
	var lines: Array[String] = []

	lines.append("=== Navigation Report ===")
	lines.append("Actors sampled: %d" % report["actors_sampled"])
	lines.append(
		(
			"Path efficiency: %.2f  (~1.0 clean, >1.6 investigate;"
			+ " slightly under 1.0 is the arrival radius, not a fault)"
		) % report["path_efficiency"]
	)
	lines.append(
		"Journeys: %d completed, %d failed"
		% [report["completed_journeys"], report["failed_journeys"]]
	)
	lines.append(
		"Recoveries: %d (%.2f per journey) - %d sidesteps, %d repaths"
		% [
			report["total_recoveries"], report["recoveries_per_journey"],
			report["total_sidesteps"], report["total_recovery_repaths"],
		]
	)
	lines.append(
		"Stalled: %.1fs total, worst single stall %.1fs"
		% [
			report["total_stalled_seconds"],
			report["longest_single_stall_seconds"],
		]
	)
	lines.append(
		"Deflected by avoidance: %.1fs" % report["total_deflected_seconds"]
	)
	lines.append("")

	for kind: String in report["by_kind"]:
		var bucket: Dictionary = report["by_kind"][kind]

		lines.append(
			"  %-9s n=%-3d efficiency %.2f  stalled %.1fs  recoveries %d"
			% [
				kind, bucket["actors"], bucket["path_efficiency"],
				bucket["stalled_seconds"], bucket["recoveries"],
			]
		)

	var organic: Dictionary = report["organic_movement"]

	lines.append("")
	lines.append(
		"Organic movement: %d seeded, %d NOT seeded, speed spread %.2f"
		% [
			organic["actors_seeded"], organic["actors_not_seeded"],
			organic["speed_multiplier_spread"],
		]
	)

	if int(organic["actors_not_seeded"]) > 0:
		lines.append(
			"  WARNING: unseeded actors walk the old uniform way -"
			+ " check seed_personal_movement() is being called."
		)

	var concerns: Array = report["actors_of_concern"]

	if concerns.is_empty():
		lines.append("")
		lines.append("No actors of concern.")

		return "\n".join(lines)

	lines.append("")
	lines.append("Actors of concern (%d):" % concerns.size())

	for actor: Dictionary in concerns:
		lines.append(
			"  %-16s efficiency %.2f  longest stall %.1fs  failed %d  state %s"
			% [
				actor["actor"], actor["path_efficiency"],
				actor["longest_stall_seconds"], actor["failed_journeys"],
				actor["state"],
			]
		)

	return "\n".join(lines)


## Writes the report to [param path] as JSON, alongside the customer and
## staff reports. Returns true on success.
static func export_json(
	tree: SceneTree,
	path: String = "user://navigation_report.json"
) -> bool:
	var report: Dictionary = build(tree)

	report["generated_unix"] = int(Time.get_unix_time_from_system())
	report["generated_iso"] = Time.get_datetime_string_from_system()
	report["report_format_version"] = 1

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		push_warning("NavigationReport could not write to '%s'." % path)
		return false

	file.store_string(JSON.stringify(report, "\t"))
	file.close()

	return true
