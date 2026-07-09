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
const LANDED_LIFETIME: float = 6.0
const FLYING_RADIUS: float = 3.0
const LANDED_RADIUS: float = 14.0
const WEB_COLOR_FLYING: Color = Color(0.95, 0.95, 0.95, 0.85)
const WEB_COLOR_LANDED: Color = Color(0.9, 0.9, 0.95, 0.75)
# Кобвеб-рендер приземлившейся паутины: N радиальных нитей + M
# концентрических колец, полупрозрачный «липкий» диск-подложка.
const WEB_SPOKE_COUNT: int = 8
const WEB_RING_COUNT: int = 3
const WEB_RING_SEGMENTS: int = 20
const WEB_LINE_WIDTH: float = 1.0
const WEB_BACKING_ALPHA_MULT: float = 0.35

var target_position: Vector2 = Vector2.ZERO
var _state: int = State.FLYING
var _landed_timer: float = 0.0
var _shape: CollisionShape2D
var _circle: CircleShape2D

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
	# body_entered edge-triggered: игрок, уже перекрывавший FLYING-web,
	# при переходе в LANDED сигнала не получит. Плюс раздутый радиус
	# может теперь включить игрока, который FLYING не касался. Deferred
	# опрос ждёт следующего physics-тика, когда Godot обновит список.
	call_deferred("_apply_slow_to_current_overlap")

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
	# Радиальные нити от центра к внешнему кольцу.
	for spoke_index in WEB_SPOKE_COUNT:
		var angle := TAU * float(spoke_index) / float(WEB_SPOKE_COUNT)
		var tip := Vector2(cos(angle), sin(angle)) * LANDED_RADIUS
		draw_line(Vector2.ZERO, tip, line_color, WEB_LINE_WIDTH, true)
	# Концентрические кольца через polyline — образуют «сетку» паутины.
	for ring_index in range(1, WEB_RING_COUNT + 1):
		var ring_radius := LANDED_RADIUS * float(ring_index) / float(WEB_RING_COUNT)
		var pts := PackedVector2Array()
		for seg in WEB_RING_SEGMENTS + 1:
			var seg_angle := TAU * float(seg) / float(WEB_RING_SEGMENTS)
			pts.append(Vector2(cos(seg_angle), sin(seg_angle)) * ring_radius)
		draw_polyline(pts, line_color, WEB_LINE_WIDTH, true)

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
