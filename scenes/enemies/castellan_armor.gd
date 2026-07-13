extends BossBase

# Кастелян — первый босс башни (этаж 5). Оживший тяжёлый доспех:
# меч + щит + charge в стену + ground slam во второй фазе. Учит
# читать телеграф, разрывать дистанцию, использовать recovery windows
# и провоцировать charge на стену. Не использует summons/bullet hell.
#
# Дизайн-инвариант: одна атака за раз. Все переходы состояний идут
# через `_set_state()`, timers других атак сбрасываются в WINDUP/ATTACK
# — исключает overlap телеграфов, ваншот-сценарии и «босс идёт и
# одновременно машет мечом».

const ShockwaveScene: PackedScene = preload("res://scenes/enemies/castellan_shockwave.tscn")

# Stable attack IDs — payload для BossBase.attack_started / attack_resolved
# и DamageContext.attack_id. Игрок / аналитика читают эти slug'и как API.
const ATTACK_SWORD_SWEEP: StringName = &"sword_sweep"
const ATTACK_SHIELD_BASH: StringName = &"shield_bash"
const ATTACK_SHIELD_CHARGE: StringName = &"shield_charge"
const ATTACK_GROUND_SLAM: StringName = &"ground_slam"
const ATTACK_CONTACT: StringName = &"contact"

# --- Base movement / senses ---
@export var speed: float = 28.0
@export var perception_radius: float = 3000.0
@export var contact_cooldown: float = 0.8

# --- Sword sweep (ближняя дуговая атака) ---
# Активен только если игрок в SWEEP_RANGE и в SWEEP_ARC_DEG от forward.
# Damage применяется один раз в active frame, никакого drag'а.
const SWEEP_WINDUP: float = 0.45
const SWEEP_ACTIVE: float = 0.10
const SWEEP_RECOVERY: float = 0.45
const SWEEP_RANGE: float = 55.0
const SWEEP_ARC_DEG: float = 100.0
const SWEEP_DAMAGE: int = 2
# Phase 2 сокращает только recovery — темп повышается, damage нет.
const SWEEP_RECOVERY_PHASE2: float = 0.32

# --- Shield bash (короткий bash с knockback'ом) ---
# Не основной damage — задача изменить позицию игрока.
const BASH_WINDUP: float = 0.30
const BASH_ACTIVE: float = 0.08
const BASH_RECOVERY: float = 0.35
const BASH_RANGE: float = 34.0
const BASH_ARC_DEG: float = 70.0
const BASH_DAMAGE: int = 1
const BASH_KNOCKBACK: float = 260.0

# --- Shield charge (главная атака и главное окно уязвимости) ---
# Направление фиксируется до старта. Movement по прямой до столкновения
# или лимита времени. Wall hit → stun = vulnerability window.
const CHARGE_TELEGRAPH: float = 0.65
const CHARGE_SPEED: float = 220.0
const CHARGE_MAX_DURATION: float = 1.6
const CHARGE_DAMAGE: int = 3
const CHARGE_MISS_RECOVERY: float = 0.5
const CHARGE_WALL_STUN: float = 1.2
# Минимальное сближение с игроком, при котором считаем что charge
# «догнал» его до попадания в стену. Не multi-hit — один раз.
const CHARGE_HIT_RADIUS: float = 24.0

# --- Ground slam (phase 2 only) ---
# Ближний удар о землю + 4 orthogonal shockwave'а. Без radial bullet ring —
# чётко читаемые векторы, большие промежутки, damage capped by плану.
const SLAM_TELEGRAPH: float = 0.70
const SLAM_NEAR_RADIUS: float = 48.0
const SLAM_NEAR_DAMAGE: int = 2
const SLAM_SHOCKWAVE_DAMAGE: int = 1
const SLAM_SHOCKWAVE_COUNT: int = 4
const SLAM_RECOVERY: float = 0.60

# --- Approach / ranges ---
const RANGE_MELEE: float = 60.0
const RANGE_CHARGE_MIN: float = 90.0
const RANGE_CHARGE_MAX: float = 260.0

# --- Attack cadence guard'ы ---
# Не повторять charge больше двух раз подряд — иначе паттерн заучивается
# как «доджь → wall → фарм stun window» и boss превращается в тренажёр.
const MAX_CONSECUTIVE_CHARGES: int = 2

