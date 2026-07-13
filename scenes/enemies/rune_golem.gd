extends BossBase

# Рунный Голем — второй босс башни (этаж 10). Каменно-латунный конструкт
# technical-зоны: рунное ядро в груди, тяжёлые кулаки, свечение вдоль
# conduits. Учит читать опасные зоны пола, планировать маршрут, ловить
# vulnerability window (перегрев), сохранять пространство для уклонения.
#
# Дизайн-инвариант: одна атака за раз, все переходы через `_set_state()`;
# safe region проверяется до активации любой lane; overheat строго после
# накопления `OVERHEAT_HEAVY_THRESHOLD` тяжёлых действий (никакого random
# overheat). Boss НЕ использует summons / bullet hell.

const RuneLineScene: PackedScene = preload("res://scenes/enemies/rune_line.tscn")

# Stable attack IDs — единый payload для BossBase.attack_started /
# attack_resolved и DamageContext. Игрок и аналитика читают эти slug'и как
# стабильный API — не переименовывать без обновления docs/engineering/bosses.
const ATTACK_FIST_SLAM: StringName = &"fist_slam"
const ATTACK_RUNE_LINE: StringName = &"rune_line"
const ATTACK_TWIN_RUNE_LINES: StringName = &"twin_rune_lines"
const ATTACK_CONTACT: StringName = &"contact"

# --- Base movement / senses ------------------------------------------------
@export var speed: float = 22.0
@export var perception_radius: float = 3000.0
@export var contact_cooldown: float = 0.9

# --- Fist slam (ближняя тяжёлая атака с телеграфом) -----------------------
# Прямоугольная зона перед боссом. Damage применяется один раз в active
# frame — no tracking после финального wind-up portion (плановый инвариант).
const SLAM_WINDUP: float = 0.55
const SLAM_ACTIVE: float = 0.10
const SLAM_RECOVERY: float = 0.60
const SLAM_LENGTH: float = 95.0
const SLAM_WIDTH: float = 62.0
const SLAM_DAMAGE: int = 3
# После финальной половины wind-up direction зафиксировано (no tracking).
# `_slam_facing` записывается в `_start_attack`; сравниваем dot product.
const SLAM_ARC_DEG: float = 100.0

# --- Rune lines (стационарные lane hazards) --------------------------------
# Фазы: warning → active → lingering. rune_line.gd управляет своей таймингой;
# boss только выбирает layouts и передаёт параметры.
const RUNE_WARNING_PHASE1: float = 0.8
const RUNE_WARNING_PHASE2: float = 0.9
const RUNE_ACTIVE: float = 0.35
const RUNE_LINGERING: float = 1.2
const RUNE_DAMAGE: int = 1
# Layout: 6 предустановленных lane относительно центра арены.
# 3 горизонтальных (top, middle, bottom), 3 вертикальных (left, middle, right).
const LANE_COUNT: int = 6
const LANE_LENGTH: float = 240.0
const LANE_WIDTH: float = 44.0
const LANE_SPACING: float = 105.0
# Время «занятия» boss'ом RUNE_CAST-фазы: warning + подготовка визуала.
const RUNE_CAST_DURATION_PHASE1: float = 0.55
const RUNE_CAST_DURATION_PHASE2: float = 0.60
const RUNE_RECOVERY: float = 0.55
const RUNE_RECOVERY_PHASE2: float = 0.45

# --- Overheat (vulnerability window) --------------------------------------
# Строго детерминированный триггер: после `OVERHEAT_HEAVY_THRESHOLD`
# тяжёлых actions boss останавливается на `OVERHEAT_DURATION` секунд.
# В это время attacks не стартуют, contact damage подавлен, incoming damage
# умножается на `OVERHEAT_DAMAGE_MULTIPLIER`.
const OVERHEAT_HEAVY_THRESHOLD: int = 3
const OVERHEAT_DURATION: float = 2.0
const OVERHEAT_DAMAGE_MULTIPLIER: float = 1.5
const OVERHEAT_TINT_COLOR: Color = Color(1.6, 1.2, 0.6, 1.0)
const OVERHEAT_PULSE_FREQ: float = PI * 8.0

# --- Attack ranges / cadence guards ---------------------------------------
const RANGE_SLAM: float = 90.0
const RANGE_RUNE_MIN: float = 90.0
const RANGE_RUNE_MAX: float = 480.0
# Минимальная пауза после любой атаки перед выбором следующей — не спам.
const POST_ATTACK_COOLDOWN: float = 0.35

