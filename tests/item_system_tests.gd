extends Node

## Technical validation for the item, slot, container and transfer systems.
##
## How to run
## ----------
## Open res://tests/item_system_tests.tscn and press F6. Results are printed to
## the Output panel. This scene is NOT the project's main scene and adds nothing
## to the tavern.
##
## Headless:
##     godot --headless --path . res://tests/item_system_tests.tscn
##
## The tests build their own [ItemDefinition] resources in code, so they never
## depend on the balance of the real drink resources and cannot be broken by a
## price or texture change.
##
## Gameplay behaviour that needs a running tavern - picking up, serving,
## cleaning and payment - is covered by the manual test list in
## docs/ITEM_SYSTEM.md.


## Quits the engine once the tests finish. Useful for headless runs.
@export var quit_when_finished: bool = false


var _tests_passed: int = 0
var _tests_failed: int = 0
var _failure_messages: PackedStringArray = []


func _ready() -> void:
	run_all_tests()

	if quit_when_finished:
		get_tree().quit(0 if _tests_failed == 0 else 1)


func run_all_tests() -> bool:
	_tests_passed = 0
	_tests_failed = 0
	_failure_messages.clear()

	print("")
	print("=== Item system tests ===")

	_test_empty_source_is_rejected()
	_test_move_into_empty_valid_slot()
	_test_invalid_tag_is_rejected()
	_test_matching_stacks_merge()
	_test_item_maximum_stack_size_is_respected()
	_test_slot_capacity_is_respected()
	_test_partial_transfer()
	_test_valid_swap()
	_test_invalid_swap_changes_nothing()
	_test_incompatible_metadata_does_not_merge()
	_test_stack_serialisation_round_trip()
	_test_container_fills_merge_target_first()
	_test_container_serialisation_round_trip()
	_test_no_duplication_or_loss()
	_test_registry_rejects_unknown_item()
	_test_carrier_rules_reject_prepared_drink_in_inventory()

	print("---")
	print(
		"Passed: %d   Failed: %d" % [
			_tests_passed,
			_tests_failed
		]
	)

	for message: String in _failure_messages:
		print("  FAILED: ", message)

	print("=========================")
	print("")

	return _tests_failed == 0


# --- Tests -------------------------------------------------------------------

func _test_empty_source_is_rejected() -> void:
	var source: ItemSlot = _make_slot(&"source", 10)
	var destination: ItemSlot = _make_slot(&"destination", 10)

	var result: ItemTransferResult = ItemTransferService.transfer(
		source,
		destination
	)

	_check(
		"1. Empty source transfer is rejected",
		result.status == ItemTransferResult.Status.SOURCE_EMPTY
			and destination.is_empty()
	)


func _test_move_into_empty_valid_slot() -> void:
	var coin: ItemDefinition = _make_definition(
		&"test_coin",
		20,
		[&"trade_good", &"small_item"]
	)

	var source: ItemSlot = _make_slot(&"source", 20)
	var destination: ItemSlot = _make_slot(&"destination", 20)

	source.set_stack(ItemStack.create(coin, 5))

	var result: ItemTransferResult = ItemTransferService.transfer(
		source,
		destination
	)

	_check(
		"2. Whole stack moves into an empty valid slot",
		result.status == ItemTransferResult.Status.MOVED
			and result.amount_moved == 5
			and source.is_empty()
			and destination.get_quantity() == 5
			and destination.get_item_id() == &"test_coin"
	)


func _test_invalid_tag_is_rejected() -> void:
	var keg: ItemDefinition = _make_definition(
		&"test_keg",
		1,
		[&"drink_stock", &"bulky_item"]
	)

	var source: ItemSlot = _make_slot(&"source", 10)
	var destination: ItemSlot = _make_slot(
		&"destination",
		10,
		[&"small_item"]
	)

	source.set_stack(ItemStack.create(keg, 1))

	var result: ItemTransferResult = ItemTransferService.transfer(
		source,
		destination
	)

	_check(
		"3. An item without an accepted tag is rejected",
		result.status == ItemTransferResult.Status.REJECTED_ITEM
			and source.get_quantity() == 1
			and destination.is_empty()
	)


func _test_matching_stacks_merge() -> void:
	var rope: ItemDefinition = _make_definition(&"test_rope", 20)

	var source: ItemSlot = _make_slot(&"source", 20)
	var destination: ItemSlot = _make_slot(&"destination", 20)

	source.set_stack(ItemStack.create(rope, 4))
	destination.set_stack(ItemStack.create(rope, 3))

	var result: ItemTransferResult = ItemTransferService.transfer(
		source,
		destination
	)

	_check(
		"4. Matching stacks merge",
		result.status == ItemTransferResult.Status.MERGED
			and source.is_empty()
			and destination.get_quantity() == 7
	)