# --- Phase 2 ---
const PHASE_2_HP_FRACTION: float = 0.55
const PHASE_TRANSITION_DURATION: float = 0.85
const PHASE_2_SPEED_MULT: float = 1.12

# Visual pulse на transition — тот же паттерн что у Necromancer cast_pulse,
# растянут на длительность transition. Легко читается «босс меняет фазу».
const TRANSITION_PULSE_FREQ: float = PI * 6.0
const TRANSITION_TINT_COLOR: Color = Color(1.4, 1.3, 0.7, 1.0)

# States. Флат enum — без вложенности, чтобы reviewer видел все переходы
# в _tick_state / _pick_next_action.
enum State {
	IDLE,
	APPROACH,
	WINDUP,
	ATTACK,
	RECOVERY,
	CHARGING,
	STUNNED,
	PHASE_TRANSITION,
	DEAD,
}

var _state: State = State.IDLE
var _state_timer: float = 0.0
var _current_attack: StringName = &""
var _contact_timer: float = 0.0

var _target: Node2D = null
# Фиксация направления для sweep/bash/charge — записывается в _set_state()
# при WINDUP/CHARGING, не пересчитывается каждый physics-tick.
var _attack_facing: Vector2 = Vector2.RIGHT
# Флаг «damage за эту атаку уже применён» — гарантирует single-hit для
# sweep/bash/charge. Сбрасывается на выход из ATTACK/CHARGING.
var _damage_applied: bool = false

# Отслеживание повторов зарядов — не спамить charge подряд.
var _consecutive_charge_count: int = 0
# Отслеживание slam — не два раза подряд.
var _last_attack: StringName = &""

# Boss-specific RNG. Seed'ится из BossSpawnContext.tower_seed +
# floor_number — deterministic для «shared tower seed» реплеев, не зависит
# от global randi (см. .claude/rules/10-tests.md про random / seed).
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	super()
	# Seed от stable контекста, а не randomize(). Тот же tower+floor всегда
	# даст одинаковую последовательность выборов атак.
	if _spawn_context != null:
		_rng.seed = _spawn_context.tower_seed * 1_299_709 + effective_floor_number() * 65_537 + 4_027
	else:
		_rng.seed = effective_floor_number() * 65_537 + 4_027
	_set_state(State.IDLE)

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_contact_timer = max(0.0, _contact_timer - delta)
	if _target == null or not is_instance_valid(_target):
		_target = _find_player()
	_tick_state(delta)

# --- State machine dispatcher --------------------------------------------