# --- Phase 2 --------------------------------------------------------------
const PHASE_2_HP_FRACTION: float = 0.5
const PHASE_TRANSITION_DURATION: float = 0.85
const PHASE_2_SPEED_MULT: float = 1.10
# Замечание: damage не увеличивается — плановый инвариант.
const TRANSITION_PULSE_FREQ: float = PI * 6.0
const TRANSITION_TINT_COLOR: Color = Color(1.4, 1.05, 0.55, 1.0)

# --- States. Flat enum — все переходы видны в _tick_state --------------
enum State {
	IDLE,
	APPROACH,
	SLAM_WINDUP,
	SLAM_ACTIVE,
	SLAM_RECOVERY,
	RUNE_CAST,
	RUNE_RECOVERY,
	OVERHEATED,
	PHASE_TRANSITION,
	DEAD,
}

var _state: State = State.IDLE
var _state_timer: float = 0.0
var _current_attack: StringName = &""
var _contact_timer: float = 0.0
var _post_attack_cooldown: float = 0.0

var _target: Node2D = null
# Facing зафиксирован в _start_attack — не пересчитывается после половины
# wind-up (плановый инвариант «no tracking after final wind-up portion»).
var _slam_facing: Vector2 = Vector2.RIGHT
var _damage_applied: bool = false

# Overheat counter. Инкрементится когда завершается тяжёлое action
# (fist_slam, rune_line, twin_rune_lines). Достигает threshold → следующий
# _set_state OVERHEATED. Сбрасывается после overheat exit.
var _heavy_action_count: int = 0
var _last_attack: StringName = &""
# Активные rune_line ноды — для cleanup при смерти и для тестов.
var _active_rune_lines: Array = []

# Boss-specific RNG. Determistic по (tower_seed, floor) — не смешиваем с
# global randi (см. `.claude/rules/10-tests.md`). Тот же tower+floor всегда
# даст одну и ту же последовательность выборов lane / atk.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	super()
	# Seed от stable контекста (не randomize()) — reproducible для реплеев.
	if _spawn_context != null:
		_rng.seed = _spawn_context.tower_seed * 1_299_709 + effective_floor_number() * 65_537 + 8_101
	else:
		_rng.seed = effective_floor_number() * 65_537 + 8_101
	_set_state(State.IDLE)

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_contact_timer = max(0.0, _contact_timer - delta)
	_post_attack_cooldown = max(0.0, _post_attack_cooldown - delta)
	if _target == null or not is_instance_valid(_target):
		_target = _find_player()
	_tick_state(delta)

# --- State dispatcher ------------------------------------------------------

func _tick_state(delta: float) -> void:
	match _state:
		State.IDLE:
			_tick_idle()
		State.APPROACH:
			_tick_approach(delta)
		State.SLAM_WINDUP:
			_tick_slam_windup(delta)
		State.SLAM_ACTIVE:
			_tick_slam_active(delta)
		State.SLAM_RECOVERY:
			_tick_slam_recovery(delta)
		State.RUNE_CAST:
			_tick_rune_cast(delta)
		State.RUNE_RECOVERY:
			_tick_rune_recovery(delta)
		State.OVERHEATED:
			_tick_overheated(delta)
		State.PHASE_TRANSITION:
			_tick_phase_transition(delta)

func _set_state(new_state: State) -> void:
	# Выход из OVERHEATED — сбрасываем счётчик тяжёлых actions.
	if _state == State.OVERHEATED and new_state != State.OVERHEATED:
		_heavy_action_count = 0
	_state = new_state
	_state_timer = 0.0
	velocity = Vector2.ZERO
	_damage_applied = false
	if new_state != State.PHASE_TRANSITION and new_state != State.OVERHEATED:
		_reset_special_visual()

# --- IDLE / APPROACH ------------------------------------------------------

func _tick_idle() -> void:
	if _target != null:
		_set_state(State.APPROACH)

func _tick_approach(delta: float) -> void:
	if _target == null:
		velocity = Vector2.ZERO
		return
	# Overheat gate: превышен threshold → входим в vulnerability window.
	# Не запускаем новую атаку. `_heavy_action_count` >= threshold задан
	# в _finish_heavy_action().
	if _heavy_action_count >= OVERHEAT_HEAVY_THRESHOLD:
		_set_state(State.OVERHEATED)
		return
	if _post_attack_cooldown > 0.0:
		_move_toward_player(delta)
		return
	var to_player := _target.global_position - global_position
	var distance := to_player.length()
	if distance <= 0.0:
		velocity = Vector2.ZERO
		return
	var chosen := _pick_next_action(distance)
	if chosen != &"":
		_start_attack(chosen, to_player.normalized())
		return
	_move_toward_player(delta)

