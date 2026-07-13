extends BossBase

# Первый босс башни. Классический некромант: медленный маг, стреляющий
# по кругу «звёздочкой» dark_orb, попутно бьющий прицельным magic_bolt
# с упреждением и периодически призывающий 3+2 свиту скелетов.
#
# Всё что здесь — специфично для Некроманта. Lifecycle (health, death,
# reward, spawn context, phase helper) вынесен в `BossBase`.

const SkeletonScene: PackedScene = preload("res://scenes/enemies/skeleton.tscn")
const SkeletonArcherScene: PackedScene = preload("res://scenes/enemies/ranged_enemy.tscn")
const SkeletonArsenal = preload("res://scenes/enemies/skeleton_arsenal.gd")

# Stable attack IDs — используются как payload для BossBase.attack_started /
# attack_resolved и для будущей аналитики. Совпадают с планом.
const ATTACK_AIMED_PROJECTILE: StringName = &"aimed_projectile"
const ATTACK_RADIAL_VOLLEY: StringName = &"radial_volley"
const ATTACK_SUMMON_MINIONS: StringName = &"summon_minions"
const ATTACK_CONTACT: StringName = &"contact"

@export var speed: float = 25.0
@export var perception_radius: float = 3000.0
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

# Призыв свиты: каждые SUMMON_COOLDOWN секунд топ-ап до SUMMON_COUNT
# живых скелетов вокруг босса. Кулдаун и каст длиннее чем у обычного
# лича — босс-битва должна дать игроку окно «босс колдует, добивай
# минионов пока не появились новые».
#
# Композиция фиксированная: 3 melee скелета + 2 archer'а. Квоты
# отслеживаются раздельно, чтобы гибель конкретной роли пополнялась
# именно этой ролью, а не случайной подменой. Cм. `plans/necromancer-minion-rebalance`.
const SUMMON_COOLDOWN: float = 10.0
const SUMMON_CAST_DURATION: float = 1.2
const SUMMON_MELEE_COUNT: int = 3
const SUMMON_RANGED_COUNT: int = 2
const SUMMON_COUNT: int = SUMMON_MELEE_COUNT + SUMMON_RANGED_COUNT
const SUMMON_OFFSET_MIN: float = 18.0
const SUMMON_OFFSET_MAX: float = 40.0
const SUMMON_TOWARD_PLAYER_ARC: float = TAU * 0.30
const SPAWN_ATTEMPTS_PER_MINION: int = 10
const FLOOR_TILE_SIZE: int = 20
const CAST_PULSE_FREQUENCY: float = PI * 8.0
const CAST_TINT_COLOR: Color = Color(0.7, 1.6, 0.85, 1.0)

# Formation anchors — расстояния от босса до слотов свиты. Melee
# фронтом между боссом и игроком, ranged на флангах чуть позади,
# чтобы образовать перекрёстный огонь.
const FORMATION_MELEE_FORWARD_SIDE: float = 28.0
const FORMATION_MELEE_FORWARD_CENTER: float = 34.0
const FORMATION_MELEE_SIDE_OFFSET: float = 22.0
const FORMATION_RANGED_BACKWARD: float = 10.0
const FORMATION_RANGED_SIDE_OFFSET: float = 56.0

# Каппы и параметры summon-профилей. Держим здесь, а не в
# summoned_creature_profile.gd — этот файл владеет конкретной свитой
# Некроманта; профиль-тип нейтрален к параметрам.
const MINION_MELEE_MAX_DAMAGE: int = 3
const MINION_RANGED_MAX_DAMAGE: int = 2
const MINION_RANGED_FIRE_INTERVAL: float = 2.1
const MINION_RANGED_FIRST_SHOT_DELAY: float = 1.0

# Скорость aimed-пули для расчёта упреждения. Должна соответствовать
# aimed_bullet_scene::speed (magic_bolt = 100). Как и в lich.gd, читаем
# через константу, не создаём инстанс bullet ради `.speed`.
const AIMED_BULLET_SPEED: float = 100.0

