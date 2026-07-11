class_name NaturalCaveGenerator
extends RefCounted

# Natural cave generator — chambers + tunnels для zone = caves.
# Отличие от BSP: chambers имеют разные размеры и не идут grid-подряд,
# tunnels — узкие corridors, MST + 1-2 extra edges → минимум одна
# alt-connection на большинстве этажей.
#
# Вариант B из плана — «Blob chambers + tunnels». Blob'ы — rectangles
# с randomized size/aspect, размещаются через jitter'ные grid slots
# (без overlap). Стены остаются рендер-совместимыми (Rect2i-based) —
# полное irregular boundary не в scope этого PR, будущее улучшение.
#
# Ключевые инварианты:
# - >=5 chambers на глубоких caves (footprint 42+×30+);
# - MST + extra_edges — граф всегда связен;
# - каждый tunnel имеет минимум 40 px ширины (walkable);
# - никаких pocket-only chambers (проверяется _is_layout_valid).

const TILE: int = 20
const CHAMBER_MIN_TILES: int = 4
const CHAMBER_MAX_TILES: int = 9
const CHAMBER_TARGET_COUNT_MIN: int = 5
const CHAMBER_TARGET_COUNT_MAX: int = 9
const TUNNEL_WIDTH_TILES: int = 2
# Extra edges масштабируются от количества chambers — на 3-4 chambers
# candidates могут дать 0-1 loop, на 7-9 хватает 2-3.
const EXTRA_EDGE_MIN: int = 1
const EXTRA_EDGE_RATIO: float = 0.33
const MIN_SPACING_TILES: int = 2

static func generate(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	_floor_number: int,
	footprint_tiles: Vector2i,
) -> void:
	var width_tiles: int = footprint_tiles.x
	var height_tiles: int = footprint_tiles.y

	# 1. Разбиваем footprint на 3×3 grid slots — chamber placement будет
	#    jitter-based внутри slot'ов, чтобы уйти от чистого grid feel.
	var slot_cols: int = 3
	var slot_rows: int = 3
	var slot_w: int = width_tiles / slot_cols
	var slot_h: int = height_tiles / slot_rows
	var slots: Array = []
	for row in slot_rows:
		for col in slot_cols:
			slots.append(Vector2i(col, row))
	# 2. Пемешиваем и берём N chambers.
	_shuffle_with_rng(slots, rng)
	var target_count: int = rng.randi_range(
		CHAMBER_TARGET_COUNT_MIN,
		mini(CHAMBER_TARGET_COUNT_MAX, slots.size()),
	)
	var placed: Array = []  # Array[Rect2i] в tile-координатах.
	for i in mini(target_count, slots.size()):
		var slot: Vector2i = slots[i]
		var slot_origin := Vector2i(slot.x * slot_w, slot.y * slot_h)
		var chamber := _try_place_chamber(slot_origin, slot_w, slot_h, placed, rng)
		if chamber.size.x > 0:
			placed.append(chamber)
	# 3. Fallback: если по каким-то причинам разместили <2 chambers,
	# ставим одну большую центральную — validator отбракует, но не
	# крешит.
	if placed.size() < 2:
		placed.clear()
		placed.append(Rect2i(
			Vector2i(2, 2),
			Vector2i(width_tiles - 4, height_tiles - 4),
		))
	# 4. Конвертируем в пиксельные rooms.
	for chamber_tile in placed:
		layout.rooms.append(Rect2i(
			chamber_tile.position * TILE,
			chamber_tile.size * TILE,
		))
	# 5. Строим MST + extra edges между chambers.
	var edges := _build_mst_edges(layout.rooms)
	var extra_count: int = maxi(EXTRA_EDGE_MIN, int(round(layout.rooms.size() * EXTRA_EDGE_RATIO)))
	var extra_edges := _pick_extra_edges(layout.rooms, edges, extra_count)
	var all_edges: Array = edges + extra_edges
	# 6. Для каждого ребра — вырезаем L-shape tunnel.
	for edge in all_edges:
		_carve_tunnel(layout, edge.a, edge.b, rng)
	# 7. Player start/exit — hint'ы: любые две chambers на разных концах
	# по X. Graph-distance selector потом заменит.
	if layout.rooms.size() >= 2:
		var left_idx: int = 0
		var right_idx: int = 0
		for i in layout.rooms.size():
			if layout.rooms[i].position.x < layout.rooms[left_idx].position.x:
				left_idx = i
			if layout.rooms[i].end.x > layout.rooms[right_idx].end.x:
				right_idx = i
		layout.player_start = layout.rooms[left_idx].get_center()
		layout.exit_position = layout.rooms[right_idx].get_center()
	# 8. Строим explicit graph по edges (даже если doorway'и не образуют
	# «shared wall» — tunnels connect chambers через corridor rects).
	var graph := RoomGraph.new(layout.rooms.size())
	for edge in all_edges:
		graph.add_edge(edge.a, edge.b)
	layout.room_graph = graph

# --- Chamber placement ------------------------------------------------------

