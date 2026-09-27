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

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_crafting_menu"):
		# Mark it handled before closing. close() unfreezes the player, which
		# re-enables their own _unhandled_key_input; letting the same Esc reach
		# them would toggle the mouse straight back to visible.
		get_viewport().set_input_as_handled()
		close()

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
	# This menu is created from the player's own key handler, so start deaf and
	# listen from the next frame on: otherwise the keypress that opened the menu
	# could also be the one that closes it.
	set_process_unhandled_key_input(false)
	call_deferred("set_process_unhandled_key_input", true)
	for inventorySlot in inventory_grid_container.get_children():
		if inventorySlot is InventorySlot:
			inventorySlot.mouse_entered.connect(show_item_info.bind(inventorySlot))
			inventorySlot.mouse_exited.connect(hide_item_info)
	for hotbar_slot in get_tree().get_nodes_in_group("HotbarSlots"):
		hotbar_slot.mouse_entered.connect(show_item_info.bind(hotbar_slot))
		hotbar_slot.mouse_exited.connect(hide_item_info)


func _enter_tree() -> void:
	EventSystem.INV_inventory_updated.connect(update_inventory)
