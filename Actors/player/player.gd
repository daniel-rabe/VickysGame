extends CharacterBody3D
@export var normalSpeed := 3.0;
@export var sprintSpeed := 5.0;
@export var jumpVelocity := 4.0;
@export var gravity := 0.2;
@export var mouseSensitivity := 0.005;
@export var walking_energy_change_per_1m := -.05

@onready var head: Node3D = $Head
@onready var interaction_ray_cast: RayCast3D = $Head/InteractionRayCast
@onready var equippable_item_holder: Node3D = %EquippableItemHolder

func set_freeze(freeze: bool) -> void:
	set_process(!freeze)
	set_physics_process(!freeze)
	set_process_input(!freeze)
	set_process_unhandled_input(!freeze)


func move() -> void:
	if not is_on_floor():
		velocity.y -= gravity;

	var isSprinting := is_on_floor() && Input.is_action_pressed("sprint");
	var speed = sprintSpeed if isSprinting else normalSpeed;
	var inputDirection := Input.get_vector("move left", "move right", "move forward", "move backward");
	var direction := transform.basis * Vector3(inputDirection.x, 0.0, inputDirection.y);

	velocity.z = direction.z * speed;
	velocity.x = direction.x * speed;

	move_and_slide();

func check_walking_energy_change(delta: float) -> void:
	if velocity.x or velocity.z:
		EventSystem.PLA_change_energy.emit(
			delta *
			walking_energy_change_per_1m *
			Vector2(velocity.x, velocity.z).length()
		)

func look_around(relative: Vector2) -> void:
	rotate_y(-relative.x * mouseSensitivity);
	head.rotate_x(-relative.y * mouseSensitivity);
	head.rotation_degrees.x = clamp(head.rotation_degrees.x, -90, 90);

func _process(_arg: float) -> void:
	interaction_ray_cast.check_interaction();

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED;

func _physics_process(delta: float) -> void:
	move();
	check_walking_energy_change(delta)
	if Input.is_action_just_pressed("use item"):
		equippable_item_holder.try_to_use_item()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		look_around(event.relative);

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("open_crafting_menu"):
		EventSystem.BUL_create_bulletin.emit(BulletinConfig.Keys.CraftingMenu);
	elif event.is_action_pressed("item_hotkey"):
		EventSystem.EQU_hotkey_pressed.emit(int(event.as_text()))

func _enter_tree() -> void:
	EventSystem.PLA_freeze_player.connect(set_freeze.bind(true))
	EventSystem.PLA_unfreeze_player.connect(set_freeze.bind(false))
