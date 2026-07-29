class_name StockStorage
extends StaticBody2D

signal contents_changed

@export var slot_count: int = 12
@export var storage_menu_scene: PackedScene
@onready var interactable: Interactable = $InteractionArea

var inventory: ItemContainer

func _ready() -> void:
	add_to_group(&"stock_storage")
	var rules := ItemSlotRules.new()
	rules.capacity = 1
	rules.accepted_tags = [&"drink_stock"]
	rules.allow_insert = true
	rules.allow_remove = true
	rules.allow_merge = true
	rules.allow_swap = true
	rules.allow_partial = true
	inventory = ItemContainer.new(&"main_stock_storage", slot_count, rules)
	inventory.container_tags = [&"storage", &"drink_stock"]
	inventory.contents_changed.connect(_on_contents_changed)

func get_interaction_display_name() -> String:
	return "Stock Storage"

func can_interact(request: InteractionRequest) -> bool:
	return request.get_actor_carrier() != null and storage_menu_scene != null

func get_interaction_actions(_request: InteractionRequest) -> Array[InteractionAction]:
	return [InteractionAction.create(&"open_storage", "Open", "Stock Storage")]

func perform_interaction(request: InteractionRequest) -> bool:
	if request.action_id != &"open_storage" or storage_menu_scene == null:
		return false
	return InteractionMenu.open_menu(storage_menu_scene, {
		"storage": self,
		"carrier": request.get_actor_carrier(),
	})

func add_item(definition: ItemDefinition, quantity: int = 1) -> int:
	if definition == null or quantity <= 0:
		return 0
	var moved := 0
	for _i in range(quantity):
		var source_rules := ItemSlotRules.new()
		source_rules.capacity = 1
		var source := ItemSlot.new(&"delivery_source", source_rules)
		source.set_stack(ItemStack.create(definition, 1))
		var result := ItemTransferService.transfer_to_container(source, inventory, 1)
		if not result.is_success():
			break
		moved += result.amount_moved
	return moved

func take_one(item_id: StringName, carrier: ItemCarrier) -> ItemTransferResult:
	if carrier == null:
		return ItemTransferResult.failure(ItemTransferResult.Status.INVALID_REQUEST)
	var source := inventory.find_slot_with_item(item_id)
	if source == null:
		return ItemTransferResult.failure(ItemTransferResult.Status.SOURCE_EMPTY)
	return ItemTransferService.transfer(source, carrier.get_slot(), 1, false)

func deposit_carried(carrier: ItemCarrier) -> ItemTransferResult:
	if carrier == null:
		return ItemTransferResult.failure(ItemTransferResult.Status.INVALID_REQUEST)
	return ItemTransferService.transfer_to_container(carrier.get_slot(), inventory)

func get_summary() -> Array[Dictionary]:
	var totals: Dictionary = {}
	for slot in inventory.get_slots():
		if slot == null or slot.is_empty():
			continue
		var definition := slot.get_definition()
		var id := definition.item_id
		if not totals.has(id):
			totals[id] = {"item_id": id, "display_name": definition.display_name, "quantity": 0}
		totals[id].quantity += slot.get_quantity()
	var result: Array[Dictionary] = []
	for value in totals.values():
		result.append(value)
	result.sort_custom(func(a, b): return a.display_name < b.display_name)
	return result

func clear_all() -> void:
	for slot in inventory.get_slots():
		slot.clear()

func _on_contents_changed() -> void:
	contents_changed.emit()
	if interactable != null:
		interactable.notify_state_changed()
