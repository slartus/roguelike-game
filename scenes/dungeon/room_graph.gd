class_name RoomGraph
extends RefCounted

# Ненаправленный граф смежности комнат этажа + метрики поверх него.
# Используется генераторами для выбора entrance/exit по расстоянию,
# определения dead-end комнат для наград, и тестами для проверки
# инвариантов топологии (циклы, ветки, критический путь).
#
# Экземпляр строится один раз после того, как генератор посадил
# rooms/corridors — через `RoomGraph.build_from_doorways(rooms, corridors)`
# или явными `add_edge(a, b)` из pipeline'а, если генератор сам знает
# соседства (residential/technical/cave). BSP path использует
# `build_from_doorways`, чтобы совместимость со старой геометрией
# сохранилась.

const _WALL_THICKNESS: int = 20
const _MIN_SHARED_WALL: int = 80  # см. DungeonGenerator.MIN_SHARED_WALL

var node_count: int
# adjacency[i] = Array[int] — индексы соседей комнаты i.
var adjacency: Array = []

func _init(rooms_count: int) -> void:
	node_count = rooms_count
	adjacency.resize(rooms_count)
	for i in rooms_count:
		adjacency[i] = []

# --- Построение --------------------------------------------------------------

static func build_from_doorways(rooms: Array[Rect2i], corridors: Array[Rect2i]) -> RoomGraph:
	# Пара rooms считается связанной, если между ними есть shared wall и
	# в этой стене лежит хотя бы один corridor rect. Порог MIN_SHARED_WALL
	# совпадает с DungeonGenerator — иначе мы бы «увидели» стены, которых
	# сам генератор не считает стенами.
	var graph := RoomGraph.new(rooms.size())
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			var wall := _shared_wall(rooms[i], rooms[j])
			if wall.is_empty():
				continue
			if not _has_corridor_in_wall(wall, corridors):
				continue
			graph.add_edge(i, j)
	return graph

# Позволяет генератору явно объявить смежность (residential spine v2,
# technical grid v2, cave chambers). Двусторонний add.
func add_edge(a: int, b: int) -> void:
	if a == b:
		return
	if a < 0 or a >= node_count or b < 0 or b >= node_count:
		return
	if not adjacency[a].has(b):
		adjacency[a].append(b)
	if not adjacency[b].has(a):
		adjacency[b].append(a)

# --- Базовые метрики ---------------------------------------------------------

func is_graph_connected() -> bool:
	if node_count <= 1:
		return true
	return bfs_distances(0).size() == node_count

# BFS от source. Возвращает Dictionary node_index -> distance (int).
# Недостижимые вершины отсутствуют в результате.
func bfs_distances(source: int) -> Dictionary:
	var dist: Dictionary = {}
	if source < 0 or source >= node_count:
		return dist
	dist[source] = 0
	var queue: Array[int] = [source]
	while queue.size() > 0:
		var v: int = queue.pop_front()
		var d: int = dist[v]
		for n in adjacency[v]:
			if dist.has(n):
				continue
			dist[n] = d + 1
			queue.append(n)
	return dist

# Кратчайшее расстояние в hops между a и b. -1 если нет пути.
func shortest_path_length(a: int, b: int) -> int:
	if a == b:
		return 0
	var dist := bfs_distances(a)
	return int(dist.get(b, -1))

# Возвращает пару (idx_a, idx_b) — концы диаметра графа (approx через
# 2× BFS). Для деревьев даёт точный диаметр; для графов с циклами —
# нижнюю оценку, что достаточно для выбора entrance/exit «подальше».
func farthest_pair() -> Vector2i:
	if node_count <= 1:
		return Vector2i(0, 0)
	var a := _bfs_farthest(0)
	var b := _bfs_farthest(a)
	return Vector2i(a, b)

func _bfs_farthest(source: int) -> int:
	var dist := bfs_distances(source)
	var best: int = source
	var best_d: int = -1
	# Стабильный tiebreak: наибольший index при равной дистанции.
	# Гарантирует детерминизм на графах, где несколько вершин на макс.
	# расстоянии.
	for v in dist.keys():
		var d: int = dist[v]
		if d > best_d or (d == best_d and v > best):
			best = v
			best_d = d
	return best

