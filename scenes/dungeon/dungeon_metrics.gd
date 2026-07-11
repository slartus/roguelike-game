class_name DungeonMetrics
extends RefCounted

# Метрики этажа — walkable area, room count, длина shortest path
# entrance→exit, dead ends, циклы, ветки. Используется тестами для
# baseline-статистики и генераторами для fallback-валидации.
#
# Все функции чистые (RefCounted, static-like) — не мутируют DungeonLayout.

const _TILE_SIZE: int = 20

# Сумма площадей всех rooms + corridors, в пикселях².
static func walkable_area(layout: DungeonLayout) -> int:
	var area := 0
	for room in layout.rooms:
		area += room.size.x * room.size.y
	for corridor in layout.corridors:
		area += corridor.size.x * corridor.size.y
	return area

# Сумма длин всех corridor rects (по большей стороне). Полезно
# как proxy «сколько бегать по коридорам».
static func corridor_length(layout: DungeonLayout) -> int:
	var total := 0
	for c in layout.corridors:
		total += maxi(c.size.x, c.size.y)
	return total

# Кратчайший граф-путь entrance→exit в hops (rooms). -1 если не связано.
static func shortest_entrance_exit_hops(layout: DungeonLayout, graph: RoomGraph) -> int:
	if layout.rooms.is_empty():
		return -1
	var start_idx := _find_room_containing(layout.rooms, layout.player_start)
	var exit_idx := _find_room_containing(layout.rooms, layout.exit_position)
	if start_idx < 0 or exit_idx < 0:
		return -1
	return graph.shortest_path_length(start_idx, exit_idx)

# Euclid distance между entrance и exit — грубая оценка «visible spread».
static func entrance_exit_pixel_distance(layout: DungeonLayout) -> float:
	return Vector2(layout.player_start).distance_to(Vector2(layout.exit_position))

# Средняя площадь комнаты в пикселях².
static func average_room_area(layout: DungeonLayout) -> float:
	if layout.rooms.is_empty():
		return 0.0
	var total := 0
	for room in layout.rooms:
		total += room.size.x * room.size.y
	return float(total) / float(layout.rooms.size())

# Прокси для «первый этаж больше одного viewport». Возвращает max
# из width/height footprint в пикселях (worst-case для сравнения с
# 640×360 viewport).
static func longest_footprint_side(layout: DungeonLayout) -> int:
	return maxi(layout.floor_bounds.size.x, layout.floor_bounds.size.y)

# --- helpers -----------------------------------------------------------------

static func _find_room_containing(rooms: Array[Rect2i], point: Vector2i) -> int:
	for i in rooms.size():
		if rooms[i].has_point(point):
			return i
	# Fallback: ближайший центр (см. RoomRoles._find_room_containing).
	var best_idx := -1
	var best_dist := INF
	for i in rooms.size():
		var d: float = (Vector2(rooms[i].get_center()) - Vector2(point)).length_squared()
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx
