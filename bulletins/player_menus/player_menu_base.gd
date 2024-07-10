extends Bulletin
class_name PlayerMenuBase
@onready var inventory_grid_container: GridContainer = %InventoryGridContainer
@onready var item_description_label: Label = %ItemDescriptionLabel
@onready var item_extra_info_label: Label = %ItemExtraInfoLabel

func update_inventory(inventory: Array) -> void:
	for i in inventory.size():
		if inventory_grid_container.get_child_count() > i:
			inventory_grid_container.get_child(i).set_item_key(inventory[i])

func close() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventSystem.BUL_destroy_bulletin.emit(BulletinConfig.Keys.CraftingMenu)
	EventSystem.PLA_unfreeze_player.emit()

func show_item_info(inventory_slot: InventorySlot) -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or inventory_slot.item_key == null:
		return
	var resource: ItemResource = ItemConfig.get_item_resource(inventory_slot.item_key)
	item_description_label.text = resource.display_name + "\n" + resource.description

func hide_item_info() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	item_description_label.text = ""

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventSystem.PLA_freeze_player.emit()
	EventSystem.INV_ask_update_inventory.emit()
	for inventorySlot in inventory_grid_container.get_children():
		if inventorySlot is InventorySlot:
			inventorySlot.mouse_entered.connect(show_item_info.bind(inventorySlot))
			inventorySlot.mouse_exited.connect(hide_item_info)
	for hotbar_slot in get_tree().get_nodes_in_group("HotbarSlots"):
		hotbar_slot.mouse_entered.connect(show_item_info.bind(hotbar_slot))
		hotbar_slot.mouse_exited.connect(hide_item_info)


func _enter_tree() -> void:
	EventSystem.INV_inventory_updated.connect(update_inventory)