# Индексы «тупиковых» комнат — степень 1 или (для одиночной комнаты) 0.
func dead_end_indices() -> Array:
	var result: Array = []
	for i in node_count:
		var deg: int = adjacency[i].size()
		if deg <= 1:
			result.append(i)
	return result

# Количество «веток» (degree >= 3) — грубая мера ветвистости этажа.
func branch_count() -> int:
	var count := 0
	for i in node_count:
		if adjacency[i].size() >= 3:
			count += 1
	return count

# Циклы в графе как разница между рёбрами и вершинами. Для связного
# графа это точное количество независимых циклов (E - V + 1). Для
# несвязного графа возвращает E - V + C_components (нужно вычислить
# компоненты отдельно); в наших pipelines граф всегда связен на момент
# вызова, потому что _is_layout_valid отсекает несвязные до генерации
# room_infos.
func cycle_count() -> int:
	var edges := 0
	for i in node_count:
		edges += adjacency[i].size()
	edges /= 2
	return edges - node_count + 1

# Индексы комнат критического пути между from_idx и to_idx.
# Возвращает Array[int] от from_idx до to_idx включительно. Пустой если пути нет.
func shortest_path(from_idx: int, to_idx: int) -> Array:
	if from_idx == to_idx:
		return [from_idx]
	var prev: Dictionary = {}
	prev[from_idx] = -1
	var queue: Array[int] = [from_idx]
	var found := false
	while queue.size() > 0 and not found:
		var v: int = queue.pop_front()
		for n in adjacency[v]:
			if prev.has(n):
				continue
			prev[n] = v
			if n == to_idx:
				found = true
				break
			queue.append(n)
	if not prev.has(to_idx):
		return []
	var path: Array = []
	var cur: int = to_idx
	while cur != -1:
		path.push_front(cur)
		cur = int(prev[cur])
	return path

# --- Внутренние (совместимы с DungeonGenerator) ------------------------------

static func _shared_wall(a: Rect2i, b: Rect2i) -> Dictionary:
	if a.end.x + _WALL_THICKNESS == b.position.x:
		var lo: int = maxi(a.position.y, b.position.y)
		var hi: int = mini(a.end.y, b.end.y)
		if hi - lo >= _MIN_SHARED_WALL:
			return {"axis": "v", "at": a.end.x, "lo": lo, "hi": hi}
	if b.end.x + _WALL_THICKNESS == a.position.x:
		var lo: int = maxi(a.position.y, b.position.y)
		var hi: int = mini(a.end.y, b.end.y)
		if hi - lo >= _MIN_SHARED_WALL:
			return {"axis": "v", "at": b.end.x, "lo": lo, "hi": hi}
	if a.end.y + _WALL_THICKNESS == b.position.y:
		var lo: int = maxi(a.position.x, b.position.x)
		var hi: int = mini(a.end.x, b.end.x)
		if hi - lo >= _MIN_SHARED_WALL:
			return {"axis": "h", "at": a.end.y, "lo": lo, "hi": hi}
	if b.end.y + _WALL_THICKNESS == a.position.y:
		var lo: int = maxi(a.position.x, b.position.x)
		var hi: int = mini(a.end.x, b.end.x)
		if hi - lo >= _MIN_SHARED_WALL:
			return {"axis": "h", "at": b.end.y, "lo": lo, "hi": hi}
	return {}

static func _has_corridor_in_wall(wall: Dictionary, corridors: Array[Rect2i]) -> bool:
	# Corridor rect стоит в общей стене, если он тонкий по оси стены
	# и укладывается в overlap range.
	for c in corridors:
		if wall.axis == "v":
			# Стена вертикальная (перпендикулярно X): corridor у стены
			# имеет position.x == wall.at и height внутри [lo, hi].
			if c.position.x != wall.at:
				continue
			if c.position.y >= wall.lo and c.end.y <= wall.hi:
				return true
		else:
			if c.position.y != wall.at:
				continue
			if c.position.x >= wall.lo and c.end.x <= wall.hi:
				return true
	return false
