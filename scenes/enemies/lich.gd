extends "res://scenes/enemies/ranged_enemy.gd"

# Lich расширяет ranged_enemy.gd способностью призывать
# скелета-миньона. Правила:
# - в один момент времени активен максимум один призванный скелет;
# - если миньон убит — через SUMMON_COOLDOWN секунд призывается новый;
# - первый призыв случается через SUMMON_COOLDOWN после спавна лича
#   (даём игроку время реагировать на лича до появления «свиты»).
#
# Призванный скелет не даёт XP/золота и не роняет пикапы —
# это ходячее раздражение, не источник прогресса. Иначе игрок
# просто пасётся возле лича и фармит призванных.

const SkeletonScene: PackedScene = preload("res://scenes/enemies/skeleton.tscn")

const SUMMON_COOLDOWN: float = 5.0
# Радиус спавна миньона — «рядом», не «где-то там». В tile'ах: min ~
# 0.75 тайла, max ~ 1.5 тайла. Ближе не пускаем чтобы скелет не
# спавнился внутри самого лича / коллизии рвались.
const SUMMON_OFFSET_MIN: float = 14.0
const SUMMON_OFFSET_MAX: float = 28.0
# Половинный угловой сектор со стороны игрока, в котором приоритетно
# ищем место. `TAU * 0.28` ≈ 100° — узко достаточно, чтобы миньон
# оказался между личом и игроком, но не намертво по прямой (в стены
# упирались бы гораздо чаще).
const SUMMON_TOWARD_PLAYER_ARC: float = TAU * 0.28
const SPAWN_ATTEMPTS: int = 12
# Половина попыток тратится на «в сторону игрока», остальные — на
# 360°-фолбэк если приоритетный сектор весь в стене.
const SPAWN_ATTEMPTS_TOWARD_PLAYER: int = 8
const FLOOR_TILE_SIZE: int = 20
# Каст-фаза перед появлением скелета: лич подсвечивается зелёным
# и не стреляет. Даёт игроку окно среагировать (или добить лича
# пока тот занят колдовством), а не «внезапный поп-ап» скелета.
const SUMMON_CAST_DURATION: float = 0.8
const CAST_PULSE_FREQUENCY: float = PI * 8.0
const CAST_TINT_COLOR: Color = Color(0.7, 1.6, 0.85, 1.0)

var _summoned_minion: Node = null
var _summon_cooldown_timer: float = SUMMON_COOLDOWN
var _summon_cast_timer: float = 0.0
var _visual_base_modulate: Color = Color.WHITE

func _ready() -> void:
	super._ready()
	var visual: Sprite2D = get_node_or_null("Visual") as Sprite2D
	if visual != null:
		_visual_base_modulate = visual.modulate

func _physics_process(delta: float) -> void:
	# Каст в приоритете: пока идёт, лич не двигается и не стреляет —
	# `super._physics_process` полностью пропускается. Это же
	# отключает kite-логику и `_shoot`.
	if _summon_cast_timer > 0.0:
		_tick_cast(delta)
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_maybe_start_summon(delta)
	# Каст мог только что начаться (`_summon_cast_timer > 0` теперь) —
	# в этом тике тоже не даём super стрелять.
	if _summon_cast_timer > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	super._physics_process(delta)

func _maybe_start_summon(delta: float) -> void:
	# WeakRef не используем — Node ссылки достаточно, а
	# is_instance_valid ловит freed / queue_freed случай.
	if _summoned_minion != null and not is_instance_valid(_summoned_minion):
		_summoned_minion = null
	if _summoned_minion != null:
		return
	_summon_cooldown_timer -= delta
	if _summon_cooldown_timer > 0.0:
		return
	# Кулдаун истёк — запускаем каст. Скелет появится через
	# SUMMON_CAST_DURATION секунд (см. _tick_cast → _finish_cast).
	_summon_cast_timer = SUMMON_CAST_DURATION

func _tick_cast(delta: float) -> void:
	_summon_cast_timer -= delta
	_apply_cast_visual()
	if _summon_cast_timer <= 0.0:
		_finish_cast()

