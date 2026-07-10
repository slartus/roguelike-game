extends Control

# Процедурная иконка монеты для HUD (bottom-right). Рисуем через _draw,
# чтобы не заводить отдельный PNG-ассет ради 14×14 иконки — тон совпадает
# с золотой палитрой (см. также environment/candle-flame золото).

const SIZE: float = 14.0
const GOLD_OUTER: Color = Color(0.98, 0.78, 0.22, 1)
const GOLD_INNER: Color = Color(1.0, 0.9, 0.36, 1)
const GOLD_HIGHLIGHT: Color = Color(1.0, 1.0, 0.85, 1)
const RIM_DARK: Color = Color(0.55, 0.42, 0.1, 1)

func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	queue_redraw()

func _draw() -> void:
	var center := Vector2(SIZE * 0.5, SIZE * 0.5)
	draw_circle(center, SIZE * 0.48, RIM_DARK)
	draw_circle(center, SIZE * 0.42, GOLD_OUTER)
	draw_circle(center, SIZE * 0.30, GOLD_INNER)
	draw_circle(center - Vector2(SIZE * 0.13, SIZE * 0.15), SIZE * 0.09, GOLD_HIGHLIGHT)
