extends Node

## Phase A: WHY customers are not being served.
##
## The gate audit answered "which condition blocked which activity". This
## answers the question upstream of it: two thirds of customers finish a
## visit with zero drinks, and a third of staff tasks are cancelled, and
## neither the committed customer_report nor the RUN_SUMMARY says why.
##
## TavernTaskService already tallies cancellation reasons
## (_cancellation_reason_counts, exposed via get_cancellation_reason_counts).
## Nothing prints it. This drives main.tscn and reads that tally directly,
## alongside per-customer wait times, so the balance pass has numbers to
## work from instead of impressions.

const RUN_SECONDS: float = 240.0
const SAMPLE_SECONDS: float = 1.0

var samples: int = 0
## customer -> seconds spent in WAITING_TO_ORDER / ORDERING
var wait_samples: Dictionary = {}
var served: Dictionary = {}
var seen: Dictionary = {}
var queue_depth_samples: Array[int] = []
var task_service: Node = null


func _ready() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	if Engine.has_singleton("Tavern") or get_node_or_null("/root/Tavern") != null:
		var tavern: Node = get_node_or_null("/root/Tavern")
		if tavern != null and tavern.has_method("open_early"):
			tavern.open_early()

	task_service = _find_task_service(main)

	var elapsed: float = 0.0
	while elapsed < RUN_SECONDS:
		await get_tree().create_timer(SAMPLE_SECONDS).timeout
		elapsed += SAMPLE_SECONDS
		_sample()

	_report()
	_export_real_run(main)
	get_tree().quit()


func _find_task_service(root: Node) -> Node:
	var direct: Node = get_node_or_null("/root/TaskBoard")
	if direct != null:
		return direct

	for node: Node in root.find_children("*", "", true, false):
		if node.has_method("get_cancellation_reason_counts"):
			return node

	return null


func _sample() -> void:
	samples += 1

	var customers: Array = get_tree().get_nodes_in_group("navigation_customers")
	if customers.is_empty():
		customers = get_tree().get_nodes_in_group("customer")

	var waiting_now: int = 0

	for c: Node in customers:
		if not is_instance_valid(c):
			continue

		var key: int = c.get_instance_id()
		seen[key] = true

		var state: int = -1
		if "current_state" in c:
			state = int(c.current_state)

		# WAITING_TO_ORDER = 3, ORDERING = 4
		if state == 3 or state == 4:
			wait_samples[key] = int(wait_samples.get(key, 0)) + 1
			waiting_now += 1

		if "drinks_consumed_this_visit" in c:
			served[key] = maxi(
				int(served.get(key, 0)),
				int(c.drinks_consumed_this_visit)
			)

	queue_depth_samples.append(waiting_now)


func _report() -> void:
	print("")
	print("=== SERVICE LATENCY PROBE ===")
	print("samples=", samples, " customers_seen=", seen.size())
	print("")

	print("--- TASK CANCELLATION REASONS ---")
	if task_service == null:
		print("  task service not found - reasons unavailable")
	else:
		var counts: Dictionary = task_service.get_cancellation_reason_counts()
		if counts.is_empty():
			print("  (none recorded)")
		else:
			var keys: Array = counts.keys()
			keys.sort_custom(
				func(a: Variant, b: Variant) -> bool:
					return int(counts[a]) > int(counts[b])
			)
			for k: Variant in keys:
				print("  ", k, ": ", counts[k])
	print("")

	print("--- TIME IN ORDER QUEUE (seconds per customer) ---")
	var buckets: Dictionary = {"0-5": 0, "6-15": 0, "16-30": 0, "31-60": 0, "60+": 0}
	var total_wait: int = 0
	for key: int in wait_samples.keys():
		var w: int = int(wait_samples[key])
		total_wait += w
		if w <= 5:
			buckets["0-5"] += 1
		elif w <= 15:
			buckets["6-15"] += 1
		elif w <= 30:
			buckets["16-30"] += 1
		elif w <= 60:
			buckets["31-60"] += 1
		else:
			buckets["60+"] += 1

	for b: String in ["0-5", "6-15", "16-30", "31-60", "60+"]:
		print("  ", b, "s: ", buckets[b], " customers")

	if not wait_samples.is_empty():
		print("  mean wait: ", snappedf(
			float(total_wait) / float(wait_samples.size()), 0.1
		), "s")
	print("")

	print("--- DRINKS SERVED ---")
	var zero: int = 0
	var some: int = 0
	for key: int in seen.keys():
		if int(served.get(key, 0)) == 0:
			zero += 1
		else:
			some += 1
	print("  served at least one: ", some)
	print("  never served: ", zero)
	print("")

	print("--- ORDER QUEUE DEPTH ---")
	var peak: int = 0
	var sum: int = 0
	for d: int in queue_depth_samples:
		peak = maxi(peak, d)
		sum += d
	print("  peak simultaneous waiting: ", peak)
	if not queue_depth_samples.is_empty():
		print("  mean waiting: ", snappedf(
			float(sum) / float(queue_depth_samples.size()), 0.1
		))
	print("")
	print("=== END SERVICE LATENCY PROBE ===")


## Drives a REAL session, then triggers the diagnostic export, so the
## committed customer_report.txt can be checked against live numbers rather
## than the export probe's synthetic empty session.
func _export_real_run(main: Node) -> void:
	var exporter: Node = main.get_node_or_null("Managers/DiagnosticRunExporter")
	if exporter == null:
		print("  exporter not found - skipping export")
		return

	if exporter.has_method("export_run"):
		exporter.export_run()
		print("  exported run")
