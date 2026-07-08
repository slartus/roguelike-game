class_name DungeonGenerator
extends RefCounted

# Детерминированный BSP-генератор этажей башни в "жилом" стиле.
#
# Классический BSP dungeon algorithm (Rogue / NetHack / RogueSharp):
# 1. Начинаем с footprint (тайловый прямоугольник, растёт с этажом).
# 2. Recursive split пополам вдоль случайной оси, пока регионы больше
#    MIN_REGION_TILES и depth < MAX_BSP_DEPTH.
# 3. В каждом leaf-регионе вырезаем комнату переменного размера
#    (80-200 px по стороне после умножения на TILE=20).
# 4. Строим граф смежности комнат (общая стена длиной >= MIN_SHARED_WALL).
# 5. MST (Kruskal + Union-Find) — гарантирует связность.
# 6. + 25% случайных extra edges для циклов и backtracking'а.
# 7. Каждое соединённое ребро → doorway в общей стене.
#
# Результат:
# - Комнаты разных размеров (кладовочки + гостиные + залы).
# - Не все смежные пары соединены (некоторые "просто соприкасаются
#   стенами").
# - Гарантированный путь start → exit + пара альтернативных маршрутов.
# - Детерминизм по seed.
#
# Boss-этажи (floor % 5 == 0) — одна большая арена (без изменений).

const TILE: int = 20
const MIN_ROOM_TILES: int = 4                        # 80 px — минимум (кладовочка)
const MAX_ROOM_TILES: int = 10                       # 200 px — максимум (гостиная)
const MIN_REGION_TILES: int = MIN_ROOM_TILES + 2     # +1 tile wall с каждой стороны
const MAX_BSP_DEPTH: int = 6
const SPLIT_MIN_RATIO: float = 0.30
const SPLIT_MAX_RATIO: float = 0.70
const ROOM_INSET_MAX_TILES: int = 2                  # random shrink 0..2 tiles
const EARLY_STOP_CHANCE: float = 0.15                # после depth 3 — шанс не сплитить

const WALL_THICKNESS: int = 20
const DOORWAY_WIDTH: int = 40
const DOORWAY_MARGIN: int = 20
const MIN_SHARED_WALL: int = DOORWAY_WIDTH + 2 * DOORWAY_MARGIN  # 80
const EXTRA_EDGE_RATIO: float = 0.25

const FLOOR_PADDING: int = 60
const ENEMY_SPAWN_MARGIN: int = 22
const CHEST_FLOOR_INTERVAL: int = 3
const BOSS_ROOM_SIZE: Vector2i = Vector2i(600, 400)

# --- Footprint scaling (заменяет grid_dim_for_floor) ---------------------

func footprint_tiles_for_floor(floor_number: int) -> Vector2i:
	# floor 1: 20x14 → 4 (при полном сплите → до ~8 leaves)
	# floor 4: 23x16
	# floor 10: 29x20
	# cap 40x28 (~15-20 leaves).
	var step: int = (floor_number - 1) / 3
	return Vector2i(mini(20 + step * 3, 40), mini(14 + step * 2, 28))

# --- BSP node (inner class) ---------------------------------------------

# Sides bitmask — какие стороны leaf'а разрешено сдвигать при carving.
# Стороны, разделяющие leaf с BSP-sibling'ом, помечаются "запрещёнными"
# и не сдвигаются — гарантирует, что sibling walls имеют полный overlap
# и MST всегда охватит все комнаты через дерево BSP.
const INSET_TOP: int = 1
const INSET_RIGHT: int = 2
const INSET_BOTTOM: int = 4
const INSET_LEFT: int = 8
const INSET_ALL: int = INSET_TOP | INSET_RIGHT | INSET_BOTTOM | INSET_LEFT

