extends CharacterBody2D

signal died_at(position: Vector2)

const SkeletonScene: PackedScene = preload("res://scenes/enemies/skeleton.tscn")

@export var display_name: String = "ENEMY_UNKNOWN"
@export var max_health: int = 30
@export var speed: float = 25.0
@export var perception_radius: float = 3000.0
@export var contact_damage: int = 3
@export var contact_cooldown: float = 0.8
@export var bullet_scene: PackedScene
@export var volley_interval: float = 2.0
@export var volley_count: int = 8
# Босс, помимо звёздочки-залпа, стреляет прицельным aimed-снарядом
# (как обычный лич — magic_bolt), с упреждением по вектору движения
# игрока. Отдельная пуля и таймер (`_aimed_fire_timer`), чтобы залп
# звёзд и прицельный выстрел жили независимо: reload одного никогда
# не влияет на другой, оба тикают параллельно каждый physics-frame.
@export var aimed_bullet_scene: PackedScene
@export var aimed_fire_interval: float = 1.0
@export var xp_reward: int = 40
@export var gold_reward: int = 20

# Призыв свиты: каждые SUMMON_COOLDOWN секунд топ-ап до SUMMON_COUNT
# живых скелетов вокруг босса. Кулдаун и каст длиннее чем у обычного
# лича — босс-битва должна дать игроку окно «босс колдует, добивай
# минионов пока не появились новые».
const SUMMON_COOLDOWN: float = 10.0
const SUMMON_CAST_DURATION: float = 1.2
const SUMMON_COUNT: int = 5
const SUMMON_OFFSET_MIN: float = 18.0
const SUMMON_OFFSET_MAX: float = 40.0
const SUMMON_TOWARD_PLAYER_ARC: float = TAU * 0.30
const SPAWN_ATTEMPTS_PER_MINION: int = 10
const FLOOR_TILE_SIZE: int = 20
const CAST_PULSE_FREQUENCY: float = PI * 8.0
const CAST_TINT_COLOR: Color = Color(0.7, 1.6, 0.85, 1.0)

# Скорость aimed-пули для расчёта упреждения. Должна соответствовать
# aimed_bullet_scene::speed (magic_bolt = 100). Как и в lich.gd, читаем
# через константу, не создаём инстанс bullet ради `.speed`.
const AIMED_BULLET_SPEED: float = 100.0

var health: int
var _target: Node2D
var _contact_timer: float = 0.0
var _volley_timer: float = 0.0
# Между залпами разворачиваем звёздочку на половину угла между лучами,
# чтобы визуально паттерн вращался и игрок не мог заучить статичные
# коридоры между пулями.
var _volley_index: int = 0
var _aimed_fire_timer: float = 0.0
var _minions: Array = []
# Стартовое значение = 0.0 → первый physics-тик сразу запустит каст
# первого батча. Босс с ходу колдует свиту, а не тратит 10 s на «зарядку»
# — игрок мгновенно видит роль призывателя. Каст (`SUMMON_CAST_DURATION`)
# всё ещё даёт окно на реакцию.
var _summon_cooldown_timer: float = 0.0
var _summon_cast_timer: float = 0.0
var _visual_base_modulate: Color = Color.WHITE

func _ready() -> void:
	add_to_group("enemy")
	var floor_num := GameState.current_floor_number
	max_health = Balance.scaled_hp(max_health, floor_num)
	contact_damage = Balance.scaled_damage(contact_damage, floor_num)
	xp_reward = Balance.scaled_xp_reward(xp_reward, floor_num)
	gold_reward = Balance.scaled_gold_reward(gold_reward, floor_num)
	health = max_health
	_volley_timer = volley_interval
	_aimed_fire_timer = aimed_fire_interval
	var visual: Sprite2D = get_node_or_null("Visual") as Sprite2D
	if visual != null:
		_visual_base_modulate = visual.modulate

