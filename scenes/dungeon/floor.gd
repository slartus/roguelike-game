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
const FLOOR_TEXTURE: Texture2D = preload("res://assets/sprites/environment/floor.png")
const WALL_TEXTURE: Texture2D = preload("res://assets/sprites/environment/wall.png")

const TILE_SIZE: int = 20
const BACKGROUND_COLOR: Color = Color(0.03, 0.02, 0.05, 1.0)

var player_start: Vector2 = Vector2.ZERO
var enemy_spawn_positions: Array[Vector2] = []
var chest_positions: Array[Vector2] = []
var door: Area2D
var floor_size: Vector2 = Vector2.ZERO
var layout: DungeonLayout
var astar_grid: AStarGrid2D

@onready var _floors_root: Node2D = $FloorsRoot
@onready var _walls_root: Node2D = $WallsRoot
@onready var _markers_root: Node2D = $MarkersRoot

func _ready() -> void:
	add_to_group("floor")
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
	_build_astar_grid()
	_place_door()
	_populate_marker_positions()
	floor_size = Vector2(layout.floor_bounds.size)

func _pick_seed() -> int:
	# Детерминированно от GameState.tower_seed + номера этажа.
	# Один tower_seed определяет весь layout всех этажей забега → можно
	# воспроизвести или поделиться seed'ом.
	return GameState.tower_seed * 100003 + GameState.current_floor_number

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
		_draw_tiled_rect(room, FLOOR_TEXTURE)
	for corridor in layout.corridors:
		_draw_tiled_rect(corridor, FLOOR_TEXTURE)

func _draw_tiled_rect(rect: Rect2i, texture: Texture2D) -> void:
	var poly := Polygon2D.new()
	var origin := Vector2(rect.position)
	var size := Vector2(rect.size)
	var points := PackedVector2Array([
		origin,
		origin + Vector2(size.x, 0),
		origin + size,
		origin + Vector2(0, size.y),
	])
	poly.polygon = points
	# UV = абсолютные координаты этажа → соседние rects дают бесшовный
	# tiling без «прыжков» текстуры на стыках комнат и коридоров.
	poly.uv = points
	poly.texture = texture
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
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
	var body_pos := Vector2(col_start * TILE_SIZE + span_width / 2.0, row * TILE_SIZE + TILE_SIZE / 2.0)
	body.position = body_pos
	var collision := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = shape_size
	collision.shape = rect_shape
	body.add_child(collision)
	var half := shape_size / 2.0
	var visual := Polygon2D.new()
	var points := PackedVector2Array([
		-half,
		Vector2(half.x, -half.y),
		half,
		Vector2(-half.x, half.y),
	])
	visual.polygon = points
	# UV на основе абсолютной позиции стены — соседние span-ы бесшовно
	# продолжают кирпичную кладку.
	var abs_origin := body_pos - half
	visual.uv = PackedVector2Array([
		abs_origin,
		abs_origin + Vector2(shape_size.x, 0),
		abs_origin + shape_size,
		abs_origin + Vector2(0, shape_size.y),
	])
	visual.texture = WALL_TEXTURE
	visual.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	body.add_child(visual)
	_walls_root.add_child(body)

func _build_astar_grid() -> void:
	# Один AStarGrid2D на весь этаж — все враги используют его через
	# группу "floor". Клетки совпадают по размеру с wall-grid'ом,
	# solid-flag = tile является стеной.
	var bounds := layout.floor_bounds
	var cols := int(ceil(float(bounds.size.x) / TILE_SIZE))
	var rows := int(ceil(float(bounds.size.y) / TILE_SIZE))
	astar_grid = AStarGrid2D.new()
	astar_grid.region = Rect2i(Vector2i.ZERO, Vector2i(cols, rows))
	astar_grid.cell_size = Vector2(TILE_SIZE, TILE_SIZE)
	astar_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar_grid.update()
	for row in rows:
		for col in cols:
			var tile_center := Vector2i(col * TILE_SIZE + TILE_SIZE / 2, row * TILE_SIZE + TILE_SIZE / 2)
			if _is_wall_at(tile_center):
				astar_grid.set_point_solid(Vector2i(col, row), true)

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
