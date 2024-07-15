extends Node

const INVENTORY_SIZE = 28
const HOTBAR_SIZE = 9

var inventory: Array = []
var hotbar : Array = []

func get_free_slot() -> int:
	return inventory.find(null)

func add_item(key: ItemConfig.Keys) -> bool:
	var slot := get_free_slot()
	if slot > -1 && slot < INVENTORY_SIZE - 1:
		inventory[slot] = key
		send_inventory()
		return true
	return false

func try_to_pickup_item(key: ItemConfig.Keys, destroy_pickuppable: Callable) -> void:
	if add_item(key):
		destroy_pickuppable.call()
	else:
		pass # Todo: show message

func send_inventory() -> void:
	EventSystem.INV_inventory_updated.emit(inventory)

func send_hotbar() -> void:
	EventSystem.INV_hotbar_updated.emit(hotbar)

func switch_two_item_indexes(
	index1: int,
	isHotbar1: bool,
	index2: int,
	isHotbar2: bool,
) -> void:
	var item1 = hotbar[index1] if isHotbar1 else inventory[index1]
	var item2 = hotbar[index2] if isHotbar2 else inventory[index2]
	if isHotbar1:
		hotbar[index1] = item2
	else:
		inventory[index1] = item2

	if isHotbar2:
		hotbar[index2] = item1
	else:
		inventory[index2] = item1

	send_hotbar()
	send_inventory()

func delete_crafting_blueprint_costs(costs : Array[BlueprintCostData]) -> void:
	for cost in costs:
		for _amount in cost.amount:
			delete_item(cost.item_key)

func delete_item(item_key: ItemConfig.Keys) -> void:
	if not inventory.has(item_key):
		return

	var index = inventory.rfind(item_key)
	if index != -1:
		inventory[index] = null

func delete_item_by_index(index: int, inHotbar: bool) -> void:
	if inHotbar:
		hotbar[index] = null
		send_hotbar()
	else:
		inventory[index] = null
		send_inventory()

func _enter_tree() -> void:
	EventSystem.INV_try_to_pickup_item.connect(try_to_pickup_item)
	EventSystem.INV_ask_update_inventory.connect(send_inventory)
	EventSystem.INV_switch_two_item_indexes.connect(switch_two_item_indexes)
	EventSystem.INV_add_item.connect(add_item)
	EventSystem.INV_delete_crafting_blueprint_costs.connect(delete_crafting_blueprint_costs)
	EventSystem.INV_delete_item_by_index.connect(delete_item_by_index)

func _ready() -> void:
	inventory.resize(INVENTORY_SIZE)
	hotbar.resize(HOTBAR_SIZE)
	inventory[0] = ItemConfig.Keys.Axe
	inventory[1] = ItemConfig.Keys.Pickaxe
	inventory[2] = ItemConfig.Keys.Tent
