extends Area2D

# Паутина, выплюнутая пауком в место нахождения игрока.
# Two-phase жизнь:
#   FLYING — летит по прямой к target_position со скоростью FLIGHT_SPEED,
#            коллизия маленькая (FLYING_RADIUS), НЕ триггерит slow.
#   LANDED — приземлилась на target_position, коллизия раздувается до
#            LANDED_RADIUS, живёт LANDED_LIFETIME секунд и `queue_free`.
#            Только в LANDED игрок в области получает slow — иначе сам
#            факт пролёта паутины над игроком уже давал бы эффект.
#
# Slow работает через счётчик источников на игроке (см. player.gd):
# каждая LANDED-паутина, содержащая игрока, +1 к _slow_source_count.
# `body_exited` / `queue_free` снимают +1 обратно.
#
# CircleShape2D в _ready пересоздаётся уникальным для инстанса — иначе
# при spawn'е нескольких паутин `_shape.shape.radius = ...` мутировал бы
# один общий sub_resource, и все инстансы получили бы одинаковый радиус.

enum State { FLYING, LANDED }

const FLIGHT_SPEED: float = 140.0
const LANDING_THRESHOLD: float = 3.0
const LANDED_LIFETIME: float = 12.0
const FLYING_RADIUS: float = 3.0
const LANDED_RADIUS: float = 14.0
const WEB_COLOR_FLYING: Color = Color(0.95, 0.95, 0.95, 0.85)
const WEB_COLOR_LANDED: Color = Color(0.9, 0.9, 0.95, 0.75)
# Рваная кобвеб-геометрия: каждая нить имеет случайную длину и угловой
# jitter, каждое кольцо разорвано на несколько арок с пропусками —
# паутина выглядит потрёпанной, а не идеально симметричной.
const WEB_SPOKE_COUNT: int = 8
const WEB_SPOKE_LENGTH_MIN_RATIO: float = 0.55
const WEB_SPOKE_LENGTH_MAX_RATIO: float = 1.0
const WEB_SPOKE_ANGLE_JITTER: float = 0.18
const WEB_RING_COUNT: int = 3
const WEB_RING_SEGMENTS: int = 24
const WEB_RING_GAP_COUNT: int = 2
const WEB_RING_GAP_ARC_MIN: float = 0.25
const WEB_RING_GAP_ARC_MAX: float = 0.7
const WEB_LINE_WIDTH: float = 1.0
const WEB_BACKING_ALPHA_MULT: float = 0.25
# Оборванные висящие концы у части нитей — маленький «хвостик» под углом.
const WEB_STRAND_TAIL_CHANCE: float = 0.5
const WEB_STRAND_TAIL_LENGTH: float = 3.0
const WEB_STRAND_TAIL_ANGLE_JITTER: float = 0.9

var target_position: Vector2 = Vector2.ZERO
var _state: int = State.FLYING
var _landed_timer: float = 0.0
var _shape: CollisionShape2D
var _circle: CircleShape2D
# Кешированная рваная геометрия — считается один раз при приземлении,
# чтобы форма паутины не мигала каждый кадр.
var _spoke_endpoints: PackedVector2Array = PackedVector2Array()
var _spoke_tails: Array = []             # Array[Array[Vector2]] (endpoint, tail_tip)
var _ring_arcs: Array = []               # Array[Array[PackedVector2Array]]

func _ready() -> void:
	add_to_group("spider_web")
	_shape = $CollisionShape2D
	_circle = CircleShape2D.new()
	_circle.radius = FLYING_RADIUS
	_shape.shape = _circle
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	queue_redraw()

func _process(delta: float) -> void:
	queue_redraw()
	if _state == State.FLYING:
		_tick_flight(delta)
	else:
		_tick_landed(delta)

func _tick_flight(delta: float) -> void:
	var to_target := target_position - global_position
	if to_target.length() <= LANDING_THRESHOLD:
		_enter_landed()
		return
	global_position += to_target.normalized() * FLIGHT_SPEED * delta