var _target: Node2D
var _contact_timer: float = 0.0
var _volley_timer: float = 0.0
# Между залпами разворачиваем звёздочку на половину угла между лучами,
# чтобы визуально паттерн вращался и игрок не мог заучить статичные
# коридоры между пулями.
var _volley_index: int = 0
var _aimed_fire_timer: float = 0.0
# Раздельное отслеживание живых миньонов: melee (3) и ranged (2).
# Гибель melee пополняется melee, гибель ranged — ranged. Общий
# счётчик через `_minions` больше не подходит: раньше при 3 melee +
# 2 ranged смерть melee'а компенсировалась бы случайным minion'ом,
# что ломало композицию 3/2.
var _melee_minions: Array = []
var _ranged_minions: Array = []
# Стартовое значение = 0.0 → первый physics-тик сразу запустит каст
# первого батча. Босс с ходу колдует свиту, а не тратит 10 s на «зарядку»
# — игрок мгновенно видит роль призывателя. Каст (`SUMMON_CAST_DURATION`)
# всё ещё даёт окно на реакцию.
var _summon_cooldown_timer: float = 0.0
var _summon_cast_timer: float = 0.0

func _ready() -> void:
	# base._ready(): группа, floor scaling для max_health / contact_damage /
	# xp / gold, health = max_health, visual_base_modulate.
	super()
	_volley_timer = volley_interval
	_aimed_fire_timer = aimed_fire_interval

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
				collider.take_damage(contact_damage, DamageContext.from_enemy_attack(self, ATTACK_CONTACT))
				attack_resolved.emit(ATTACK_CONTACT, true)
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
	attack_started.emit(ATTACK_RADIAL_VOLLEY)
	for angle in _compute_volley_angles(_volley_index):
		var bullet := bullet_scene.instantiate()
		bullet.global_position = global_position
		bullet.direction = Vector2.RIGHT.rotated(angle)
		bullet.source_enemy = self
		bullet.attack_id = &"volley"
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
	attack_started.emit(ATTACK_AIMED_PROJECTILE)
	var bullet := aimed_bullet_scene.instantiate()
	bullet.global_position = global_position
	bullet.direction = direction
	bullet.source_enemy = self
	bullet.attack_id = &"aimed_shot"
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
#
# Композиция фиксированная: 3 melee + 2 archer. Квоты пополняются
# раздельно — если игрок сначала выбил всех melee, следующий каст
# создаёт именно melee, а не рандомную подмену. Профили миньонов
# заданы через `SummonedCreatureProfile`, что убирает случайное
# iron-оружие / полный floor-scaling / farm-rewards, из-за которых
# призванные скелеты могли наносить 6-7 damage при 5 HP игрока.

func _maybe_start_summon(delta: float) -> void:
	_cleanup_minions()
	if _total_alive_minions() >= SUMMON_COUNT:
		return
	_summon_cooldown_timer -= delta
	if _summon_cooldown_timer > 0.0:
		return
	_summon_cast_timer = SUMMON_CAST_DURATION
	attack_started.emit(ATTACK_SUMMON_MINIONS)

func _tick_cast(delta: float) -> void:
	_summon_cast_timer -= delta
	_apply_cast_visual()
	if _summon_cast_timer <= 0.0:
		_finish_cast()

func _finish_cast() -> void:
	_summon_cast_timer = 0.0
	_reset_cast_visual()
	# Топ-ап раздельно: недостающие melee → melee, недостающие
	# ranged → ranged. Cм. plans/necromancer-minion-rebalance.
	# Если ни одного места не нашлось (весь этаж стены), кулдаун
	# остался ≤ 0 — следующий тик снова запустит каст.
	var spawned := _summon_batch()
	if spawned > 0:
		_summon_cooldown_timer = SUMMON_COOLDOWN
		attack_resolved.emit(ATTACK_SUMMON_MINIONS, true)
	else:
		attack_resolved.emit(ATTACK_SUMMON_MINIONS, false)

