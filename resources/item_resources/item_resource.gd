extends Resource
class_name ItemResource

@export var item_key : ItemConfig.Keys
@export var display_name := "item name"
@export var icon : Texture2D
@export_multiline var description := "description"
# Whether an item can be equipped is not authored here. ItemConfig.is_equippable()
# derives it from EQUIPPABLE_ITEM_SCENES, so the answer cannot drift away from
# whether there is actually a held-item scene to instantiate.
