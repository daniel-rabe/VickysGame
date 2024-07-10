extends PlayerMenuBase
@onready var crafting_button_container: GridContainer = %CraftingButtonContainer
@export var crafting_button_scene : PackedScene

func show_crafting_info(item_key: ItemConfig.Keys) -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or item_key == null:
		return
	var resource := ItemConfig.get_item_resource(item_key)
	item_description_label.text = resource.display_name + "\n" + resource.description

	var blueprint := ItemConfig.get_item_blueprint(item_key)
	var texts := [
		"Requirements:",
		"Tinderbox" if blueprint.needs_tinderbox else "",
		"Multitool" if blueprint.needs_multitool else "",
	]
	for cost_resource in blueprint.costs:
		texts.append("%s: %d" % [
			ItemConfig.get_item_resource(cost_resource.item_key).display_name,
			cost_resource.amount
		])
	item_extra_info_label.text = "\n".join(texts.filter(isNotEmpty))

func isNotEmpty(_value: String) -> bool:
	return _value != null and _value != ""

func hide_crafting_info() -> void:
	item_description_label.text = ""
	item_extra_info_label.text = ""

func hide_item_info() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	item_description_label.text = ""

func crafting_button_pressed(item_key: ItemConfig.Keys) -> void:
	EventSystem.INV_delete_crafting_blueprint_costs.emit(
		ItemConfig.get_item_blueprint(item_key).costs
	)
	EventSystem.INV_add_item.emit(item_key)

func update_inventory(inventory: Array) -> void:
	super(inventory)
	for crafting_button in crafting_button_container.get_children():
		var costs = ItemConfig.get_item_blueprint(crafting_button.item_key).costs
		var disable_button := false
		for cost_data in costs:
			if inventory.count(cost_data.item_key) < cost_data.amount:
				disable_button = true
				break
		crafting_button.button.disabled = disable_button

func _ready() -> void:
	for craftable_item_key in ItemConfig.CRAFTABLE_ITEM_KEYS:
		var crafting_button := crafting_button_scene.instantiate()
		crafting_button_container.add_child(crafting_button)
		crafting_button.set_item_key(craftable_item_key)
		crafting_button.button.mouse_entered.connect(show_crafting_info.bind(crafting_button.item_key))
		crafting_button.button.mouse_exited.connect(hide_crafting_info)
		crafting_button.button.pressed.connect(crafting_button_pressed.bind(crafting_button.item_key))
	super()
