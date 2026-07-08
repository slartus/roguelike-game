extends CharacterBody2D

# Ranged (Skeleton Archer, Lich). Двигается по kite-паттерну: держится
# на preferred_range дистанции от игрока и стреляет когда игрок в
# perception_radius.
#
# States (implicit):
# - Idle: игрок вне perception → стоим, не стреляем.
# - Close-in: dist > preferred_range → идём к игроку.
# - Retreat: dist < min_range → отходим спиной.
# - Fire: min_range <= dist <= preferred_range → стоим и стреляем.

signal died_at(position: Vector2)

@export var display_name: String = "ENEMY_UNKNOWN"
@export var max_health: int = 2
@export var fire_interval: float = 1.5
@export var bullet_scene: PackedScene
@export var pickup_scene: PackedScene
@export var pickup_drop_chance: float = 0.3
@export var xp_reward: int = 7
@export var gold_reward: int = 2
@export var perception_radius: float = 200.0
@export var speed: float = 30.0
@export var preferred_range: float = 160.0
@export var min_range: float = 100.0

# Stuck detection: у ranged-врагов нет A* и они ходят по прямой. Если
# упёрлись в стену при попытке подойти/отойти — через STUCK_TIMEOUT
# уходим в escape (перпендикуляр к player-line) на ESCAPE_DURATION.
const STUCK_VELOCITY_RATIO: float = 0.15
const STUCK_TIMEOUT: float = 0.3
const ESCAPE_DURATION: float = 0.4

var health: int
var _target: Node2D
var _fire_timer: float = 0.0
var _stuck_timer: float = 0.0
var _escape_timer: float = 0.0
var _escape_direction: Vector2 = Vector2.ZERO
var _last_escape_side: float = 0.0

func _ready() -> void:
	add_to_group("enemy")
	var floor_num := GameState.current_floor_number
	max_health = Balance.scaled_hp(max_health, floor_num)
	xp_reward = Balance.scaled_xp_reward(xp_reward, floor_num)
	gold_reward = Balance.scaled_gold_reward(gold_reward, floor_num)
	health = max_health
	_fire_timer = randf() * fire_interval

func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = _find_player()
	if _target == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var dist := global_position.distance_to(_target.global_position)
	if dist > perception_radius:
		# Игрок вне видимости — не двигаемся, не стреляем.
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Kiting: приближаемся если далеко, отходим если близко.
	var to_player := (_target.global_position - global_position).normalized()
	var intended_dir: Vector2 = Vector2.ZERO
	if dist > preferred_range:
		intended_dir = to_player
	elif dist < min_range:
		intended_dir = -to_player

	if _escape_timer > 0.0:
		_escape_timer -= delta
		velocity = _escape_direction * speed
	elif intended_dir != Vector2.ZERO:
		velocity = intended_dir * speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	_update_stuck_state(intended_dir, delta)

	# Стрельба — всегда пока игрок в perception.
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = fire_interval
		_shoot()

func _update_stuck_state(intended_dir: Vector2, delta: float) -> void:
	# Проверяем «застряли ли» только если реально пытались двигаться —
	# на ideal-range ranged-враг штатно стоит на месте, ложных срабатываний
	# быть не должно.
	var wanted_to_move := intended_dir != Vector2.ZERO or _escape_timer > 0.0
	if wanted_to_move and velocity.length() < speed * STUCK_VELOCITY_RATIO:
		_stuck_timer += delta
		if _stuck_timer >= STUCK_TIMEOUT and _escape_timer <= 0.0:
			_escape_direction = _pick_escape_direction(intended_dir)
			_escape_timer = ESCAPE_DURATION
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0
		# Успешно двигаемся — сброс side, чтобы разрешить случайный
		# выбор при следующем застревании.
		_last_escape_side = 0.0

func _pick_escape_direction(intended_dir: Vector2) -> Vector2:
	var base := intended_dir if intended_dir != Vector2.ZERO else Vector2.RIGHT
	# При повторном застревании сразу пробуем противоположную сторону.
	var side: float
	if _last_escape_side != 0.0:
		side = -_last_escape_side
	else:
		side = 1.0 if randf() > 0.5 else -1.0
	_last_escape_side = side
	return base.rotated(side * PI / 2.0)

func _shoot() -> void:
	if bullet_scene == null or _target == null:
		return
	var direction := (_target.global_position - global_position).normalized()
	if direction == Vector2.ZERO:
		return
	var bullet := bullet_scene.instantiate()
	bullet.global_position = global_position
	bullet.direction = direction
	get_tree().current_scene.add_child(bullet)

func _find_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

func take_damage(amount: int) -> void:
	health -= amount
	modulate = Color(1, 0.5, 0.5)
	await get_tree().create_timer(0.08).timeout
	if is_inside_tree():
		modulate = Color.WHITE
	if health <= 0 and is_inside_tree():
		died_at.emit(global_position)
		EventLog.log_kill(display_name, xp_reward, gold_reward)
		GameState.award_xp(xp_reward)
		GameState.award_gold(gold_reward)
		_drop_pickup()
		queue_free()

func _drop_pickup() -> void:
	if pickup_scene == null:
		return
	if randf() > pickup_drop_chance:
		return
	var pickup := pickup_scene.instantiate()
	pickup.global_position = global_position
	get_tree().current_scene.add_child.call_deferred(pickup)
