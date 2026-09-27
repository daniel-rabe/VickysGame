extends CharacterBody3D

const ANIM_BLEND = .2

enum State {
	Idle,
	Wander,
	Dead,
	Flee,
	Hurt,
	Chase,
	Attack
}

var state := State.Idle
var player_in_vision_range := false

@onready var idle_timer: Timer = %IdleTimer
@onready var wander_timer: Timer = %WanderTimer
@onready var disappear_after_death_timer: Timer = %DisappearAfterDeathTimer
@onready var flee_timer: Timer = %FleeTimer

@onready var player : CharacterBody3D = get_tree().get_first_node_in_group("Player")

@onready var main_collision_shape: CollisionShape3D = $CollisionShape3D
@onready var meat_spawn_marker: Marker3D = $MeatSpawnMarker
@onready var eyes_marker: Marker3D = $EyesMarker
@onready var animation_player: AnimationPlayer = %AnimationPlayer
@onready var attack_hit_area: Area3D = $AttackHitArea
@onready var navigation_agent_3d: NavigationAgent3D = $NavigationAgent3D
@onready var vision_area_collision_shape: CollisionShape3D = $VisionArea/VisionAreaCollisionShape

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
@export var flee_time := 3
@export var is_aggressive := false
@export var attacking_distance := 2.0
@export var damage := 20.0
@export var vision_range := 15
@export var vision_fov := 80.0
@export var gravity := 9.8 # m/s^2, matches the project's default_gravity

@onready var health := max_health

func animation_finished(_animation_name: String) -> void:
	match state:
		State.Idle:
			animation_player.play(idle_animations.pick_random(), ANIM_BLEND)
		State.Hurt:
			if not is_aggressive:
				set_state(State.Flee)
			else:
				set_state(State.Chase)
		State.Attack:
			set_state(State.Chase)

func look_forward() -> void:
	rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z) + PI, turn_speed_weight)

# Steering only ever sets the horizontal plane. Assigning `velocity` wholesale
# would wipe the vertical component and cancel gravity every frame.
func set_horizontal_velocity(direction: Vector3, speed: float) -> void:
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

func stop_horizontal_velocity() -> void:
	velocity.x = 0.0
	velocity.z = 0.0

func pick_wander_velocity() -> void:
	var direction := Vector2(0, -1).rotated(randf() * PI * 2) # -1 means forward
	set_horizontal_velocity(Vector3(direction.x, 0, direction.y), normal_speed)

func wander_loop() -> void:
	look_forward()

	if is_aggressive and can_see_player():
		set_state(State.Chase)

func idle_loop() -> void:
	if is_aggressive and can_see_player():
		set_state(State.Chase)

func flee_loop() -> void:
	look_forward()

func chase_loop() -> void:
	look_forward()
	if global_position.distance_to(player.global_position) < attacking_distance:
		return set_state(State.Attack)
	navigation_agent_3d.target_position = player.global_position
	var direction := global_position.direction_to(navigation_agent_3d.get_next_path_position())
	direction.y = 0
	set_horizontal_velocity(direction.normalized(), alarmed_speed)

func attack_loop() -> void:
	var direction := global_position.direction_to(player.global_position)
	rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z) + PI, turn_speed_weight)

func attack() -> void:
	if player in attack_hit_area.get_overlapping_bodies():
		EventSystem.PLA_change_health.emit(-damage)

func _physics_process(delta: float) -> void:
	# Gravity and move_and_slide sit outside the match so they run in every state,
	# including Hurt, which has no per-frame case: an animal hit mid-stride used to
	# hang motionless in the air until its flinch animation finished. Nothing
	# applied gravity at all before, so animals simply floated wherever they were.
	if not is_on_floor():
		velocity.y -= gravity * delta

	match state:
		State.Idle:
			idle_loop()
		State.Wander:
			wander_loop()
		State.Flee:
			flee_loop()
		State.Chase:
			chase_loop()
		State.Attack:
			attack_loop()

	move_and_slide()

func _ready() -> void:
	animation_player.animation_finished.connect(animation_finished)
	vision_area_collision_shape.shape.radius = vision_range

func pick_away_from_velocity() -> bool:
	if not player:
		return false

	var direction := player.global_position.direction_to(global_position)
	direction.y = 0
	set_horizontal_velocity(direction.normalized(), alarmed_speed)
	return true

func player_in_fov() -> bool:
	if not player:
		return false
	var direction_to_player := global_position.direction_to(player.global_position)
	var forward := -global_transform.basis.z
	return direction_to_player.angle_to(forward) <= deg_to_rad(vision_fov)

func can_see_player() -> bool:
	return player_in_vision_range and player_in_fov() and player_in_los()

func player_in_los() -> bool:
	if not player:
		return false
	# Aim at the player's head node when it is there, so the ray clears the
	# terrain the player is standing on; fall back to their origin otherwise.
	var player_head := player.get_node_or_null(^"Head") as Node3D
	var ray_target := player_head.global_position if player_head else player.global_position
	var query_params := PhysicsRayQueryParameters3D.new()
	query_params.from = eyes_marker.global_position
	query_params.to = ray_target
	query_params.collision_mask = 1 + 64 # ground + static_body
	var space_state := get_world_3d().direct_space_state
	return space_state.intersect_ray(query_params).is_empty()

func set_state(new_state: State) -> void:
	state = new_state
	# Every entry starts from a clean slate. Each branch used to stop the timers it
	# happened to remember, and Idle and Wander stopped none - so a flee_timer left
	# running would keep firing and drag the animal back to Idle every few seconds
	# for the rest of its life, cancelling each new Wander.
	idle_timer.stop()
	wander_timer.stop()
	flee_timer.stop()

	match state:
		State.Idle:
			stop_horizontal_velocity()
			idle_timer.start(randf_range(min_idle_time, max_idle_time))
			animation_player.play(idle_animations.pick_random(), ANIM_BLEND)
		State.Wander:
			pick_wander_velocity()
			wander_timer.start(randf_range(min_wander_time, max_wander_time))
			animation_player.play("Walk", ANIM_BLEND)
		State.Hurt:
			stop_horizontal_velocity()
			animation_player.play(hurt_animations.pick_random(), ANIM_BLEND)
		State.Flee:
			if (pick_away_from_velocity()):
				animation_player.play("Gallop", ANIM_BLEND)
				flee_timer.start(flee_time)
			else:
				set_state(State.Idle)
		State.Chase:
			animation_player.play("Gallop", ANIM_BLEND)
		State.Attack:
			stop_horizontal_velocity()
			animation_player.play("Attack", ANIM_BLEND)
		State.Dead:
			animation_player.play("Death", ANIM_BLEND)
			main_collision_shape.disabled = true
			var meat_scene = ItemConfig.get_pickuppable_item(ItemConfig.Keys.RawMeat)
			EventSystem.SPA_spawn_scene.emit(meat_scene, meat_spawn_marker.global_transform)
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

func _on_vision_area_body_entered(body: Node3D) -> void:
	if body == player:
		player_in_vision_range = true


func _on_vision_area_body_exited(body: Node3D) -> void:
	if body == player:
		player_in_vision_range = false
