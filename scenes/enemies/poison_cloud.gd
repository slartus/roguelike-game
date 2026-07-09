extends Area2D

# Облако зловония, оставленное зомби. Живёт LIFETIME секунд, после
# чего queue_free. Игрок, вошедший в облако, получает статус
# «заражён ядом» на POISON_DURATION секунд.
#
# Рендер — процедурный через _draw (без спрайта): зелёный полупрозрачный
# круг с fade-in в первые 10% жизни и fade-out на оставшихся 90%. Так
# облако читается сразу, но не выглядит «моргнуло-исчезло».
#
# Начальный overlap: если игрок стоит в точке спавна, `body_entered`
# не срабатывает ретроактивно. Поэтому в _ready через call_deferred
# опрашиваем `get_overlapping_bodies()` и вручную вызываем handler
# для каждого пересекающегося тела.

const LIFETIME: float = 4.0
const RADIUS: float = 16.0
const POISON_DURATION: float = 3.0
const CLOUD_COLOR: Color = Color(0.4, 0.75, 0.2, 0.55)
const FADE_IN_FRACTION: float = 0.1
# Клубки: N штук на орбите вокруг центра. Каждый клубок дышит
# (радиус модулируется sin по времени) и медленно вращается вокруг
# центра — облако «шевелится», а не стоит статичной кляксой.
const PUFF_COUNT: int = 6
const PUFF_ORBIT_RADIUS: float = 9.0
const PUFF_BASE_RADIUS: float = 8.5
const PUFF_PULSE_AMPLITUDE: float = 2.0
const PUFF_PULSE_FREQUENCY: float = 1.9
const CLOUD_ROTATION_SPEED: float = 0.55
const CORE_PUFF_RADIUS: float = 7.0
const CORE_PUFF_ALPHA_MULT: float = 1.15
const PUFF_ALPHA_MULT: float = 0.8
const PUFF_GREEN_MULT: float = 1.05
const PUFF_BLUE_MULT: float = 0.8

var _time_alive: float = 0.0

func _ready() -> void:
	add_to_group("poison_cloud")
	body_entered.connect(_on_body_entered)
	call_deferred("_check_initial_overlap")
	queue_redraw()

func _process(delta: float) -> void:
	_time_alive += delta
	queue_redraw()
	if _time_alive >= LIFETIME:
		queue_free()

func _draw() -> void:
	var alpha_factor := _current_alpha_factor()
	var base_color := Color(
		CLOUD_COLOR.r,
		CLOUD_COLOR.g,
		CLOUD_COLOR.b,
		CLOUD_COLOR.a * alpha_factor,
	)
	# Центральный тёмно-зелёный «сгусток» — чтобы облако выглядело плотным
	# в центре и не читалось как «6 отдельных кружков».
	var core_color := Color(
		base_color.r * 0.9,
		base_color.g,
		base_color.b * 0.7,
		base_color.a * CORE_PUFF_ALPHA_MULT,
	)
	draw_circle(Vector2.ZERO, CORE_PUFF_RADIUS, core_color)
	# Клубки на орбите — вращение + пульсация радиуса.
	var rotation_offset := _time_alive * CLOUD_ROTATION_SPEED
	var puff_color := Color(
		base_color.r,
		base_color.g * PUFF_GREEN_MULT,
		base_color.b * PUFF_BLUE_MULT,
		base_color.a * PUFF_ALPHA_MULT,
	)
	for i in PUFF_COUNT:
		var angle := TAU * float(i) / float(PUFF_COUNT) + rotation_offset
		var pos := Vector2(cos(angle), sin(angle)) * PUFF_ORBIT_RADIUS
		# Фазовый сдвиг по индексу — соседние клубки дышат в противофазу,
		# облако визуально «клубится», а не пульсирует одним куском.
		var pulse := sin(_time_alive * PUFF_PULSE_FREQUENCY + float(i))
		var radius := PUFF_BASE_RADIUS + pulse * PUFF_PULSE_AMPLITUDE
		draw_circle(pos, radius, puff_color)

func _current_alpha_factor() -> float:
	var t := clampf(_time_alive / LIFETIME, 0.0, 1.0)
	var alpha_factor: float
	if t < FADE_IN_FRACTION:
		alpha_factor = t / FADE_IN_FRACTION
	else:
		alpha_factor = 1.0 - (t - FADE_IN_FRACTION) / (1.0 - FADE_IN_FRACTION)
	return clampf(alpha_factor, 0.0, 1.0)

func _check_initial_overlap() -> void:
	# call_deferred → выполняется на idle frame после того как физика
	# зарегистрировала Area2D. get_overlapping_bodies() к этому моменту
	# уже даёт корректный список.
	if not is_inside_tree():
		return
	for body in get_overlapping_bodies():
		_on_body_entered(body)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if body.has_method("apply_poison"):
		body.apply_poison(POISON_DURATION)