class BSPNode extends RefCounted:
	var region: Rect2i          # tile-координаты
	var left: BSPNode
	var right: BSPNode
	var room: Rect2i            # pixel-координаты, populated только у leaves
	var inset_mask: int = 15    # какие стороны можно отступать (default: все)

	func is_leaf() -> bool:
		return left == null and right == null

# --- Entry point --------------------------------------------------------

func generate(seed_value: int, floor_number: int, is_boss: bool) -> DungeonLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var layout := DungeonLayout.new()
	layout.is_boss_floor = is_boss
	if is_boss:
		_generate_boss_floor(layout)
	else:
		_generate_tower_floor(layout, rng, floor_number)
	_compute_bounds(layout)
	_normalize(layout)
	return layout

# --- Regular floor: BSP + MST + extra edges ------------------------------

func _generate_tower_floor(layout: DungeonLayout, rng: RandomNumberGenerator, floor_number: int) -> void:
	var footprint := footprint_tiles_for_floor(floor_number)
	var root := BSPNode.new()
	root.region = Rect2i(Vector2i.ZERO, footprint)

	_split(root, 0, rng)

	var leaves: Array[BSPNode] = []
	_collect_leaves(root, leaves)
	# Fallback: если BSP не сплитился ни разу (маленький footprint), берём
	# root как единственную комнату.
	if leaves.is_empty():
		leaves.append(root)

	# Вырезаем комнату в каждом leaf (inset ограничен маской sibling'а)
	for leaf in leaves:
		leaf.room = _carve_room(leaf.region, leaf.inset_mask, rng)
		layout.rooms.append(leaf.room)

	# Строим граф смежности: edges = список {a: int, b: int, wall: Dictionary}
	var edges := _build_adjacency_edges(layout.rooms)

	# MST через Kruskal
	var mst_edges := _kruskal_mst(edges, layout.rooms.size())

	# 25% extra edges из non-MST для циклов
	var mst_set := {}
	for e in mst_edges:
		mst_set[_edge_key(e)] = true
	var extra_candidates: Array = []
	for e in edges:
		if not mst_set.has(_edge_key(e)):
			extra_candidates.append(e)
	var extra_count: int = int(ceili(extra_candidates.size() * EXTRA_EDGE_RATIO))
	_shuffle_with_rng(extra_candidates, rng)
	var picked_edges: Array = mst_edges.duplicate()
	for i in mini(extra_count, extra_candidates.size()):
		picked_edges.append(extra_candidates[i])

	# Carve doorways для каждого выбранного edge
	for e in picked_edges:
		var corridor := _carve_doorway(e.wall, rng)
		layout.corridors.append(corridor)

	# Player start = argmin(room.position.x + room.position.y)
	# Exit = argmax(room.end.x + room.end.y)
	var start_idx := _pick_extreme_room(layout.rooms, false)
	var exit_idx := _pick_extreme_room(layout.rooms, true)
	var start_room: Rect2i = layout.rooms[start_idx]
	var exit_room: Rect2i = layout.rooms[exit_idx]
	layout.player_start = start_room.get_center()
	layout.exit_position = exit_room.get_center()

	# Enemy spawns во всех комнатах кроме start/exit
	for i in layout.rooms.size():
		if i == start_idx or i == exit_idx:
			continue
		_add_enemy_spawns(layout, layout.rooms[i], rng, 2, 3)

	# Chest на этажах кратных 3 — одна точка в случайной middle-комнате
	if floor_number % CHEST_FLOOR_INTERVAL == 0:
		var middle_indices: Array[int] = []
		for i in layout.rooms.size():
			if i != start_idx and i != exit_idx:
				middle_indices.append(i)
		if middle_indices.size() > 0:
			var chest_idx := middle_indices[rng.randi_range(0, middle_indices.size() - 1)]
			var chest_room: Rect2i = layout.rooms[chest_idx]
			var offset := Vector2i(rng.randi_range(-20, 20), rng.randi_range(-20, 20))
			layout.chest_positions.append(chest_room.get_center() + offset)

