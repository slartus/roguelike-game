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
# Скрипт делится на Adult (enemy.tscn) и Small (small_slime.tscn) варианты
# через @export'ы can_bud / can_split_on_death / bud_scene / death_split_scene.
#
# Почкование: если can_bud=true и есть bud_scene — при первом переходе
# WANDER→CHASE стартует BUD_DELAY-таймер, по истечении спавнится дитё из
# bud_scene. Каждый слайм почкуется максимум один раз (`_has_budded`).
# У Adult bud_scene = small_slime.tscn (в .tscn) — почка это Small.
# Small имеет can_bud=false и сам не почкуется.
#
# Разделение при смерти: если can_split_on_death=true и есть death_split_scene —
# при летальном ударе спавнятся death_split_count детей из death_split_scene.
# У Adult death_split_scene = small_slime.tscn — Adult распадается на 2 Small.
# Экономический баланс держится через собственные stat Small Slime
# (max_health=1, xp=2, gold=1) в его .tscn, а не runtime-половинием на кадре
# смерти. pickup_scene у детей обнуляется, чтобы почкование не превращалось
# в лут-механику.

const REST_DURATION: float = 0.55
const JUMP_DURATION: float = 0.35
const JUMP_SPEED_MULTIPLIER: float = 2.4
const BOUNCE_STRETCH_Y: float = 0.35
const BOUNCE_SQUASH_X: float = 0.15

const BUD_DELAY: float = 4.0
# Радиус спавна почки — «рядом»: min ~ 0.6 тайла, max ~ 1.1 тайла.
# Слишком близко — коллизии рвутся, слишком далеко — визуально
# теряется связь «мать → дочка».
const BUD_OFFSET_MIN: float = 12.0
const BUD_OFFSET_MAX: float = 22.0
const BUD_SPAWN_ATTEMPTS: int = 8
const BUD_FLOOR_TILE_SIZE: int = 20

# Осколки летят по противоположным сторонам от точки смерти на
# DEATH_SPLIT_OFFSET пикселей. Значение подобрано под визуал Small Slime
# (~r=3.5 в мире), чтобы два ребёнка не перекрывались коллизиями.
const DEATH_SPLIT_OFFSET: float = 4.0

# Разделяем семейство слаймов на Adult (эта сцена, enemy.tscn) и Small
# (small_slime.tscn). Adult размножается: почкуется при агре и распадается
# на Small при смерти. Small не размножается: can_bud=false и
# can_split_on_death=false в .tscn small_slime.tscn.
#
# bud_scene / death_split_scene позволяют задать «во что именно» превращаются
# дети — обычно это ExtResource small_slime.tscn. Если сцена не задана,
# соответствующая механика не работает (spawn_bud вернёт false).
@export var can_bud: bool = true
@export var can_split_on_death: bool = true
@export var bud_scene: PackedScene
@export var death_split_scene: PackedScene
@export var death_split_count: int = 2

enum JumpPhase { REST, JUMP }

var _jump_phase: int = JumpPhase.REST
var _phase_timer: float = 0.0
var _base_speed: float = 0.0
var _visual: Sprite2D
var _visual_base_scale: Vector2 = Vector2.ONE

var _has_budded: bool = false
var _bud_delay_timer: float = 0.0
var _was_chasing: bool = false

# Runtime-override для сценариев, где даже Adult нужно временно
# запретить почковаться и делиться (например, спавн из другого места
# без дальнейшего размножения). Основной путь блокировки — через
# can_bud / can_split_on_death в .tscn (Small Slime).
var _is_sterile: bool = false

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
	if _has_budded or _is_sterile or not can_bud:
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
	if bud_scene == null:
		return false
	var parent := get_parent()
	if parent == null:
		return false
	var spawn_pos := _pick_bud_position()
	if spawn_pos == Vector2.INF:
		return false
	var bud = bud_scene.instantiate()
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

func take_damage(amount: int) -> void:
	# super.take_damage — coroutine с await get_tree().create_timer(0.08).
	# Синхронная часть (health -= amount, modulate = red) уже выполнилась
	# к моменту, когда super yield'нется на await. Не await'им super,
	# чтобы наш split-код спавнил детей ДО того как super.queue_free()
	# уберёт мать из дерева — иначе get_parent()/global_position перестанут
	# быть валидными.
	var was_alive := health > 0
	super.take_damage(amount)
	if was_alive and health <= 0 and not _is_sterile and can_split_on_death:
		_spawn_death_split()

func _spawn_death_split() -> void:
	if death_split_scene == null:
		return
	var parent := get_parent()
	if parent == null:
		return
	# Случайный угол разлёта: дети летят в противоположные стороны от
	# точки смерти, чтобы не спавниться поверх друг друга.
	var angle := randf() * TAU
	var axis := Vector2(cos(angle), sin(angle)) * DEATH_SPLIT_OFFSET
	for i in death_split_count:
		var child = death_split_scene.instantiate()
		var offset := axis if i == 0 else -axis
		child.global_position = global_position + offset
		parent.add_child(child)
		# Осколки Small Slime уже балансируются собственными stat в
		# small_slime.tscn (низкий HP, xp=2, gold=1). Экономически цепь
		# «adult 5xp + 2 × 2xp = 9xp» слабее чем «одиночный adult
		# + одиночный small свободные» — фарм-баланс из .tscn.
		# Pickup всё равно занулим — иначе small unconstrained мог бы
		# ронять зелья и превращать почкование в лут-механику.
		child.pickup_scene = null
