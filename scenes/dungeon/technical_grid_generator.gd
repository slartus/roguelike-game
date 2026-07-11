class_name TechnicalGridGenerator
extends RefCounted

# Technical grid v2 — служебный этаж (zone = technical, floor 7-10) с
# ДВУМЯ параллельными main corridors + большими машинными между ними +
# maintenance rooms на внешних краях + 2-3 cross-connectors.
#
# Форма:
# +--------------------------------------------------+
# | maint0 | maint1 | maint2 | maint3 | maint4       |  ← top-band rooms
# +--D--------D-------D--------D--------D------------+
# ═══════════════════════════════════════════════════   ← top corridor (rail)
# +-----------+-----------+-----------+
# | machine 0 | machine 1 | machine 2 |                ← middle band (big)
# +-----------+-----------+-----------+
# ═══════════════════════════════════════════════════   ← bottom corridor (rail)
# +--D--------D-------D--------D--------D------------+
# | maint5 | maint6 | maint7 | maint8 | maint9       |  ← bottom-band rooms
# +--------------------------------------------------+
#
# Cross-connectors (не показаны) — 2-3 вертикальных rect, соединяют
# top rail с bottom rail напрямую в промежутках между machine rooms.
# Создают дополнительные loops. Shortcut'ы (машина ↔ смежная maint)
# опционально.

const TILE: int = 20
const RAIL_WIDTH_TILES: int = 2                 # 40 px — узкий служебный
const MAINT_MIN_WIDTH_TILES: int = 4
const MAINT_MAX_WIDTH_TILES: int = 6
const MAINT_MIN_DEPTH_TILES: int = 4
const MAINT_MAX_DEPTH_TILES: int = 5
const MACHINE_MIN_WIDTH_TILES: int = 8
const MACHINE_MAX_WIDTH_TILES: int = 12
const MACHINE_MIN_DEPTH_TILES: int = 5
const DOORWAY_WIDTH_TILES: int = 2

