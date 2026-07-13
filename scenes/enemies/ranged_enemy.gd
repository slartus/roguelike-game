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
# monster_level <= 0 → fallback на GameState.current_floor_number.
# Spawn-система задаёт monster_level > 0 через configure_spawn() ДО add_child(),
# чтобы _ready увидел уже финальный уровень и корректно применил Balance.scaled_*.
@export var monster_level: int = 0
# elite_rank прибавляется к effective monster level: champion +1, elite +2.
@export var elite_rank: int = 0
@export var fire_interval: float = 1.5
@export var bullet_scene: PackedScene
@export var pickup_scene: PackedScene
@export var pickup_drop_chance: float = 0.15
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

# Wander: пока цель вне perception, ranged не стоит столбом, а
# бродит случайно. Скорость понижена, чтобы визуально отличалось
# от активного kiting.
@export var wander_speed_ratio: float = 0.4
@export var wander_change_interval: float = 2.5
# Темпераменты: ID семейства и явный override (0 = catalog rolls).
@export var creature_type_id: StringName = &""
@export var temperament_id: StringName = &""

# Множители темпераментов — вынесены в const'ы, чтобы правки чисел шли
# одной точкой (те же значения продублированы в enemy.gd/charger.gd
# по своему набору полей — общее семейство описано в plans/).
const TEMPERAMENT_AGGRESSIVE_FIRE_INTERVAL_MULT: float = 0.85
const TEMPERAMENT_AGGRESSIVE_SPEED_MULT: float = 1.08
const TEMPERAMENT_AGGRESSIVE_RANGE_MULT: float = 0.90
const TEMPERAMENT_CAUTIOUS_PREFERRED_MULT: float = 1.15
const TEMPERAMENT_CAUTIOUS_MIN_MULT: float = 1.20
const TEMPERAMENT_CAUTIOUS_RETREAT_MULT: float = 1.20
const TEMPERAMENT_RESTLESS_WANDER_RATIO_MULT: float = 1.35
const TEMPERAMENT_RESTLESS_WANDER_INTERVAL_MULT: float = 0.60
const TEMPERAMENT_WATCHFUL_PERCEPTION_MULT: float = 1.30
const TEMPERAMENT_WATCHFUL_WANDER_RATIO_MULT: float = 0.80

var health: int
var temperament_seed: int = 0
# Множитель скорости отступления (dist < min_range). CAUTIOUS
# поднимает до 1.20; остальные — 1.0. Приближение и wander всегда
# используют базовую `speed`.
var retreat_speed_multiplier: float = 1.0
var _has_explicit_seed: bool = false
var _temperament_applied: bool = false
# Профиль вызова свиты (см. summoned_creature_profile.gd). Задаётся
# боссом ДО add_child() через configure_summon(). Подклассы (архер)
# читают arsenal_pool и max_damage, базовый класс — первое-выстрел
# delay, fire_interval override и reward-guard'ы.
var _summon_profile: SummonedCreatureProfile
var _target: Node2D
var _fire_timer: float = 0.0
var _stuck_timer: float = 0.0
var _escape_timer: float = 0.0
var _escape_direction: Vector2 = Vector2.ZERO
var _last_escape_side: float = 0.0
var _wander_direction: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemy")
	_apply_temperament()
	var level := get_effective_monster_level()
	max_health = Balance.scaled_hp(max_health, level)
	xp_reward = Balance.scaled_xp_reward(xp_reward, level)
	gold_reward = Balance.scaled_gold_reward(gold_reward, level)
	health = max_health
	# Summon guard: применяется ПОСЛЕ scaled_*, чтобы окончательные
	# rewards обнулились даже при mid-fight изменении Balance.
	if _summon_profile != null:
		if not _summon_profile.grants_xp:
			xp_reward = 0
		if not _summon_profile.grants_gold:
			gold_reward = 0
		if not _summon_profile.grants_drops:
			pickup_scene = null
		if _summon_profile.fire_interval_override > 0.0:
			fire_interval = _summon_profile.fire_interval_override
	# First-shot delay: свежий summon не должен стрелять почти мгновенно
	# — игроку нужно окно чтобы «заметить новый источник угрозы».
	# `_fire_timer` ловится каждый physics-frame в _physics_process:
	# пока > 0, выстрела нет.
	if _summon_profile != null and _summon_profile.first_attack_delay > 0.0:
		_fire_timer = _summon_profile.first_attack_delay
	else:
		_fire_timer = randf() * fire_interval

func get_effective_monster_level() -> int:
	return MonsterLevelUtil.effective_level(monster_level, elite_rank)

func configure_spawn(level: int, elite: int = 0, creature_seed: int = 0) -> void:
	monster_level = maxi(1, level)
	elite_rank = maxi(0, elite)
	temperament_seed = creature_seed
	_has_explicit_seed = true

func configure_summon(profile: SummonedCreatureProfile) -> void:
	# Вызвать ДО add_child(). После add_child() Godot запускает _ready(),
	# где стоит super._ready() → Balance.scaled_*, temperament resolve,
	# _fire_timer инициализация — «поздний» override уже не подхватится.
	_summon_profile = profile
	monster_level = maxi(1, profile.monster_level)
	elite_rank = maxi(0, profile.elite_rank)
	temperament_seed = 0
	_has_explicit_seed = true
	if profile.temperament_id != &"":
		temperament_id = profile.temperament_id

