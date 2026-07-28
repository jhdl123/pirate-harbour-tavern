class_name StorageInventoryMenu
extends InteractionMenuView

var storage: StockStorage
var carrier: ItemCarrier
var list: VBoxContainer
var carried_label: Label
var message_label: Label

func _ready() -> void:
	_build_ui()

func setup(context: Dictionary) -> void:
	storage = context.get("storage") as StockStorage
	carrier = context.get("carrier") as ItemCarrier
	if storage != null and not storage.contents_changed.is_connected(_refresh):
		storage.contents_changed.connect(_refresh)
	_refresh()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.62)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 430)
	centre.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	margin.add_child(rows)
	var title := Label.new()
	title.text = "STOCK STORAGE"
	title.add_theme_font_size_override("font_size", 28)
	rows.add_child(title)
	carried_label = Label.new()
	rows.add_child(carried_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	rows.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	message_label = Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(message_label)
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	var deposit := Button.new()
	deposit.text = "Deposit carried item"
	deposit.pressed.connect(_deposit)
	buttons.add_child(deposit)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): request_close())
	buttons.add_child(close)

func _refresh() -> void:
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()
	if storage == null:
		message_label.text = "Storage is not configured."
		return
	var summary := storage.get_summary()
	if summary.is_empty():
		var empty := Label.new()
		empty.text = "Storage is empty."
		list.add_child(empty)
	for entry in summary:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s × %d" % [entry.display_name, entry.quantity]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var take := Button.new()
		take.text = "Take one"
		take.pressed.connect(_take.bind(entry.item_id))
		row.add_child(take)
		list.add_child(row)
	_update_carried()

func _update_carried() -> void:
	if carrier == null or not carrier.is_carrying():
		carried_label.text = "Carried: Empty"
	else:
		var stack := carrier.get_carried_stack()
		carried_label.text = "Carried: %s × %d" % [stack.get_display_name(), stack.quantity]

func _take(item_id: StringName) -> void:
	var result := storage.take_one(item_id, carrier)
	message_label.text = result.get_message()
	_refresh()

func _deposit() -> void:
	var result := storage.deposit_carried(carrier)
	message_label.text = result.get_message()
	_refresh()
