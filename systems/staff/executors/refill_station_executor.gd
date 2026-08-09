class_name RefillStationExecutor
extends StaffTaskExecutor

var _pending_action: StringName = &""
var _refilled: bool = false

func can_claim(worker: Node, task: TavernTask) -> bool:
	var carrier := get_carrier(worker)
	var storage := _get_stock_source(task)
	var station := task.get_target() as DrinksStation
	if carrier == null or storage == null or station == null or task.required_definition == null:
		return false
	if carrier.is_carrying_item(task.required_definition.item_id):
		return station.current_servings < station.maximum_servings
	if carrier.is_carrying():
		return false
	return int(storage.call(&"count_item", task.required_definition.item_id)) > 0 and station.current_servings < station.maximum_servings

func get_next_step(worker: Node, task: TavernTask) -> StaffTaskStep:
	_pending_action = &""
	if _refilled:
		return StaffTaskStep.complete()
	var carrier := get_carrier(worker)
	var storage := _get_stock_source(task)
	var station := task.get_target() as DrinksStation
	if carrier == null or storage == null or station == null or task.required_definition == null:
		return StaffTaskStep.fail(&"refill_world_object_missing")
	if station.current_servings >= station.stock_reset_threshold:
		return StaffTaskStep.complete()
	if carrier.is_carrying_item(task.required_definition.item_id):
		var station_stand := get_standing_position_near(worker, station.global_position)
		if not is_in_working_position(worker, station.global_position, station_stand, get_reach(worker)):
			return StaffTaskStep.move_to(station_stand, 10.0, station.get_interaction_display_name())
		_pending_action = &"refill"
		return StaffTaskStep.act("refill station")
	if carrier.is_carrying():
		return StaffTaskStep.release(&"hands_not_free")
	if int(storage.call(&"count_item", task.required_definition.item_id)) <= 0:
		return StaffTaskStep.release(&"storage_stock_unavailable")
	var storage_stand := get_standing_position_near(worker, storage.global_position)
	if not is_in_working_position(worker, storage.global_position, storage_stand, get_reach(worker)):
		return StaffTaskStep.move_to(storage_stand, 10.0, storage.get_interaction_display_name())
	_pending_action = &"collect_stock"
	return StaffTaskStep.act("collect station stock")

func perform_action(worker: Node, task: TavernTask) -> ActionResult:
	var carrier := get_carrier(worker)
	if carrier == null or task.required_definition == null:
		return ActionResult.FAILED
	match _pending_action:
		&"collect_stock":
			var storage := _get_stock_source(task)
			if storage == null:
				return ActionResult.FAILED
			var result: ItemTransferResult = storage.call(
				&"take_one", task.required_definition.item_id, carrier
			)
			return ActionResult.DONE if result.is_success() else ActionResult.FAILED
		&"refill":
			var station := task.get_target() as DrinksStation
			if station == null:
				return ActionResult.FAILED
			if not station.staff_refill_from(carrier):
				return ActionResult.FAILED
			_refilled = true
			return ActionResult.DONE
	return ActionResult.FAILED

## Anything that can report and hand over stock: StockStorage, or a storeroom
## StockedDisplay now that deliveries land in the props.
func _get_stock_source(task: TavernTask) -> Node:
	var source := task.get_source()

	if source == null:
		return null

	if not source.has_method(&"count_item") or not source.has_method(&"take_one"):
		return null

	return source


func estimate_travel_pixels(worker: Node, task: TavernTask) -> float:
	var storage := task.get_source() as Node2D
	var station := task.get_target() as Node2D
	if storage == null or station == null:
		return -1.0
	return get_worker_position(worker).distance_to(storage.global_position) + storage.global_position.distance_to(station.global_position)

func get_interaction_count(_worker: Node, _task: TavernTask) -> int:
	return 2
