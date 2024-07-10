extends Node

func _ready() -> void:
	change_stage(StageConfig.Keys.Island)

func change_stage(key: StageConfig.Keys) -> void:
	for child in get_children():
		child.queue_free()
	var newStage := StageConfig.get_stage(key)
	if newStage is Node:
		add_child(newStage)