func _test_item_maximum_stack_size_is_respected() -> void:
	var rope: ItemDefinition = _make_definition(&"test_rope_small", 5)

	var source: ItemSlot = _make_slot(&"source", 99)
	var destination: ItemSlot = _make_slot(&"destination", 99)

	source.set_stack(ItemStack.create(rope, 5))
	destination.set_stack(ItemStack.create(rope, 3))

	var result: ItemTransferResult = ItemTransferService.transfer(
		source,
		destination
	)

	# The slot allows 99 but the item allows 5, so only 2 fit.
	_check(
		"5. The item's maximum stack size is respected",
		result.status == ItemTransferResult.Status.PARTIALLY_MERGED
			and destination.get_quantity() == 5
			and source.get_quantity() == 3
	)


func _test_slot_capacity_is_respected() -> void:
	var rope: ItemDefinition = _make_definition(&"test_rope_big", 99)

	var source: ItemSlot = _make_slot(&"source", 99)
	var destination: ItemSlot = _make_slot(&"destination", 4)

	source.set_stack(ItemStack.create(rope, 10))

	var result: ItemTransferResult = ItemTransferService.transfer(
		source,
		destination
	)

	# The item allows 99 but the slot allows 4.
	_check(
		"6. The slot's own capacity is respected",
		result.status == ItemTransferResult.Status.PARTIALLY_MOVED
			and destination.get_quantity() == 4
			and source.get_quantity() == 6
	)


func _test_partial_transfer() -> void:
	var rope: ItemDefinition = _make_definition(&"test_rope_partial", 20)

	var source: ItemSlot = _make_slot(&"source", 20)
	var destination: ItemSlot = _make_slot(&"destination", 20)

	source.set_stack(ItemStack.create(rope, 10))

	var result: ItemTransferResult = ItemTransferService.transfer(
		source,
		destination,
		3
	)

	_check(
		"7. A requested partial amount transfers",
		result.status == ItemTransferResult.Status.MOVED
			and result.amount_moved == 3
			and source.get_quantity() == 7
			and destination.get_quantity() == 3
	)


func _test_valid_swap() -> void:
	var grog: ItemDefinition = _make_definition(
		&"test_grog",
		1,
		[&"prepared_drink", &"service_item"]
	)

	var ale: ItemDefinition = _make_definition(
		&"test_ale",
		1,
		[&"prepared_drink", &"service_item"]
	)

	var source: ItemSlot = _make_slot(&"hands", 1)
	var destination: ItemSlot = _make_slot(&"bar_slot", 1)

	source.set_stack(ItemStack.create(grog, 1))
	destination.set_stack(ItemStack.create(ale, 1))

	var result: ItemTransferResult = ItemTransferService.transfer(
		source,
		destination
	)

	_check(
		"8. Two different valid items swap",
		result.status == ItemTransferResult.Status.SWAPPED
			and source.get_item_id() == &"test_ale"
			and destination.get_item_id() == &"test_grog"
	)


func _test_invalid_swap_changes_nothing() -> void:
	var keg: ItemDefinition = _make_definition(
		&"test_keg_swap",
		1,
		[&"drink_stock", &"bulky_item"]
	)

	var rag: ItemDefinition = _make_definition(
		&"test_rag_swap",
		1,
		[&"tool", &"small_item"]
	)

	# The destination only accepts small items, so the keg cannot go in.
	var source: ItemSlot = _make_slot(&"source", 1)
	var destination: ItemSlot = _make_slot(
		&"destination",
		1,
		[&"small_item"]
	)

	source.set_stack(ItemStack.create(keg, 1))
	destination.set_stack(ItemStack.create(rag, 1))

	var result: ItemTransferResult = ItemTransferService.transfer(
		source,
		destination
	)

	_check(
		"9. An invalid swap changes neither slot",
		not result.is_success()
			and source.get_item_id() == &"test_keg_swap"
			and destination.get_item_id() == &"test_rag_swap"
			and source.get_quantity() == 1
			and destination.get_quantity() == 1
	)


func _test_incompatible_metadata_does_not_merge() -> void:
	var wine: ItemDefinition = _make_definition(&"test_wine", 10)

	var source: ItemSlot = _make_slot(&"source", 10)
	var destination: ItemSlot = _make_slot(&"destination", 10)

	source.set_stack(
		ItemStack.create(wine, 2, {"vintage": 1712})
	)

	destination.set_stack(
		ItemStack.create(wine, 2, {"vintage": 1699})
	)

	var result: ItemTransferResult = ItemTransferService.transfer(
		source,
		destination
	)

	_check(
		"10. Stacks with different metadata do not merge",
		result.status == ItemTransferResult.Status.INCOMPATIBLE_STACKS
			and source.get_quantity() == 2
			and destination.get_quantity() == 2
			and int(destination.peek().metadata["vintage"]) == 1699
	)


func _test_stack_serialisation_round_trip() -> void:
	var registry: ItemRegistry = ItemRegistry.new()

	var salt: ItemDefinition = _make_definition(
		&"test_salt",
		30,
		[&"resource", &"trade_good"]
	)

	registry.register(salt)

	var original: ItemStack = ItemStack.create(
		salt,
		12,
		{"origin": "harbour"}
	)

	var data: Dictionary = original.to_dictionary()

	var restored: ItemStack = ItemStack.from_dictionary(
		data,
		registry
	)

	_check(
		"11. A stack serialises and restores",
		data["item_id"] == "test_salt"
			and restored.get_item_id() == &"test_salt"
			and restored.quantity == 12
			and restored.metadata.get("origin", "") == "harbour"
			and restored.definition == salt
	)