func _move_toward_player(delta: float) -> void:
	if _target == null:
		return
	var to_player := _target.global_position - global_position
	if to_player.length() <= 0.0:
		return
	var direction := to_player.normalized()
	var effective_speed := speed * (PHASE_2_SPEED_MULT if current_phase == 2 else 1.0)
	velocity = direction * effective_speed
	var collision := move_and_collide(velocity * delta)
	if collision == null:
		return
	var collider := collision.get_collider()
	if collider != null and collider.is_in_group("player") and _contact_timer <= 0.0:
		if collider.has_method("take_damage"):
			collider.take_damage(1, DamageContext.from_enemy_attack(self, ATTACK_CONTACT))
		_contact_timer = contact_cooldown

# --- Attack selection ------------------------------------------------------

# Возвращает stable id выбранной атаки, либо &"" если продолжаем движение.
# Weighted state-aware: близко → slam, дальше → rune lane. В phase 2 — twin
# при подходящей дистанции.
func _pick_next_action(distance: float) -> StringName:
	# Phase 2: twin rune lines. Требуют дистанции, чтобы игрок читал telegraph
	# и мог выбрать safe corridor.
	if current_phase == 2 and distance >= RANGE_RUNE_MIN and distance <= RANGE_RUNE_MAX:
		if _last_attack != ATTACK_TWIN_RUNE_LINES and _rng.randf() < 0.45:
			return ATTACK_TWIN_RUNE_LINES

	# Rune line — любой phase, если дистанция подходящая.
	if distance >= RANGE_RUNE_MIN and distance <= RANGE_RUNE_MAX:
		# Не два rune-lane action'а подряд — иначе игрок «зажат» между двумя
		# волнами warning'ов.
		if _last_attack != ATTACK_RUNE_LINE and _last_attack != ATTACK_TWIN_RUNE_LINES:
			if _rng.randf() < 0.55:
				return ATTACK_RUNE_LINE

	# Ближняя дистанция → slam.
	if distance <= RANGE_SLAM:
		return ATTACK_FIST_SLAM

	return &""

func _start_attack(attack_id: StringName, facing: Vector2) -> void:
	_current_attack = attack_id
	_slam_facing = facing
	_last_attack = attack_id
	attack_started.emit(attack_id)
	match attack_id:
		ATTACK_FIST_SLAM:
			_set_state(State.SLAM_WINDUP)
		ATTACK_RUNE_LINE, ATTACK_TWIN_RUNE_LINES:
			_set_state(State.RUNE_CAST)

# --- SLAM: windup → active (single-hit) → recovery -----------------------

func _tick_slam_windup(delta: float) -> void:
	_state_timer += delta
	# Отслеживание игрока до половины wind-up — потом direction фиксируется
	# (плановый инвариант «no tracking after final wind-up portion»).
	if _state_timer < SLAM_WINDUP * 0.5 and _target != null and is_instance_valid(_target):
		var to_player := _target.global_position - global_position
		if to_player.length() > 0.0:
			_slam_facing = to_player.normalized()
	if _state_timer >= SLAM_WINDUP:
		_set_state(State.SLAM_ACTIVE)

func _tick_slam_active(delta: float) -> void:
	_state_timer += delta
	# Damage frame — один раз за атаку.
	if not _damage_applied:
		_apply_slam_damage()
		_damage_applied = true
	if _state_timer >= SLAM_ACTIVE:
		_finish_heavy_action(ATTACK_FIST_SLAM)
		_set_state(State.SLAM_RECOVERY)

func _apply_slam_damage() -> void:
	if _target == null or not is_instance_valid(_target):
		attack_resolved.emit(ATTACK_FIST_SLAM, false)
		return
	var to_player := _target.global_position - global_position
	var distance := to_player.length()
	if distance > SLAM_LENGTH or distance <= 0.0:
		attack_resolved.emit(ATTACK_FIST_SLAM, false)
		return
	var arc_rad := deg_to_rad(SLAM_ARC_DEG)
	var direction := to_player.normalized()
	# Ортогональная rectangle: dot против slam_facing.
	if _slam_facing.dot(direction) < cos(arc_rad * 0.5):
		attack_resolved.emit(ATTACK_FIST_SLAM, false)
		return
	# Ширина: проверяем perpendicular offset игрока от оси slam.
	var perp := Vector2(-_slam_facing.y, _slam_facing.x)
	if abs(perp.dot(to_player)) > SLAM_WIDTH * 0.5:
		attack_resolved.emit(ATTACK_FIST_SLAM, false)
		return
	if _target.has_method("take_damage"):
		_target.take_damage(SLAM_DAMAGE, DamageContext.from_enemy_attack(self, ATTACK_FIST_SLAM))
	attack_resolved.emit(ATTACK_FIST_SLAM, true)