func _tick_state(delta: float) -> void:
	match _state:
		State.IDLE:
			_tick_idle()
		State.APPROACH:
			_tick_approach(delta)
		State.WINDUP:
			_tick_windup(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.RECOVERY:
			_tick_recovery(delta)
		State.CHARGING:
			_tick_charging(delta)
		State.STUNNED:
			_tick_stunned(delta)
		State.PHASE_TRANSITION:
			_tick_phase_transition(delta)

func _set_state(new_state: State) -> void:
	_state = new_state
	_state_timer = 0.0
	velocity = Vector2.ZERO
	_damage_applied = false
	if new_state != State.PHASE_TRANSITION:
		_reset_transition_visual()

# --- IDLE / APPROACH -----------------------------------------------------

func _tick_idle() -> void:
	if _target != null:
		_set_state(State.APPROACH)

func _tick_approach(delta: float) -> void:
	if _target == null:
		velocity = Vector2.ZERO
		return
	var to_player := _target.global_position - global_position
	var distance := to_player.length()
	if distance <= 0.0:
		velocity = Vector2.ZERO
		return
	# Выбор действия по дистанции. Ближе → sweep/bash. Дальше → charge.
	# Слишком близко для charge — не выбираем charge, чтобы не отталкивать
	# босса и тем не «отдавать» игроку окно для kite'а.
	var chosen := _pick_next_action(distance)
	if chosen != &"":
		_start_attack(chosen, to_player.normalized())
		return
	# Иначе просто движемся ближе. `move_and_collide` — не move_and_slide,
	# чтобы стены не «толкали» босса по касательной (важно для стабильных
	# позиций на арене).
	var direction := to_player.normalized()
	var effective_speed := speed * (PHASE_2_SPEED_MULT if current_phase == 2 else 1.0)
	velocity = direction * effective_speed
	var collision := move_and_collide(velocity * delta)
	# Контактный урон подавлен по плану: боссу нельзя ваншотить обычным
	# «наступил на игрока». Оставляем ровно 1 damage максимум за cooldown.
	if collision != null:
		var collider := collision.get_collider()
		if collider != null and collider.is_in_group("player") and _contact_timer <= 0.0:
			if collider.has_method("take_damage"):
				collider.take_damage(1, DamageContext.from_enemy_attack(self, ATTACK_CONTACT))
			_contact_timer = contact_cooldown

# --- Attack selection ----------------------------------------------------

# Возвращает stable id выбранной атаки либо &"" если продолжаем движение.
# state-aware: учитывает дистанцию, фазу, счётчики недавних атак.
func _pick_next_action(distance: float) -> StringName:
	# Phase 2: shockwave slam. Не два раза подряд; предпочитаем на среднюю
	# дистанцию, чтобы был смысл в orthogonal shockwaves (иначе player
	# просто вне SLAM_NEAR_RADIUS и не пересекается ни с одной волной).
	if current_phase == 2 and distance > RANGE_MELEE and distance < RANGE_CHARGE_MIN * 1.4:
		if _last_attack != ATTACK_GROUND_SLAM and _rng.randf() < 0.55:
			return ATTACK_GROUND_SLAM

	# Дальняя дистанция → charge, если не превышен consecutive-cap.
	if distance >= RANGE_CHARGE_MIN and distance <= RANGE_CHARGE_MAX:
		if _consecutive_charge_count < MAX_CONSECUTIVE_CHARGES:
			return ATTACK_SHIELD_CHARGE
		# Иначе: подходим ближе, не спамим charge.

	# Ближний контакт: sweep (более damage'жимый) чаще, bash (позиционка) реже.
	if distance <= RANGE_MELEE:
		if _rng.randf() < 0.65:
			return ATTACK_SWORD_SWEEP
		return ATTACK_SHIELD_BASH

	return &""

func _start_attack(attack_id: StringName, facing: Vector2) -> void:
	_current_attack = attack_id
	_attack_facing = facing
	# Обновляем счётчики повторов.
	if attack_id == ATTACK_SHIELD_CHARGE:
		_consecutive_charge_count += 1
	else:
		_consecutive_charge_count = 0
	_last_attack = attack_id
	_set_state(State.WINDUP)
	attack_started.emit(attack_id)

# --- WINDUP: телеграф. Damage NOT применяется. ---------------------------

func _tick_windup(delta: float) -> void:
	_state_timer += delta
	var duration := _current_windup_duration()
	if _state_timer >= duration:
		_enter_active_phase()

func _current_windup_duration() -> float:
	match _current_attack:
		ATTACK_SWORD_SWEEP:
			return SWEEP_WINDUP
		ATTACK_SHIELD_BASH:
			return BASH_WINDUP
		ATTACK_SHIELD_CHARGE:
			return CHARGE_TELEGRAPH
		ATTACK_GROUND_SLAM:
			return SLAM_TELEGRAPH
	return 0.0

func _enter_active_phase() -> void:
	# Charge — особый случай: не ATTACK-state, а CHARGING (движение по
	# прямой до collision/timeout). Остальные атаки — короткий ATTACK
	# frame + RECOVERY.
	if _current_attack == ATTACK_SHIELD_CHARGE:
		_set_state(State.CHARGING)
		return
	if _current_attack == ATTACK_GROUND_SLAM:
		_execute_ground_slam()
	_set_state(State.ATTACK)

# --- ATTACK: короткое активное окно (sweep/bash). Damage применяется раз. -

func _tick_attack(delta: float) -> void:
	_state_timer += delta
	# Damage frame — один раз за атаку, немедленно после входа в ATTACK.
	if not _damage_applied:
		_apply_attack_damage()
		_damage_applied = true
	var active_duration := _current_active_duration()
	if _state_timer >= active_duration:
		_set_state(State.RECOVERY)

func _current_active_duration() -> float:
	match _current_attack:
		ATTACK_SWORD_SWEEP:
			return SWEEP_ACTIVE
		ATTACK_SHIELD_BASH:
			return BASH_ACTIVE
		ATTACK_GROUND_SLAM:
			# Near-hit применён в _execute_ground_slam до входа в ATTACK,
			# сам ATTACK-frame — визуальная задержка перед RECOVERY.
			return 0.05
	return 0.05

func _apply_attack_damage() -> void:
	match _current_attack:
		ATTACK_SWORD_SWEEP:
			_apply_sector_damage(SWEEP_RANGE, SWEEP_ARC_DEG, SWEEP_DAMAGE, false)
		ATTACK_SHIELD_BASH:
			_apply_sector_damage(BASH_RANGE, BASH_ARC_DEG, BASH_DAMAGE, true)
		ATTACK_GROUND_SLAM:
			pass  # near-impact уже применён; здесь не дублируем

# Применяет sector-damage игроку, если он в конусе `arc_deg` от
# `_attack_facing` и в пределах `range_px`. Не multi-hit (вызывается
# один раз за атаку).
func _apply_sector_damage(range_px: float, arc_deg: float, damage: int, apply_knockback: bool) -> void:
	if _target == null or not is_instance_valid(_target):
		attack_resolved.emit(_current_attack, false)
		return
	var to_player := _target.global_position - global_position
	var distance := to_player.length()
	if distance > range_px or distance <= 0.0:
		attack_resolved.emit(_current_attack, false)
		return
	var arc_rad := deg_to_rad(arc_deg)
	var direction := to_player.normalized()
	if _attack_facing.dot(direction) < cos(arc_rad * 0.5):
		attack_resolved.emit(_current_attack, false)
		return
	if _target.has_method("take_damage"):
		_target.take_damage(damage, DamageContext.from_enemy_attack(self, _current_attack))
	if apply_knockback and _target is CharacterBody2D:
		# Мягкий knockback через velocity: одноразовый импульс, физика
		# сама затормозит. Не teleport — иначе игрок «прошибает» стены.
		var pushed := _target as CharacterBody2D
		pushed.velocity = direction * BASH_KNOCKBACK
	attack_resolved.emit(_current_attack, true)

# --- RECOVERY: полная беспомощность, боссу нельзя ходить/атаковать -------

func _tick_recovery(delta: float) -> void:
	_state_timer += delta
	var duration := _current_recovery_duration()
	if _state_timer >= duration:
		_set_state(State.APPROACH)

func _current_recovery_duration() -> float:
	match _current_attack:
		ATTACK_SWORD_SWEEP:
			return SWEEP_RECOVERY_PHASE2 if current_phase == 2 else SWEEP_RECOVERY
		ATTACK_SHIELD_BASH:
			return BASH_RECOVERY
		ATTACK_SHIELD_CHARGE:
			return CHARGE_MISS_RECOVERY
		ATTACK_GROUND_SLAM:
			return SLAM_RECOVERY
	return 0.3

# --- CHARGING: движение по фиксированной прямой -------------------------

func _tick_charging(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= CHARGE_MAX_DURATION:
		# Промах по времени. Recovery без stun'а.
		_current_attack = ATTACK_SHIELD_CHARGE
		attack_resolved.emit(ATTACK_SHIELD_CHARGE, false)
		_set_state(State.RECOVERY)
		return
	velocity = _attack_facing * CHARGE_SPEED
	var collision := move_and_collide(velocity * delta)
	if collision != null:
		_resolve_charge_collision(collision)
		return
	# Не multi-hit: даже если игрок оказался в CHARGE_HIT_RADIUS, damage
	# применяется один раз и boss переходит в RECOVERY (без stun'а —
	# полноценный wall stun только при wall impact).
	if not _damage_applied and _target != null and is_instance_valid(_target):
		var distance := global_position.distance_to(_target.global_position)
		if distance <= CHARGE_HIT_RADIUS:
			if _target.has_method("take_damage"):
				_target.take_damage(CHARGE_DAMAGE, DamageContext.from_enemy_attack(self, ATTACK_SHIELD_CHARGE))
			_damage_applied = true
			attack_resolved.emit(ATTACK_SHIELD_CHARGE, true)
			_current_attack = ATTACK_SHIELD_CHARGE
			_set_state(State.RECOVERY)

func _resolve_charge_collision(collision: KinematicCollision2D) -> void:
	var collider := collision.get_collider()
	# Игрок под charge получает damage один раз, потом recovery.
	if collider != null and collider.is_in_group("player"):
		if not _damage_applied and collider.has_method("take_damage"):
			collider.take_damage(CHARGE_DAMAGE, DamageContext.from_enemy_attack(self, ATTACK_SHIELD_CHARGE))
			_damage_applied = true
			attack_resolved.emit(ATTACK_SHIELD_CHARGE, true)
		_current_attack = ATTACK_SHIELD_CHARGE
		_set_state(State.RECOVERY)
		return
	# Всё остальное (стены, статические prop'ы) — stun. Это ключевое
	# vulnerability window для игрока (см. Acceptance criteria плана).
	attack_resolved.emit(ATTACK_SHIELD_CHARGE, _damage_applied)
	_current_attack = ATTACK_SHIELD_CHARGE
	_set_state(State.STUNNED)

func _tick_stunned(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= CHARGE_WALL_STUN:
		_set_state(State.APPROACH)

# --- GROUND SLAM: near-hit + 4 shockwaves --------------------------------

func _execute_ground_slam() -> void:
	# Near-impact: круговое AoE вокруг босса. Damage capped 2 (плана).
	# attack_resolved эмиттится строго один раз за атаку — симметрично
	# attack_started, иначе telemetry (docs/engineering/bosses.md заявляет
	# started/resolved как stable API) разъедется на miss'ах.
	var resolved: bool = false
	if _target != null and is_instance_valid(_target):
		var distance := global_position.distance_to(_target.global_position)
		if distance <= SLAM_NEAR_RADIUS and _target.has_method("take_damage"):
			_target.take_damage(SLAM_NEAR_DAMAGE, DamageContext.from_enemy_attack(self, ATTACK_GROUND_SLAM))
			attack_resolved.emit(ATTACK_GROUND_SLAM, true)
			resolved = true
	_spawn_shockwaves()
	if not resolved:
		attack_resolved.emit(ATTACK_GROUND_SLAM, false)

func _spawn_shockwaves() -> void:
	# Ровно 4 orthogonal shockwaves. Ни в коем случае не radial ring —
	# читаемые векторы, большие промежутки.
	var directions := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	var parent := get_parent()
	if parent == null:
		return
	for direction in directions:
		var wave := ShockwaveScene.instantiate()
		wave.global_position = global_position
		wave.direction = direction
		wave.source_enemy = self
		wave.damage = SLAM_SHOCKWAVE_DAMAGE
		parent.add_child(wave)

# --- PHASE 2 transition --------------------------------------------------

func _tick_phase_transition(delta: float) -> void:
	_state_timer += delta
	_apply_transition_visual()
	if _state_timer >= PHASE_TRANSITION_DURATION:
		_reset_transition_visual()
		set_phase(2)
		_set_state(State.APPROACH)

func _apply_transition_visual() -> void:
	var visual := get_node_or_null("Visual") as Sprite2D
	if visual == null:
		return
	var progress := clampf(_state_timer / PHASE_TRANSITION_DURATION, 0.0, 1.0)
	var pulse := (sin(progress * TRANSITION_PULSE_FREQ) + 1.0) * 0.5
	var mix := clampf(0.35 + progress * 0.4 + pulse * 0.25, 0.0, 1.0)
	visual.modulate = _visual_base_modulate.lerp(TRANSITION_TINT_COLOR, mix)

func _reset_transition_visual() -> void:
	var visual := get_node_or_null("Visual") as Sprite2D
	if visual != null:
		visual.modulate = _visual_base_modulate

# --- take_damage override: перехватываем момент phase transition ---------

func take_damage(amount: int, context: DamageContext = null) -> void:
	# STUNNED и PHASE_TRANSITION намеренно не блокируют damage: stun это
	# vulnerability window (плановое окно для игрока), transition не
	# защищает боссу HP. Новые атаки при этом не стартуют — гарантировано
	# state machine'ом (см. _tick_stunned / _tick_phase_transition).
	Analytics.record_damage_dealt(mini(health, amount), context)
	health -= amount
	modulate = Color(1, 0.5, 0.5)
	# Проверка на переход фазы ДО flash-таймера: иначе если damage убил
	# босса в момент < threshold, phase_changed эмитнется уже мёртвым
	# node и запустит transition поверх died.
	if _state != State.PHASE_TRANSITION and current_phase == 1 and health > 0:
		if float(health) / float(max_health) <= PHASE_2_HP_FRACTION:
			_set_state(State.PHASE_TRANSITION)
	await get_tree().create_timer(0.08).timeout
	if is_inside_tree():
		modulate = Color.WHITE
	if health <= 0 and is_inside_tree():
		_set_state(State.DEAD)
		_handle_death(context)
