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
	var t := clampf(_time_alive / LIFETIME, 0.0, 1.0)
	var alpha_factor: float
	if t < FADE_IN_FRACTION:
		alpha_factor = t / FADE_IN_FRACTION
	else:
		alpha_factor = 1.0 - (t - FADE_IN_FRACTION) / (1.0 - FADE_IN_FRACTION)
	alpha_factor = clampf(alpha_factor, 0.0, 1.0)
	var color := Color(CLOUD_COLOR.r, CLOUD_COLOR.g, CLOUD_COLOR.b, CLOUD_COLOR.a * alpha_factor)
	draw_circle(Vector2.ZERO, RADIUS, color)

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