func _summon_batch() -> int:
	_cleanup_minions()
	var parent := get_parent()
	if parent == null:
		return 0
	var spawned := 0
	var missing_melee: int = maxi(0, SUMMON_MELEE_COUNT - _melee_minions.size())
	for slot in missing_melee:
		var pos := _pick_melee_position(_melee_minions.size())
		if pos == Vector2.INF:
			break
		var minion := _spawn_melee_at(pos, parent)
		if minion == null:
			break
		_melee_minions.append(minion)
		spawned += 1
	var missing_ranged: int = maxi(0, SUMMON_RANGED_COUNT - _ranged_minions.size())
	for slot in missing_ranged:
		var pos := _pick_ranged_position(_ranged_minions.size())
		if pos == Vector2.INF:
			break
		var minion := _spawn_ranged_at(pos, parent)
		if minion == null:
			break
		_ranged_minions.append(minion)
		spawned += 1
	return spawned

func _spawn_melee_at(pos: Vector2, parent: Node) -> Node:
	var skeleton = SkeletonScene.instantiate()
	# configure_summon() задаёт monster_level=1 / rewards=off / arsenal
	# pool / max_damage cap / temperament override ДО _ready(). Без
	# этого призванный скелет полу-fallback скейлился по boss floor 5
	# и мог случайно получить iron sword с 6-7 damage.
	skeleton.configure_summon(_build_melee_profile())
	skeleton.global_position = pos
	parent.add_child(skeleton)
	_record_spawned_analytics(skeleton)
	return skeleton

func _spawn_ranged_at(pos: Vector2, parent: Node) -> Node:
	var archer = SkeletonArcherScene.instantiate()
	archer.configure_summon(_build_ranged_profile())
	archer.global_position = pos
	parent.add_child(archer)
	_record_spawned_analytics(archer)
	return archer

func _record_spawned_analytics(spawned_enemy: Node) -> void:
	var enemy_id: StringName = &"unknown"
	if spawned_enemy.scene_file_path != "":
		enemy_id = StringName(spawned_enemy.scene_file_path.get_file().get_basename())
	var temperament: StringName = &""
	if "temperament_id" in spawned_enemy:
		temperament = StringName(str(spawned_enemy.temperament_id))
	var rank: int = 0
	if "elite_rank" in spawned_enemy:
		rank = int(spawned_enemy.elite_rank)
	Analytics.record_enemy_spawned(enemy_id, temperament, rank)

func _build_melee_profile() -> SummonedCreatureProfile:
	var p := SummonedCreatureProfile.new()
	p.summon_owner_id = &"necromancer"
	p.summon_role = &"melee"
	p.monster_level = 1
	p.elite_rank = 0
	p.grants_xp = false
	p.grants_gold = false
	p.grants_drops = false
	# aggressive исключён: тот же speed×1.12 + cooldown×0.85 в паре с
	# 3-мя melee и залпами босса даёт слишком плотный pressure. Оставляем
	# двух умеренных: persistent (упорнее преследует) и watchful (шире
	# perception, тише при wander).
	p.allowed_temperaments = [
		CreatureTemperament.PERSISTENT,
		CreatureTemperament.WATCHFUL,
	]
	p.temperament_id = _pick_from_allowed(p.allowed_temperaments)
	p.arsenal_pool = SkeletonArsenal.NECROMANCER_MINION_MELEE
	p.max_damage = MINION_MELEE_MAX_DAMAGE
	return p

