extends Node

const INVENTORY_SIZE = 28
const HOTBAR_SIZE = 9

var inventory: Array = []
var hotbar : Array = []

func get_free_slot() -> int:
	return inventory.find(null)

func add_item(key: ItemConfig.Keys) -> bool:
	# get_free_slot() already returns -1 when the inventory is full, so an upper
	# bound is redundant - and at INVENTORY_SIZE - 1 it rejected the valid last
	# slot, making the inventory one slot smaller than advertised.
	var slot := get_free_slot()
	if slot > -1:
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

# Crafting has to be one checked operation. Previously the menu emitted "delete
# the costs" and "add the result" as two independent signals and could not see
# that the second one failed, so a craft into a full inventory consumed the
# materials and produced nothing.
func craft_item(item_key: ItemConfig.Keys) -> bool:
	var blueprint := ItemConfig.get_item_blueprint(item_key)
	if blueprint == null:
		return false

	var total_cost := 0
	for cost in blueprint.costs:
		if inventory.count(cost.item_key) < cost.amount:
			return false
		total_cost += cost.amount

	# The result needs one slot. Consuming the costs frees total_cost of them,
	# so only a costless recipe can actually run out of room.
	if inventory.count(null) + total_cost < 1:
		return false

	delete_crafting_blueprint_costs(blueprint.costs)
	return add_item(item_key)

func delete_crafting_blueprint_costs(costs : Array[BlueprintCostData]) -> void:
	for cost in costs:
		for _amount in cost.amount:
			delete_item(cost.item_key)
	# delete_item() is silent on purpose so a multi-item removal broadcasts once,
	# but the removal as a whole must not leave listeners showing stale contents.
	send_inventory()

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
	EventSystem.INV_craft_item.connect(craft_item)
	EventSystem.INV_delete_item_by_index.connect(delete_item_by_index)

func _ready() -> void:
	inventory.resize(INVENTORY_SIZE)
	hotbar.resize(HOTBAR_SIZE)
	inventory[0] = ItemConfig.Keys.Axe
	inventory[1] = ItemConfig.Keys.Pickaxe
	inventory[2] = ItemConfig.Keys.Tent
	# Broadcast the starting state, otherwise every listener keeps the empty
	# array it was built with: the hotbar UI stays blank and EquippedItemManager
	# indexes into a zero-length hotbar on the first hotkey press.
	#
	# Deferred on purpose. The stage (and this manager with it) is added from
	# StageController._ready(), which runs before the HUD's own _ready(), so
	# broadcasting here directly would reach hotbar slots whose @onready node
	# references are still null. By the end of the frame the whole tree is ready.
	send_inventory.call_deferred()
	send_hotbar.call_deferred()
