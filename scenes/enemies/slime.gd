extends "res://scenes/enemies/enemy.gd"

# Слайм передвигается прыжками, а не равномерным ходом.
# Цикл REST → JUMP → REST … запускается сразу в _ready и никогда
# не останавливается — фаза меняется по таймеру, независимо от того,
# видит слайм цель или нет (пусть даже в WANDER он рывками смещается).
#
# REST: `speed = 0` → super._physics_process не даёт слайму двигаться.
# JUMP: `speed = _base_speed * JUMP_SPEED_MULTIPLIER` → пока фаза
#       активна, слайм рвётся к цели с сильно повышенной скоростью.
# Visual синхронно «подпрыгивает»: во время JUMP scale раздувается по Y
# и слегка сжимается по X через sin(t*PI) — стандартный squash-and-stretch.
#
# Почкование: при первом переходе WANDER→CHASE (агра) стартует
# BUD_DELAY-таймер. По истечении спавнится ещё один слайм рядом.
# Каждый слайм почкуется максимум один раз — `_has_budded` защищает
# от повторов, даже если слайм снова уходит в WANDER и опять агрится.
# Дочерний слайм — обычный, поэтому сам он тоже сможет отпочковаться
# при собственном первом агра.

const REST_DURATION: float = 0.55
const JUMP_DURATION: float = 0.35
const JUMP_SPEED_MULTIPLIER: float = 2.4
const BOUNCE_STRETCH_Y: float = 0.35
const BOUNCE_SQUASH_X: float = 0.15

const BUD_DELAY: float = 2.0
# Радиус спавна почки — «рядом»: min ~ 0.6 тайла, max ~ 1.1 тайла.
# Слишком близко — коллизии рвутся, слишком далеко — визуально
# теряется связь «мать → дочка».
const BUD_OFFSET_MIN: float = 12.0
const BUD_OFFSET_MAX: float = 22.0
const BUD_SPAWN_ATTEMPTS: int = 8
const BUD_FLOOR_TILE_SIZE: int = 20

enum JumpPhase { REST, JUMP }

var _jump_phase: int = JumpPhase.REST
var _phase_timer: float = 0.0
var _base_speed: float = 0.0
var _visual: Sprite2D
var _visual_base_scale: Vector2 = Vector2.ONE

var _has_budded: bool = false
var _bud_delay_timer: float = 0.0
var _was_chasing: bool = false

func _ready() -> void:
	super._ready()
	_base_speed = speed
	_visual = get_node_or_null("Visual") as Sprite2D
	if _visual != null:
		_visual_base_scale = _visual.scale
	# Стартуем с рандомного момента REST-фазы — группа слаймов не
	# прыгает в унисон, каждый по-своему.
	_phase_timer = randf() * REST_DURATION

func _physics_process(delta: float) -> void:
	_tick_phase(delta)
	_apply_visual_bounce()
	# Меняем speed до вызова super: super._chase_direct умножает
	# direction на speed, поэтому speed=0 полностью «замораживает»
	# слайма в REST, а x2.4 даёт заметный рывок в JUMP.
	if _jump_phase == JumpPhase.REST:
		speed = 0.0
	else:
		speed = _base_speed * JUMP_SPEED_MULTIPLIER
	super._physics_process(delta)
	# Восстанавливаем базу — потребители через `.speed` не увидят
	# временного значения.
	speed = _base_speed
	_tick_bud(delta)

func _tick_phase(delta: float) -> void:
	_phase_timer -= delta
	if _phase_timer > 0.0:
		return
	if _jump_phase == JumpPhase.REST:
		_jump_phase = JumpPhase.JUMP
		_phase_timer = JUMP_DURATION
	else:
		_jump_phase = JumpPhase.REST
		_phase_timer = REST_DURATION

func _apply_visual_bounce() -> void:
	if _visual == null:
		return
	if _jump_phase == JumpPhase.REST:
		_visual.scale = _visual_base_scale
		return
	# t: 0 → 1 → 0 за время JUMP_DURATION, sin(t*PI) даёт плавный пик.
	var t := clampf(1.0 - (_phase_timer / JUMP_DURATION), 0.0, 1.0)
	var bounce := sin(t * PI)
	_visual.scale = Vector2(
		_visual_base_scale.x * (1.0 - BOUNCE_SQUASH_X * bounce),
		_visual_base_scale.y * (1.0 + BOUNCE_STRETCH_Y * bounce),
	)

func _tick_bud(delta: float) -> void:
	if _has_budded:
		return
	var is_chasing := _state == State.CHASE
	# Ловим фронт WANDER→CHASE. Таймер стартует только один раз за
	# «сессию» агра: если слайм успел уйти в WANDER и снова агриться
	# ДО того как _bud_delay_timer истёк, timer продолжает тикать.
	if is_chasing and not _was_chasing and _bud_delay_timer <= 0.0:
		_bud_delay_timer = BUD_DELAY
	_was_chasing = is_chasing
	if _bud_delay_timer <= 0.0:
		return
	_bud_delay_timer -= delta
	if _bud_delay_timer > 0.0:
		return
	_bud_delay_timer = 0.0
	if _spawn_bud():
		_has_budded = true
	# Если спавн не удался (все ближайшие клетки — стены), _has_budded
	# остаётся false, но и таймер не рестартует автоматически — почка
	# просто пропадает. Это редкий edge case: слайм окружён стеной
	# со всех сторон одновременно.

func _spawn_bud() -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	var spawn_pos := _pick_bud_position()
	if spawn_pos == Vector2.INF:
		return false
	# load() вместо preload(): enemy.tscn использует slime.gd, из slime.gd
	# preload(enemy.tscn) даст циклическую зависимость на парсинге.
	var scene: PackedScene = load("res://scenes/enemies/enemy.tscn")
	if scene == null:
		return false
	var bud = scene.instantiate()
	bud.global_position = spawn_pos
	parent.add_child(bud)
	return true

func _pick_bud_position() -> Vector2:
	var floor_node := get_tree().get_first_node_in_group("floor")
	# Без Floor (тесты / автономный запуск) — просто случайное кольцо
	# без валидации, слайму хватит A* и stuck-detector'а чтобы выбраться.
	if floor_node == null or floor_node.astar_grid == null:
		return global_position + _random_bud_offset()
	for _i in BUD_SPAWN_ATTEMPTS:
		var candidate := global_position + _random_bud_offset()
		if _is_bud_walkable(floor_node, candidate):
			return candidate
	return Vector2.INF

func _random_bud_offset() -> Vector2:
	var angle := randf() * TAU
	var distance := randf_range(BUD_OFFSET_MIN, BUD_OFFSET_MAX)
	return Vector2(cos(angle), sin(angle)) * distance

func _is_bud_walkable(floor_node: Node, pos: Vector2) -> bool:
	var cell := Vector2i(int(pos.x / BUD_FLOOR_TILE_SIZE), int(pos.y / BUD_FLOOR_TILE_SIZE))
	if not floor_node.astar_grid.is_in_boundsv(cell):
		return false
	return not floor_node.astar_grid.is_point_solid(cell)
