extends BossBase

# Necromancer — третий босс башни (этаж 15, ritual_crypt basement-арена).
# Проверка на приоритет целей, контроль свиты, чтение phase-меняющегося
# projectile pressure и использование summon-окна для отхода/дамажа.
#
# Дизайн-инварианты (см. plans/boss-roadmap-claude-plans/04_necromancer_third_boss_rework.md):
# - Одна атака за раз — scheduler state machine (choose → telegraph →
#   resolve → recovery); mutual exclusion aimed / radial / summon.
# - Фазы по HP: 1 = 100–60% (без radial), 2 = 60–25% (aimed + radial),
#   3 = 25–0% (быстрее cadence, короче summon cooldown).
# - Damage caps: aimed <= 3, radial <= 1, minions <= 3 melee / 2 arrow.
# - Radial и aimed не выпускаются одновременно; после radial минимум
#   RADIAL_MIN_PAUSE секунд без aimed.
# - Свита: фиксировано 3 melee + 2 ranged; квоты пополняются раздельно;
#   миньоны не приносят XP/gold/drops (см. plans/necromancer-minion-rebalance).
# - Boss-specific RNG детерминирован по (tower_seed, floor) — реплеи стабильны.
# - Cleanup on death: DEAD-стейт останавливает scheduler; ни каст, ни залп,
#   ни aimed не должны стартовать после смерти босса.

const SkeletonScene: PackedScene = preload("res://scenes/enemies/skeleton.tscn")
const SkeletonArcherScene: PackedScene = preload("res://scenes/enemies/ranged_enemy.tscn")
const SkeletonArsenal = preload("res://scenes/enemies/skeleton_arsenal.gd")

# Stable attack IDs — payload для BossBase.attack_started / attack_resolved
# и DamageContext. Игрок, аналитика и тесты читают эти slug'и как контракт.
const ATTACK_AIMED_PROJECTILE: StringName = &"aimed_projectile"
const ATTACK_RADIAL_VOLLEY: StringName = &"radial_volley"
const ATTACK_SUMMON_MINIONS: StringName = &"summon_minions"
const ATTACK_CONTACT: StringName = &"contact"

# --- Movement / senses ----------------------------------------------------
@export var speed: float = 25.0
@export var perception_radius: float = 3000.0
@export var contact_cooldown: float = 0.8
@export var bullet_scene: PackedScene
@export var aimed_bullet_scene: PackedScene

# --- Bullet configuration (radial + aimed) --------------------------------
# Radial: 8 лучей, damage <= 1 (плановый cap). Каждый второй залп сдвинут
# на step/2, чтобы звёздочка визуально вращалась.
const RADIAL_BULLET_COUNT: int = 8
const RADIAL_BULLET_DAMAGE: int = 1
const AIMED_BULLET_DAMAGE_PHASE1: int = 2
const AIMED_BULLET_DAMAGE_PHASE23: int = 3

# Скорость aimed-пули (magic_bolt = 100) — для расчёта упреждения. Хранится
# как константа, а не читается из instance bullet — не создаём инстанс ради
# `.speed`. Идентично lich.gd::_compute_lead_direction.
const AIMED_BULLET_SPEED: float = 100.0

# --- Scheduler cadence ----------------------------------------------------
# Aimed shot: базовая cadence phase 1/2, ускоренная phase 3. Cadence — это
# gap между двумя aimed'ами; фактическая частота = AIMED_INTERVAL +
# AIMED_TELEGRAPH + AIMED_RECOVERY.
const AIMED_TELEGRAPH: float = 0.45
const AIMED_RECOVERY: float = 0.35
const AIMED_INTERVAL_PHASE1: float = 1.8
const AIMED_INTERVAL_PHASE2: float = 1.8
const AIMED_INTERVAL_PHASE3: float = 1.2

# Radial: telegraph короче cast'а призыва, но с явной визуальной волной.
# Активен только в phase 2+. После radial минимум RADIAL_MIN_PAUSE секунд
# любая атака недоступна — плановый инвариант «no radial → aimed → radial
# spam».
const RADIAL_TELEGRAPH: float = 0.7
const RADIAL_RECOVERY: float = 0.6
const RADIAL_INTERVAL: float = 3.0
const RADIAL_MIN_PAUSE: float = 0.6