func _physics_process(delta: float) -> void:
	_contact_timer = max(0.0, _contact_timer - delta)
	if _target == null or not is_instance_valid(_target):
		_target = _find_player()
	if _target == null:
		velocity = Vector2.ZERO
		return
	# Каст в приоритете: пока идёт, босс не двигается, не бьёт залпом
	# и не атакует контактом (velocity = 0 → move_and_collide без
	# перемещения ниже не выполняется). Даёт игроку окно.
	if _summon_cast_timer > 0.0:
		_tick_cast(delta)
		velocity = Vector2.ZERO
		return
	_maybe_start_summon(delta)
	if _summon_cast_timer > 0.0:
		velocity = Vector2.ZERO
		return

	_volley_timer -= delta
	_aimed_fire_timer -= delta

	var dir := (_target.global_position - global_position).normalized()
	velocity = dir * speed
	var collision := move_and_collide(velocity * delta)
	if collision:
		var collider := collision.get_collider()
		if collider and collider.is_in_group("player") and _contact_timer <= 0.0:
			if collider.has_method("take_damage"):
				collider.take_damage(contact_damage)
			_contact_timer = contact_cooldown

	if _volley_timer <= 0.0:
		_volley_timer = volley_interval
		_fire_volley()

	if _aimed_fire_timer <= 0.0:
		_aimed_fire_timer = aimed_fire_interval
		_fire_aimed_shot()

func _fire_volley() -> void:
	if bullet_scene == null:
		return
	for angle in _compute_volley_angles(_volley_index):
		var bullet := bullet_scene.instantiate()
		bullet.global_position = global_position
		bullet.direction = Vector2.RIGHT.rotated(angle)
		get_tree().current_scene.add_child(bullet)
	_volley_index += 1

# Углы залпа: каждый второй раз сдвиг на step/2, чтобы звёздочка
# вращалась между кадрами. Выделено в pure-функцию ради тестов.
func _compute_volley_angles(index: int) -> Array:
	var step := TAU / float(volley_count)
	var offset := step * 0.5 if index % 2 == 1 else 0.0
	var angles: Array = []
	for i in volley_count:
		angles.append(step * float(i) + offset)
	return angles

# Прицельный выстрел «как у лича» — magic_bolt с упреждением по вектору
# движения игрока. Формула идентична lich.gd::_compute_lead_direction,
# отдельная константа AIMED_BULLET_SPEED соответствует aimed_bullet_scene.
func _fire_aimed_shot() -> void:
	if aimed_bullet_scene == null or _target == null:
		return
	var target_velocity: Vector2 = Vector2.ZERO
	if _target is CharacterBody2D:
		target_velocity = _target.velocity
	var direction := _compute_lead_direction(_target.global_position, target_velocity)
	if direction == Vector2.ZERO:
		return
	var bullet := aimed_bullet_scene.instantiate()
	bullet.global_position = global_position
	bullet.direction = direction
	get_tree().current_scene.add_child(bullet)

# Pure-функция расчёта направления с упреждением. Копия формулы
# lich.gd::_compute_lead_direction — те же 5 строк, но со своей
# константой скорости пули (у босса magic_bolt speed = 100, у лича
# тоже 100 сейчас; хранятся раздельно, потому что aimed_bullet_scene
# у босса — отдельный export). Тестируется без спавна пули.
func _compute_lead_direction(target_pos: Vector2, target_velocity: Vector2) -> Vector2:
	var to_target := target_pos - global_position
	var distance := to_target.length()
	if distance <= 0.0:
		return Vector2.ZERO
	var time_to_hit := distance / AIMED_BULLET_SPEED
	var predicted := target_pos + target_velocity * time_to_hit
	return (predicted - global_position).normalized()

# --- Summon свиты -------------------------------------------------

func _maybe_start_summon(delta: float) -> void:
	_cleanup_minions()
	if _minions.size() >= SUMMON_COUNT:
		return
	_summon_cooldown_timer -= delta
	if _summon_cooldown_timer > 0.0:
		return
	_summon_cast_timer = SUMMON_CAST_DURATION

func _tick_cast(delta: float) -> void:
	_summon_cast_timer -= delta
	_apply_cast_visual()
	if _summon_cast_timer <= 0.0:
		_finish_cast()

func _finish_cast() -> void:
	_summon_cast_timer = 0.0
	_reset_cast_visual()
	# Топ-ап до SUMMON_COUNT: если жив k, спавним (SUMMON_COUNT − k).
	# Если ни одного места не нашлось (весь этаж стены), кулдаун
	# остался ≤ 0 — следующий тик снова запустит каст.
	var spawned := _summon_batch()
	if spawned > 0:
		_summon_cooldown_timer = SUMMON_COOLDOWN

