class_name MeleeHitbox
extends Area2D

# Hitbox ближнего боя. Форма зависит от attack_type:
# - melee_arc: круговой сектор радиуса `length` с углом `arc_degrees`. Собираем
#   через CircleShape2D (радиус) + локальный angular-filter в _try_hit —
#   Godot не умеет polygon-sector shape без вложенного polygon, а CircleShape
#   + фильтр даёт то же поведение дешевле.
# - melee_thrust: длинный узкий прямоугольник RectangleShape2D(length × width),
#   сдвинутый на length/2 вперёд — читается как укол копьём.
#
# Rotation Area2D всегда = direction.angle() → локальный +X совпадает с
# направлением атаки. Это упрощает и sector-фильтр (сравниваем с 0 rad),
# и _draw в локальных координатах.
#
# Визуал: процедурная отрисовка через _draw. Живёт longer than active_time —
# active фаза наносит урон, visual фаза добивает fade-out даже если удар уже
# отработал. Итоговое queue_free — по _visual_life.

const MIN_VISUAL_LIFE := 0.16
const FADE_IN_RATIO := 0.15
const HOLD_RATIO := 0.35
const ARC_SEGMENTS := 14
# Два «ветерка» — тонкие дуги на разном радиусе, читаются как след клинка.
# Внутренняя короче (стартовая часть замаха), внешняя длиннее (конец замаха).
const ARC_INNER_RADIUS_RATIO := 0.55
const ARC_OUTER_RADIUS_RATIO := 0.92
const ARC_LINE_WIDTH := 2.0
# Каждый ветерок покрывает не всю дугу, а её среднюю часть — так на концах
# сектора получаются «хвосты», а не резкий обрыв.
const ARC_STREAK_COVERAGE := 0.85
const SWING_COLOR := Color(1.0, 0.95, 0.7, 0.7)
const SWING_EDGE_COLOR := Color(1.0, 0.98, 0.85, 0.9)
const THRUST_TIP_COLOR := Color(1.0, 0.9, 0.6, 0.9)
# Для thrust — два коротких forward-штриха на разной высоте, читаются как
# «свист» вокруг древка копья.
const THRUST_STREAK_LENGTH_RATIO := 0.7
const THRUST_STREAK_OFFSET_RATIO := 0.35

var attack_type: String = "melee_arc"
var damage: int = 1
var knockback: float = 0.0
var active_time: float = 0.08
var arc_degrees: float = 80.0
var hitbox_length: float = 36.0
var hitbox_width: float = 34.0
# Attribution: weapon_id для аналитики. Пустая StringName → attribution
# на level "unknown". WeaponController выставляет через configure().
var source_weapon_id: StringName = &""
# attacks_with_hit нужно инкрементить не более одного раза на activation,
# даже если hitbox цепляет несколько targets в одном arc'е.
var _analytics_hit_recorded: bool = false

var _source_position: Vector2 = Vector2.ZERO
var _shape: CollisionShape2D
var _hit_targets: Dictionary = {}
var _life_timer: float = 0.0
var _visual_life: float = 0.0
var _did_initial_scan: bool = false
var _stopped_damaging: bool = false
# Кешируем половину угла в радианах — на каждый _try_hit и каждый _draw
# всё равно нужно, посчитаем один раз в configure().
var _half_arc_rad: float = 0.0

func _ready() -> void:
	# configure() создаёт CollisionShape2D через add_child до того как сам
	# hitbox добавлен в дерево. Godot автоименует его @CollisionShape2D@ /
	# похоже — get_node("CollisionShape2D") не найдёт, ищем по типу через
	# children. Если shape нет — забыли configure(), это dev-error.
	for child in get_children():
		if child is CollisionShape2D:
			_shape = child
			break
	assert(_shape != null, "MeleeHitbox: configure() должен быть вызван до add_child")
	body_entered.connect(_on_body_entered)