# Summon: cooldown длиннее, чтобы окно каста не совпадало с окном aimed'а.
# Phase 3 сокращает cooldown ради нарастающего давления, но композицию
# 3+2 не расширяет (плановый инвариант «не увеличивать minion count»).
const SUMMON_COOLDOWN_PHASE12: float = 10.0
const SUMMON_COOLDOWN_PHASE3: float = 7.5
const SUMMON_CAST_DURATION: float = 1.2
const SUMMON_RECOVERY: float = 0.5
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

# Formation anchors — расстояния от босса до слотов свиты. Melee фронтом
# между боссом и игроком, ranged на флангах чуть позади, чтобы образовать
# перекрёстный огонь и не окружить игрока сразу.
const FORMATION_MELEE_FORWARD_SIDE: float = 28.0
const FORMATION_MELEE_FORWARD_CENTER: float = 34.0
const FORMATION_MELEE_SIDE_OFFSET: float = 22.0
const FORMATION_RANGED_BACKWARD: float = 10.0
const FORMATION_RANGED_SIDE_OFFSET: float = 56.0

# Каппы миньонов. Живут здесь, а не в summoned_creature_profile.gd — этот
# файл владеет конкретной свитой Некроманта; профиль-тип нейтрален к числам.
const MINION_MELEE_MAX_DAMAGE: int = 3
const MINION_RANGED_MAX_DAMAGE: int = 2
const MINION_RANGED_FIRE_INTERVAL: float = 2.1
const MINION_RANGED_FIRST_SHOT_DELAY: float = 1.0

# --- Phase thresholds -----------------------------------------------------
# Плановые границы: 60% и 25%. Переход через каждый порог — visible
# PHASE_TRANSITION-стейт (пауза scheduler'а, визуальная вспышка).
const PHASE_2_HP_FRACTION: float = 0.60
const PHASE_3_HP_FRACTION: float = 0.25
const PHASE_TRANSITION_DURATION: float = 0.75
const TRANSITION_PULSE_FREQ: float = PI * 6.0
const TRANSITION_TINT_COLOR: Color = Color(0.85, 0.55, 1.5, 1.0)

# --- States. Flat enum — все переходы видны в _tick_state ----------------
enum State {
	IDLE,
	APPROACH,
	AIMED_TELEGRAPH,
	AIMED_RECOVERY,
	RADIAL_TELEGRAPH,
	RADIAL_RECOVERY,
	SUMMON_CAST,
	SUMMON_RECOVERY,
	PHASE_TRANSITION,
	DEAD,
}

var _state: State = State.IDLE
var _state_timer: float = 0.0
var _current_attack: StringName = &""
var _target: Node2D
var _contact_timer: float = 0.0

# Timers-кулдауны на выбор следующей атаки. Тикают в APPROACH; вне
# APPROACH они не двигаются, поэтому cooldown реально «пауза до следующего
# APPROACH-выбора», а не глобальная. Это даёт scheduler'у явное mutual
# exclusion: пока идёт telegraph/recovery одной атаки, другая свою очередь
# не пропустит.
# Aimed стартует не мгновенно (плановый инвариант «no instant shot on
# spawn»): полный interval * 0.5 даёт задержку >= AIMED_TELEGRAPH, чтобы
# у игрока было окно среагировать на телеграф первого выстрела.
var _aimed_cooldown_timer: float = AIMED_INTERVAL_PHASE1 * 0.5
# Radial стартует «холодным»: даже с первого перехода в phase 2 первый
# залп не мгновенный (тикает во время phase 1 APPROACH). Само правило
# «phase 1 без radial» дополнительно защищено scheduler'ом.
var _radial_cooldown_timer: float = RADIAL_INTERVAL
# Summon стартует нулём: первый physics-тик тут же запустит каст первого
# батча. Игрок мгновенно понимает роль призывателя, а не тратит 10 s на
# «зарядку».
var _summon_cooldown_timer: float = 0.0
# Общий gate post-radial: пока > 0, никакая атака не выбирается. Даёт
# игроку окно после залпа звёздочки на репозиционирование.
var _post_radial_pause_timer: float = 0.0

# Индекс залпа для чередования звёздочки. Хранится сквозь фазы —
# монотонность важна для теста `_compute_volley_angles`.
var _volley_index: int = 0