func _test_container_fills_merge_target_first() -> void:
	var barrel_hoop: ItemDefinition = _make_definition(&"test_hoop", 10)

	var container: ItemContainer = _make_container(
		&"test_store",
		3,
		10
	)

	container.get_slot(1).set_stack(
		ItemStack.create(barrel_hoop, 8)
	)

	var result: ItemTransferResult = container.add_item(
		barrel_hoop,
		5
	)

	# 2 top up slot 1, the remaining 3 open slot 0.
	_check(
		"12. A container fills matching stacks before empty slots",
		result.is_success()
			and result.amount_moved == 5
			and container.get_slot(1).get_quantity() == 10
			and container.get_slot(0).get_quantity() == 3
			and container.get_total_quantity(&"test_hoop") == 13
	)


func _test_container_serialisation_round_trip() -> void:
	var registry: ItemRegistry = ItemRegistry.new()

	var nail: ItemDefinition = _make_definition(&"test_nail", 50)
	registry.register(nail)

	var original: ItemContainer = _make_container(
		&"test_crate",
		4,
		50
	)

	original.get_slot(2).set_stack(ItemStack.create(nail, 17))

	var data: Dictionary = original.to_dictionary()

	var restored: ItemContainer = _make_container(
		&"test_crate",
		4,
		50
	)

	restored.from_dictionary(data, registry)

	_check(
		"13. A container serialises and restores to the same slots",
		restored.get_slot(2).get_quantity() == 17
			and restored.get_slot(2).get_item_id() == &"test_nail"
			and restored.get_slot(0).is_empty()
			and restored.get_total_quantity(&"test_nail") == 17
	)


func _test_no_duplication_or_loss() -> void:
	var plank: ItemDefinition = _make_definition(&"test_plank", 10)

	var source: ItemSlot = _make_slot(&"source", 10)
	var destination: ItemSlot = _make_slot(&"destination", 3)

	source.set_stack(ItemStack.create(plank, 10))

	var total_before: int = (
		source.get_quantity() + destination.get_quantity()
	)

	ItemTransferService.transfer(source, destination)
	ItemTransferService.transfer(source, destination)
	ItemTransferService.transfer(destination, source)

	var total_after: int = (
		source.get_quantity() + destination.get_quantity()
	)

	_check(
		"14. Repeated transfers neither duplicate nor lose items",
		total_before == 10 and total_after == 10
	)


func _test_registry_rejects_unknown_item() -> void:
	var registry: ItemRegistry = ItemRegistry.new()

	var restored: ItemStack = ItemStack.from_dictionary(
		{
			"item_id": "item_that_no_longer_exists",
			"quantity": 4,
		},
		registry
	)

	_check(
		"15. An unknown saved item loads as an empty stack",
		restored.is_empty() and registry.get_definition(&"nope") == null
	)


func _test_carrier_rules_reject_prepared_drink_in_inventory() -> void:
	var grog: ItemDefinition = _make_definition(
		&"test_grog_inventory",
		1,
		[&"prepared_drink", &"service_item"]
	)

	var rules: ItemSlotRules = ItemSlotRules.new()
	rules.capacity = 99
	rules.rejected_tags = [&"prepared_drink", &"bulky_item"]

	var backpack: ItemContainer = ItemContainer.new(
		&"test_backpack",
		12,
		rules
	)

	var result: ItemTransferResult = backpack.add_item(grog, 1)

	_check(
		"16. A personal inventory refuses prepared drinks",
		result.status == ItemTransferResult.Status.REJECTED_ITEM
			and backpack.is_empty()
	)


# --- Helpers -----------------------------------------------------------------

func _make_definition(
	item_id: StringName,
	maximum_stack_size: int = 1,
	tags: Array[StringName] = []
) -> ItemDefinition:
	var definition: ItemDefinition = ItemDefinition.new()

	definition.item_id = item_id
	definition.display_name = String(item_id).capitalize()
	definition.maximum_stack_size = maximum_stack_size
	definition.tags = tags

	return definition


func _make_slot(
	slot_id: StringName,
	capacity: int,
	accepted_tags: Array[StringName] = []
) -> ItemSlot:
	var rules: ItemSlotRules = ItemSlotRules.new()

	rules.capacity = capacity
	rules.accepted_tags = accepted_tags

	return ItemSlot.new(slot_id, rules)


func _make_container(
	container_id: StringName,
	slot_count: int,
	capacity: int
) -> ItemContainer:
	var rules: ItemSlotRules = ItemSlotRules.new()
	rules.capacity = capacity

	return ItemContainer.new(
		container_id,
		slot_count,
		rules
	)


func _check(
	test_name: String,
	condition: bool
) -> void:
	if condition:
		_tests_passed += 1
		print("  PASS  ", test_name)
		return

	_tests_failed += 1
	_failure_messages.append(test_name)
	print("  FAIL  ", test_name)
