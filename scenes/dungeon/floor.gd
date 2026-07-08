extends Node2D

# Инстанс одного этажа подземелья. При _ready:
# 1. Генерирует layout через DungeonGenerator (seed берётся из GameState).
# 2. Рисует пол (rooms + corridors) как Polygon2D поверх тёмного фона.
# 3. Строит стены: для каждой tile-ячейки, не входящей ни в комнату,
#    ни в коридор, создаётся StaticBody2D с RectangleShape2D. Смежные
#    tiles в одной строке объединяются в один rect (per-row merge)
#    для сокращения числа тел.
# 4. Инстансирует дверь на exit_position (использует существующую door.tscn).
# 5. Экспортирует player_start, enemy_spawn_positions, chest_positions,
#    door и floor_size для потребителей (Main).

const DungeonGeneratorClass = preload("res://scenes/dungeon/dungeon_generator.gd")
const DOOR_SCENE: PackedScene = preload("res://scenes/rooms/door.tscn")

const TILE_SIZE: int = 20
const WALL_COLOR: Color = Color(0.08, 0.07, 0.11, 1.0)
const FLOOR_COLOR: Color = Color(0.22, 0.20, 0.26, 1.0)
const BACKGROUND_COLOR: Color = Color(0.05, 0.04, 0.08, 1.0)

var player_start: Vector2 = Vector2.ZERO
var enemy_spawn_positions: Array[Vector2] = []
var chest_positions: Array[Vector2] = []
var door: Area2D
var floor_size: Vector2 = Vector2.ZERO
var layout: DungeonLayout

@onready var _floors_root: Node2D = $FloorsRoot
@onready var _walls_root: Node2D = $WallsRoot
@onready var _markers_root: Node2D = $MarkersRoot

func _ready() -> void:
	var seed_value := _pick_seed()
	var generator := DungeonGeneratorClass.new()
	layout = generator.generate(
		seed_value,
		GameState.current_floor_number,
		_is_boss_floor(),
	)
	_draw_background()
	_draw_floor_tiles()
	_build_walls()
	_place_door()
	_populate_marker_positions()
	floor_size = Vector2(layout.floor_bounds.size)

func _pick_seed() -> int:
	# Смена сида при каждом заходе: одна и та же комната не повторяется.
	return GameState.current_floor_number * 100003 + int(Time.get_unix_time_from_system() * 1000) % 100003

func _is_boss_floor() -> bool:
	return GameState.current_floor_number % 5 == 0

func _draw_background() -> void:
	var bg := Polygon2D.new()
	var size := layout.floor_bounds.size
	bg.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0),
		Vector2(size.x, size.y),
		Vector2(0, size.y),
	])
	bg.color = BACKGROUND_COLOR
	_floors_root.add_child(bg)

func _draw_floor_tiles() -> void:
	for room in layout.rooms:
		_draw_rect(room, FLOOR_COLOR)
	for corridor in layout.corridors:
		_draw_rect(corridor, FLOOR_COLOR)

func _draw_rect(rect: Rect2i, color: Color) -> void:
	var poly := Polygon2D.new()
	var origin := Vector2(rect.position)
	var size := Vector2(rect.size)
	poly.polygon = PackedVector2Array([
		origin,
		origin + Vector2(size.x, 0),
		origin + size,
		origin + Vector2(0, size.y),
	])
	poly.color = color
	_floors_root.add_child(poly)

func _build_walls() -> void:
	var bounds := layout.floor_bounds
	var cols := int(ceil(float(bounds.size.x) / TILE_SIZE))
	var rows := int(ceil(float(bounds.size.y) / TILE_SIZE))
	for row in rows:
		var span_start := -1
		for col in cols:
			var tile_center := Vector2i(col * TILE_SIZE + TILE_SIZE / 2, row * TILE_SIZE + TILE_SIZE / 2)
			var is_wall := _is_wall_at(tile_center)
			if is_wall:
				if span_start == -1:
					span_start = col
			else:
				if span_start >= 0:
					_create_wall_span(span_start, col, row)
					span_start = -1
		if span_start >= 0:
			_create_wall_span(span_start, cols, row)

func _is_wall_at(point: Vector2i) -> bool:
	for room in layout.rooms:
		if room.has_point(point):
			return false
	for corridor in layout.corridors:
		if corridor.has_point(point):
			return false
	return true

func _create_wall_span(col_start: int, col_end: int, row: int) -> void:
	var body := StaticBody2D.new()
	var span_width := TILE_SIZE * (col_end - col_start)
	var shape_size := Vector2(span_width, TILE_SIZE)
	body.position = Vector2(col_start * TILE_SIZE + span_width / 2.0, row * TILE_SIZE + TILE_SIZE / 2.0)
	var collision := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = shape_size
	collision.shape = rect_shape
	body.add_child(collision)
	var half := shape_size / 2.0
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([
		-half,
		Vector2(half.x, -half.y),
		half,
		Vector2(-half.x, half.y),
	])
	visual.color = WALL_COLOR
	body.add_child(visual)
	_walls_root.add_child(body)

func _place_door() -> void:
	door = DOOR_SCENE.instantiate()
	door.position = Vector2(layout.exit_position)
	_markers_root.add_child(door)

func _populate_marker_positions() -> void:
	player_start = Vector2(layout.player_start)
	enemy_spawn_positions.clear()
	for point in layout.enemy_spawns:
		enemy_spawn_positions.append(Vector2(point))
	chest_positions.clear()
	for point in layout.chest_positions:
		chest_positions.append(Vector2(point))