# Настраивается ДО add_child, чтобы _ready увидел уже финальный box.
func configure(
	source: Node2D,
	direction: Vector2,
	dmg: int,
	length: float,
	width: float,
	life: float,
	kb: float,
	type: String = "melee_arc",
	arc_deg: float = 80.0,
) -> void:
	attack_type = type
	damage = dmg
	knockback = kb
	active_time = life
	arc_degrees = arc_deg
	hitbox_length = length
	hitbox_width = width
	_half_arc_rad = deg_to_rad(arc_degrees) * 0.5
	# Оставляем visual чуть дольше чем active — active_time у оружия ~80 ms,
	# на 60 FPS это ~5 кадров и глазом не читается. MIN_VISUAL_LIFE даёт
	# fade-out после того как урон уже отработал.
	_visual_life = maxf(active_time, MIN_VISUAL_LIFE)
	# Хранение source position нужно для sector-filter'а arc'а: угол считаем
	# от _source_position → body, не от global_position самого hitbox'а
	# (для thrust они разные — hitbox смещён на length/2 вперёд).
	_source_position = source.global_position
	var angle := direction.angle()
	rotation = angle
	var cs := CollisionShape2D.new()
	match attack_type:
		"melee_thrust":
			# Прямоугольник в front of source: сдвигаем на length/2 вперёд,
			# CollisionShape точно центрирован на позиции узла.
			global_position = _source_position + direction * (length * 0.5)
			var rect := RectangleShape2D.new()
			rect.size = Vector2(length, width)
			cs.shape = rect
		_:
			# melee_arc и любой неизвестный тип → сектор круга. hitbox стоит
			# в источнике, radius = length, dead zone за спиной отрезается
			# angular-фильтром в _try_hit.
			global_position = _source_position
			var circle := CircleShape2D.new()
			circle.radius = length
			cs.shape = circle
	add_child(cs)

func _physics_process(delta: float) -> void:
	# Первый physics tick — враги, стоявшие внутри hitbox'а на момент
	# spawn'а, ещё не выдали body_entered (сигнал шлётся только на новом
	# overlap). Сканируем текущий snapshot сами. На последующих кадрах —
	# только body_entered, чтобы не дублировать удары.
	if not _did_initial_scan:
		_did_initial_scan = true
		for body in get_overlapping_bodies():
			_try_hit(body)
	_life_timer += delta
	# После active_time — гасим hitbox: больше не бьём и не мониторим новые
	# overlap'ы, но продолжаем рендериться до _visual_life.
	if _life_timer >= active_time and not _stopped_damaging:
		_stopped_damaging = true
		monitoring = false
	# queue_redraw — alpha меняется каждый кадр, статичная картинка не
	# передаст «взмаха и затухания».
	queue_redraw()
	if _life_timer >= _visual_life:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if _stopped_damaging:
		return
	_try_hit(body)

