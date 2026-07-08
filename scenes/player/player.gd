extends CharacterBody2D

signal health_changed(current: int, maximum: int)

@export var speed: float = 90.0
@export var bullet_scene: PackedScene
@export var fire_interval: float = 0.25

var max_health: int
var health: int
var _fire_cooldown: float = 0.0

func _ready() -> void:
	add_to_group("player")
	max_health = GameState.player_max_health
	health = clampi(GameState.player_health, 1, max_health)
	health_changed.emit(health, max_health)

func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_vector * speed
	move_and_slide()

	_fire_cooldown = max(0.0, _fire_cooldown - delta)
	if Input.is_action_pressed("attack") and _fire_cooldown <= 0.0:
		_shoot_towards_mouse()
		_fire_cooldown = fire_interval

func _shoot_towards_mouse() -> void:
	if bullet_scene == null:
		return
	var direction := (get_global_mouse_position() - global_position).normalized()
	if direction == Vector2.ZERO:
		return
	var bullet := bullet_scene.instantiate()
	bullet.global_position = global_position
	bullet.direction = direction
	get_tree().current_scene.add_child(bullet)

func take_damage(amount: int) -> void:
	health = max(0, health - amount)
	GameState.player_health = health
	health_changed.emit(health, max_health)
	modulate = Color(1, 0.5, 0.5)
	await get_tree().create_timer(0.1).timeout
	if is_inside_tree():
		modulate = Color.WHITE
	if health == 0:
		_die()

func heal(amount: int) -> void:
	health = min(max_health, health + amount)
	GameState.player_health = health
	health_changed.emit(health, max_health)

func _die() -> void:
	GameState.reset_run()
	get_tree().reload_current_scene()
