extends Control

# Мини-превью одного этажа: рисует rooms, corridors, player start (зелёный
# круг) и exit (жёлтый круг) в заданной области. Масштабируется под
# rect_size. Используется в dungeon_preview_screen.

const BACKGROUND: Color = Color(0.06, 0.05, 0.09, 1)
const WALL: Color = Color(0.09, 0.08, 0.12, 1)
const FLOOR_COLOR: Color = Color(0.35, 0.32, 0.42, 1)
const CORRIDOR_COLOR: Color = Color(0.28, 0.26, 0.36, 1)
const START_COLOR: Color = Color(0.4, 0.9, 0.4, 1)
const EXIT_COLOR: Color = Color(0.95, 0.85, 0.2, 1)
const OUTLINE: Color = Color(0.15, 0.12, 0.18, 1)

var layout: DungeonLayout
var floor_number: int = 0

func set_data(new_layout: DungeonLayout, new_floor_number: int) -> void:
	layout = new_layout
	floor_number = new_floor_number
	queue_redraw()

func _draw() -> void:
	if layout == null:
		return
	var bounds := layout.floor_bounds
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return
	# Масштабирование: fit floor в этот Control.
	var margin := 4.0
	var avail := size - Vector2(margin * 2.0, margin * 2.0)
	var scale := minf(avail.x / bounds.size.x, avail.y / bounds.size.y)
	if scale <= 0:
		return
	var offset := Vector2(margin, margin) + (avail - Vector2(bounds.size) * scale) * 0.5

	# Фон-контейнер
	draw_rect(Rect2(Vector2.ZERO, size), WALL, true)
	draw_rect(Rect2(offset, Vector2(bounds.size) * scale), BACKGROUND, true)

	# Комнаты
	for room in layout.rooms:
		var r := Rect2(
			offset + Vector2(room.position) * scale,
			Vector2(room.size) * scale,
		)
		draw_rect(r, FLOOR_COLOR, true)

	# Коридоры / дверные проёмы
	for corridor in layout.corridors:
		var r := Rect2(
			offset + Vector2(corridor.position) * scale,
			Vector2(corridor.size) * scale,
		)
		draw_rect(r, CORRIDOR_COLOR, true)

	# Обводка комнат
	for room in layout.rooms:
		var r := Rect2(
			offset + Vector2(room.position) * scale,
			Vector2(room.size) * scale,
		)
		draw_rect(r, OUTLINE, false, 1.0)

	# Player start (зелёная точка)
	var start_px := offset + Vector2(layout.player_start) * scale
	draw_circle(start_px, 4.0, START_COLOR)

	# Exit (жёлтая точка)
	var exit_px := offset + Vector2(layout.exit_position) * scale
	draw_circle(exit_px, 4.0, EXIT_COLOR)

	# Номер этажа + boss маркер
	var label := "Floor %d" % floor_number
	if layout.is_boss_floor:
		label += " (BOSS)"
	var font := ThemeDB.fallback_font
	var font_size := 10
	draw_string(font, Vector2(6, 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color.WHITE)
