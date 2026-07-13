class_name EntranceExitSelector
extends RefCounted

# Выбор entrance и exit по расстоянию в графе комнат. Замена старой
# эвристики «min(x+y)/max(x+y)» — теперь entrance/exit сидят на
# графовом диаметре, что даёт заметно более длинный critical path и
# убирает случаи, когда exit виден с start по прямой.
#
# Дополнительно: не выбираем крохотные rooms (<1600 px², т.е. <4×4 tile) —
# они читаются как альковы, а не как входные помещения.
#
# Возвращает пару (start_idx, exit_idx). Оба гарантированно валидные,
# start != exit, если в графе >= 2 достижимых комнаты; иначе оба = 0.

const _MIN_ROOM_AREA_PX2: int = 1600

# Пороги минимальной хоп-дистанции между entrance и exit по зонам.
# Если графовое расстояние ниже — фиксируем как fallback: пусть тесты
# статистики ловят, что зона слишком тесная и требует пересмотра.
const _ZONE_MIN_HOPS := {
	"tower_top": 3,
	"residential": 4,
	"technical": 4,
	"lower_tower": 5,
	"basement": 5,
	"caves": 4,
}

static func choose(
	rooms: Array[Rect2i],
	graph: RoomGraph,
	zone: String = "",
) -> Vector2i:
	if rooms.is_empty():
		return Vector2i(0, 0)
	if rooms.size() == 1:
		return Vector2i(0, 0)
	# 1. Кандидаты — комнаты достаточной площади. Если таких <2, берём все.
	var eligible: Array = []
	for i in rooms.size():
		var area: int = rooms[i].size.x * rooms[i].size.y
		if area >= _MIN_ROOM_AREA_PX2:
			eligible.append(i)
	if eligible.size() < 2:
		eligible.clear()
		for i in rooms.size():
			eligible.append(i)
	# 2. Ищем пару с максимальной BFS-дистанцией в графе. 2× BFS —
	# приближение диаметра, но здесь нам нужна конкретная пара среди
	# eligible, поэтому делаем полный проход из «фарвест» точки.
	var seed_node: int = eligible[0]
	var far_a := _bfs_farthest_in(graph, seed_node, eligible)
	var far_b := _bfs_farthest_in(graph, far_a, eligible)
	# 3. Fallback если графовая дистанция слишком мала (< zone_min_hops).
	# Это диагностический сигнал: генератор дал compact-топологию.
	# Мы всё равно возвращаем найденную пару — гарантия start != exit
	# важнее «идеальной длины». Тесты статистики отдельно проверят
	# распределение hops.
	var _min_hops_hint: int = _ZONE_MIN_HOPS.get(zone, 3)
	if far_a == far_b:
		# Пара свернулась в одну комнату — берём любую другую сначала
		# из eligible, затем из ВСЕХ rooms (гарантирует start != exit
		# даже если после area-filter в eligible осталась одна).
		var alternate: int = -1
		for i in eligible:
			if i != far_a:
				alternate = i
				break
		if alternate < 0:
			for i in rooms.size():
				if i != far_a:
					alternate = i
					break
		if alternate >= 0:
			far_b = alternate
	return Vector2i(far_a, far_b)

# Пиксельная позиция «стартовой точки внутри room» — центр комнаты.
# Совместимо со старым player_start = room.get_center().
static func room_center(rooms: Array[Rect2i], idx: int) -> Vector2i:
	return rooms[idx].get_center()

# --- Внутренние -------------------------------------------------------------

static func _bfs_farthest_in(graph: RoomGraph, source: int, eligible: Array) -> int:
	# BFS от source; возвращает вершину из eligible с максимальной
	# дистанцией. Tiebreak — стабильно по возрастанию index (совпадает
	# с RoomGraph._bfs_farthest — оба используют больший index при
	# равной дистанции: в RoomGraph реализовано как `v > best`, здесь
	# тоже даём приоритет большему index'у).
	var dist := graph.bfs_distances(source)
	var eligible_set: Dictionary = {}
	for e in eligible:
		eligible_set[e] = true
	var best: int = source
	var best_d: int = -1
	for v in dist.keys():
		if not eligible_set.has(v):
			continue
		var d: int = dist[v]
		if d > best_d or (d == best_d and v > best):
			best = v
			best_d = d
	return best
