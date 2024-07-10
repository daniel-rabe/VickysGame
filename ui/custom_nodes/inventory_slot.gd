extends TextureRect
class_name InventorySlot

@onready var icon_texture_rect: TextureRect = $MarginContainer/IconTextureRect

var item_key

func set_item_key(_item_key) -> void:
	item_key = _item_key
	updateIcon()

func updateIcon() -> void:
	if item_key == null:
		icon_texture_rect.texture = null
	else:
		var resource = ItemConfig.get_item_resource(item_key)
		icon_texture_rect.texture = resource == null if null else resource.icon

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_key == null:
		return null
	else:
		var drag_preview := TextureRect.new()
		drag_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drag_preview.custom_minimum_size = Vector2(80, 80)
		drag_preview.modulate = Color(1, 1, 1, .7)
		drag_preview.texture = icon_texture_rect.texture
		set_drag_preview(drag_preview)
		return self

func _can_drop_data(_at_position: Vector2, origin_slot: Variant) -> bool:
	if item_key != null and origin_slot is HotbarSlot:
		return ItemConfig.get_item_resource(item_key).is_equippable
	return origin_slot is InventorySlot

func _drop_data(_at_position: Vector2, origin_slot: Variant) -> void:
	EventSystem.INV_switch_two_item_indexes.emit(
		origin_slot.get_index(),
		origin_slot is HotbarSlot,
		get_index(),
		self is HotbarSlot
	)
