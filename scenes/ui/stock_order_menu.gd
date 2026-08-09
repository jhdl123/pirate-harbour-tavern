class_name StockOrderMenu
extends InteractionMenuView

## Stock ordering form opened by the physical supply ledger.

const ROW_NAME_WIDTH: float = 250.0
const PRICE_WIDTH: float = 90.0
const QUANTITY_WIDTH: float = 54.0
const SUBTOTAL_WIDTH: float = 100.0

@onready var supplier_label: Label = %SupplierLabel
@onready var description_label: Label = %DescriptionLabel
@onready var balance_label: Label = %BalanceLabel
@onready var row_list: VBoxContainer = %RowList
@onready var total_label: Label = %TotalLabel
@onready var status_label: Label = %StatusLabel
@onready var confirm_button: Button = %ConfirmButton
@onready var cancel_button: Button = %CancelButton

var supplier: SupplierDefinition = null
var order_manager: OrderManager = null

var _quantities: Dictionary = {}
var _quantity_labels: Dictionary = {}
var _subtotal_labels: Dictionary = {}
var _controls: Array[Control] = []
var _submitted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	confirm_button.pressed.connect(_submit_order)
	cancel_button.pressed.connect(_close_menu)


func setup(context: Dictionary) -> void:
	super.setup(context)

	supplier = context.get("supplier") as SupplierDefinition
	order_manager = context.get("order_manager") as OrderManager

	if supplier == null or order_manager == null:
		status_label.text = "The order form is not configured."
		confirm_button.disabled = true
		return

	supplier_label.text = supplier.display_name
	description_label.text = supplier.description

	_build_catalogue()
	_refresh_summary()

	confirm_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_close_menu()
		get_viewport().set_input_as_handled()


## Registry used to name containers and contents in the catalogue.
##
## Filled-container offers have no ItemDefinition to read a name from, so the
## display text is composed from the beverage registry instead. Missing it is
## not fatal - the entry falls back to its raw ids.
func _get_beverage_registry() -> BeverageRegistry:
	for node in get_tree().get_nodes_in_group(&"beverage_storage"):
		var storage := node as BeverageStorage

		if storage != null and storage.registry != null:
			return storage.registry

	return null


func _build_catalogue() -> void:
	for child: Node in row_list.get_children():
		child.queue_free()

	_quantities.clear()
	_quantity_labels.clear()
	_subtotal_labels.clear()
	_controls.clear()

	for entry: OrderCatalogueEntry in supplier.entries:
		if entry == null or not entry.is_valid():
			continue

		var item_id: StringName = entry.get_offer_id()
		_quantities[item_id] = 0

		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row_list.add_child(row)

		var item_label: Label = Label.new()
		item_label.custom_minimum_size.x = ROW_NAME_WIDTH
		item_label.text = entry.get_display_name(_get_beverage_registry())
		item_label.tooltip_text = entry.get_detail_text(_get_beverage_registry())
		row.add_child(item_label)

		var price_label: Label = Label.new()
		price_label.custom_minimum_size.x = PRICE_WIDTH
		price_label.text = "£%d each" % entry.get_unit_price()
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(price_label)

		var minus_button: Button = Button.new()
		minus_button.text = "−"
		minus_button.custom_minimum_size = Vector2(38, 34)
		minus_button.pressed.connect(
			_change_quantity.bind(entry, -1)
		)
		row.add_child(minus_button)
		_controls.append(minus_button)

		var quantity_label: Label = Label.new()
		quantity_label.custom_minimum_size.x = QUANTITY_WIDTH
		quantity_label.text = "0"
		quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(quantity_label)
		_quantity_labels[item_id] = quantity_label

		var plus_button: Button = Button.new()
		plus_button.text = "+"
		plus_button.custom_minimum_size = Vector2(38, 34)
		plus_button.pressed.connect(
			_change_quantity.bind(entry, 1)
		)
		row.add_child(plus_button)
		_controls.append(plus_button)

		var subtotal_label: Label = Label.new()
		subtotal_label.custom_minimum_size.x = SUBTOTAL_WIDTH
		subtotal_label.text = "£0"
		subtotal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(subtotal_label)
		_subtotal_labels[item_id] = subtotal_label


func _change_quantity(
	entry: OrderCatalogueEntry,
	change: int
) -> void:
	if _submitted or entry == null:
		return

	var item_id: StringName = entry.get_offer_id()
	var current_quantity: int = int(_quantities.get(item_id, 0))
	var new_quantity: int = clampi(
		current_quantity + change,
		0,
		entry.get_maximum_quantity()
	)

	_quantities[item_id] = new_quantity

	var quantity_label: Label = _quantity_labels.get(item_id) as Label
	var subtotal_label: Label = _subtotal_labels.get(item_id) as Label

	if quantity_label != null:
		quantity_label.text = str(new_quantity)

	if subtotal_label != null:
		subtotal_label.text = "£%d" % (
			new_quantity * entry.get_unit_price()
		)

	status_label.text = ""
	_refresh_summary()


func _refresh_summary() -> void:
	var total: int = _calculate_total()
	var balance: int = 0

	if order_manager != null and order_manager.economy_manager != null:
		balance = order_manager.economy_manager.get_money()

	balance_label.text = "Available funds: £%d" % balance
	total_label.text = "Order total: £%d" % total

	confirm_button.disabled = (
		_submitted
		or total <= 0
		or total > balance
	)

	if not _submitted and total > balance:
		status_label.text = "You cannot afford this order."


func _calculate_total() -> int:
	if supplier == null:
		return 0

	var total: int = 0

	for entry: OrderCatalogueEntry in supplier.entries:
		if entry == null:
			continue

		var quantity: int = int(
			_quantities.get(entry.get_offer_id(), 0)
		)

		total += quantity * entry.get_unit_price()

	return total


func _submit_order() -> void:
	if _submitted or order_manager == null:
		return

	var result: Dictionary = order_manager.submit_order(
		supplier,
		_quantities
	)

	status_label.text = String(result.get("message", ""))

	if not bool(result.get("success", false)):
		_refresh_summary()
		return

	_submitted = true
	confirm_button.disabled = true
	confirm_button.text = "Order placed"
	cancel_button.text = "Close"

	for control: Control in _controls:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if control is Button:
			(control as Button).disabled = true

	_refresh_summary()


func _close_menu() -> void:
	request_close({"order_submitted": _submitted})