func _finish_cast() -> void:
	_summon_cast_timer = 0.0
	_reset_cast_visual()
	# Если спавн не удался (все ближайшие клетки — стены), кулдаун
	# остался ≤ 0, следующий тик _maybe_start_summon снова запустит
	# каст. Игрок видит непрерывное колдовство лича, пока тот не
	# найдёт свободное место.
	_summon_skeleton()

func _apply_cast_visual() -> void:
	var visual := get_node_or_null("Visual") as Sprite2D
	if visual == null:
		return
	# Прогресс каста 0..1: чем ближе к финалу, тем ярче зелёный
	# пик. Синусоидальная пульсация поверх линейной интерполяции
	# делает эффект «набирает мощь».
	var progress := 1.0 - clampf(_summon_cast_timer / SUMMON_CAST_DURATION, 0.0, 1.0)
	var pulse := (sin(progress * CAST_PULSE_FREQUENCY) + 1.0) * 0.5
	var mix := clampf(0.3 + progress * 0.4 + pulse * 0.3, 0.0, 1.0)
	visual.modulate = _visual_base_modulate.lerp(CAST_TINT_COLOR, mix)

func _reset_cast_visual() -> void:
	var visual := get_node_or_null("Visual") as Sprite2D
	if visual != null:
		visual.modulate = _visual_base_modulate

func _summon_skeleton() -> bool:
	# Родитель лича — обычно Main._enemies_root; сиблинг-скелет
	# попадает туда же, автоматически в группу enemy через _ready.
	# get_parent() безопаснее чем get_tree().current_scene — в тестах
	# current_scene может быть null.
	var parent := get_parent()
	if parent == null:
		return false
	var spawn_pos := _pick_valid_spawn_position()
	if spawn_pos == Vector2.INF:
		return false
	var skeleton = SkeletonScene.instantiate()
	skeleton.global_position = spawn_pos
	parent.add_child(skeleton)
	# Обнуляем награды ПОСЛЕ add_child. В _ready родительский
	# enemy.gd прогоняет xp/gold через Balance.scaled_*_reward, где
	# `maxi(1, …)` превращает 0 в 1 — обнулять до add_child
	# бесполезно. Отдельно: pickup_scene читается только в _drop_pickup
	# (уже при смерти), тоже безопасно назначать сейчас.
	skeleton.xp_reward = 0
	skeleton.gold_reward = 0
	skeleton.pickup_scene = null
	_summoned_minion = skeleton
	_summon_cooldown_timer = SUMMON_COOLDOWN
	return true

func _pick_valid_spawn_position() -> Vector2:
	# Приоритет: сначала пробуем сектор в сторону игрока (миньон
	# оказывается «между личом и игроком» и работает как живой щит),
	# потом — фолбэк на 360°. В обоих случаях фильтруем по AStarGrid
	# is_point_solid, иначе скелет спавнится в стену и застревает.
	var floor_node := get_tree().get_first_node_in_group("floor")
	# В тестах / автономно (без Main + Floor) деградируем к простому
	# спавну без валидации — тесты живут без dungeon.
	if floor_node == null or floor_node.astar_grid == null:
		return global_position + _random_offset_toward_player()
	var toward_player := _direction_to_player()
	if toward_player != Vector2.ZERO:
		for i in SPAWN_ATTEMPTS_TOWARD_PLAYER:
			var candidate := global_position + _random_offset_in_arc(toward_player)
			if _is_walkable(floor_node, candidate):
				return candidate
	# Fallback: полное кольцо 360° вокруг лича.
	for i in SPAWN_ATTEMPTS:
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

func _random_offset_toward_player() -> Vector2:
	# Утилита для fallback-ветки без floor: если игрок известен, кладём
	# скелета в сектор к игроку; иначе — случайное кольцо. Совпадает
	# по смыслу с приоритетным сектором в основной функции.
	var toward_player := _direction_to_player()
	if toward_player == Vector2.ZERO:
		var angle := randf() * TAU
		var distance := randf_range(SUMMON_OFFSET_MIN, SUMMON_OFFSET_MAX)
		return Vector2(cos(angle), sin(angle)) * distance
	return _random_offset_in_arc(toward_player)

func _random_offset_in_arc(center_dir: Vector2) -> Vector2:
	# center_dir == ZERO → полный круг; иначе сектор SUMMON_TOWARD_PLAYER_ARC
	# вокруг center_dir.
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