func _tick_landed(delta: float) -> void:
	_landed_timer -= delta
	if _landed_timer <= 0.0:
		_release_all_slowed_bodies()
		queue_free()

func _enter_landed() -> void:
	global_position = target_position
	_state = State.LANDED
	_landed_timer = LANDED_LIFETIME
	_circle = CircleShape2D.new()
	_circle.radius = LANDED_RADIUS
	_shape.shape = _circle
	_build_ragged_geometry()
	# body_entered edge-triggered: игрок, уже перекрывавший FLYING-web,
	# при переходе в LANDED сигнала не получит. Плюс раздутый радиус
	# может теперь включить игрока, который FLYING не касался. Deferred
	# опрос ждёт следующего physics-тика, когда Godot обновит список.
	call_deferred("_apply_slow_to_current_overlap")

func _build_ragged_geometry() -> void:
	# Считается один раз при приземлении и кешируется — нити не «дышат»
	# каждый кадр, паутина висит как единая порванная сетка.
	_spoke_endpoints = PackedVector2Array()
	_spoke_tails = []
	for spoke_index in WEB_SPOKE_COUNT:
		var base_angle := TAU * float(spoke_index) / float(WEB_SPOKE_COUNT)
		var angle := base_angle + randf_range(-WEB_SPOKE_ANGLE_JITTER, WEB_SPOKE_ANGLE_JITTER)
		var length_ratio := randf_range(WEB_SPOKE_LENGTH_MIN_RATIO, WEB_SPOKE_LENGTH_MAX_RATIO)
		var length := LANDED_RADIUS * length_ratio
		var direction := Vector2(cos(angle), sin(angle))
		var tip := direction * length
		_spoke_endpoints.append(tip)
		# Половина нитей заканчивается коротким «хвостом» под углом —
		# как оборванная порванная нить.
		if randf() < WEB_STRAND_TAIL_CHANCE:
			var tail_angle := angle + randf_range(-WEB_STRAND_TAIL_ANGLE_JITTER, WEB_STRAND_TAIL_ANGLE_JITTER)
			var tail_tip := tip + Vector2(cos(tail_angle), sin(tail_angle)) * WEB_STRAND_TAIL_LENGTH
			_spoke_tails.append([tip, tail_tip])
	_ring_arcs = []
	for ring_index in range(1, WEB_RING_COUNT + 1):
		var ring_radius := LANDED_RADIUS * float(ring_index) / float(WEB_RING_COUNT)
		_ring_arcs.append(_build_ring_arcs(ring_radius))

func _build_ring_arcs(ring_radius: float) -> Array:
	# Кольцо разорвано на арки: делим круг на WEB_RING_GAP_COUNT
	# пропусков и рисуем сектора между ними. Пропуски случайной ширины,
	# случайные стартовые углы — каждое кольцо получает свой «рисунок».
	var gaps := []
	for _i in WEB_RING_GAP_COUNT:
		var gap_start := randf() * TAU
		var gap_arc := randf_range(WEB_RING_GAP_ARC_MIN, WEB_RING_GAP_ARC_MAX)
		gaps.append([gap_start, fmod(gap_start + gap_arc, TAU)])
	# Прогоняем полный круг с шагом-сегментом и сохраняем в текущую арку
	# только точки, не попадающие в один из пропусков. При попадании
	# закрываем текущую арку и начинаем новую.
	var arcs: Array = []
	var current := PackedVector2Array()
	for seg in WEB_RING_SEGMENTS + 1:
		var seg_angle := TAU * float(seg) / float(WEB_RING_SEGMENTS)
		if _is_in_any_gap(seg_angle, gaps):
			if current.size() >= 2:
				arcs.append(current)
			current = PackedVector2Array()
			continue
		current.append(Vector2(cos(seg_angle), sin(seg_angle)) * ring_radius)
	if current.size() >= 2:
		arcs.append(current)
	return arcs

