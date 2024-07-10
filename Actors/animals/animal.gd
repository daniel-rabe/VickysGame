extends CharacterBody3D

const ANIM_BLEND = .2

enum State {
	Idle,
	Wander,
	Dead,
	Flee,
	Hurt
}

var state := State.Idle

@onready var idle_timer: Timer = %IdleTimer
@onready var wander_timer: Timer = %WanderTimer
@onready var disappear_after_death_timer: Timer = %DisappearAfterDeathTimer
@onready var flee_timer: Timer = %FleeTimer

@onready var player : CharacterBody3D = get_tree().get_first_node_in_group("Player")

@onready var main_collision_shape: CollisionShape3D = $CollisionShape3D
@onready var meat_spawn_marker: Marker3D = $MeatSpawnMarker
@onready var animation_player: AnimationPlayer = %AnimationPlayer

@export var max_health := 80.0
@export var normal_speed := .6
@export var alarmed_speed := 1.8
@export var idle_animations: Array[String] = []
@export var hurt_animations: Array[String] = []
@export var turn_speed_weight := .07
@export var min_idle_time := 2.0
@export var max_idle_time := 7.0
@export var min_wander_time := 2.0
@export var max_wander_time := 4.0
@export var is_aggressive := false
@export var flee_time := 3

@onready var health := max_health

func animation_finished(_animation_name: String) -> void:
	if state == State.Idle:
		animation_player.play(idle_animations.pick_random(), ANIM_BLEND)
	elif state == State.Hurt:
		if not is_aggressive:
			set_state(State.Flee)

func look_forward() -> void:
	rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z) + PI, turn_speed_weight)

func pick_wander_velocity() -> void:
	var direction := Vector2(0, -1).rotated(randf() * PI * 2) # -1 means forward
	velocity = Vector3(direction.x, 0, direction.y) * normal_speed

func wander_loop() -> void:
	look_forward()
	move_and_slide()

func flee_loop() -> void:
	look_forward()
	move_and_slide()

func _physics_process(_delta: float) -> void:
	if state == State.Wander:
		wander_loop()
	elif state == State.Flee:
		flee_loop()

func _ready() -> void:
	animation_player.animation_finished.connect(animation_finished)

func pick_away_from_velocity() -> bool:
	if not player:
		return false

	var direction := player.global_position.direction_to(global_position)
	direction.y = 0
	velocity = direction.normalized() * alarmed_speed
	return true

func set_state(new_state: State) -> void:
	state = new_state
	match state:
		State.Idle:
			idle_timer.start(randf_range(min_idle_time, max_idle_time))
			animation_player.play(idle_animations.pick_random(), ANIM_BLEND)
		State.Wander:
			pick_wander_velocity()
			wander_timer.start(randf_range(min_wander_time, max_wander_time))
			animation_player.play("Walk", ANIM_BLEND)
		State.Hurt:
			idle_timer.stop()
			wander_timer.stop()
			flee_timer.stop()
			animation_player.play(hurt_animations.pick_random(), ANIM_BLEND)
		State.Flee:
			if (pick_away_from_velocity()):
				animation_player.play("Gallop", ANIM_BLEND)
				flee_timer.start(flee_time)
			else:
				set_state(State.Idle)
		State.Dead:
			animation_player.play("Death", ANIM_BLEND)
			main_collision_shape.disabled = true
			var meat_scene = ItemConfig.get_pickuppable_item(ItemConfig.Keys.RawMeat)
			EventSystem.SPA_spawn_scene.emit(meat_scene, meat_spawn_marker.global_transform)
			idle_timer.stop()
			wander_timer.stop()
			flee_timer.stop()
			set_physics_process(false)
			disappear_after_death_timer.start(10)

func _on_idle_timer_timeout() -> void:
	set_state(State.Wander)


func _on_wander_timer_timeout() -> void:
	set_state(State.Idle)


func _on_disappear_after_death_timer_timeout() -> void:
	queue_free()

func _on_flee_timer_timeout() -> void:
	set_state(State.Idle)

func take_hit(weapon_item_resource: WeaponItemResource) -> void:
	health -= weapon_item_resource.damage
	if state != State.Dead and health <= 0:
		set_state(State.Dead)
	elif not state in [State.Flee, State.Dead]:
		set_state(State.Hurt)

