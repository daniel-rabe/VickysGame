extends Node3D

@onready var items: Node3D = $Items

func spawn_scene(scene : PackedScene, tform : Transform3D) -> void:
	var object := scene.instantiate()
	object.global_transform = tform
	items.add_child(object)

func _enter_tree() -> void:
	EventSystem.SPA_spawn_scene.connect(spawn_scene)
