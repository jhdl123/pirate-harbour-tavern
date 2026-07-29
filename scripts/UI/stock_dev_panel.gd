class_name StockDevPanel
extends CanvasLayer

## Rapid system-testing panel (F10). Every button calls a real game-system
## method - see ARCHITECTURE_OVERVIEW.md. Disabled outside debug/editor
## builds so it can never accidentally ship active in an exported release;
## see KNOWN_ISSUES.md for the current, coarse nature of that check.
##
## Phase 2B.1: grouped under section headers (Customer AI / Simulation /
## Stock & Economy) purely for readability as the button list grew - every
## button is unchanged in behaviour from before the grouping.
##
## Phase 3A: added Staff, Tasks and Communication sections, and put the whole
## button list inside a ScrollContainer because it no longer fits on screen.
## Every Phase 3A button goes through a real system method in exactly the same
## way the older ones do - the closest thing to an exception is
## "Return worker to idle", which teleports and says so on the button.

@export var economy_manager: EconomyManager
@export var order_manager: OrderManager
@export var item_registry: ItemRegistry

## Phase 3A: writes the staff/task/communication JSON report.
@export var staff_report_manager: StaffReportManager

## Phase 3A: for the rescan button, which re-derives tasks from the world.
@export var task_coordinator: TavernTaskCoordinator

## Phase 3A: for toggling the message log open from here.
@export var communication_ui: CommunicationUI

## Phase 3A: scene instanced by "Spawn Tavern Hand" when none is present.
@export var staff_scene: PackedScene

## Phase 2B: lets the "Export Customer AI Report" button call the same
## explicit method testers can already call directly - see
## CustomerAIReportManager.finalize_and_write_report()'s doc comment for why
## this works (and writes something meaningful) even when
## CustomerAIDiagnosticsConfig.export_enabled has been off all session.
@export var customer_ai_report_manager: CustomerAIReportManager

## Phase 2B.1: for "Serve All Drinks" - reads the existing active-customer
## roster rather than searching the tree for a new group.
@export var game_manager: GameManager

var panel: PanelContainer
var status: Label
var _enabled: bool = false

func _ready() -> void:
	_enabled = OS.is_debug_build()
	if not _enabled:
		return
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	panel.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event.is_action_pressed(&"stock_dev_panel"):
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.position = Vector2(906, 24)
	panel.custom_minimum_size = Vector2(354, 0)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)
	var title := Label.new()
	title.text = "DEV TOOLS [F10]"
	title.add_theme_font_size_override("font_size", 18)
	outer.add_child(title)
	# The list outgrew the screen once Staff, Tasks and Communication were
	# added, so it scrolls rather than running off the bottom.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)

	_add_section(rows, "Customer AI")
	_add_button(rows, "Export Customer AI report", _export_customer_ai_report)
	_add_button(rows, "Enable/disable tavern activities", _toggle_tavern_activities)
	_add_button(rows, "Force first customer to socialise", _force_first_customer_to_socialise)
	_add_button(rows, "Force first customer to use darts", _force_first_customer_to_darts)
	_add_button(rows, "Release all activity reservations", _release_all_activity_reservations)
	_add_button(rows, "Show activity reservations", _show_activity_reservations)

	_add_section(rows, "Simulation")
	_add_button(rows, "Advance 1 game hour", func(): WorldTime.advance_minutes(60))
	_add_button(rows, "Skip 24 game hours", func(): WorldTime.advance_minutes(1440))
	_add_button(rows, "Serve all waiting drinks", _serve_all_drinks)
	_add_button(rows, "Clean all tables", _clean_all_tables)

	_add_section(rows, "Stock & Economy")
	_add_button(rows, "Add £100", func(): economy_manager.add_money(100, &"developer"))
	_add_button(rows, "Add 2 of each stock", _add_test_stock)
	_add_button(rows, "Empty all drink stations", func(): _each_station(func(s): s.empty_stock()))
	_add_button(rows, "Fill all drink stations", func(): _each_station(func(s): s.fill_stock()))
	_add_button(rows, "Complete next delivery", _complete_next)
	_add_button(rows, "Complete all deliveries", _complete_all)

	_add_section(rows, "Staff")
	_add_button(rows, "Spawn / reset Tavern Hand", _spawn_or_reset_staff)
	_add_button(rows, "Enable / disable all staff AI", _toggle_all_staff)
	_add_button(rows, "Pause / resume first worker", _toggle_first_worker)
	_add_button(rows, "Show worker state", _show_worker_state)
	_add_button(rows, "Force-release current task", _force_release_task)
	_add_button(rows, "Force navigation failure test", _force_navigation_failure)
	_add_button(rows, "Return worker to idle (teleports)", _teleport_worker_home)

	_add_section(rows, "Tasks")
	_add_button(rows, "Show task board", _show_task_board)
	_add_button(rows, "Show claimed tasks", _show_claimed_tasks)
	_add_button(rows, "Show task reservations", _show_task_reservations)
	_add_button(rows, "Create test serving task", _create_test_serving_task)
	_add_button(rows, "Create test cleaning task", _create_test_cleaning_task)

	_add_section(rows, "Communication")
	_add_button(rows, "Trigger low-stock warning", _trigger_low_stock)
	_add_button(rows, "Trigger out-of-stock alert", _trigger_out_of_stock)
	_add_button(rows, "Trigger stock-restored resolution", _trigger_stock_restored)
	_add_button(rows, "Trigger staff dialogue", _trigger_staff_dialogue)
	_add_button(rows, "List active alerts", _list_active_alerts)
	_add_button(rows, "Acknowledge next alert", _acknowledge_next_alert)
	_add_button(rows, "Resolve all alerts", _resolve_all_alerts)
	_add_button(rows, "Toggle message log", _toggle_message_log)
	_add_button(rows, "Clear notification history", _clear_history)

	_add_section(rows, "Diagnostics")
	_add_button(rows, "Show staff summary", _show_staff_summary)
	_add_button(rows, "Export staff / task / comms report", _export_staff_report)

	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Developer actions use the real game systems."
	outer.add_child(status)

