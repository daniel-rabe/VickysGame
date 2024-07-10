extends Node3D

@export var attributes : HittableObjectAttributes
@export var residue_static_body : StaticBody3D

@onready var item_spawn_points: Node3D = $ItemSpawnPoints

var current_health : float

func register_hit(weapon_item_resource : WeaponItemResource) -> void:
	if not attributes.weapon_filter.is_empty() and not weapon_item_resource.item_key in attributes.weapon_filter:
		return

	current_health -= weapon_item_resource.damage

	print(current_health)
	if current_health <= 0:
		die()

func die() ->  void:
	var scene = ItemConfig.get_pickuppable_item(attributes.drop_item_key)
	for marker in item_spawn_points.get_children():
		EventSystem.SPA_spawn_scene.emit(scene, marker.global_transform)
	if item_spawn_points == null:
		queue_free()
	else:
		for child in get_children():
			child.queue_free()
		add_child(residue_static_body)

func _ready() -> void:
	if item_spawn_points != null and residue_static_body != null:
		remove_child(residue_static_body)
	current_health = attributes.max_health
