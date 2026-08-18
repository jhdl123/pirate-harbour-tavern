extends Node2D

## Exports a real diagnostic run and checks what landed on disk.
##
## Testing the exporter by calling its formatters would prove nothing - the
## whole value is that the files exist, carry the Git commit, and report the
## same numbers the live systems hold.

var passed: int = 0
var failed: int = 0
var main: Node = null
var exporter: Node = null


func _ready() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout

	exporter = main.get_node_or_null(^"Managers/DiagnosticRunExporter")

	_check_wiring()
	_check_chain_validation()
	await _check_export()
	_check_fault_detection()

	print("RESULT %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("[PASS] %s" % label)
	else:
		failed += 1
		print("[FAIL] %s %s" % [label, detail])


func _check_wiring() -> void:
	_ok("the exporter is in the scene", exporter != null)

	if exporter == null:
		return

	_ok("it observes the customer report manager",
		exporter.customer_ai_report_manager != null)
	_ok("it observes the staff report manager",
		exporter.staff_report_manager != null)

	# The gap that shipped a broken button: the exporter node existed and the
	# probe was happy, but the F10 panel's reference to it was never checked.
	# Verifying a node exists is not verifying it is WIRED to its caller.
	var panel: Node = main.get_node_or_null(^"StockDevPanel")

	_ok("the dev panel is in the scene", panel != null)

	if panel != null:
		_ok("the dev panel holds the exporter",
			panel.diagnostic_run_exporter != null,
			"F10 would report 'No DiagnosticRunExporter assigned'")
		_ok("the dev panel points at the real exporter",
			panel.diagnostic_run_exporter == exporter)

		# And every other node_path on the panel, since one silently-null
		# reference is exactly as invisible as the next.
		for property: String in [
			"economy_manager", "order_manager", "staff_report_manager",
			"task_coordinator", "customer_ai_report_manager", "game_manager",
		]:
			_ok("the dev panel has %s wired" % property,
				panel.get(property) != null)

	# It must never keep its own copy of game state.
	var git: Dictionary = exporter._get_git_info()
	print("  git branch=%s short=%s" % [git["branch"], git["short"]])
	_ok("git information is readable without a Git binary",
		String(git["commit"]) != "unknown",
		"got %s" % git["commit"])


func _check_chain_validation() -> void:
	var chain: Dictionary = ServiceChainValidator.validate_all(get_tree())

	_ok("every orderable drink is validated", chain.size() >= 7,
		"only %d drinks" % chain.size())

	print("--- service chain ---")

	for drink_id: String in chain:
		var entry: Dictionary = chain[drink_id]
		print("  %-14s %s%s" % [
			drink_id, entry["result"],
			"" if String(entry["result"]) == "PASS"
			else "  breaks at: " + String(entry["first_failure_name"]),
		])

	# The validator must agree with the game, so a chain that reports PASS for
	# a drink no station serves would be worse than no validator at all.
	for drink_id: String in chain:
		var entry: Dictionary = chain[drink_id]
		var identities: Dictionary = entry["identities"]

		if String(entry["result"]) != "PASS":
			continue

		_ok("%s PASS names a real station" % drink_id,
			String(identities.get("service_station", "none")) != "none")
		_ok("%s PASS names a real restock item" % drink_id,
			String(identities.get("restock_item", "none")) != "none")


## Breaks the chain on purpose and confirms the validator notices.
##
## A validator that has only ever reported PASS is indistinguishable from one
## that cannot fail. Every check here is reverted immediately.
func _check_fault_detection() -> void:
	print("--- fault injection ---")

	# 1. A station asking for the wrong stock - the grog-barrel bug.
	var station: DrinksStation = null

	for node in get_tree().get_nodes_in_group(&"drink_stations"):
		var candidate := node as DrinksStation

		if candidate.served_drink != null and candidate.served_drink.item_id == &"port_wine":
			station = candidate
			break

	if station != null:
		var original: ItemDefinition = station.refill_item
		station.refill_item = load("res://Data/items/stock/grog_barrel.tres")

		var chain: Dictionary = ServiceChainValidator.validate_all(get_tree())
		_ok("a station asking for the wrong stock is caught",
			String(chain["port_wine"]["result"]) == "FAIL",
			"reported %s" % chain["port_wine"]["result"])

		station.refill_item = original

	# 2. A storeroom display that disagrees with its own storage.
	var display: StockedDisplay = null

	for node in get_tree().get_nodes_in_group(&"stocked_display"):
		var candidate := node as StockedDisplay

		if candidate.storage_backed and candidate.content_id == &"port_wine":
			display = candidate
			break

	if display != null:
		var registry: BeverageRegistry = main.get_node(^"Managers/Cellar").registry
		var batch := FilledContainer.new()
		batch.container = registry.get_container(&"crate")
		batch.content_id = &"port_wine"
		batch.quantity = batch.container.maximum_capacity
		display.get_storage().add_batch(batch)

		# Force the display out of step with its storage, as a broken
		# subscription would.
		display.set_visible_units(0)

		var chain: Dictionary = ServiceChainValidator.validate_all(get_tree())
		_ok("a display that disagrees with its storage is caught",
			String(chain["port_wine"]["result"]) == "FAIL",
			"reported %s" % chain["port_wine"]["result"])

		display._refresh_units_from_storage()

	# And back to a clean bill of health.
	var final_chain: Dictionary = ServiceChainValidator.validate_all(get_tree())
	var still_failing: Array[String] = []

	for drink_id: String in final_chain:
		if String(final_chain[drink_id]["result"]) != "PASS":
			still_failing.append(drink_id)

	_ok("the tavern is clean again after the injections",
		still_failing.is_empty(), "still failing: %s" % str(still_failing))


func _check_export() -> void:
	if exporter == null:
		return

	exporter.test_purpose = "Automated probe"
	exporter.developer_notes = "Written by diagnostic_export_probe."
	exporter.record_stock_event(&"DELIVERY", "Probe Cask", 96, "probe")

	# Drive the F10 button itself, not just export_run() - the button is what
	# reported "No DiagnosticRunExporter assigned".
	var panel: Node = main.get_node_or_null(^"StockDevPanel")

	if panel != null:
		panel._export_diagnostic_run()
		_ok("the F10 button exports rather than reporting a missing exporter",
			not String(panel.status.text).contains("No DiagnosticRunExporter"),
			panel.status.text)

	var archive: String = exporter.export_run()

	_ok("export_run returned an archive path", archive != "", archive)

	if archive == "":
		return

	await get_tree().process_frame

	for filename: String in ["RUN_SUMMARY.md", "drinks_report.txt",
			"stock_report.txt", "system_diagnostics.txt"]:
		_ok("latest/%s exists" % filename,
			FileAccess.file_exists("res://debug/latest/%s" % filename))
		_ok("archive/%s exists" % filename,
			FileAccess.file_exists("%s/%s" % [archive, filename]))

	_ok("debug/README.md exists",
		FileAccess.file_exists("res://debug/README.md"))

	var summary: FileAccess = FileAccess.open(
		"res://debug/latest/RUN_SUMMARY.md", FileAccess.READ
	)
	var text: String = "" if summary == null else summary.get_as_text()

	if summary != null:
		summary.close()

	_ok("the summary records a Git commit",
		text.contains("Git commit:") and not text.contains("Git commit: unknown"))
	_ok("the summary carries a systems table", text.contains("| System |"))
	_ok("the summary states an overall result",
		text.contains("## Overall Result"))
	_ok("the summary carries the developer notes",
		text.contains("diagnostic_export_probe"))
	_ok("the summary lists per-drink chain results",
		text.contains("## Drink Chain Results"))

	# The metrics must come from the real managers, not placeholders.
	_ok("the summary carries real metrics",
		not text.contains("(no metrics available)"),
		"metrics section was empty")

	var stock: FileAccess = FileAccess.open(
		"res://debug/latest/stock_report.txt", FileAccess.READ
	)
	var stock_text: String = "" if stock == null else stock.get_as_text()

	if stock != null:
		stock.close()

	_ok("the stock report compares authoritative and displayed quantities",
		stock_text.contains("Authoritative units")
		and stock_text.contains("Displayed units"))
	_ok("the stock report logs stock events",
		stock_text.contains("Probe Cask"))

	print("--- RUN_SUMMARY.md (first 30 lines) ---")

	var shown: int = 0

	for line: String in text.split("\n"):
		print("  %s" % line)
		shown += 1

		if shown >= 30:
			break
