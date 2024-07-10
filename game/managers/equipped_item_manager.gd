extends Node

var active_hotbar_slot
var hotbar : Array

func hotbar_updated(temp_hotbar: Array) -> void:
	hotbar = temp_hotbar

func hotbar_pressed(hotkey: int) -> void:
	var hotbar_index = hotkey - 1
	if hotbar[hotbar_index] == null:
		return
	if active_hotbar_slot != hotbar_index:
		active_hotbar_slot = hotbar_index
		EventSystem.EQU_equip_item.emit(hotbar[hotbar_index])
		EventSystem.EQU_active_hotbar_slot_updated.emit(hotbar_index)
	else:
		active_hotbar_slot = null
		EventSystem.EQU_unequip_item.emit()
		EventSystem.EQU_active_hotbar_slot_updated.emit(null)

func delete_equipped_item() -> void:
	EventSystem.INV_delete_item_by_index.emit(active_hotbar_slot, true)
	EventSystem.EQU_active_hotbar_slot_updated.emit(null)
	active_hotbar_slot = null

func _ready() -> void:
	EventSystem.EQU_active_hotbar_slot_updated.emit(null)

func _enter_tree() -> void:
	EventSystem.INV_hotbar_updated.connect(hotbar_updated)
	EventSystem.EQU_hotkey_pressed.connect(hotbar_pressed)
	EventSystem.EQU_delete_equipped_item.connect(delete_equipped_item)
