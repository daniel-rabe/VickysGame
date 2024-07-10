extends InventorySlot
class_name HotbarSlot

const ACTIVE_COLOR = Color.WHITE
const UNACTIVE_COLOR = Color(.8,.8,.8,.6)

func set_highlighted(enabled: bool) -> void:
	modulate = UNACTIVE_COLOR if not enabled else ACTIVE_COLOR

func _ready() -> void:
	$NumberTextureRect/NumberLabel.text = str(get_index() + 1)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is InventorySlot and ItemConfig.get_item_resource(data.item_key).is_equippable
