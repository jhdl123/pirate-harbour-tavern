class_name TavernTaskCoordinator
extends Node

## Turns things that happen in the tavern into entries on the task board.
##
## This is the only script in the game that knows both what a customer is and
## what a task is. Keeping that knowledge in one node is what lets the board
## stay gameplay-free and lets chairs, customers and stations stay unaware that
## staff exist at all.
##
## [b]It does two jobs[/b]
##
## [codeblock]
## produce     listen to world signals, create and cancel tasks
## validate    answer "is this task still a real requirement?" for the board
## [/codeblock]
##
## Validation is the more important half. It is what makes a player override
## free: nothing has to tell the board that you cleaned the chair yourself,
## because the next validation finds the chair clean and cancels the task.
##
## [b]Why signals rather than scanning[/b]
##
## A scan would mean walking every chair and every customer several times a
## second forever. Instead each chair's [CleanableComponent] and each customer
## report their own changes, and the only periodic work here is refreshing how
## urgent the waiting customers have become - which genuinely does change with
## time and nothing else emits.


@export_category("Wiring")

## Where customers come from. Used to hear about new arrivals.
@export var game_manager: GameManager


@export_category("Behaviour")

## Seconds between urgency refreshes for waiting customers.
##
## Patience drains continuously, so this is the one thing that cannot be purely
## event-driven. Twice a second is far finer than a player can perceive and
## costs a loop over the handful of open serve tasks.
@export_range(0.1, 10.0, 0.1)
var urgency_refresh_seconds: float = 0.5


@export_category("Debug")

@export var show_debug_messages: bool = false


var _urgency_elapsed: float = 0.0

## Chairs we have already wired up, so re-scanning is harmless.
var _connected_chairs: Array[Chair] = []

## Customers we have already wired up.
var _connected_customers: Array[Node] = []


func _ready() -> void:
	_register_validators()
	_connect_board_signals()

	# Chairs and any customers that already exist are picked up on the first
	# frame; everything after that arrives by signal.
	call_deferred(&"_initial_scan")


## Watches tasks leaving the board, so a requirement that outlived its task is
## noticed immediately rather than waiting for something else to happen.
##
## The case that made this necessary: cleaning an empty glass can break it, and
## the chair then needs cleaning again. The old task legitimately completed -
## the worker did exactly what it was asked - but the seat is still dirty, and
## the [signal CleanableComponent.task_changed] that announced the broken glass
## fired while the old task was still live, so deduplication correctly refused
## to create a second one. Re-checking the chair once the task has actually
## retired closes that window.
func _connect_board_signals() -> void:
	if not TaskBoard.task_completed.is_connected(_on_board_task_finished):
		TaskBoard.task_completed.connect(_on_board_task_finished)

	if not TaskBoard.task_cancelled.is_connected(_on_board_task_finished):
		TaskBoard.task_cancelled.connect(_on_board_task_finished)


## Re-creates a task when the world still needs one.
##
## Deliberately not connected to [signal TavernTaskService.task_failed]: a task
## that exhausted its failure budget is one the tavern could not do, and
## immediately recreating it would spin forever on, say, a chair that has been
## walled off. That case is recorded as an issue instead, and the F10 rescan
## brings it back once a human has had a look.
func _on_board_task_finished(
	task: TavernTask
) -> void:
	if task == null:
		return

	match task.task_type:
		TavernTaskTypes.CLEAN_SEAT:
			# No-ops when the seat is genuinely clean, so this is safe to call
			# after every cleaning task however it ended.
			_create_clean_task(task.get_target() as Chair)

		TavernTaskTypes.SERVE_DRINK:
			# A customer who orders again re-announces itself through
			# service_state_changed, so nothing is needed here yet. Left as an
			# explicit branch so the next task type added has somewhere obvious
			# to go.
			pass


func _initial_scan() -> void:
	_connect_chairs()

	if game_manager == null:
		push_warning(
			"TavernTaskCoordinator has no GameManager assigned, so it cannot "
			+ "hear about new customers and no serve tasks will be created."
		)
		return

	if not game_manager.customer_spawned.is_connected(_on_customer_spawned):
		game_manager.customer_spawned.connect(_on_customer_spawned)

	for customer: Node in game_manager.active_customers:
		_connect_customer(customer)


func _process(
	delta: float
) -> void:
	if not Simulation.updates_actors():
		return

	_urgency_elapsed += delta

	if _urgency_elapsed < urgency_refresh_seconds:
		return

	_urgency_elapsed = 0.0

	_refresh_serve_urgency()


# -----------------------------------------------------------------------------
# Validators
# -----------------------------------------------------------------------------

