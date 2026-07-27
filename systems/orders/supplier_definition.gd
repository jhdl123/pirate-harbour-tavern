class_name SupplierDefinition
extends Resource

## Configurable catalogue and delivery rules for one supplier.
##
## The order ledger uses a dependable harbour supplier today. A visiting trader
## can later use the same catalogue-entry model while supplying a temporary,
## limited or changing list of products.

@export_category("Identity")
@export var supplier_id: StringName = &""
@export var display_name: String = "Unnamed Supplier"
@export_multiline var description: String = ""

@export_category("Catalogue")
@export var entries: Array[OrderCatalogueEntry] = []

@export_category("Delivery")
@export_range(0, 30, 1)
var delivery_delay_days: int = 1


func get_entry(item_id: StringName) -> OrderCatalogueEntry:
	for entry: OrderCatalogueEntry in entries:
		if entry == null or entry.item == null:
			continue

		if entry.item.item_id == item_id:
			return entry

	return null


func is_valid() -> bool:
	if supplier_id.is_empty() or display_name.strip_edges().is_empty():
		return false

	for entry: OrderCatalogueEntry in entries:
		if entry != null and entry.is_valid():
			return true

	return false