# Раздельные квоты миньонов: melee (3) и ranged (2). Гибель melee
# пополняется melee, гибель ranged — ranged; общий счётчик недостаточен.
var _melee_minions: Array = []
var _ranged_minions: Array = []

# Boss-specific RNG. Deterministic по (tower_seed, floor) — тот же сид
# всегда даёт ту же последовательность выбора «aimed vs radial», углов
# summon-arc'а и т.п. Не смешиваем с global randi (см. `.claude/rules/10-tests.md`).
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	# super() применяет floor scaling ДО того, как мы seed'им RNG по
	# effective_floor_number() — иначе seed считался бы от stale floor'а.
	super()
	# Seed от stable контекста (не randomize()) — reproducible для реплеев
	# и тестов. Отдельная константа — свой prime, чтобы не совпадать с
	# rune_golem RNG (тот же tower_seed → разные stream'ы боссов).
	if _spawn_context != null:
		_rng.seed = _spawn_context.tower_seed * 2_654_099 + effective_floor_number() * 65_537 + 3_517
	else:
		_rng.seed = effective_floor_number() * 65_537 + 3_517

# --- Main tick ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_contact_timer = max(0.0, _contact_timer - delta)
	if _target == null or not is_instance_valid(_target):
		_target = _find_player()
	_tick_state(delta)

func _tick_state(delta: float) -> void:
	match _state:
		State.IDLE:
			_tick_idle()
		State.APPROACH:
			_tick_approach(delta)
		State.AIMED_TELEGRAPH:
			_tick_aimed_telegraph(delta)
		State.AIMED_RECOVERY:
			_tick_aimed_recovery(delta)
		State.RADIAL_TELEGRAPH:
			_tick_radial_telegraph(delta)
		State.RADIAL_RECOVERY:
			_tick_radial_recovery(delta)
		State.SUMMON_CAST:
			_tick_summon_cast(delta)
		State.SUMMON_RECOVERY:
			_tick_summon_recovery(delta)
		State.PHASE_TRANSITION:
			_tick_phase_transition(delta)

func _set_state(new_state: State) -> void:
	# Прерывание атаки: если уходим из telegraph/cast с непустым
	# `_current_attack`, эмиттим `attack_resolved(false)` для telemetry-
	# симметрии (`attack_started` уже был эмиттнут в `_start_attack`).
	# `_current_attack` очищается сразу после fire — успешный fire эмиттит
	# resolved сам и обнуляет поле, так что нормальные переходы (телеграф
	# → recovery) сюда не попадают.
	if new_state != _state and _current_attack != &"":
		if _state == State.AIMED_TELEGRAPH \
				or _state == State.RADIAL_TELEGRAPH \
				or _state == State.SUMMON_CAST:
			attack_resolved.emit(_current_attack, false)
			_current_attack = &""
	_state = new_state
	_state_timer = 0.0
	velocity = Vector2.ZERO
	# Визуал каста сбрасываем при выходе из summon/transition; иначе
	# зелёный/фиолетовый tint «зависнет» до следующего каста.
	if new_state != State.SUMMON_CAST and new_state != State.PHASE_TRANSITION:
		_reset_cast_visual()

# --- IDLE / APPROACH -----------------------------------------------------

func _tick_idle() -> void:
	if _target != null:
		_set_state(State.APPROACH)

func _tick_approach(delta: float) -> void:
	# Все cadence-таймеры тикают в APPROACH — вне attack'ов и casts.
	_aimed_cooldown_timer = max(0.0, _aimed_cooldown_timer - delta)
	_radial_cooldown_timer = max(0.0, _radial_cooldown_timer - delta)
	_summon_cooldown_timer = max(0.0, _summon_cooldown_timer - delta)
	_post_radial_pause_timer = max(0.0, _post_radial_pause_timer - delta)
	if _target == null:
		velocity = Vector2.ZERO
		return
	var chosen := _pick_next_action()
	if chosen != &"":
		_start_attack(chosen)
		return
	_move_toward_player(delta)