func _try_hit(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("player"):
		return
	if _hit_targets.has(body):
		return
	if not body.has_method("take_damage"):
		return
	if not _is_in_damage_sector(body):
		return
	if not _has_line_of_sight_to(body):
		# Между источником удара и врагом стена — арка/укол не должны
		# доставать сквозь неё, даже если враг геометрически в секторе.
		return
	_hit_targets[body] = true
	# Attribution: собираем DamageContext от weapon → enemy.
	var ctx := DamageContext.new()
	ctx.source_type = &"player_weapon"
	ctx.source_id = source_weapon_id
	ctx.attack_id = StringName(attack_type)
	ctx.target_type = &"enemy"
	if body.scene_file_path != "":
		ctx.target_id = StringName(body.scene_file_path.get_file().get_basename())
	if "temperament_id" in body:
		ctx.temperament_id = StringName(str(body.temperament_id))
	if "elite_rank" in body:
		ctx.elite_rank = int(body.elite_rank)
	# source_level = уровень источника (weapon), НЕ target'а — оставляем 0.
	body.take_damage(damage, ctx)
	# attacks_with_hit — один раз на activation, независимо от N целей.
	if not _analytics_hit_recorded:
		Analytics.record_player_attack_hit(source_weapon_id)
		_analytics_hit_recorded = true
	# Knockback пока опциональный: если у target есть метод apply_knockback,
	# зовём его. Иначе тихо игнорируем — M3 задокументировано как "если
	# легко сделать". Сложный knockback остаётся на будущее.
	if knockback > 0.0 and body.has_method("apply_knockback"):
		var direction_to_body: Vector2 = (body.global_position - _source_position).normalized()
		body.apply_knockback(direction_to_body * knockback)

# Для thrust форма — прямоугольник, сама CollisionShape уже отрезает всё
# лишнее, фильтр не нужен. Для arc — фильтруем по углу: только тела внутри
# сектора ±_half_arc_rad от направления атаки (локальный +X).
func _is_in_damage_sector(body: Node) -> bool:
	if attack_type == "melee_thrust":
		return true
	if not (body is Node2D):
		return true
	var to_body_local: Vector2 = (body.global_position - _source_position).rotated(-rotation)
	# Дегенеративный случай: тело ровно в источнике. Считаем «попал».
	if to_body_local.length_squared() <= 0.0001:
		return true
	return absf(to_body_local.angle()) <= _half_arc_rad

func _has_line_of_sight_to(body: Node) -> bool:
	if not (body is Node2D):
		return true
	return LineOfSight.is_clear(get_world_2d(), _source_position, body.global_position)

func _draw() -> void:
	var alpha := _visual_alpha()
	if alpha <= 0.0:
		return
	match attack_type:
		"melee_thrust":
			_draw_thrust(alpha)
		_:
			_draw_arc(alpha)

func _visual_alpha() -> float:
	if _visual_life <= 0.0:
		return 0.0
	var t: float = clampf(_life_timer / _visual_life, 0.0, 1.0)
	if t < FADE_IN_RATIO:
		return t / FADE_IN_RATIO
	var end_hold := FADE_IN_RATIO + HOLD_RATIO
	if t < end_hold:
		return 1.0
	return 1.0 - (t - end_hold) / (1.0 - end_hold)

func _draw_arc(alpha: float) -> void:
	# Локальные координаты: +X = направление атаки, origin = игрок.
	# Вместо заливки сектора рисуем два «ветерка» — тонкие дуги на разном
	# радиусе. Читаются как след клинка, не перекрывают игровое поле.
	var inner_edge := SWING_COLOR
	inner_edge.a *= alpha * 0.85
	var outer_edge := SWING_EDGE_COLOR
	outer_edge.a *= alpha
	var coverage_half := _half_arc_rad * ARC_STREAK_COVERAGE
	_draw_arc_streak(hitbox_length * ARC_INNER_RADIUS_RATIO, coverage_half, inner_edge)
	_draw_arc_streak(hitbox_length * ARC_OUTER_RADIUS_RATIO, coverage_half, outer_edge)

func _draw_arc_streak(radius: float, coverage_half: float, color: Color) -> void:
	# Полилиния по дуге радиуса `radius`, охватывающая ±coverage_half от
	# направления атаки. draw_polyline даёт постоянную толщину и корректные
	# стыки без «зубцов» на низком segments count.
	var points := PackedVector2Array()
	for i in ARC_SEGMENTS + 1:
		var a: float = lerpf(-coverage_half, coverage_half, float(i) / ARC_SEGMENTS)
		points.append(Vector2(cos(a), sin(a)) * radius)
	draw_polyline(points, color, ARC_LINE_WIDTH, true)

func _draw_thrust(alpha: float) -> void:
	# Для thrust вместо заливки прямоугольника — два коротких «ветерка»
	# вдоль направления укола на разной высоте (сверху/снизу от древка) +
	# треугольный наконечник у переднего края. Даёт визуал «свиста копья»,
	# не закрывает врага сплошным прямоугольником.
	var half_len := hitbox_length * 0.5
	var streak_len := hitbox_length * THRUST_STREAK_LENGTH_RATIO
	var streak_offset := hitbox_width * THRUST_STREAK_OFFSET_RATIO
	var streak_color := SWING_EDGE_COLOR
	streak_color.a *= alpha
	# Верхний штрих: от -streak_len/2 до +streak_len/2 по локальному X,
	# y = -streak_offset.
	draw_line(
		Vector2(-streak_len * 0.5, -streak_offset),
		Vector2(streak_len * 0.5, -streak_offset),
		streak_color,
		ARC_LINE_WIDTH,
	)
	draw_line(
		Vector2(-streak_len * 0.5, streak_offset),
		Vector2(streak_len * 0.5, streak_offset),
		streak_color,
		ARC_LINE_WIDTH,
	)
	var tip := THRUST_TIP_COLOR
	tip.a *= alpha
	var tip_len := minf(6.0, hitbox_length * 0.2)
	var tip_wid := hitbox_width * 0.5 + 3.0
	var tip_points := PackedVector2Array([
		Vector2(half_len, 0.0),
		Vector2(half_len - tip_len, -tip_wid),
		Vector2(half_len - tip_len, tip_wid),
	])
	draw_colored_polygon(tip_points, tip)