# --- BSP split ----------------------------------------------------------

func _split(node: BSPNode, depth: int, rng: RandomNumberGenerator) -> void:
	if depth >= MAX_BSP_DEPTH:
		return
	if depth >= 3 and rng.randf() < EARLY_STOP_CHANCE:
		return

	var region := node.region
	# Проверка: можем ли сплитить хотя бы по одной оси
	var can_split_x := region.size.x >= 2 * MIN_REGION_TILES + 1
	var can_split_y := region.size.y >= 2 * MIN_REGION_TILES + 1
	if not can_split_x and not can_split_y:
		return

	# Выбор оси: длиннее сторона, с 20% шансом flip'а
	var split_horizontal: bool
	if can_split_x and not can_split_y:
		split_horizontal = false
	elif can_split_y and not can_split_x:
		split_horizontal = true
	else:
		var wider := region.size.x >= region.size.y
		split_horizontal = not wider
		if rng.randf() < 0.20:
			split_horizontal = not split_horizontal

	var axis_len: int = region.size.y if split_horizontal else region.size.x
	# 1 tile для стены между половинами
	var usable_len := axis_len - 1
	# Границы split point (должны оставить MIN_REGION_TILES с каждой стороны)
	var split_min: int = MIN_REGION_TILES
	var split_max: int = usable_len - MIN_REGION_TILES
	if split_max <= split_min:
		return
	# Random split point в диапазоне
	var min_ratio_pos: int = int(usable_len * SPLIT_MIN_RATIO)
	var max_ratio_pos: int = int(usable_len * SPLIT_MAX_RATIO)
	var lo: int = maxi(split_min, min_ratio_pos)
	var hi: int = mini(split_max, max_ratio_pos)
	if hi <= lo:
		lo = split_min
		hi = split_max
	var split_at: int = rng.randi_range(lo, hi)

	# Строим два child-региона с 1-tile gap для стены
	var left := BSPNode.new()
	var right := BSPNode.new()
	if split_horizontal:
		left.region = Rect2i(region.position, Vector2i(region.size.x, split_at))
		right.region = Rect2i(
			Vector2i(region.position.x, region.position.y + split_at + 1),
			Vector2i(region.size.x, region.size.y - split_at - 1),
		)
		# Top ребёнок не сдвигает свою нижнюю сторону (общая стена с right).
		# Bottom ребёнок не сдвигает свою верхнюю сторону.
		left.inset_mask = node.inset_mask & ~INSET_BOTTOM
		right.inset_mask = node.inset_mask & ~INSET_TOP
	else:
		left.region = Rect2i(region.position, Vector2i(split_at, region.size.y))
		right.region = Rect2i(
			Vector2i(region.position.x + split_at + 1, region.position.y),
			Vector2i(region.size.x - split_at - 1, region.size.y),
		)
		# Left ребёнок не сдвигает свою правую сторону.
		# Right ребёнок не сдвигает свою левую.
		left.inset_mask = node.inset_mask & ~INSET_RIGHT
		right.inset_mask = node.inset_mask & ~INSET_LEFT

	node.left = left
	node.right = right
	_split(left, depth + 1, rng)
	_split(right, depth + 1, rng)

func _collect_leaves(node: BSPNode, out: Array[BSPNode]) -> void:
	if node == null:
		return
	if node.is_leaf():
		out.append(node)
		return
	_collect_leaves(node.left, out)
	_collect_leaves(node.right, out)

# --- Room carving в leaf-регионе ---------------------------------------