## Teaches the board how to re-check each kind of task it holds.
##
## The board calls these constantly - before every claim, on every sweep, and
## on every worker tick - so they must be cheap and must read the real world
## rather than anything cached here.
func _register_validators() -> void:
	TaskBoard.register_validator(
		TavernTaskTypes.SERVE_DRINK,
		_is_serve_task_still_needed
	)

	TaskBoard.register_validator(
		TavernTaskTypes.CLEAN_SEAT,
		_is_clean_task_still_needed
	)


func _is_serve_task_still_needed(
	task: TavernTask
) -> bool:
	var customer: Node = task.get_target()

	if customer == null or not is_instance_valid(customer):
		return false

	if not customer.has_method(&"is_awaiting_service"):
		return false

	if not bool(customer.call(&"is_awaiting_service")):
		return false

	# The customer may have changed their mind about what they wanted, which
	# makes this task about the wrong drink rather than no longer needed.
	var wanted: DrinkDefinition = customer.call(&"get_requested_drink")

	if wanted == null:
		return false

	if task.required_definition == null:
		return false

	return wanted.item_id == task.required_definition.item_id


func _is_clean_task_still_needed(
	task: TavernTask
) -> bool:
	var chair: Chair = task.get_target() as Chair

	if chair == null or not is_instance_valid(chair):
		return false

	if chair.cleanable == null:
		return false

	# Still dirty, or currently being cleaned by whoever holds the task.
	return chair.cleanable.has_cleaning_task()


# -----------------------------------------------------------------------------
# Customers and serving
# -----------------------------------------------------------------------------

func _on_customer_spawned(
	customer: Node
) -> void:
	_connect_customer(customer)


func _connect_customer(
	customer: Node
) -> void:
	if customer == null or not is_instance_valid(customer):
		return

	if _connected_customers.has(customer):
		return

	if not customer.has_signal(&"service_state_changed"):
		return

	customer.service_state_changed.connect(_on_customer_service_state_changed)

	_connected_customers.append(customer)

	# A customer that is already waiting when we hear about it still needs a
	# task, so evaluate immediately rather than waiting for the next change.
	_on_customer_service_state_changed(customer)


func _on_customer_service_state_changed(
	customer: Node
) -> void:
	if customer == null or not is_instance_valid(customer):
		return

	var key: String = TavernTaskService.build_node_key(
		TavernTaskTypes.SERVE_DRINK,
		customer
	)

	var existing: TavernTask = TaskBoard.find_by_target_key(key)

	if not bool(customer.call(&"is_awaiting_service")):
		# Served, gave up, or left. Either way the requirement has gone - unless
		# a worker is the reason it has gone. This signal fires from inside
		# Customer.try_serve(), one tick before the worker gets to report the
		# success, so cancelling here would file a completed delivery as
		# "no longer required" and lose it from the diagnostics.
		if (
			existing != null
			and not existing.is_terminal()
			and not existing.is_resolution_pending
		):
			TaskBoard.cancel(existing, &"customer_no_longer_waiting")

		_forget_customer_if_gone(customer)
		return

	var wanted: DrinkDefinition = customer.call(&"get_requested_drink")

	if wanted == null:
		return

	if existing != null and not existing.is_terminal():
		# Same customer, different drink: the old task describes work nobody
		# wants doing any more.
		if (
			existing.required_definition == null
			or existing.required_definition.item_id != wanted.item_id
		):
			TaskBoard.cancel(existing, &"order_changed")
		else:
			return

	var task: TavernTask = TaskBoard.create_task(
		TavernTaskTypes.SERVE_DRINK,
		key,
		{
			"target": customer,
			"required_item": wanted,
			"required_quantity": 1,
			"urgency": _get_customer_urgency(customer),
			"metadata": {
				"customer_name": String(customer.name),
				"drink": String(wanted.item_id),
			},
		}
	)

	if task != null and show_debug_messages:
		print(
			"[TaskCoordinator] ",
			customer.name,
			" wants ",
			wanted.display_name,
			" -> ",
			task.task_id
		)


func _refresh_serve_urgency() -> void:
	for task: TavernTask in TaskBoard.get_open_tasks_of_type(
		TavernTaskTypes.SERVE_DRINK
	):
		var customer: Node = task.get_target()

		if customer == null:
			continue

		TaskBoard.set_urgency(task, _get_customer_urgency(customer))


func _get_customer_urgency(
	customer: Node
) -> float:
	if customer == null or not customer.has_method(&"get_service_urgency"):
		return 0.0

	return float(customer.call(&"get_service_urgency"))


func _forget_customer_if_gone(
	customer: Node
) -> void:
	if customer != null and is_instance_valid(customer):
		return

	_connected_customers.erase(customer)