static func generate(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	_floor_number: int,
	footprint_tiles: Vector2i,
) -> void:
	var width_px: int = footprint_tiles.x * TILE
	var height_px: int = footprint_tiles.y * TILE

	# --- Расчёт вертикального лэйаута ---------------------------------------
	# Верх: TILE gap + top maint band + TILE gap + top rail
	# Середина: middle band (machines)
	# Низ: bottom rail + TILE gap + bottom maint band + TILE gap
	var rail_height: int = RAIL_WIDTH_TILES * TILE
	var maint_depth_tiles: int = clampi(
		MAINT_MAX_DEPTH_TILES, MAINT_MIN_DEPTH_TILES, MAINT_MAX_DEPTH_TILES,
	)
	var maint_depth: int = maint_depth_tiles * TILE
	# Разделяем оставшуюся высоту на middle band.
	var reserved_top: int = TILE + maint_depth + TILE + rail_height
	var reserved_bottom: int = rail_height + TILE + maint_depth + TILE
	var middle_height: int = height_px - reserved_top - reserved_bottom
	# Если middle слишком мал — уменьшаем maint depth, чтоб machine влезла.
	if middle_height < MACHINE_MIN_DEPTH_TILES * TILE:
		maint_depth = MAINT_MIN_DEPTH_TILES * TILE
		reserved_top = TILE + maint_depth + TILE + rail_height
		reserved_bottom = rail_height + TILE + maint_depth + TILE
		middle_height = height_px - reserved_top - reserved_bottom
	if middle_height < MACHINE_MIN_DEPTH_TILES * TILE:
		# Нет места на 2 rails — bail out на legacy single-corridor логику.
		# Просто одну rail в середине, без machine band.
		_generate_single_rail_fallback(layout, rng, footprint_tiles)
		return

	var top_maint_y: int = TILE
	var top_rail_y: int = top_maint_y + maint_depth + TILE
	var middle_y: int = top_rail_y + rail_height
	var bottom_rail_y: int = middle_y + middle_height
	var bottom_maint_y: int = bottom_rail_y + rail_height + TILE

	# --- Rails (два main corridors) -----------------------------------------
	var top_rail := Rect2i(0, top_rail_y, width_px, rail_height)
	var bottom_rail := Rect2i(0, bottom_rail_y, width_px, rail_height)
	layout.corridors.append(top_rail)      # index 0 — main corridor (для test compat)
	layout.corridors.append(bottom_rail)   # index 1

	# --- Middle band: machine rooms -----------------------------------------
	# room_metadata[i] = {"band": String, "index_in_band": int}
	var room_metadata: Array = []
	var middle_indices: Array = _carve_middle_machines(
		layout, rng, room_metadata,
		width_px, middle_y, middle_height,
		top_rail, bottom_rail,
	)

	# --- Top maintenance band ------------------------------------------------
	var top_indices: Array = _carve_maint_row(
		layout, rng, room_metadata,
		width_px, top_maint_y, maint_depth,
		true, top_rail,
	)
	# --- Bottom maintenance band --------------------------------------------
	var bottom_indices: Array = _carve_maint_row(
		layout, rng, room_metadata,
		width_px, bottom_maint_y, maint_depth,
		false, bottom_rail,
	)

	# --- Cross-connectors: 2-3 вертикальных rect ----------------------------
	# Между machine rooms — в «промежутках» ставим вертикальный corridor
	# от top rail до bottom rail. Не пересекаемся с machine rooms.
	# ВАЖНО: floor_bounds ещё не вычислен на этом шаге (compute_bounds
	# идёт позже в DungeonGenerator), поэтому передаём width_px явно —
	# иначе правый slot справа от последней machine никогда не появится.
	var connector_slots: Array = _find_connector_slots(middle_indices, layout, width_px)
	var connector_count: int = clampi(connector_slots.size(), 0, 3)
	if connector_count > 0:
		_shuffle_with_rng(connector_slots, rng)
	for i in mini(connector_count, connector_slots.size()):
		var slot: Dictionary = connector_slots[i]
		# slot = {"x_lo": int, "x_hi": int}. Ставим 2-tile connector.
		var conn_width: int = RAIL_WIDTH_TILES * TILE
		var conn_x: int = slot.x_lo + rng.randi_range(0, maxi(0, slot.x_hi - slot.x_lo - conn_width))
		layout.corridors.append(Rect2i(
			conn_x, top_rail.end.y,
			conn_width, bottom_rail.position.y - top_rail.end.y,
		))

	# --- Player start / exit (hints, overwritten by graph-distance) ---------
	layout.player_start = Vector2i(
		top_rail.position.x + TILE + TILE / 2,
		(top_rail.position.y + bottom_rail.end.y) / 2,
	)
	layout.exit_position = Vector2i(
		top_rail.end.x - TILE - TILE / 2,
		(top_rail.position.y + bottom_rail.end.y) / 2,
	)

	# --- Graph ---------------------------------------------------------------
	layout.room_graph = _build_graph(layout, room_metadata, middle_indices, top_indices, bottom_indices)

# --- Fallback (когда footprint слишком мал для 2 rails) ---------------------

static func _generate_single_rail_fallback(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	footprint_tiles: Vector2i,
) -> void:
	# Дегенеративный случай — оставляем один rail с maint комнатами по обе
	# стороны. Простая цепочка без wing.
	var width_px: int = footprint_tiles.x * TILE
	var height_px: int = footprint_tiles.y * TILE
	var rail_height: int = RAIL_WIDTH_TILES * TILE
	var rail_y: int = (height_px - rail_height) / 2
	var rail_rect := Rect2i(0, rail_y, width_px, rail_height)
	layout.corridors.append(rail_rect)
	var maint_depth: int = MAINT_MIN_DEPTH_TILES * TILE
	var room_metadata: Array = []
	var top_indices: Array = _carve_maint_row(
		layout, rng, room_metadata,
		width_px, rail_y - TILE - maint_depth, maint_depth,
		true, rail_rect,
	)
	var bottom_indices: Array = _carve_maint_row(
		layout, rng, room_metadata,
		width_px, rail_y + rail_height + TILE, maint_depth,
		false, rail_rect,
	)
	layout.player_start = Vector2i(
		rail_rect.position.x + TILE + TILE / 2,
		rail_rect.get_center().y,
	)
	layout.exit_position = Vector2i(
		rail_rect.end.x - TILE - TILE / 2,
		rail_rect.get_center().y,
	)
	# Простая графовая модель fallback'а: цепочка top + цепочка bottom
	# соединены по крайним точкам через rail.
	var graph := RoomGraph.new(layout.rooms.size())
	for i in range(top_indices.size() - 1):
		graph.add_edge(top_indices[i], top_indices[i + 1])
	for i in range(bottom_indices.size() - 1):
		graph.add_edge(bottom_indices[i], bottom_indices[i + 1])
	if not top_indices.is_empty() and not bottom_indices.is_empty():
		graph.add_edge(top_indices[0], bottom_indices[0])
		graph.add_edge(top_indices[top_indices.size() - 1], bottom_indices[bottom_indices.size() - 1])
	layout.room_graph = graph

