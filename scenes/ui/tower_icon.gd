extends Control

# Процедурная иконка башни для HUD (bottom-right). Простой силуэт:
# крены сверху, тело башни, тёмное окно. 14×14 px, рисуется через _draw,
# чтобы не заводить PNG-ассет ради одной иконки.

const SIZE: float = 14.0
const STONE: Color = Color(0.72, 0.72, 0.75, 1)
const STONE_DARK: Color = Color(0.38, 0.38, 0.42, 1)
const WINDOW: Color = Color(0.12, 0.12, 0.18, 1)

func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	queue_redraw()

func _draw() -> void:
	# Тело башни (y=4..13).
	var body := Rect2(3.0, 4.0, 8.0, 9.0)
	draw_rect(body, STONE, true)
	draw_rect(body, STONE_DARK, false)
	# Три крена сверху (крен = зубец). Промежутки между ними — «вырубы».
	for x_off in [3.0, 6.0, 9.0]:
		draw_rect(Rect2(x_off, 2.0, 2.0, 2.0), STONE, true)
	# Окно посередине.
	draw_rect(Rect2(6.0, 7.0, 2.0, 3.0), WINDOW, true)