func _carve_room(region: Rect2i, inset_mask: int, rng: RandomNumberGenerator) -> Rect2i:
	# region в tile-координатах. Комната шринкается на 0..2 tiles только
	# на сторонах, разрешённых inset_mask. Стороны, общие с BSP-sibling'ом,
	# не двигаются — sibling-adjacency остаётся полной, MST охватывает все.

	# Максимальный inset на каждой стороне: 0 если сторона запрещена, иначе
	# ROOM_INSET_MAX_TILES.
	var can_top: bool = (inset_mask & INSET_TOP) != 0
	var can_right: bool = (inset_mask & INSET_RIGHT) != 0
	var can_bottom: bool = (inset_mask & INSET_BOTTOM) != 0
	var can_left: bool = (inset_mask & INSET_LEFT) != 0

	var max_inset_left: int = ROOM_INSET_MAX_TILES if can_left else 0
	var max_inset_top: int = ROOM_INSET_MAX_TILES if can_top else 0
	var max_inset_right: int = ROOM_INSET_MAX_TILES if can_right else 0
	var max_inset_bottom: int = ROOM_INSET_MAX_TILES if can_bottom else 0

	# Гарантируем что комната >= MIN_ROOM_TILES
	max_inset_left = mini(max_inset_left, (region.size.x - MIN_ROOM_TILES) / 2)
	max_inset_right = mini(max_inset_right, region.size.x - MIN_ROOM_TILES - max_inset_left)
	max_inset_top = mini(max_inset_top, (region.size.y - MIN_ROOM_TILES) / 2)
	max_inset_bottom = mini(max_inset_bottom, region.size.y - MIN_ROOM_TILES - max_inset_top)

	var inset_left: int = rng.randi_range(0, maxi(0, max_inset_left))
	var inset_top: int = rng.randi_range(0, maxi(0, max_inset_top))
	var inset_right: int = rng.randi_range(0, maxi(0, max_inset_right))
	var inset_bottom: int = rng.randi_range(0, maxi(0, max_inset_bottom))

	# Ограничиваем сверху MAX_ROOM_TILES — только на разрешённых сторонах.
	var room_w: int = region.size.x - inset_left - inset_right
	var room_h: int = region.size.y - inset_top - inset_bottom
	if room_w > MAX_ROOM_TILES:
		var extra: int = room_w - MAX_ROOM_TILES
		# Разбрасываем extra только по разрешённым сторонам.
		if can_left and can_right:
			var add_left: int = rng.randi_range(0, extra)
			inset_left += add_left
			inset_right += extra - add_left
		elif can_left:
			inset_left += extra
		elif can_right:
			inset_right += extra
		# Если ни одна сторона не разрешена — оставляем большую комнату.
		if can_left or can_right:
			room_w = MAX_ROOM_TILES
	if room_h > MAX_ROOM_TILES:
		var extra_h: int = room_h - MAX_ROOM_TILES
		if can_top and can_bottom:
			var add_top: int = rng.randi_range(0, extra_h)
			inset_top += add_top
			inset_bottom += extra_h - add_top
		elif can_top:
			inset_top += extra_h
		elif can_bottom:
			inset_bottom += extra_h
		if can_top or can_bottom:
			room_h = MAX_ROOM_TILES

	var tile_pos := Vector2i(region.position.x + inset_left, region.position.y + inset_top)
	var tile_size := Vector2i(room_w, room_h)

	# Конвертация tile → pixel
	return Rect2i(tile_pos * TILE, tile_size * TILE)

# --- Adjacency graph ---------------------------------------------------

func _build_adjacency_edges(rooms: Array[Rect2i]) -> Array:
	var edges: Array = []
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			var wall := _shared_wall(rooms[i], rooms[j])
			if not wall.is_empty():
				edges.append({"a": i, "b": j, "wall": wall})
	return edges