func _move_toward_player(delta: float) -> void:
	if _target == null:
		velocity = Vector2.ZERO
		return
	var to_player := _target.global_position - global_position
	if to_player.length() <= 0.0:
		velocity = Vector2.ZERO
		return
	var direction := to_player.normalized()
	velocity = direction * speed
	var collision := move_and_collide(velocity * delta)
	if collision == null:
		return
	var collider := collision.get_collider()
	if collider != null and collider.is_in_group("player") and _contact_timer <= 0.0:
		if collider.has_method("take_damage"):
			collider.take_damage(contact_damage, DamageContext.from_enemy_attack(self, ATTACK_CONTACT))
			attack_resolved.emit(ATTACK_CONTACT, true)
		_contact_timer = contact_cooldown

# --- Attack selection ----------------------------------------------------

# Плановый порядок приоритетов внутри scheduler'а:
# 1. Summon, если квоты не полные и cooldown готов — призыв важнее damage.
# 2. Radial (только phase 2+), если готов и нет post-radial gap.
# 3. Aimed, если готов и нет post-radial gap.
# 4. Иначе — движение.
func _pick_next_action() -> StringName:
	if _post_radial_pause_timer > 0.0:
		return &""
	if _needs_summon() and _summon_cooldown_timer <= 0.0:
		return ATTACK_SUMMON_MINIONS
	if current_phase >= 2 and _radial_cooldown_timer <= 0.0:
		# Radial имеет приоритет над aimed, когда готов: иначе aimed (с
		# короче cooldown'ом) каждый раз откатывал бы radial к следующему
		# тику и залп никогда не выпускался.
		return ATTACK_RADIAL_VOLLEY
	if _aimed_cooldown_timer <= 0.0:
		return ATTACK_AIMED_PROJECTILE
	return &""

func _needs_summon() -> bool:
	_cleanup_minions()
	return _total_alive_minions() < SUMMON_COUNT

func _start_attack(attack_id: StringName) -> void:
	_current_attack = attack_id
	attack_started.emit(attack_id)
	match attack_id:
		ATTACK_AIMED_PROJECTILE:
			_set_state(State.AIMED_TELEGRAPH)
		ATTACK_RADIAL_VOLLEY:
			_set_state(State.RADIAL_TELEGRAPH)
		ATTACK_SUMMON_MINIONS:
			_set_state(State.SUMMON_CAST)

# --- AIMED PROJECTILE: telegraph → fire → recovery -----------------------