# --- Machine rooms в middle band -------------------------------------------

static func _carve_middle_machines(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	room_metadata: Array,
	width_px: int,
	band_y: int,
	band_height: int,
	top_rail: Rect2i,
	bottom_rail: Rect2i,
) -> Array:
	var indices: Array = []
	var cursor_x: int = TILE
	var end_x: int = width_px - TILE
	var machine_depth: int = band_height  # используем всю высоту middle band
	while cursor_x + MACHINE_MIN_WIDTH_TILES * TILE <= end_x:
		var width_tiles: int = rng.randi_range(MACHINE_MIN_WIDTH_TILES, MACHINE_MAX_WIDTH_TILES)
		var width_px_room: int = width_tiles * TILE
		if cursor_x + width_px_room > end_x:
			width_px_room = end_x - cursor_x
			if width_px_room < MACHINE_MIN_WIDTH_TILES * TILE:
				break
		var machine := Rect2i(cursor_x, band_y, width_px_room, machine_depth)
		var idx: int = layout.rooms.size()
		layout.rooms.append(machine)
		indices.append(idx)
		room_metadata.append({"band": "middle", "index_in_band": indices.size() - 1})
		# Doorways: сверху к top_rail, снизу к bottom_rail.
		_carve_doorway_vertical(layout, rng, machine, top_rail, true)
		_carve_doorway_vertical(layout, rng, machine, bottom_rail, false)
		cursor_x += width_px_room + TILE
	return indices

# --- Maint rows выше/ниже rails --------------------------------------------

static func _carve_maint_row(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	room_metadata: Array,
	total_width_px: int,
	band_y: int,
	band_depth: int,
	above_rail: bool,
	rail_rect: Rect2i,
) -> Array:
	var indices: Array = []
	var cursor_x: int = TILE
	var end_x: int = total_width_px - TILE
	var depth_tiles: int = clampi(
		int(band_depth / TILE),
		MAINT_MIN_DEPTH_TILES,
		MAINT_MAX_DEPTH_TILES,
	)
	var depth_px: int = depth_tiles * TILE
	if above_rail:
		band_y = rail_rect.position.y - TILE - depth_px
	while cursor_x + MAINT_MIN_WIDTH_TILES * TILE <= end_x:
		var width_tiles: int = rng.randi_range(MAINT_MIN_WIDTH_TILES, MAINT_MAX_WIDTH_TILES)
		var width_px_room: int = width_tiles * TILE
		if cursor_x + width_px_room > end_x:
			width_px_room = end_x - cursor_x
			if width_px_room < MAINT_MIN_WIDTH_TILES * TILE:
				break
		var room := Rect2i(cursor_x, band_y, width_px_room, depth_px)
		var idx: int = layout.rooms.size()
		layout.rooms.append(room)
		indices.append(idx)
		room_metadata.append({
			"band": ("top" if above_rail else "bottom"),
			"index_in_band": indices.size() - 1,
		})
		_carve_doorway_vertical(layout, rng, room, rail_rect, not above_rail)
		cursor_x += width_px_room + TILE
	return indices

# --- Doorway helpers -------------------------------------------------------

