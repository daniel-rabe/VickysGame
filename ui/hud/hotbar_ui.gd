extends HBoxContainer

func update_hotbar(hotbar: Array) -> void:
	for slot in get_children():
		slot.set_item_key(hotbar[slot.get_index()])

func active_slot_updated(hotbar_slot_index) -> void:
	for hotbar_slot in get_children():
		hotbar_slot.set_highlighted(hotbar_slot.get_index() == hotbar_slot_index)

func _enter_tree() -> void:
	EventSystem.INV_hotbar_updated.connect(update_hotbar)
	EventSystem.EQU_active_hotbar_slot_updated.connect(active_slot_updated)