func _tick_slam_recovery(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= SLAM_RECOVERY:
		_post_attack_cooldown = POST_ATTACK_COOLDOWN
		_set_state(State.APPROACH)

# --- RUNE CAST: boss выбирает lanes, спавнит их, ждёт end of cast --------

func _tick_rune_cast(delta: float) -> void:
	_state_timer += delta
	if not _damage_applied:
		_spawn_rune_pattern()
		_damage_applied = true
	var duration := RUNE_CAST_DURATION_PHASE2 if current_phase == 2 else RUNE_CAST_DURATION_PHASE1
	if _state_timer >= duration:
		attack_resolved.emit(_current_attack, true)
		_finish_heavy_action(_current_attack)
		_set_state(State.RUNE_RECOVERY)

func _tick_rune_recovery(delta: float) -> void:
	_state_timer += delta
	var duration := RUNE_RECOVERY_PHASE2 if current_phase == 2 else RUNE_RECOVERY
	if _state_timer >= duration:
		_post_attack_cooldown = POST_ATTACK_COOLDOWN
		_set_state(State.APPROACH)

# --- Rune lane pattern selection + spawn ---------------------------------

# Выбирает pattern и спавнит соответствующие rune_line ноды. Учитывает
# safe-region invariant и single/twin количество lanes по фазе.
func _spawn_rune_pattern() -> void:
	var layouts := _get_lane_layouts()
	if layouts.is_empty():
		return
	var selected: Array = _select_pattern(layouts)
	if selected.is_empty():
		return
	var warning_duration := RUNE_WARNING_PHASE2 if _current_attack == ATTACK_TWIN_RUNE_LINES else RUNE_WARNING_PHASE1
	for lane_data in selected:
		_spawn_lane(lane_data, warning_duration)

# Возвращает список Dictionary { center, direction } для 6 предустановленных
# lanes относительно центра арены. Индексация:
# 0 — horizontal top
# 1 — horizontal middle
# 2 — horizontal bottom
# 3 — vertical left
# 4 — vertical middle
# 5 — vertical right
func _get_lane_layouts() -> Array:
	var arena_center := _arena_center()
	var layouts: Array = []
	layouts.append({"center": arena_center + Vector2(0, -LANE_SPACING), "direction": Vector2.RIGHT})
	layouts.append({"center": arena_center, "direction": Vector2.RIGHT})
	layouts.append({"center": arena_center + Vector2(0, LANE_SPACING), "direction": Vector2.RIGHT})
	layouts.append({"center": arena_center + Vector2(-LANE_SPACING, 0), "direction": Vector2.DOWN})
	layouts.append({"center": arena_center, "direction": Vector2.DOWN})
	layouts.append({"center": arena_center + Vector2(LANE_SPACING, 0), "direction": Vector2.DOWN})
	return layouts

func _arena_center() -> Vector2:
	if _spawn_context != null and _spawn_context.arena_rect.size != Vector2.ZERO:
		return _spawn_context.arena_rect.get_center()
	return global_position

# Выбирает pattern (1 или 2 lane) в зависимости от атаки. Всегда возвращает
# набор, оставляющий safe region — validated через `_pattern_leaves_safe_region`.
# Если случайный выбор не проходит validation — перебирает fallback'и.
func _select_pattern(layouts: Array) -> Array:
	if _current_attack == ATTACK_TWIN_RUNE_LINES:
		return _select_twin_pattern(layouts)
	# Single lane: выбор одного индекса. Одна lane всегда оставляет safe
	# region (только треть или четверть арены заблокирована).
	var index := _rng.randi_range(0, LANE_COUNT - 1)
	return [layouts[index]]

func _select_twin_pattern(layouts: Array) -> Array:
	# Twin: любые два разных lane. Приоритет перпендикулярным парам
	# (horizontal + vertical) — они всегда оставляют широкие quadrants.
	# Fallback: две параллельных не смежных lane.
	var perp_pairs := _perpendicular_pairs()
	var pair_index := _rng.randi_range(0, perp_pairs.size() - 1)
	var pair: Array = perp_pairs[pair_index]
	var result := [layouts[pair[0]], layouts[pair[1]]]
	if _pattern_leaves_safe_region(result):
		return result
	# Fallback: любая пара с validation. Deterministically iterate.
	for i in range(LANE_COUNT):
		for j in range(i + 1, LANE_COUNT):
			var candidate := [layouts[i], layouts[j]]
			if _pattern_leaves_safe_region(candidate):
				return candidate
	# Extreme fallback — single lane, лучше downgrade, чем сломать invariant.
	return [layouts[0]]

# 9 перпендикулярных пар: horizontal (0/1/2) × vertical (3/4/5).
# Хранится как const — не пересобираем на каждый spawn twin_rune_lines.
const PERPENDICULAR_PAIRS: Array = [
	[0, 3], [0, 4], [0, 5],
	[1, 3], [1, 4], [1, 5],
	[2, 3], [2, 4], [2, 5],
]

func _perpendicular_pairs() -> Array:
	return PERPENDICULAR_PAIRS

# Grid-validation safe region. Строим 8×6 grid поверх арены, отмечаем
# cells, попадающие в lane rectangles, потом flood-fill свободных cells и
# проверяем, что connected свободный component имеет размер >= threshold.
# Не оптимальный path simulation — достаточно (по плану) grid validation.
const SAFE_GRID_COLS: int = 8
const SAFE_GRID_ROWS: int = 6
const SAFE_MIN_CELLS: int = 6

func _pattern_leaves_safe_region(lanes: Array) -> bool:
	var rect := _arena_rect_or_default()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return true
	var cell_size := Vector2(rect.size.x / float(SAFE_GRID_COLS), rect.size.y / float(SAFE_GRID_ROWS))
	var blocked: Dictionary = {}
	for row in range(SAFE_GRID_ROWS):
		for col in range(SAFE_GRID_COLS):
			var cell_center := rect.position + Vector2(
				(float(col) + 0.5) * cell_size.x,
				(float(row) + 0.5) * cell_size.y,
			)
			for lane in lanes:
				if _point_in_lane(cell_center, lane):
					blocked[Vector2i(col, row)] = true
					break
	var free_count := SAFE_GRID_COLS * SAFE_GRID_ROWS - blocked.size()
	if free_count < SAFE_MIN_CELLS:
		return false
	# Flood-fill: находим наибольшую connected free region.
	var visited: Dictionary = {}
	var max_component := 0
	for row in range(SAFE_GRID_ROWS):
		for col in range(SAFE_GRID_COLS):
			var key := Vector2i(col, row)
			if blocked.has(key) or visited.has(key):
				continue
			var component_size := _flood_fill_free(key, blocked, visited)
			if component_size > max_component:
				max_component = component_size
	return max_component >= SAFE_MIN_CELLS

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

func _flood_fill_free(start: Vector2i, blocked: Dictionary, visited: Dictionary) -> int:
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	var count: int = 0
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		count += 1
		for offset in NEIGHBOR_OFFSETS:
			var next: Vector2i = cell + offset
			if next.x < 0 or next.x >= SAFE_GRID_COLS or next.y < 0 or next.y >= SAFE_GRID_ROWS:
				continue
			if blocked.has(next) or visited.has(next):
				continue
			visited[next] = true
			queue.append(next)
	return count

func _point_in_lane(point: Vector2, lane: Dictionary) -> bool:
	var center: Vector2 = lane["center"]
	var direction: Vector2 = lane["direction"]
	var perp: Vector2 = Vector2(-direction.y, direction.x)
	var offset: Vector2 = point - center
	var along: float = absf(direction.dot(offset))
	var perpendicular: float = absf(perp.dot(offset))
	return along <= LANE_LENGTH * 0.5 and perpendicular <= LANE_WIDTH * 0.5

func _arena_rect_or_default() -> Rect2:
	if _spawn_context != null and _spawn_context.arena_rect.size != Vector2.ZERO:
		return _spawn_context.arena_rect
	# Fallback: arena размером с default profile (620×420), центр по позиции.
	return Rect2(global_position - Vector2(310, 210), Vector2(620, 420))

func _spawn_lane(lane_data: Dictionary, warning_duration: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var lane := RuneLineScene.instantiate()
	lane.global_position = lane_data["center"]
	lane.direction = lane_data["direction"]
	lane.length = LANE_LENGTH
	lane.width = LANE_WIDTH
	lane.warning_duration = warning_duration
	lane.active_duration = RUNE_ACTIVE
	lane.lingering_duration = RUNE_LINGERING
	lane.damage = RUNE_DAMAGE
	lane.source_enemy = self
	# tree_exited → чистка списка; иначе после queue_free ссылки будут висеть.
	lane.tree_exited.connect(_on_rune_line_exited.bind(lane))
	_active_rune_lines.append(lane)
	parent.add_child(lane)

func _on_rune_line_exited(lane: Node) -> void:
	_active_rune_lines.erase(lane)

# --- Heavy action bookkeeping + overheat ---------------------------------

# Инкрементит счётчик тяжёлых actions. Триггер overheat срабатывает в
# _tick_approach — не сразу здесь, потому что RECOVERY должно завершиться,
# и только следующий цикл выбирает OVERHEATED (иначе overheat отменит
# recovery посреди аника).
func _finish_heavy_action(attack_id: StringName) -> void:
	# Guard: считаем только эти три heavy атаки.
	if attack_id != ATTACK_FIST_SLAM \
			and attack_id != ATTACK_RUNE_LINE \
			and attack_id != ATTACK_TWIN_RUNE_LINES:
		return
	_heavy_action_count += 1

func _tick_overheated(delta: float) -> void:
	_state_timer += delta
	_apply_overheat_visual()
	if _state_timer >= OVERHEAT_DURATION:
		_reset_special_visual()
		# Post-check: если игрок за overheat пробил порог phase 2, take_damage
		# намеренно не запустил PHASE_TRANSITION (не прерывает vulnerability
		# window). Здесь на выходе — принудительно проверяем threshold,
		# иначе boss остался бы в phase 1 и twin_rune_lines недостижимы.
		if current_phase == 1 and health > 0 and float(health) / float(max_health) <= PHASE_2_HP_FRACTION:
			_set_state(State.PHASE_TRANSITION)
			return
		_set_state(State.APPROACH)

func _apply_overheat_visual() -> void:
	var visual := get_node_or_null("Visual") as Sprite2D
	if visual == null:
		return
	var progress := clampf(_state_timer / OVERHEAT_DURATION, 0.0, 1.0)
	var pulse := (sin(progress * OVERHEAT_PULSE_FREQ) + 1.0) * 0.5
	var mix := clampf(0.4 + pulse * 0.5, 0.0, 1.0)
	visual.modulate = _visual_base_modulate.lerp(OVERHEAT_TINT_COLOR, mix)

func _reset_special_visual() -> void:
	var visual := get_node_or_null("Visual") as Sprite2D
	if visual != null:
		visual.modulate = _visual_base_modulate

func is_overheated() -> bool:
	return _state == State.OVERHEATED

# --- Phase 2 transition --------------------------------------------------

func _tick_phase_transition(delta: float) -> void:
	_state_timer += delta
	_apply_transition_visual()
	if _state_timer >= PHASE_TRANSITION_DURATION:
		_reset_special_visual()
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

# --- take_damage override: overheat multiplier + phase transition guard --

func take_damage(amount: int, context: DamageContext = null) -> void:
	# Multiplier только во время OVERHEATED — vulnerability window, как в плане.
	var effective: int = int(round(float(amount) * OVERHEAT_DAMAGE_MULTIPLIER)) if _state == State.OVERHEATED else amount
	Analytics.record_damage_dealt(mini(health, effective), context)
	health -= effective
	modulate = Color(1, 0.5, 0.5)
	# Phase transition — до flash-таймера. Иначе если damage убил боссa на
	# threshold'е, phase_changed эмиттнется у freed ноды.
	if _state != State.PHASE_TRANSITION and _state != State.OVERHEATED and current_phase == 1 and health > 0:
		if float(health) / float(max_health) <= PHASE_2_HP_FRACTION:
			_set_state(State.PHASE_TRANSITION)
	await get_tree().create_timer(0.08).timeout
	if is_inside_tree():
		modulate = Color.WHITE
	if health <= 0 and is_inside_tree():
		_cleanup_active_rune_lines()
		_set_state(State.DEAD)
		_handle_death(context)

# Cleanup rune_line нод — чтобы они не остались висеть на арене после
# смерти босса (плановый инвариант «effects cleanup after boss death»).
func _cleanup_active_rune_lines() -> void:
	for lane in _active_rune_lines.duplicate():
		if lane != null and is_instance_valid(lane) and lane.is_inside_tree():
			lane.queue_free()
	_active_rune_lines.clear()
