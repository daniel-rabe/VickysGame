extends EquippableItem
class_name EquippableConstructable

const VALID_MATERIAL: StandardMaterial3D = preload("res://resources/materials/constructable_valid_material.tres")
const INVALID_MATERIAL: StandardMaterial3D = preload("res://resources/materials/constructable_invalid_material.tres")

@onready var item_place_ray: RayCast3D = $ItemPlaceRay
@onready var constructable_area: Area3D = $ConstructableArea
@onready var constructable_area_collision_shape: CollisionShape3D = $ConstructableArea/CollisionShape3D
@onready var constructable_preview_mesh: MeshInstance3D = $ConstructableArea/ConstructablePreviewMesh

var constructable_item_key: ItemConfig.Keys
var obstactles: Array[Node3D] = []
var place_valid := false
var is_constructing := false

func set_valid(value: bool) -> void:
	if value == place_valid:
		return
	set_preview_material(VALID_MATERIAL if value else INVALID_MATERIAL)
	place_valid = value

func check_build_validity() -> bool:
	if item_place_ray.is_colliding():
		constructable_area.global_position = item_place_ray.get_collision_point()
		return obstactles.is_empty()
	constructable_area.global_position = item_place_ray.to_global(item_place_ray.target_position)
	return false

func try_to_construct() -> void:
	if  not place_valid:
		return
	is_constructing = true
	EventSystem.EQU_delete_equipped_item.emit()
	constructable_area.hide()
	set_process(false)
	EventSystem.SPA_spawn_scene.emit(
		ItemConfig.get_constructable_scene(constructable_item_key),
		constructable_area.global_transform
	)

func destroy_self() -> void:
	if is_constructing:
		EventSystem.EQU_unequip_item.emit()

func set_preview_material(material: StandardMaterial3D) -> void:
	for surfaceIndex in constructable_preview_mesh.mesh.get_surface_count():
		constructable_preview_mesh.set_surface_override_material(surfaceIndex, material)

func _ready() -> void:
	constructable_area.rotation = Vector3.ZERO
	constructable_preview_mesh.mesh = $MeshHolder.get_child(0).mesh.duplicate()
	constructable_area_collision_shape.shape = constructable_preview_mesh.mesh.create_convex_shape()
	set_preview_material(INVALID_MATERIAL)

func _process(_delta: float) -> void:
	constructable_area.global_rotation.y = global_rotation.y + PI
	set_valid(check_build_validity())


func _on_constructable_area_body_entered(body: Node3D) -> void:
	obstactles.append(body)


func _on_constructable_area_body_exited(body: Node3D) -> void:
	obstactles.erase(body)
