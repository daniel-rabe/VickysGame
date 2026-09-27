extends Node

var bulletins := {}

func create_bulletin(key: BulletinConfig.Keys, extra_arg = null) -> void:
	# Asking for a bulletin that already exists refreshes it rather than doing
	# nothing, so a caller can update its contents in place. Destroying and
	# recreating would leave both copies drawn for the frame before the old one
	# is freed. Bulletin.initialize() is a no-op by default, so this only affects
	# bulletins that actually implement it.
	if bulletins.has(key):
		bulletins[key].initialize(extra_arg);
		return
	var new_bulletin := BulletinConfig.get_bulletin(key);
	new_bulletin.initialize(extra_arg);
	add_child(new_bulletin);
	bulletins[key] = new_bulletin;

func destroy_bulletin(key: BulletinConfig.Keys) -> void:
	if bulletins.has(key):
		bulletins[key].queue_free();
		bulletins.erase(key);

func _enter_tree() -> void:
	EventSystem.BUL_create_bulletin.connect(create_bulletin);
	EventSystem.BUL_destroy_bulletin.connect(destroy_bulletin);
