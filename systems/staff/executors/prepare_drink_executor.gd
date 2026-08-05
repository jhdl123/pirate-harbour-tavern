class_name PrepareDrinkExecutor
extends StaffTaskExecutor

var _pending_action: StringName = &""
var _placed: bool = false

func can_claim(worker: Node, task: TavernTask) -> bool:
	var carrier := get_carrier(worker)
	if carrier == null or carrier.is_carrying():
		return false
	var station := task.get_source() as DrinksStation
	var counter := task.get_target() as BarCounter
	if station == null or counter == null or task.required_definition == null:
		return false
	if station.served_drink == null or station.served_drink.item_id != task.required_definition.item_id:
		return false
	return station.current_servings > 0 and _find_empty_slot(counter) >= 0

func on_claimed(_worker: Node, task: TavernTask) -> bool:
	var counter := task.get_target() as BarCounter
	if counter == null:
		return false
	var slot_index := _find_empty_slot(counter)
	if slot_index < 0:
		return false
	task.source_data[&"destination_slot_index"] = slot_index
	return true

func get_next_step(worker: Node, task: TavernTask) -> StaffTaskStep:
	_pending_action = &""
	if _placed:
		return StaffTaskStep.complete()
	var carrier := get_carrier(worker)
	var station := task.get_source() as DrinksStation
	var counter := task.get_target() as BarCounter
	if carrier == null or station == null or counter == null:
		return StaffTaskStep.fail(&"prepare_world_object_missing")
	if task.required_definition == null:
		return StaffTaskStep.fail(&"no_required_item")
	if carrier.is_carrying_item(task.required_definition.item_id):
		return _step_to_counter(worker, task, counter)
	if carrier.is_carrying():
		return StaffTaskStep.release(&"hands_not_free")
	if station.current_servings <= 0:
		return StaffTaskStep.release(&"station_empty")
	var stand_at := get_standing_position_near(worker, station.global_position)
	if not is_in_working_position(worker, station.global_position, stand_at, get_reach(worker)):
		return StaffTaskStep.move_to(stand_at, 10.0, station.get_interaction_display_name())
	_pending_action = &"pour"
	return StaffTaskStep.act("pour drink")

func perform_action(worker: Node, task: TavernTask) -> ActionResult:
	match _pending_action:
		&"pour":
			var station := task.get_source() as DrinksStation
			var carrier := get_carrier(worker)
			if station == null or carrier == null:
				return ActionResult.FAILED
			return ActionResult.DONE if station.staff_dispense_to(carrier) else ActionResult.FAILED
		&"place":
			var counter := task.get_target() as BarCounter
			var carrier := get_carrier(worker)
			if counter == null or carrier == null:
				return ActionResult.FAILED
			var slot_index := int(task.source_data.get(&"destination_slot_index", -1))
			var slot := counter.get_service_slot(slot_index)
			if slot == null or not slot.is_empty():
				slot_index = _find_empty_slot(counter)
				if slot_index < 0:
					return ActionResult.FAILED
				task.source_data[&"destination_slot_index"] = slot_index
				slot = counter.get_service_slot(slot_index)
			var result := ItemTransferService.transfer(carrier.get_slot(), slot, 1, false)
			if not result.is_success():
				return ActionResult.FAILED
			_placed = true
			return ActionResult.DONE
	return ActionResult.FAILED

func _step_to_counter(worker: Node, task: TavernTask, counter: BarCounter) -> StaffTaskStep:
	var slot_index := int(task.source_data.get(&"destination_slot_index", -1))
	var slot := counter.get_service_slot(slot_index)
	if slot == null or not slot.is_empty():
		slot_index = _find_empty_slot(counter)
		if slot_index < 0:
			return StaffTaskStep.release(&"bar_slots_full")
		task.source_data[&"destination_slot_index"] = slot_index
	var marker := counter.get_service_slot_marker(slot_index)
	if marker == null:
		return StaffTaskStep.fail(&"bar_slot_marker_missing")

	# The bartender works behind the counter. The item still lands in the same
	# logical slot the Tavern Hand collects from on the customer side; only
	# the approach point differs. Walking round to the front to put a drink
	# down is what this replaces.
	var access_position: Vector2 = counter.get_slot_access_position(
		slot_index,
		BarCounter.SlotAccess.DEPOSIT
	)

	var stand_at := get_standing_position_near(worker, access_position)
	if not is_in_working_position(worker, marker.global_position, stand_at, get_reach(worker)):
		return StaffTaskStep.move_to(
			stand_at,
			8.0,
			"bar slot %d (deposit side)" % slot_index
		)
	_pending_action = &"place"
	return StaffTaskStep.act("place prepared drink")

func _find_empty_slot(counter: BarCounter) -> int:
	if counter == null or counter.get_service_container() == null:
		return -1
	for i in range(counter.get_service_container().get_slot_count()):
		var slot := counter.get_service_slot(i)
		if slot != null and slot.is_empty():
			return i
	return -1

func estimate_travel_pixels(worker: Node, task: TavernTask) -> float:
	var station := task.get_source() as Node2D
	var counter := task.get_target() as Node2D
	if station == null or counter == null:
		return -1.0
	return get_worker_position(worker).distance_to(station.global_position) + station.global_position.distance_to(counter.global_position)

func get_interaction_count(_worker: Node, _task: TavernTask) -> int:
	return 2
