class_name DrinkData
extends Resource


@export_category("Identity")
@export var item_type: ItemType.Type = ItemType.Type.GROG
@export var display_name: String = "Grog"

@export_category("Economy")
@export var sale_price: int = 5

@export_category("Timing")
@export var drink_duration: float = 8.0

@export_category("Visuals")
@export var order_icon_texture: Texture2D
@export var carried_texture: Texture2D
@export var full_glass_texture: Texture2D
@export var empty_glass_texture: Texture2D
@export var broken_glass_texture: Texture2D

@export_category("Breakage")
@export var break_chance_multiplier: float = 1.0