# Возвращает Dictionary с информацией о общей стене или {} если стены нет.
# axis: "v" (вертикальная стена, ↕) или "h" (горизонтальная, ↔)
# at: координата стены по перпендикулярной оси
# lo, hi: диапазон overlap по параллельной оси
func _shared_wall(a: Rect2i, b: Rect2i) -> Dictionary:
	# Вертикальные стены: A справа от B или наоборот, с WALL_THICKNESS gap
	if a.end.x + WALL_THICKNESS == b.position.x:
		var lo: int = maxi(a.position.y, b.position.y)
		var hi: int = mini(a.end.y, b.end.y)
		if hi - lo >= MIN_SHARED_WALL:
			return {"axis": "v", "at": a.end.x, "lo": lo, "hi": hi}
	if b.end.x + WALL_THICKNESS == a.position.x:
		var lo: int = maxi(a.position.y, b.position.y)
		var hi: int = mini(a.end.y, b.end.y)
		if hi - lo >= MIN_SHARED_WALL:
			return {"axis": "v", "at": b.end.x, "lo": lo, "hi": hi}
	# Горизонтальные стены
	if a.end.y + WALL_THICKNESS == b.position.y:
		var lo: int = maxi(a.position.x, b.position.x)
		var hi: int = mini(a.end.x, b.end.x)
		if hi - lo >= MIN_SHARED_WALL:
			return {"axis": "h", "at": a.end.y, "lo": lo, "hi": hi}
	if b.end.y + WALL_THICKNESS == a.position.y:
		var lo: int = maxi(a.position.x, b.position.x)
		var hi: int = mini(a.end.x, b.end.x)
		if hi - lo >= MIN_SHARED_WALL:
			return {"axis": "h", "at": b.end.y, "lo": lo, "hi": hi}
	return {}

# --- MST (Kruskal + Union-Find) ----------------------------------------

func _kruskal_mst(edges: Array, node_count: int) -> Array:
	# Weight = отрицательная длина shared wall (широкие стены приоритетнее).
	# Tiebreak: (min(a, b), max(a, b)) для детерминизма.
	var sorted := edges.duplicate()
	sorted.sort_custom(func(x, y): return _edge_sort_key(x) < _edge_sort_key(y))
	var parent: Array[int] = []
	parent.resize(node_count)
	for i in node_count:
		parent[i] = i
	var picked: Array = []
	for e in sorted:
		if _uf_union(parent, e.a, e.b):
			picked.append(e)
		if picked.size() == node_count - 1:
			break
	return picked

func _edge_sort_key(e: Dictionary) -> Array:
	var overlap_len: int = e.wall.hi - e.wall.lo
	var i0: int = mini(e.a, e.b)
	var i1: int = maxi(e.a, e.b)
	# Отрицательная длина → sort ascending даёт длинные стены первыми.
	return [-overlap_len, i0, i1]

func _edge_key(e: Dictionary) -> String:
	var i0: int = mini(e.a, e.b)
	var i1: int = maxi(e.a, e.b)
	return "%d_%d" % [i0, i1]

