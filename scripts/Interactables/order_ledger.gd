class_name OrderLedger
extends Node2D

## Physical management station used to place dependable stock orders.

@export var supplier: SupplierDefinition
@export var order_menu_scene: PackedScene


func get_interaction_display_name() -> String:
	return "Supply Ledger"


func get_interaction_actions(
	_request: InteractionRequest
) -> Array[InteractionAction]:
	var actions: Array[InteractionAction] = []

	var action: InteractionAction = InteractionAction.create(
		&"open_order_ledger",
		"Read",
		"Supply Ledger"
	)

	if supplier == null:
		action.as_unavailable("No supplier is assigned.")
	elif order_menu_scene == null:
		action.as_unavailable("The order form is unavailable.")
	elif _get_order_manager() == null:
		action.as_unavailable("The order system is unavailable.")

	actions.append(action)
	return actions


func perform_interaction(request: InteractionRequest) -> bool:
	if request.action_id != &"open_order_ledger":
		return false

	var order_manager: OrderManager = _get_order_manager()

	if order_manager == null:
		return false

	return InteractionMenu.open_menu(
		order_menu_scene,
		{
			"supplier": supplier,
			"order_manager": order_manager,
			"actor": request.actor,
			"source": self,
		}
	)


func _get_order_manager() -> OrderManager:
	return get_tree().get_first_node_in_group(
		&"order_manager"
	) as OrderManager
