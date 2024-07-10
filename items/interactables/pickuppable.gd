extends Interactable

class_name Pickuppable;

@export var itemKey : ItemConfig.Keys;

@onready var parent : Node3D = get_parent();

func start_interaction() -> void:
	EventSystem.INV_try_to_pickup_item.emit(itemKey, destroy_self)

func destroy_self() -> void:
	parent.queue_free()