func _summon_batch() -> int:
	_cleanup_minions()
	var parent := get_parent()
	if parent == null:
		return 0
	var missing := SUMMON_COUNT - _minions.size()
	var spawned := 0
	for i in missing:
		var pos := _pick_valid_spawn_position()
		if pos == Vector2.INF:
			break
		var skeleton = SkeletonScene.instantiate()
		skeleton.global_position = pos
		parent.add_child(skeleton)
		# Обнуляем награды ПОСЛЕ add_child. В _ready enemy.gd прогоняет
		# xp/gold через Balance.scaled_*_reward, где maxi(1, …)
		# превращает 0 в 1 — обнулять до add_child бесполезно.
		skeleton.xp_reward = 0
		skeleton.gold_reward = 0
		skeleton.pickup_scene = null
		_minions.append(skeleton)
		spawned += 1
	return spawned

func _cleanup_minions() -> void:
	var alive: Array = []
	for m in _minions:
		if m != null and is_instance_valid(m):
			alive.append(m)
	_minions = alive

func _pick_valid_spawn_position() -> Vector2:
	# Приоритет: сектор к игроку → миньоны становятся живым щитом
	# между Necromancer'ом и целью. Fallback: полный круг.
	var floor_node := get_tree().get_first_node_in_group("floor")
	if floor_node == null or floor_node.astar_grid == null:
		return global_position + _random_offset_in_arc(_direction_to_player())
	var toward_player := _direction_to_player()
	if toward_player != Vector2.ZERO:
		for i in SPAWN_ATTEMPTS_PER_MINION:
			var candidate := global_position + _random_offset_in_arc(toward_player)
			if _is_walkable(floor_node, candidate):
				return candidate
	for i in SPAWN_ATTEMPTS_PER_MINION:
		var candidate := global_position + _random_offset_in_arc(Vector2.ZERO)
		if _is_walkable(floor_node, candidate):
			return candidate
	return Vector2.INF

func _direction_to_player() -> Vector2:
	if _target == null or not is_instance_valid(_target):
		return Vector2.ZERO
	var diff := _target.global_position - global_position
	if diff == Vector2.ZERO:
		return Vector2.ZERO
	return diff.normalized()

func _random_offset_in_arc(center_dir: Vector2) -> Vector2:
	var base_angle: float
	if center_dir == Vector2.ZERO:
		base_angle = randf() * TAU
	else:
		var center_angle := center_dir.angle()
		base_angle = center_angle + randf_range(-SUMMON_TOWARD_PLAYER_ARC * 0.5, SUMMON_TOWARD_PLAYER_ARC * 0.5)
	var distance := randf_range(SUMMON_OFFSET_MIN, SUMMON_OFFSET_MAX)
	return Vector2(cos(base_angle), sin(base_angle)) * distance

func _is_walkable(floor_node: Node, pos: Vector2) -> bool:
	var cell := Vector2i(int(pos.x / FLOOR_TILE_SIZE), int(pos.y / FLOOR_TILE_SIZE))
	if not floor_node.astar_grid.is_in_boundsv(cell):
		return false
	return not floor_node.astar_grid.is_point_solid(cell)

func _apply_cast_visual() -> void:
	var visual := get_node_or_null("Visual") as Sprite2D
	if visual == null:
		return
	var progress := 1.0 - clampf(_summon_cast_timer / SUMMON_CAST_DURATION, 0.0, 1.0)
	var pulse := (sin(progress * CAST_PULSE_FREQUENCY) + 1.0) * 0.5
	var mix := clampf(0.3 + progress * 0.4 + pulse * 0.3, 0.0, 1.0)
	visual.modulate = _visual_base_modulate.lerp(CAST_TINT_COLOR, mix)

func _reset_cast_visual() -> void:
	var visual := get_node_or_null("Visual") as Sprite2D
	if visual != null:
		visual.modulate = _visual_base_modulate

# ------------------------------------------------------------------

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
		GameState.award_enemy_kill()
		queue_free()