func _is_in_any_gap(angle: float, gaps: Array) -> bool:
	var normalized := fmod(angle, TAU)
	if normalized < 0.0:
		normalized += TAU
	for gap in gaps:
		var start_a: float = gap[0]
		var end_a: float = gap[1]
		if start_a <= end_a:
			if normalized >= start_a and normalized <= end_a:
				return true
		else:
			# Пропуск пересекает 0 — проверяем две ветки.
			if normalized >= start_a or normalized <= end_a:
				return true
	return false

func _apply_slow_to_current_overlap() -> void:
	if not is_inside_tree():
		return
	for body in get_overlapping_bodies():
		_apply_slow(body)

func _draw() -> void:
	if _state == State.FLYING:
		_draw_flying_glob()
	else:
		_draw_landed_cobweb()

func _draw_flying_glob() -> void:
	# «Липкий комок»: основная круглая масса + маленький светлый блик
	# со смещением, чтобы глоб не выглядел плоским кругом в полёте.
	draw_circle(Vector2.ZERO, FLYING_RADIUS, WEB_COLOR_FLYING)
	var highlight := Color(1.0, 1.0, 1.0, WEB_COLOR_FLYING.a * 0.6)
	draw_circle(Vector2(-FLYING_RADIUS * 0.4, -FLYING_RADIUS * 0.4), FLYING_RADIUS * 0.45, highlight)

func _draw_landed_cobweb() -> void:
	# Ближе к концу LANDED — плавно затухаем, чтобы игрок видел
	# приближающееся исчезновение паутины.
	var t := clampf(1.0 - _landed_timer / LANDED_LIFETIME, 0.0, 1.0)
	var alpha_factor := 1.0 if t < 0.75 else 1.0 - (t - 0.75) / 0.25
	var line_color := Color(
		WEB_COLOR_LANDED.r,
		WEB_COLOR_LANDED.g,
		WEB_COLOR_LANDED.b,
		WEB_COLOR_LANDED.a * clampf(alpha_factor, 0.0, 1.0),
	)
	# Мягкая подложка-диск — чтобы липкая зона читалась даже если
	# радиальные нити «пустоваты».
	var backing := Color(line_color.r, line_color.g, line_color.b, line_color.a * WEB_BACKING_ALPHA_MULT)
	draw_circle(Vector2.ZERO, LANDED_RADIUS, backing)
	# Радиальные нити — с случайными длинами и небольшим угловым jitter.
	for tip in _spoke_endpoints:
		draw_line(Vector2.ZERO, tip, line_color, WEB_LINE_WIDTH, true)
	# Оборванные «хвосты» — короткий отрезок из конца нити под углом.
	for tail_pair in _spoke_tails:
		var tail_start: Vector2 = tail_pair[0]
		var tail_end: Vector2 = tail_pair[1]
		draw_line(tail_start, tail_end, line_color, WEB_LINE_WIDTH, true)
	# Кольца-арки — каждое кольцо разорвано на несколько дуг с пропусками.
	for ring_arcs in _ring_arcs:
		for arc in ring_arcs:
			draw_polyline(arc, line_color, WEB_LINE_WIDTH, true)

func _on_body_entered(body: Node) -> void:
	# В FLYING паутина «пролетает» мимо игрока — slow не применяется.
	if _state != State.LANDED:
		return
	_apply_slow(body)

func _on_body_exited(body: Node) -> void:
	if _state != State.LANDED:
		return
	_release_slow(body)

func _apply_slow(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if body.has_method("enter_slow_source"):
		body.enter_slow_source()

func _release_slow(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if body.has_method("exit_slow_source"):
		body.exit_slow_source()

func _release_all_slowed_bodies() -> void:
	# Финальный «выпуск»: если паутина исчезает пока игрок ещё внутри,
	# без ручного релиза счётчик slow-источников на игроке зависнет и
	# он останется медленным навсегда.
	if not is_inside_tree():
		return
	for body in get_overlapping_bodies():
		_release_slow(body)