static func _carve_doorway_vertical(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	room: Rect2i,
	rail_rect: Rect2i,
	room_below_rail: bool,
) -> void:
	# Вертикальный doorway между room и rail. room_below_rail=true если
	# room сидит ниже rail, false — выше.
	var door_width_px: int = DOORWAY_WIDTH_TILES * TILE
	var min_x: int = room.position.x + TILE
	var max_x: int = room.end.x - door_width_px - TILE
	if max_x <= min_x:
		max_x = min_x
	var door_x: int = rng.randi_range(min_x, max_x)
	var door_y: int
	var door_height: int
	if room_below_rail:
		# room ниже rail → doorway между rail.end.y и room.position.y.
		door_y = rail_rect.end.y
		door_height = room.position.y - rail_rect.end.y
	else:
		door_y = room.end.y
		door_height = rail_rect.position.y - room.end.y
	if door_height <= 0:
		return
	layout.corridors.append(Rect2i(door_x, door_y, door_width_px, door_height))

# --- Cross-connector slots -------------------------------------------------

static func _find_connector_slots(
	middle_indices: Array,
	layout: DungeonLayout,
	width_px: int,
) -> Array:
	# Промежутки между смежными machine rooms — там можно поставить
	# вертикальный connector напрямую от top rail до bottom rail.
	var slots: Array = []
	# Слева от первой machine.
	if not middle_indices.is_empty():
		var first: Rect2i = layout.rooms[middle_indices[0]]
		if first.position.x >= TILE * 2:
			slots.append({"x_lo": TILE, "x_hi": first.position.x - TILE})
	# Между machines.
	for i in range(middle_indices.size() - 1):
		var a: Rect2i = layout.rooms[middle_indices[i]]
		var b: Rect2i = layout.rooms[middle_indices[i + 1]]
		if b.position.x - a.end.x >= TILE * 2:
			slots.append({"x_lo": a.end.x, "x_hi": b.position.x - TILE})
	# Справа от последней. Используем переданный width_px, потому что
	# layout.floor_bounds ещё не вычислен на этом этапе pipeline.
	if not middle_indices.is_empty():
		var last: Rect2i = layout.rooms[middle_indices[middle_indices.size() - 1]]
		if last.end.x + TILE * 2 <= width_px:
			slots.append({"x_lo": last.end.x, "x_hi": width_px - TILE})
	return slots

# --- Graph -----------------------------------------------------------------

static func _build_graph(
	layout: DungeonLayout,
	room_metadata: Array,
	middle_indices: Array,
	top_indices: Array,
	bottom_indices: Array,
) -> RoomGraph:
	# Модель:
	# - top chain (по X): top_indices[i] ↔ top_indices[i+1]
	# - bottom chain: bottom_indices[i] ↔ bottom_indices[i+1]
	# - middle chain: middle_indices[i] ↔ middle_indices[i+1]
	# - каждая middle machine соединена с ближайшим top и ближайшим bottom
	#   (по X-центру) — physical doorways через rail дают именно это.
	var graph := RoomGraph.new(layout.rooms.size())
	for i in range(top_indices.size() - 1):
		graph.add_edge(top_indices[i], top_indices[i + 1])
	for i in range(bottom_indices.size() - 1):
		graph.add_edge(bottom_indices[i], bottom_indices[i + 1])
	for i in range(middle_indices.size() - 1):
		graph.add_edge(middle_indices[i], middle_indices[i + 1])
	# Middle ↔ top / bottom.
	for m_idx in middle_indices:
		var machine: Rect2i = layout.rooms[m_idx]
		var m_cx: int = machine.get_center().x
		var t_idx: int = _nearest_by_x(layout, top_indices, m_cx)
		if t_idx >= 0:
			graph.add_edge(m_idx, t_idx)
		var b_idx: int = _nearest_by_x(layout, bottom_indices, m_cx)
		if b_idx >= 0:
			graph.add_edge(m_idx, b_idx)
	return graph

static func _nearest_by_x(layout: DungeonLayout, indices: Array, target_x: int) -> int:
	if indices.is_empty():
		return -1
	var best: int = indices[0]
	var best_dist: int = abs(layout.rooms[best].get_center().x - target_x)
	for i in range(1, indices.size()):
		var idx: int = indices[i]
		var d: int = abs(layout.rooms[idx].get_center().x - target_x)
		if d < best_dist:
			best_dist = d
			best = idx
	return best

static func _shuffle_with_rng(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