static func _try_place_chamber(
	slot_origin: Vector2i,
	slot_w: int,
	slot_h: int,
	placed: Array,
	rng: RandomNumberGenerator,
) -> Rect2i:
	# Внутри slot: chamber размера [MIN, MAX] tiles, jitter position так,
	# чтобы chamber помещался в slot и не касался соседей ближе чем
	# MIN_SPACING_TILES.
	var chamber_w: int = rng.randi_range(
		CHAMBER_MIN_TILES,
		mini(CHAMBER_MAX_TILES, maxi(CHAMBER_MIN_TILES, slot_w - MIN_SPACING_TILES)),
	)
	var chamber_h: int = rng.randi_range(
		CHAMBER_MIN_TILES,
		mini(CHAMBER_MAX_TILES, maxi(CHAMBER_MIN_TILES, slot_h - MIN_SPACING_TILES)),
	)
	# Пробуем 4 попытки placement.
	for attempt in 4:
		var jitter_x: int = rng.randi_range(0, maxi(0, slot_w - chamber_w - 1))
		var jitter_y: int = rng.randi_range(0, maxi(0, slot_h - chamber_h - 1))
		var candidate := Rect2i(
			slot_origin + Vector2i(jitter_x, jitter_y),
			Vector2i(chamber_w, chamber_h),
		)
		if _fits_without_overlap(candidate, placed):
			return candidate
	return Rect2i(Vector2i.ZERO, Vector2i.ZERO)

static func _fits_without_overlap(candidate: Rect2i, placed: Array) -> bool:
	var buffered := candidate.grow(MIN_SPACING_TILES)
	for other in placed:
		if buffered.intersects(other):
			return false
	return true

# --- MST + extra edges ------------------------------------------------------

static func _build_mst_edges(rooms: Array) -> Array:
	# Kruskal по расстоянию между центрами chambers.
	var edges: Array = []
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			var d_sq: int = _center_distance_sq(rooms[i], rooms[j])
			edges.append({"a": i, "b": j, "weight": d_sq})
	edges.sort_custom(func(x, y): return _edge_sort_key(x) < _edge_sort_key(y))
	var parent: Array[int] = []
	parent.resize(rooms.size())
	for i in rooms.size():
		parent[i] = i
	var picked: Array = []
	for e in edges:
		if _uf_union(parent, e.a, e.b):
			picked.append(e)
		if picked.size() == rooms.size() - 1:
			break
	return picked

static func _pick_extra_edges(
	rooms: Array,
	mst_edges: Array,
	count: int,
) -> Array:
	# Кандидаты — non-MST edges. Берём top-N по возрастанию длины
	# (самые короткие → локальные loops, а не глобальные перепрыжки).
	var mst_set: Dictionary = {}
	for e in mst_edges:
		mst_set[_edge_key(e)] = true
	var candidates: Array = []
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			var e := {"a": i, "b": j, "weight": _center_distance_sq(rooms[i], rooms[j])}
			if not mst_set.has(_edge_key(e)):
				candidates.append(e)
	if candidates.is_empty():
		return []
	candidates.sort_custom(func(x, y): return _edge_sort_key(x) < _edge_sort_key(y))
	# Берём count самых коротких — они создают локальные loops
	# (визуально «крюки», а не глобальные перепрыжки).
	var picked: Array = []
	for i in mini(count, candidates.size()):
		picked.append(candidates[i])
	return picked

static func _edge_sort_key(e: Dictionary) -> Array:
	return [int(e.weight), int(e.a), int(e.b)]

static func _edge_key(e: Dictionary) -> String:
	var i0: int = mini(int(e.a), int(e.b))
	var i1: int = maxi(int(e.a), int(e.b))
	return "%d_%d" % [i0, i1]

static func _uf_find(parent: Array[int], x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x

static func _uf_union(parent: Array[int], a: int, b: int) -> bool:
	var ra := _uf_find(parent, a)
	var rb := _uf_find(parent, b)
	if ra == rb:
		return false
	parent[ra] = rb
	return true

static func _center_distance_sq(a: Rect2i, b: Rect2i) -> int:
	var ac := a.get_center()
	var bc := b.get_center()
	return (ac.x - bc.x) * (ac.x - bc.x) + (ac.y - bc.y) * (ac.y - bc.y)

# --- Tunnel carving --------------------------------------------------------

static func _carve_tunnel(
	layout: DungeonLayout,
	a_idx: int,
	b_idx: int,
	rng: RandomNumberGenerator,
) -> void:
	# L-shape tunnel: сначала horizontal segment от центра A до центра B по X,
	# затем vertical segment. Ширина TUNNEL_WIDTH_TILES.
	var a: Rect2i = layout.rooms[a_idx]
	var b: Rect2i = layout.rooms[b_idx]
	var ac := a.get_center()
	var bc := b.get_center()
	var tunnel_w: int = TUNNEL_WIDTH_TILES * TILE
	# Порядок L: рандомно horizontal→vertical или vertical→horizontal.
	var horizontal_first := rng.randf() < 0.5
	if horizontal_first:
		var h := Rect2i(
			Vector2i(mini(ac.x, bc.x), ac.y - tunnel_w / 2),
			Vector2i(abs(bc.x - ac.x), tunnel_w),
		)
		if h.size.x > 0:
			layout.corridors.append(h)
		var v := Rect2i(
			Vector2i(bc.x - tunnel_w / 2, mini(ac.y, bc.y)),
			Vector2i(tunnel_w, abs(bc.y - ac.y)),
		)
		if v.size.y > 0:
			layout.corridors.append(v)
	else:
		var v := Rect2i(
			Vector2i(ac.x - tunnel_w / 2, mini(ac.y, bc.y)),
			Vector2i(tunnel_w, abs(bc.y - ac.y)),
		)
		if v.size.y > 0:
			layout.corridors.append(v)
		var h := Rect2i(
			Vector2i(mini(ac.x, bc.x), bc.y - tunnel_w / 2),
			Vector2i(abs(bc.x - ac.x), tunnel_w),
		)
		if h.size.x > 0:
			layout.corridors.append(h)

# --- Utility ---------------------------------------------------------------

static func _shuffle_with_rng(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