func _tick_aimed_telegraph(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= AIMED_TELEGRAPH:
		_fire_aimed_shot()
		_aimed_cooldown_timer = _aimed_interval_for_phase()
		_set_state(State.AIMED_RECOVERY)

func _tick_aimed_recovery(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= AIMED_RECOVERY:
		_set_state(State.APPROACH)

# Прицельный выстрел «как у лича» — magic_bolt с упреждением по вектору
# движения игрока. Формула идентична lich.gd::_compute_lead_direction —
# pure-функция для тестов.
#
# Обнуляем `_current_attack` после resolve — так `_set_state` при
# нормальном переходе AIMED_TELEGRAPH → AIMED_RECOVERY не дублирует
# resolved-эмит (см. `_set_state`'s interrupt guard).
func _fire_aimed_shot() -> void:
	if aimed_bullet_scene == null or _target == null:
		attack_resolved.emit(ATTACK_AIMED_PROJECTILE, false)
		_current_attack = &""
		return
	var target_velocity: Vector2 = Vector2.ZERO
	if _target is CharacterBody2D:
		target_velocity = _target.velocity
	var direction := _compute_lead_direction(_target.global_position, target_velocity)
	if direction == Vector2.ZERO:
		attack_resolved.emit(ATTACK_AIMED_PROJECTILE, false)
		_current_attack = &""
		return
	var bullet := aimed_bullet_scene.instantiate()
	bullet.global_position = global_position
	bullet.direction = direction
	bullet.damage = _aimed_damage_for_phase()
	bullet.source_enemy = self
	bullet.attack_id = &"aimed_shot"
	get_tree().current_scene.add_child(bullet)
	attack_resolved.emit(ATTACK_AIMED_PROJECTILE, true)
	_current_attack = &""

func _compute_lead_direction(target_pos: Vector2, target_velocity: Vector2) -> Vector2:
	var to_target := target_pos - global_position
	var distance := to_target.length()
	if distance <= 0.0:
		return Vector2.ZERO
	var time_to_hit := distance / AIMED_BULLET_SPEED
	var predicted := target_pos + target_velocity * time_to_hit
	return (predicted - global_position).normalized()

func _aimed_interval_for_phase() -> float:
	match current_phase:
		3:
			return AIMED_INTERVAL_PHASE3
		2:
			return AIMED_INTERVAL_PHASE2
		_:
			return AIMED_INTERVAL_PHASE1

func _aimed_damage_for_phase() -> int:
	if current_phase >= 2:
		return AIMED_BULLET_DAMAGE_PHASE23
	return AIMED_BULLET_DAMAGE_PHASE1

# --- RADIAL VOLLEY: telegraph → fire → recovery (phase 2+) ---------------

func _tick_radial_telegraph(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= RADIAL_TELEGRAPH:
		_fire_volley()
		_radial_cooldown_timer = RADIAL_INTERVAL
		# Post-radial gap блокирует aimed на RADIAL_MIN_PAUSE секунд —
		# инвариант «no aimed прямо после radial без окна на репозицию».
		_post_radial_pause_timer = RADIAL_MIN_PAUSE
		_set_state(State.RADIAL_RECOVERY)

func _tick_radial_recovery(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= RADIAL_RECOVERY:
		_set_state(State.APPROACH)

func _fire_volley() -> void:
	if bullet_scene == null:
		attack_resolved.emit(ATTACK_RADIAL_VOLLEY, false)
		_current_attack = &""
		return
	for angle in _compute_volley_angles(_volley_index):
		var bullet := bullet_scene.instantiate()
		bullet.global_position = global_position
		bullet.direction = Vector2.RIGHT.rotated(angle)
		bullet.damage = RADIAL_BULLET_DAMAGE
		bullet.source_enemy = self
		bullet.attack_id = &"volley"
		get_tree().current_scene.add_child(bullet)
	_volley_index += 1
	attack_resolved.emit(ATTACK_RADIAL_VOLLEY, true)
	_current_attack = &""

# Углы залпа: каждый второй раз сдвиг на step/2, чтобы звёздочка вращалась
# между кадрами. Pure-функция ради тестов.
func _compute_volley_angles(index: int) -> Array:
	var step := TAU / float(RADIAL_BULLET_COUNT)
	var offset := step * 0.5 if index % 2 == 1 else 0.0
	var angles: Array = []
	for i in RADIAL_BULLET_COUNT:
		angles.append(step * float(i) + offset)
	return angles

# --- SUMMON: cast (boss заморожен) → spawn → recovery --------------------

func _tick_summon_cast(delta: float) -> void:
	_state_timer += delta
	_apply_cast_visual()
	if _state_timer >= SUMMON_CAST_DURATION:
		_finish_cast()

func _tick_summon_recovery(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= SUMMON_RECOVERY:
		_set_state(State.APPROACH)

func _finish_cast() -> void:
	_reset_cast_visual()
	# Топ-ап раздельно: недостающие melee → melee, недостающие
	# ranged → ranged. Cм. plans/necromancer-minion-rebalance.
	var spawned := _summon_batch()
	if spawned > 0:
		_summon_cooldown_timer = _summon_cooldown_for_phase()
		attack_resolved.emit(ATTACK_SUMMON_MINIONS, true)
	else:
		# Ни одного места не нашлось (весь этаж стены) — короткий cooldown,
		# чтобы попробовать снова, а не подвиснуть.
		_summon_cooldown_timer = 0.5
		attack_resolved.emit(ATTACK_SUMMON_MINIONS, false)
	# Обнуляем ДО _set_state, чтобы interrupt-guard в _set_state не увидел
	# «незавершённый» attack (мы только что resolved его выше).
	_current_attack = &""
	_set_state(State.SUMMON_RECOVERY)

func _summon_cooldown_for_phase() -> float:
	if current_phase >= 3:
		return SUMMON_COOLDOWN_PHASE3
	return SUMMON_COOLDOWN_PHASE12

# --- Batch summon --------------------------------------------------------

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
	# configure_summon() задаёт monster_level=1 / rewards=off / arsenal pool /
	# max_damage cap / temperament override ДО _ready(). Без этого призванный
	# скелет полу-fallback скейлился бы по boss floor и мог случайно получить
	# iron sword с 6-7 damage.
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
	# aggressive исключён: тот же speed×1.12 + cooldown×0.85 в паре с 3-мя
	# melee и залпами босса даёт слишком плотный pressure. Оставляем двух
	# умеренных: persistent (упорнее преследует) и watchful (шире perception,
	# тише при wander).
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
	# aggressive исключён: fire_interval×0.85 + range×0.90 сокращают окно
	# уклонения; при двух ranged + boss projectiles это слишком.
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
	return allowed[_rng.randi() % allowed.size()]

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

# --- Formation slots -----------------------------------------------------

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

# Ищет walkable-клетку рядом с anchor: если сам anchor подходит — возвращает
# его, иначе разлетается по спирали с шагом FLOOR_TILE_SIZE. Fallback —
# прежний random-arc.
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
# заспавнится вовсе.
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
		base_angle = _rng.randf() * TAU
	else:
		var center_angle := center_dir.angle()
		base_angle = center_angle + _rng.randf_range(-SUMMON_TOWARD_PLAYER_ARC * 0.5, SUMMON_TOWARD_PLAYER_ARC * 0.5)
	var distance := _rng.randf_range(SUMMON_OFFSET_MIN, SUMMON_OFFSET_MAX)
	return Vector2(cos(base_angle), sin(base_angle)) * distance

func _is_walkable(floor_node: Node, pos: Vector2) -> bool:
	var cell := Vector2i(int(pos.x / FLOOR_TILE_SIZE), int(pos.y / FLOOR_TILE_SIZE))
	if not floor_node.astar_grid.is_in_boundsv(cell):
		return false
	return not floor_node.astar_grid.is_point_solid(cell)

# --- Cast visual ---------------------------------------------------------

func _apply_cast_visual() -> void:
	var visual := get_node_or_null("Visual") as Sprite2D
	if visual == null:
		return
	var progress := clampf(_state_timer / SUMMON_CAST_DURATION, 0.0, 1.0)
	var pulse := (sin(progress * CAST_PULSE_FREQUENCY) + 1.0) * 0.5
	var mix := clampf(0.3 + progress * 0.4 + pulse * 0.3, 0.0, 1.0)
	visual.modulate = _visual_base_modulate.lerp(CAST_TINT_COLOR, mix)

func _reset_cast_visual() -> void:
	var visual := get_node_or_null("Visual") as Sprite2D
	if visual != null:
		visual.modulate = _visual_base_modulate

# --- Phase transition ----------------------------------------------------

func _tick_phase_transition(delta: float) -> void:
	_state_timer += delta
	_apply_transition_visual()
	if _state_timer >= PHASE_TRANSITION_DURATION:
		_reset_cast_visual()
		var target_phase := _phase_for_health_fraction(float(health) / float(max_health))
		if target_phase > current_phase:
			set_phase(target_phase)
		_set_state(State.APPROACH)

func _apply_transition_visual() -> void:
	var visual := get_node_or_null("Visual") as Sprite2D
	if visual == null:
		return
	var progress := clampf(_state_timer / PHASE_TRANSITION_DURATION, 0.0, 1.0)
	var pulse := (sin(progress * TRANSITION_PULSE_FREQ) + 1.0) * 0.5
	var mix := clampf(0.35 + progress * 0.4 + pulse * 0.25, 0.0, 1.0)
	visual.modulate = _visual_base_modulate.lerp(TRANSITION_TINT_COLOR, mix)

# Мап HP-фракция → номер фазы. Плановые пороги 60% и 25%.
func _phase_for_health_fraction(fraction: float) -> int:
	if fraction <= PHASE_3_HP_FRACTION:
		return 3
	if fraction <= PHASE_2_HP_FRACTION:
		return 2
	return 1

# --- take_damage: phase transition + death cleanup -----------------------

func take_damage(amount: int, context: DamageContext = null) -> void:
	Analytics.record_damage_dealt(mini(health, amount), context)
	health -= amount
	modulate = Color(1, 0.5, 0.5)
	# Phase transition — до flash-таймера. Иначе если damage убил боссa на
	# threshold'е, phase_changed эмиттнется у freed ноды.
	if _state != State.PHASE_TRANSITION and _state != State.DEAD and health > 0:
		var target_phase := _phase_for_health_fraction(float(health) / float(max_health))
		if target_phase > current_phase:
			_set_state(State.PHASE_TRANSITION)
	await get_tree().create_timer(0.08).timeout
	if is_inside_tree():
		modulate = Color.WHITE
	if health <= 0 and is_inside_tree():
		_set_state(State.DEAD)
		_handle_death(context)