# Роль миньона в свите босса. Используется boss.gd для раздельного
# учёта живых minion'ов по квоте (3 melee / 2 ranged). Возвращает
# пустой StringName для обычного лучника вне boss-summon'а.
func get_summon_role() -> StringName:
	return _summon_profile.summon_role if _summon_profile != null else &""

func _apply_temperament() -> void:
	if _temperament_applied:
		return
	_temperament_applied = true
	var seed_value: int
	if _has_explicit_seed:
		seed_value = temperament_seed
	else:
		seed_value = CreatureTemperament.compute_fallback_seed(
			creature_type_id, global_position)
	temperament_id = CreatureTemperament.resolve_id(
		temperament_id, creature_type_id, seed_value)
	if temperament_id == &"":
		return
	_apply_temperament_modifiers()

func _apply_temperament_modifiers() -> void:
	match temperament_id:
		CreatureTemperament.AGGRESSIVE:
			fire_interval *= TEMPERAMENT_AGGRESSIVE_FIRE_INTERVAL_MULT
			speed *= TEMPERAMENT_AGGRESSIVE_SPEED_MULT
			preferred_range *= TEMPERAMENT_AGGRESSIVE_RANGE_MULT
			min_range *= TEMPERAMENT_AGGRESSIVE_RANGE_MULT
		CreatureTemperament.CAUTIOUS:
			preferred_range *= TEMPERAMENT_CAUTIOUS_PREFERRED_MULT
			min_range *= TEMPERAMENT_CAUTIOUS_MIN_MULT
			retreat_speed_multiplier = TEMPERAMENT_CAUTIOUS_RETREAT_MULT
		CreatureTemperament.RESTLESS:
			wander_speed_ratio = minf(1.0,
				wander_speed_ratio * TEMPERAMENT_RESTLESS_WANDER_RATIO_MULT)
			wander_change_interval *= TEMPERAMENT_RESTLESS_WANDER_INTERVAL_MULT
		CreatureTemperament.WATCHFUL:
			perception_radius *= TEMPERAMENT_WATCHFUL_PERCEPTION_MULT
			wander_speed_ratio *= TEMPERAMENT_WATCHFUL_WANDER_RATIO_MULT
		# PERSISTENT — не используется ranged-семейством в этой фиче.
		_:
			pass

func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = _find_player()
	if _target == null:
		_wander(delta)
		return

	var dist := global_position.distance_to(_target.global_position)
	if dist > perception_radius:
		# Игрок вне видимости — бродим, не стреляем. Раньше стояли
		# столбом на месте спавна, что выглядело как «выключенный NPC»,
		# особенно на больших этажах, где игрок долго добирается.
		_wander(delta)
		return

	# Kiting: приближаемся если далеко, отходим если близко.
	var to_player := (_target.global_position - global_position).normalized()
	var intended_dir: Vector2 = Vector2.ZERO
	var is_retreat := false
	if dist > preferred_range:
		intended_dir = to_player
	elif dist < min_range:
		intended_dir = -to_player
		is_retreat = true

	# Retreat_speed_multiplier применяется только при отступлении (dist <
	# min_range). Приближение и escape-fallback идут по базовой `speed` —
	# иначе CAUTIOUS-ranged догонял бы игрока быстрее обычного.
	var move_speed := speed
	if is_retreat:
		move_speed *= retreat_speed_multiplier

	if _escape_timer > 0.0:
		_escape_timer -= delta
		velocity = _escape_direction * move_speed
	elif intended_dir != Vector2.ZERO:
		velocity = intended_dir * move_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	_update_stuck_state(intended_dir, delta, move_speed)

	# Стрельба — всегда пока игрок в perception.
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = fire_interval
		_shoot()

func _update_stuck_state(intended_dir: Vector2, delta: float, desired_speed: float = -1.0) -> void:
	# Проверяем «застряли ли» только если реально пытались двигаться —
	# на ideal-range ranged-враг штатно стоит на месте, ложных срабатываний
	# быть не должно. desired_speed — фактическая целевая скорость
	# (базовая или retreat×multiplier), нужна чтобы CAUTIOUS-ranged не
	# ложно триггерил stuck при увеличенном отступе.
	var reference_speed := desired_speed if desired_speed > 0.0 else speed
	var wanted_to_move := intended_dir != Vector2.ZERO or _escape_timer > 0.0
	if wanted_to_move and velocity.length() < reference_speed * STUCK_VELOCITY_RATIO:
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

func _wander(delta: float) -> void:
	# Аналогично melee `enemy.gd::_wander`: случайное направление,
	# смена по таймеру или при упоре в стену. Скорость ×
	# wander_speed_ratio (0.4) — визуально «прогуливается», не бегает.
	# Fire timer НЕ убывает — стрелять надо только при активной цели.
	_wander_timer -= delta
	if _wander_timer <= 0.0 or _wander_direction == Vector2.ZERO:
		_pick_wander_direction()
	velocity = _wander_direction * speed * wander_speed_ratio
	move_and_slide()
	if velocity.length() < 1.0:
		_wander_direction = -_wander_direction.rotated(randf_range(-PI / 3.0, PI / 3.0))
		_wander_timer = 0.0

func _pick_wander_direction() -> void:
	var angle := randf() * TAU
	_wander_direction = Vector2.RIGHT.rotated(angle)
	_wander_timer = wander_change_interval

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
	_configure_bullet(bullet)
	get_tree().current_scene.add_child(bullet)

# Hook для подклассов (например skeleton_archer.gd) — тюнить только
# что созданный bullet перед добавлением в сцену: damage bonus,
# статусные эффекты, homing, etc.
func _configure_bullet(_bullet: Node) -> void:
	pass

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