# -----------------------------------------------------------------------------
# Chairs and cleaning
# -----------------------------------------------------------------------------

func _connect_chairs() -> void:
	for chair: Chair in _find_chairs():
		if chair == null or _connected_chairs.has(chair):
			continue

		if chair.cleanable == null:
			continue

		if not chair.cleanable.task_changed.is_connected(
			_on_chair_cleaning_task_changed
		):
			chair.cleanable.task_changed.connect(
				_on_chair_cleaning_task_changed.bind(chair)
			)

		if not chair.cleanable.cleaning_completed.is_connected(
			_on_chair_cleaning_finished
		):
			chair.cleanable.cleaning_completed.connect(
				_on_chair_cleaning_finished.bind(chair)
			)

		_connected_chairs.append(chair)

		# A chair that is already dirty at startup still needs a task.
		if chair.cleanable.has_cleaning_task():
			_create_clean_task(chair)


## Every chair in the tavern.
##
## Found through the seat reservation tag rather than a new group, so chairs do
## not have to remember to register themselves with a second system. Falls back
## to the GameManager's table list when the tags are not set up.
func _find_chairs() -> Array[Chair]:
	var chairs: Array[Chair] = []

	var tree: SceneTree = get_tree()

	if tree != null:
		for node: Node in tree.get_nodes_in_group(
			Reservable.group_for_tag(&"seat")
		):
			var reservable: Reservable = node as Reservable

			if reservable == null:
				continue

			var chair: Chair = reservable.get_parent() as Chair

			if chair != null and not chairs.has(chair):
				chairs.append(chair)

	if not chairs.is_empty():
		return chairs

	if game_manager == null:
		return chairs

	for table: Table in game_manager.tables:
		if table == null:
			continue

		for chair: Chair in table.get_chairs():
			if chair != null and not chairs.has(chair):
				chairs.append(chair)

	return chairs


func _on_chair_cleaning_task_changed(
	_task: CleaningTask,
	chair: Chair
) -> void:
	# Fires both when a seat becomes dirty and when cleaning turns one mess
	# into another - broken glass after an empty glass. A new requirement in
	# either case.
	_create_clean_task(chair)


func _on_chair_cleaning_finished(
	chair: Chair
) -> void:
	if chair == null or not is_instance_valid(chair):
		return

	var key: String = TavernTaskService.build_node_key(
		TavernTaskTypes.CLEAN_SEAT,
		chair
	)

	var task: TavernTask = TaskBoard.find_by_target_key(key)

	if task == null or task.is_terminal():
		return

	# A worker mid-clean has already flagged the outcome as settled, and will
	# complete its own task on its next tick. Leave it alone.
	if task.is_resolution_pending:
		return

	# Otherwise somebody else cleaned it - the player, or a developer tool.
	# Cancelled rather than completed: nobody on the board earned it.
	TaskBoard.cancel(task, &"cleaned_by_other")


func _create_clean_task(
	chair: Chair
) -> void:
	if chair == null or not is_instance_valid(chair):
		return

	if chair.cleanable == null or not chair.cleanable.has_cleaning_task():
		return

	var key: String = TavernTaskService.build_node_key(
		TavernTaskTypes.CLEAN_SEAT,
		chair
	)

	var task: TavernTask = TaskBoard.create_task(
		TavernTaskTypes.CLEAN_SEAT,
		key,
		{
			"target": chair,
			# A dirty seat cannot be reserved by a new customer, so every one
			# of them is directly costing the tavern a seat. That is the whole
			# justification for cleaning out-ranking nothing else.
			"urgency": 0.5,
			"metadata": {
				"chair_name": String(chair.name),
				"table_name": (
					"" if chair.get_table() == null
					else String(chair.get_table().name)
				),
			},
		}
	)

	if task != null and show_debug_messages:
		print("[TaskCoordinator] ", chair.name, " needs cleaning -> ",
			task.task_id)


# -----------------------------------------------------------------------------
# Developer helpers
# -----------------------------------------------------------------------------

## Re-examines the whole tavern and creates any task that is missing.
##
## Not needed in normal play - every requirement announces itself - but useful
## after a developer tool has cleared the board, and a cheap way to prove that
## the signal wiring has not drifted from reality.
func rescan() -> int:
	var created_before: int = TaskBoard.get_open_task_count()

	_connect_chairs()

	for chair: Chair in _find_chairs():
		if chair.cleanable != null and chair.cleanable.has_cleaning_task():
			_create_clean_task(chair)

	if game_manager != null:
		for customer: Node in game_manager.active_customers:
			_connect_customer(customer)
			_on_customer_service_state_changed(customer)

	return TaskBoard.get_open_task_count() - created_before