func _add_section(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = Color(1, 1, 1, 0.7)
	parent.add_child(label)

func _add_button(parent: VBoxContainer, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)

func _get_storage() -> StockStorage:
	var nodes := get_tree().get_nodes_in_group(&"stock_storage")
	return nodes[0] as StockStorage if not nodes.is_empty() else null

func _add_test_stock() -> void:
	var storage := _get_storage()
	if storage == null:
		status.text = "No storage container found."
		return
	if item_registry == null:
		status.text = "No ItemRegistry assigned to the dev panel."
		return
	var grog := item_registry.get_definition(&"grog_barrel")
	var ale := item_registry.get_definition(&"ale_keg")
	if grog == null or ale == null:
		status.text = "ItemRegistry is missing grog_barrel or ale_keg."
		return
	var moved := storage.add_item(grog, 2) + storage.add_item(ale, 2)
	status.text = "Added %d stock items." % moved

func _each_station(callback: Callable) -> void:
	var count := 0
	for node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station := node as DrinksStation
		if station != null:
			callback.call(station)
			count += 1
	status.text = "Updated %d drink stations." % count

func _complete_next() -> void:
	status.text = "Completed next delivery." if order_manager != null and order_manager.complete_next_delivery() else "No pending delivery or no storage space."

func _complete_all() -> void:
	var count := order_manager.complete_all_deliveries() if order_manager != null else 0
	status.text = "Completed %d deliveries." % count

func _export_customer_ai_report() -> void:
	if customer_ai_report_manager == null:
		status.text = "No CustomerAIReportManager assigned."
		return
	var path := customer_ai_report_manager.finalize_and_write_report()
	status.text = (
		"Report written to " + path if path != ""
		else "Could not write the Customer AI report - see the Output panel."
	)

## Toggles every TavernActivityPoint in the tree via its own real
## set_enabled() (which reserves/releases itself through the existing
## Reservable machinery - see that method's doc comment) rather than a
## separate developer-only disabled flag.
var _tavern_activities_enabled: bool = true

func _toggle_tavern_activities() -> void:
	_tavern_activities_enabled = not _tavern_activities_enabled
	var count := 0
	for node in get_tree().get_nodes_in_group(Reservable.group_for_tag(&"darts")):
		var reservable := node as Reservable
		if reservable == null:
			continue
		var point := reservable.get_parent() as TavernActivityPoint
		if point == null:
			continue
		point.set_enabled(_tavern_activities_enabled)
		count += 1
	status.text = "%s %d tavern activity point(s)." % [
		("Enabled" if _tavern_activities_enabled else "Disabled"), count
	]

## "Selected customer" - there is no in-game customer-picker yet, so this
## (and the Darts equivalent below) act on the first entry in
## GameManager.active_customers as a documented simplification. See
## docs/CUSTOMER_AI_SYSTEM.md's Phase 2C developer-tools note.
func _get_first_active_customer() -> Node:
	if game_manager == null or game_manager.active_customers.is_empty():
		return null
	return game_manager.active_customers[0]

func _force_first_customer_to_socialise() -> void:
	var customer := _get_first_active_customer()
	if customer == null or not customer.has_method("force_activity_for_testing"):
		status.text = "No active customer available."
		return
	var forced: bool = customer.call("force_activity_for_testing", &"socialise_at_seat")
	status.text = (
		"Forced %s to socialise." % customer.name if forced
		else "Could not force socialise (no AI configured on that customer)."
	)

func _force_first_customer_to_darts() -> void:
	var customer := _get_first_active_customer()
	if customer == null or not customer.has_method("force_activity_for_testing"):
		status.text = "No active customer available."
		return
	var forced: bool = customer.call("force_activity_for_testing", &"visit_tavern_activity")
	status.text = (
		"Forced %s toward darts." % customer.name if forced
		else "Could not force darts (no AI configured, or darts unavailable)."
	)

## Unconditional release (passing no actor argument) - a genuine developer
## reset, not something a normal customer path would ever call, since a
## customer only ever releases its own reservation.
func _release_all_activity_reservations() -> void:
	var count := 0
	for node in get_tree().get_nodes_in_group(Reservable.group_for_tag(&"darts")):
		var reservable := node as Reservable
		if reservable == null or reservable.is_free():
			continue
		reservable.release()
		count += 1
	status.text = "Released %d activity reservation(s)." % count

func _show_activity_reservations() -> void:
	var lines: Array[String] = []
	for node in get_tree().get_nodes_in_group(Reservable.group_for_tag(&"darts")):
		var reservable := node as Reservable
		if reservable == null:
			continue
		var point := reservable.get_parent() as TavernActivityPoint
		var label: String = String(point.activity_id) if point != null else String(reservable.name)
		var holder := reservable.get_holder()
		lines.append(
			"%s: %s" % [
				label,
				(String(holder.name) if holder != null else "free")
			]
		)
	status.text = (
		"\n".join(lines) if not lines.is_empty()
		else "No tavern activity points found."
	)

## Calls Customer.force_serve_now() on every active customer currently
## waiting for a drink - that method itself re-checks State.ORDERING, so
## this never touches a customer mid-drink, mid-relax, or still walking to
## a seat. See Customer.force_serve_now()'s own doc comment for exactly
## which existing serve logic this reuses (all of it, past the point a real
## player's carried item would have been checked).
func _serve_all_drinks() -> void:
	if game_manager == null:
		status.text = "No GameManager assigned."
		return
	var count := 0
	for customer: Node in game_manager.active_customers:
		if customer == null or not customer.has_method("force_serve_now"):
			continue
		if customer.get("current_state") != Customer.State.ORDERING:
			continue
		customer.call("force_serve_now")
		count += 1
	status.text = "Served %d waiting customer(s)." % count

## Instantly completes every chair's pending cleaning task via the existing
## CleanableComponent, the same component a player's cleaning action already
## resolves through - no separate dirty-state flag invented for this
## shortcut. Finds chairs through the existing seat-reservation tagging
## (DestinationBroker/Reservable), not a new group. A chair with no pending
## task (including any currently occupied chair - cleaning tasks only ever
## start after a customer's reservation is released) is left untouched.
func _clean_all_tables() -> void:
	var count := 0
	for node in get_tree().get_nodes_in_group(Reservable.group_for_tag(&"seat")):
		var reservable := node as Reservable
		if reservable == null:
			continue
		var chair := reservable.get_parent() as Chair
		if chair == null or chair.cleanable == null:
			continue
		if chair.cleanable.has_cleaning_task():
			chair.cleanable.clear_cleaning_task()
			count += 1
	status.text = "Cleaned %d table(s)." % count


# -----------------------------------------------------------------------------
# Phase 3A - Staff
# -----------------------------------------------------------------------------
#
# Every button below drives the real systems. Two are honestly labelled as
# developer shortcuts because they have no gameplay equivalent: the teleport
# home, and the injected navigation failure. Everything else does exactly what
# the game does.

## Every StaffMember currently in the world.
##
## Reads the group StaffMember adds itself to, rather than a list this panel
## would have to keep in step.
func _get_staff() -> Array[StaffMember]:
	var workers: Array[StaffMember] = []

	for node: Node in get_tree().get_nodes_in_group(&"tavern_staff"):
		var worker: StaffMember = node as StaffMember

		if worker != null:
			workers.append(worker)

	return workers


func _get_first_worker() -> StaffMember:
	var workers: Array[StaffMember] = _get_staff()

	return null if workers.is_empty() else workers[0]


## Removes every worker and instances a fresh one from staff_scene.
##
## The reset half matters more than the spawn half: it proves a worker can be
## destroyed mid-task without leaking a claim or a reservation, because the
## board sweep picks the orphaned task up on its next pass.
func _spawn_or_reset_staff() -> void:
	if staff_scene == null:
		status.text = "No staff scene assigned to the dev panel."
		return

	var existing: Array[StaffMember] = _get_staff()
	var spawn_position: Vector2 = Vector2.ZERO
	var parent: Node = null

	if not existing.is_empty():
		spawn_position = existing[0].global_position
		parent = existing[0].get_parent()

	for worker: StaffMember in existing:
		worker.queue_free()

	if parent == null:
		parent = get_tree().current_scene.get_node_or_null("Entities")

	if parent == null:
		status.text = "Could not find an Entities node to spawn into."
		return

	var replacement: Node = staff_scene.instantiate()

	parent.add_child(replacement)

	if spawn_position != Vector2.ZERO:
		(replacement as Node2D).global_position = spawn_position

	status.text = "Replaced %d worker(s) with a fresh Tavern Hand." % existing.size()


func _toggle_all_staff() -> void:
	var workers: Array[StaffMember] = _get_staff()

	if workers.is_empty():
		status.text = "No staff in the tavern."
		return

	# Whatever the first worker is doing, everybody does the opposite of it,
	# so the button never leaves a mixed state behind.
	var enable: bool = not workers[0].is_work_enabled

	for worker: StaffMember in workers:
		if enable:
			worker.resume_work()
		else:
			worker.pause_work()

	status.text = "%s %d worker(s)." % [
		("Enabled" if enable else "Disabled"),
		workers.size(),
	]


func _toggle_first_worker() -> void:
	var worker: StaffMember = _get_first_worker()

	if worker == null:
		status.text = "No staff in the tavern."
		return

	var enabled: bool = worker.toggle_work()

	status.text = "%s is now %s." % [
		String(worker.get_staff_id()),
		("working" if enabled else "paused"),
	]


func _show_worker_state() -> void:
	var workers: Array[StaffMember] = _get_staff()

	if workers.is_empty():
		status.text = "No staff in the tavern."
		return

	var lines: Array[String] = []

	for worker: StaffMember in workers:
		lines.append(worker.get_debug_line())

	status.text = "\n".join(lines)

	print("\n".join(lines))


func _force_release_task() -> void:
	var worker: StaffMember = _get_first_worker()

	if worker == null:
		status.text = "No staff in the tavern."
		return

	var task_name: String = (
		"nothing" if worker.current_task == null
		else String(worker.current_task.task_id)
	)

	if worker.developer_release_current_task():
		status.text = "Released %s back to the board." % task_name
		return

	status.text = "%s is not holding a task." % String(worker.get_staff_id())


func _force_navigation_failure() -> void:
	var worker: StaffMember = _get_first_worker()

	if worker == null:
		status.text = "No staff in the tavern."
		return

	worker.developer_force_navigation_failure()

	status.text = (
		"Injected a navigation failure into %s - watch its retry count and "
		% String(worker.get_staff_id())
		+ "the task's reservations."
	)


func _teleport_worker_home() -> void:
	var worker: StaffMember = _get_first_worker()

	if worker == null:
		status.text = "No staff in the tavern."
		return

	worker.developer_return_to_idle()

	status.text = "Teleported %s to its idle point (developer only)." % String(
		worker.get_staff_id()
	)


# -----------------------------------------------------------------------------
# Phase 3A - Tasks
# -----------------------------------------------------------------------------

func _show_task_board() -> void:
	var open: Array[TavernTask] = TaskBoard.get_open_tasks()
	var summary: Dictionary = TaskBoard.get_summary()

	var lines: Array[String] = [
		"created %d / completed %d / cancelled %d / failed %d" % [
			int(summary["tasks_created"]),
			int(summary["tasks_completed"]),
			int(summary["tasks_cancelled"]),
			int(summary["tasks_failed"]),
		]
	]

	if open.is_empty():
		lines.append("No open tasks - the tavern is up to date.")
	else:
		for task: TavernTask in open:
			lines.append(task.describe())

	status.text = "\n".join(lines)

	print("\n".join(lines))


func _show_claimed_tasks() -> void:
	var active: Array[TavernTask] = TaskBoard.get_active_tasks()

	if active.is_empty():
		status.text = "No task is currently claimed."
		return

	var lines: Array[String] = []

	for task: TavernTask in active:
		lines.append("%s -> %s (%s)" % [
			String(task.task_id),
			String(task.assigned_worker_id),
			task.get_state_name(),
		])

	status.text = "\n".join(lines)


func _show_task_reservations() -> void:
	var lines: Array[String] = []

	for task: TavernTask in TaskBoard.get_open_tasks():
		if task.reservations.is_empty():
			continue

		var subjects: Array[String] = []

		for reservable: Reservable in task.reservations:
			if reservable == null or not is_instance_valid(reservable):
				continue

			var subject: Node = reservable.get_subject()

			subjects.append(
				String(reservable.name) if subject == null
				else String(subject.name)
			)

		lines.append("%s holds %s" % [
			String(task.task_id),
			", ".join(subjects),
		])

	status.text = (
		"\n".join(lines) if not lines.is_empty()
		else "No task is holding a reservation."
	)


## Rebuilds the board from the current world state.
##
## Not a fake task: the coordinator re-scans every waiting customer and every
## dirty chair and creates whatever is genuinely missing. If this produces a
## task the event-driven path should already have created, that is a real bug
## worth knowing about.
func _create_test_serving_task() -> void:
	if task_coordinator == null:
		status.text = "No TavernTaskCoordinator assigned to the dev panel."
		return

	var created: int = task_coordinator.rescan()

	var waiting: int = 0

	if game_manager != null:
		for customer: Node in game_manager.active_customers:
			if customer != null and customer.has_method("is_awaiting_service"):
				if bool(customer.call("is_awaiting_service")):
					waiting += 1

	status.text = (
		"Rescanned the world: %d task(s) created, %d customer(s) waiting. "
		% [created, waiting]
		+ "Prepare a drink and place it on the bar to unblock service."
	)


func _create_test_cleaning_task() -> void:
	if task_coordinator == null:
		status.text = "No TavernTaskCoordinator assigned to the dev panel."
		return

	# Dirty a genuinely free chair through the chair's own API, then let the
	# coordinator notice it exactly as it would after a real customer left.
	var dirtied: String = ""

	for node: Node in get_tree().get_nodes_in_group(
		Reservable.group_for_tag(&"seat")
	):
		var reservable: Reservable = node as Reservable

		if reservable == null or not reservable.is_free():
			continue

		var chair: Chair = reservable.get_parent() as Chair

		if chair == null or chair.cleanable == null:
			continue

		if chair.cleanable.has_cleaning_task():
			continue

		if chair.empty_glass_task == null:
			continue

		chair.cleanable.set_cleaning_task(chair.empty_glass_task)
		dirtied = String(chair.name)
		break

	var created: int = task_coordinator.rescan()

	status.text = (
		"No free clean chair to dirty." if dirtied.is_empty()
		else "Dirtied %s; %d cleaning task(s) now on the board." % [
			dirtied,
			created,
		]
	)


# -----------------------------------------------------------------------------
# Phase 3A - Communication
# -----------------------------------------------------------------------------

func _get_first_station() -> DrinksStation:
	for node: Node in get_tree().get_nodes_in_group(&"drink_stations"):
		var station: DrinksStation = node as DrinksStation

		if station != null:
			return station

	return null


## Drops a real station below its real threshold.
##
## The alert that appears is produced by the station's own stock evaluation and
## the StockAlertCoordinator, not by this panel - so if nothing appears, the
## alert pipeline is genuinely broken rather than untested.
func _trigger_low_stock() -> void:
	var station: DrinksStation = _get_first_station()

	if station == null:
		status.text = "No drink stations found."
		return

	station.set_servings(maxi(station.low_stock_threshold - 1, 1))

	status.text = "%s set to %d servings - expect one WARNING alert." % [
		station.get_interaction_display_name(),
		station.current_servings,
	]


func _trigger_out_of_stock() -> void:
	var station: DrinksStation = _get_first_station()

	if station == null:
		status.text = "No drink stations found."
		return

	station.empty_stock()

	status.text = (
		"%s emptied - the existing warning should escalate to CRITICAL "
		% station.get_interaction_display_name()
		+ "rather than a second alert appearing."
	)


func _trigger_stock_restored() -> void:
	var station: DrinksStation = _get_first_station()

	if station == null:
		status.text = "No drink stations found."
		return

	station.fill_stock()

	status.text = (
		"%s refilled - its alert should resolve automatically."
		% station.get_interaction_display_name()
	)


func _trigger_staff_dialogue() -> void:
	var worker: StaffMember = _get_first_worker()

	var speaker_name: String = (
		"Tavern Hand" if worker == null
		else worker.get_interaction_display_name()
	)

	Comms.say(
		speaker_name,
		"Everything's under control out here, but keep an eye on the barrels.",
		CommMessage.Category.STAFF
	)

	if worker != null:
		worker.say("Keep an eye on the barrels.")

	status.text = "Posted a speaker message from %s." % speaker_name


func _list_active_alerts() -> void:
	var alerts: Array[CommMessage] = Comms.get_active_alerts()

	if alerts.is_empty():
		status.text = "No active alerts."
		return

	var lines: Array[String] = []

	for message: CommMessage in alerts:
		lines.append("[%s] %s%s" % [
			message.get_severity_name(),
			message.title,
			(" (acknowledged)" if message.is_acknowledged else ""),
		])

	status.text = "\n".join(lines)


func _acknowledge_next_alert() -> void:
	for message: CommMessage in Comms.get_active_alerts():
		if message.is_acknowledged:
			continue

		Comms.acknowledge(message)

		status.text = "Acknowledged: %s" % message.title
		return

	status.text = "Nothing left to acknowledge."


func _resolve_all_alerts() -> void:
	var count: int = 0

	for message: CommMessage in Comms.get_active_alerts():
		if Comms.resolve(message, &"developer_resolved"):
			count += 1

	status.text = "Resolved %d alert(s)." % count


func _toggle_message_log() -> void:
	if communication_ui == null:
		status.text = "No CommunicationUI assigned to the dev panel."
		return

	var visible_now: bool = communication_ui.set_history_visible(
		not communication_ui.is_history_visible()
	)

	status.text = "Message log %s." % ("shown" if visible_now else "hidden")


func _clear_history() -> void:
	var cleared: int = Comms.clear_history()

	if communication_ui != null:
		communication_ui.set_history_visible(
			communication_ui.is_history_visible()
		)

	status.text = "Cleared %d history entr%s." % [
		cleared,
		("y" if cleared == 1 else "ies"),
	]


# -----------------------------------------------------------------------------
# Phase 3A - Diagnostics
# -----------------------------------------------------------------------------

func _show_staff_summary() -> void:
	if staff_report_manager == null:
		status.text = "No StaffReportManager assigned to the dev panel."
		return

	var summary: String = staff_report_manager.get_summary_text()

	status.text = summary

	print(summary)


func _export_staff_report() -> void:
	if staff_report_manager == null:
		status.text = "No StaffReportManager assigned to the dev panel."
		return

	var path: String = staff_report_manager.finalize_and_write_report()

	status.text = (
		"Report written to " + path if path != ""
		else "Could not write the staff report - see the Output panel."
	)