func _build_ranged_profile() -> SummonedCreatureProfile:
	var p := SummonedCreatureProfile.new()
	p.summon_owner_id = &"necromancer"
	p.summon_role = &"ranged"
	p.monster_level = 1
	p.elite_rank = 0
	p.grants_xp = false
	p.grants_gold = false
	p.grants_drops = false
	# aggressive исключён: fire_interval×0.85 + range×0.90 сокращают
	# окно уклонения; при двух ranged + boss projectiles это слишком.
	p.allowed_temperaments = [
		CreatureTemperament.CAUTIOUS,
		CreatureTemperament.WATCHFUL,
	]
	p.temperament_id = _pick_from_allowed(p.allowed_temperaments)
	p.arsenal_pool = SkeletonArsenal.NECROMANCER_MINION_RANGED
	p.max_damage = MINION_RANGED_MAX_DAMAGE
	p.first_attack_delay = MINION_RANGED_FIRST_SHOT_DELAY
	p.fire_interval_override = MINION_RANGED_FIRE_INTERVAL
	return p

func _pick_from_allowed(allowed: Array[StringName]) -> StringName:
	if allowed.is_empty():
		return &""
	return allowed[randi() % allowed.size()]

func _cleanup_minions() -> void:
	_melee_minions = _cleanup_role_list(_melee_minions)
	_ranged_minions = _cleanup_role_list(_ranged_minions)

func _cleanup_role_list(list: Array) -> Array:
	var alive: Array = []
	for m in list:
		if m != null and is_instance_valid(m):
			alive.append(m)
	return alive

func _total_alive_minions() -> int:
	return _melee_minions.size() + _ranged_minions.size()

# Formation-slots. Melee фронтом (лево / центр / право между боссом
# и игроком), ranged на флангах чуть позади. Позиции ищутся по
# fallback-спирали, если основной anchor попал в стену или в
# существующего minion'а.
func _pick_melee_position(slot_index: int) -> Vector2:
	var forward := _direction_to_player()
	if forward == Vector2.ZERO:
		return _pick_fallback_position()
	var right := forward.orthogonal()
	var anchors := [
		global_position + forward * FORMATION_MELEE_FORWARD_SIDE + right * -FORMATION_MELEE_SIDE_OFFSET,
		global_position + forward * FORMATION_MELEE_FORWARD_CENTER,
		global_position + forward * FORMATION_MELEE_FORWARD_SIDE + right * FORMATION_MELEE_SIDE_OFFSET,
	]
	var anchor: Vector2 = anchors[slot_index % anchors.size()]
	return _find_walkable_near(anchor)

func _pick_ranged_position(slot_index: int) -> Vector2:
	var forward := _direction_to_player()
	if forward == Vector2.ZERO:
		return _pick_fallback_position()
	var right := forward.orthogonal()
	var anchors := [
		global_position - forward * FORMATION_RANGED_BACKWARD + right * -FORMATION_RANGED_SIDE_OFFSET,
		global_position - forward * FORMATION_RANGED_BACKWARD + right * FORMATION_RANGED_SIDE_OFFSET,
	]
	var anchor: Vector2 = anchors[slot_index % anchors.size()]
	return _find_walkable_near(anchor)

# Ищет walkable-клетку рядом с anchor: если сам anchor подходит —
# возвращает его, иначе разлетается по спирали с шагом
# `FLOOR_TILE_SIZE`. Fallback — прежний random-arc.
func _find_walkable_near(anchor: Vector2) -> Vector2:
	var floor_node := get_tree().get_first_node_in_group("floor")
	if floor_node == null or floor_node.astar_grid == null:
		return anchor
	if _is_walkable(floor_node, anchor):
		return anchor
	for radius_step in 3:
		var radius := FLOOR_TILE_SIZE * (radius_step + 1)
		for angle_deg in range(0, 360, 30):
			var candidate := anchor + Vector2.RIGHT.rotated(deg_to_rad(angle_deg)) * radius
			if _is_walkable(floor_node, candidate):
				return candidate
	return _pick_fallback_position()

# Fallback на случай, если formation-anchor'ы все в стенах: старый
# random-arc paths вокруг босса. Не Vector2.INF — иначе миньон не
# заспавнится вовсе, а мы гарантируем attempt.
func _pick_fallback_position() -> Vector2:
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