func _uf_find(parent: Array[int], x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x

func _uf_union(parent: Array[int], a: int, b: int) -> bool:
	var ra := _uf_find(parent, a)
	var rb := _uf_find(parent, b)
	if ra == rb:
		return false
	parent[ra] = rb
	return true

# Fisher-Yates shuffle с внешним rng (не зависит от глобального random).
func _shuffle_with_rng(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

# --- Doorway carving ---------------------------------------------------

func _carve_doorway(wall: Dictionary, rng: RandomNumberGenerator) -> Rect2i:
	var overlap_len: int = wall.hi - wall.lo
	var slack: int = maxi(1, overlap_len - 2 * DOORWAY_MARGIN - DOORWAY_WIDTH)
	var start: int = wall.lo + DOORWAY_MARGIN + rng.randi_range(0, slack)
	if wall.axis == "v":
		return Rect2i(
			Vector2i(wall.at, start),
			Vector2i(WALL_THICKNESS, DOORWAY_WIDTH),
		)
	else:
		return Rect2i(
			Vector2i(start, wall.at),
			Vector2i(DOORWAY_WIDTH, WALL_THICKNESS),
		)

# --- Extreme rooms (top-left / bottom-right) ---------------------------

func _pick_extreme_room(rooms: Array[Rect2i], maximize: bool) -> int:
	var best_idx := 0
	var best_score: int = rooms[0].position.x + rooms[0].position.y
	if maximize:
		best_score = rooms[0].end.x + rooms[0].end.y
	for i in range(1, rooms.size()):
		var score: int = rooms[i].position.x + rooms[i].position.y
		if maximize:
			score = rooms[i].end.x + rooms[i].end.y
		if maximize:
			if score > best_score:
				best_score = score
				best_idx = i
		else:
			if score < best_score:
				best_score = score
				best_idx = i
	return best_idx

# --- Boss floor (без изменений) ----------------------------------------

func _generate_boss_floor(layout: DungeonLayout) -> void:
	var room := Rect2i(Vector2i.ZERO, BOSS_ROOM_SIZE)
	layout.rooms.append(room)
	layout.player_start = Vector2i(BOSS_ROOM_SIZE.x / 6, BOSS_ROOM_SIZE.y / 2)
	layout.exit_position = Vector2i(BOSS_ROOM_SIZE.x * 5 / 6, BOSS_ROOM_SIZE.y / 2)

# --- Общие helper'ы (сохранены) ----------------------------------------

func _add_enemy_spawns(layout: DungeonLayout, room: Rect2i, rng: RandomNumberGenerator, min_count: int, max_count: int) -> void:
	# Небольшие комнаты не тянут 3 спавна — clamp по площади.
	var margin: int = ENEMY_SPAWN_MARGIN
	var inner_w: int = maxi(1, room.size.x - margin * 2)
	var inner_h: int = maxi(1, room.size.y - margin * 2)
	var area_slots: int = maxi(1, (inner_w * inner_h) / 3600)  # ~60x60 px на слот
	var count: int = mini(rng.randi_range(min_count, max_count), area_slots)
	for i in count:
		var x: int = room.position.x + margin + rng.randi_range(0, inner_w)
		var y: int = room.position.y + margin + rng.randi_range(0, inner_h)
		layout.enemy_spawns.append(Vector2i(x, y))

func _compute_bounds(layout: DungeonLayout) -> void:
	if layout.rooms.is_empty():
		layout.floor_bounds = Rect2i(Vector2i.ZERO, Vector2i(100, 100))
		return
	var min_x := 2147483647
	var min_y := 2147483647
	var max_x := -2147483648
	var max_y := -2147483648
	for room in layout.rooms:
		min_x = mini(min_x, room.position.x)
		min_y = mini(min_y, room.position.y)
		max_x = maxi(max_x, room.end.x)
		max_y = maxi(max_y, room.end.y)
	for corridor in layout.corridors:
		min_x = mini(min_x, corridor.position.x)
		min_y = mini(min_y, corridor.position.y)
		max_x = maxi(max_x, corridor.end.x)
		max_y = maxi(max_y, corridor.end.y)
	layout.floor_bounds = Rect2i(
		Vector2i(min_x - FLOOR_PADDING, min_y - FLOOR_PADDING),
		Vector2i(max_x - min_x + FLOOR_PADDING * 2, max_y - min_y + FLOOR_PADDING * 2),
	)

func _normalize(layout: DungeonLayout) -> void:
	var offset: Vector2i = -layout.floor_bounds.position
	for i in layout.rooms.size():
		layout.rooms[i] = Rect2i(layout.rooms[i].position + offset, layout.rooms[i].size)
	for i in layout.corridors.size():
		layout.corridors[i] = Rect2i(layout.corridors[i].position + offset, layout.corridors[i].size)
	for i in layout.enemy_spawns.size():
		layout.enemy_spawns[i] = layout.enemy_spawns[i] + offset
	for i in layout.chest_positions.size():
		layout.chest_positions[i] = layout.chest_positions[i] + offset
	layout.player_start = layout.player_start + offset
	layout.exit_position = layout.exit_position + offset
	layout.floor_bounds = Rect2i(Vector2i.ZERO, layout.floor_bounds.size)
