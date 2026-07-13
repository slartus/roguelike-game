class_name ResidentialSpineGenerator
extends RefCounted

# Residential spine v2 — план здания с центральным коридором и
# комнатами по обе стороны + перпендикулярное «крыло» с 2-3 доп.
# комнатами + минимум один shortcut между смежными side-rooms.
#
# Используется для tower_top и residential zones.
#
# Форма:
#         wing corridor
#             │
#     ┌───────┼───────┐
#     │ w0    │ w1    │
#     └───┬───┴───┬───┘
#         │       │           ↑ wing rooms (branch)
# +-------┼-------┼--------------------+
# |room0  door  door                    |
# |----D-------D-------D-------D-------|
# |                                    |
# |            main corridor           |  ← main chain: r0-r1-...-rN
# |                                    |
# |----D-------D-------D-------D-------|
# |room5  door  door                    |
# +------------------------------------+
#         ↑ shortcut между room1 и room2 создаёт loop.
#
# Гарантии для этой версии:
# - main corridor + минимум 1 wing → ветвление ≥ 1;
# - 1 room-to-room shortcut → loop ≥ 1 (при >= 4 side-rooms);
# - build_graph заполняет layout.room_graph явно.

const TILE: int = 20
const CORRIDOR_WIDTH_TILES: int = 3
const ROOM_MIN_WIDTH_TILES: int = 4
const ROOM_MAX_WIDTH_TILES: int = 8
const ROOM_MIN_DEPTH_TILES: int = 4
const ROOM_MAX_DEPTH_TILES: int = 6
const DOORWAY_WIDTH_TILES: int = 2
const WING_MIN_WIDTH_TILES: int = 4
const WING_MAX_WIDTH_TILES: int = 6
const WING_DEPTH_TILES: int = 4
const WING_CORRIDOR_WIDTH_TILES: int = 2

static func generate(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	_floor_number: int,
	footprint_tiles: Vector2i,
) -> void:
	var width_px: int = footprint_tiles.x * TILE
	var height_px: int = footprint_tiles.y * TILE

	# 1. Main corridor в вертикальной середине.
	var corridor_height: int = CORRIDOR_WIDTH_TILES * TILE
	var corridor_y: int = (height_px - corridor_height) / 2
	var corridor_rect := Rect2i(0, corridor_y, width_px, corridor_height)
	layout.corridors.append(corridor_rect)

	# 2. Полосы над/под коридором. Оставляем 1-tile gap для стены+doorway.
	var top_band_height: int = corridor_y - TILE - TILE
	var bottom_band_height: int = height_px - (corridor_y + corridor_height) - TILE - TILE
	top_band_height = maxi(top_band_height, ROOM_MIN_DEPTH_TILES * TILE)
	bottom_band_height = maxi(bottom_band_height, ROOM_MIN_DEPTH_TILES * TILE)

	# Собираем rooms и door-metadata (для последующей graph-сборки).
	# room_metadata[i] = {"side": "top"|"bottom", "door_x": int}.
	var room_metadata: Array = []

	_carve_row_of_rooms(
		layout, rng, room_metadata,
		width_px, TILE, top_band_height,
		true, corridor_rect,
	)
	_carve_row_of_rooms(
		layout, rng, room_metadata,
		width_px, corridor_y + corridor_height + TILE, bottom_band_height,
		false, corridor_rect,
	)

	# 3. Player start/exit — временные (перекроются graph-distance selector'ом).
	# Даём hints по концам, чтобы _apply_graph_distance_entrance_exit имел
	# fallback: если графовый выбор развалится, эти координаты остаются.
	layout.player_start = Vector2i(
		corridor_rect.position.x + TILE + TILE / 2,
		corridor_rect.get_center().y,
	)
	layout.exit_position = Vector2i(
		corridor_rect.end.x - TILE - TILE / 2,
		corridor_rect.get_center().y,
	)

	# 4. Wing (побочный коридор с 2-3 комнатами).
	# Только если у нас есть top-band для его размещения над коридором.
	# Ставим wing выше main corridor, слева-центре — так центр этажа
	# получает branch (T-shape). Без wing если footprint слишком узкий.
	_maybe_add_wing(layout, rng, room_metadata, corridor_rect, width_px, height_px)

	# 5. Shortcut между смежными side-rooms — если есть 4+ комнаты.
	# Прошиваем узкий вертикальный doorway между двумя соседями в одном
	# ряду. Создаёт loop поверх main-corridor-chain.
	_maybe_add_shortcut(layout, rng, room_metadata)

	# 6. Строим граф.
	layout.room_graph = _build_graph(layout, room_metadata)

static func _carve_row_of_rooms(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	room_metadata: Array,
	total_width_px: int,
	band_y: int,
	band_depth_px: int,
	rooms_above_corridor: bool,
	corridor_rect: Rect2i,
) -> void:
	var room_depth_tiles: int = clampi(
		int(band_depth_px / TILE),
		ROOM_MIN_DEPTH_TILES,
		ROOM_MAX_DEPTH_TILES,
	)
	var room_depth_px: int = room_depth_tiles * TILE
	if rooms_above_corridor:
		band_y = corridor_rect.position.y - TILE - room_depth_px

	var cursor_x: int = TILE
	var end_x: int = total_width_px - TILE
	while cursor_x + ROOM_MIN_WIDTH_TILES * TILE <= end_x:
		var room_width_tiles: int = rng.randi_range(ROOM_MIN_WIDTH_TILES, ROOM_MAX_WIDTH_TILES)
		var room_width_px: int = room_width_tiles * TILE
		if cursor_x + room_width_px > end_x:
			room_width_px = end_x - cursor_x
			if room_width_px < ROOM_MIN_WIDTH_TILES * TILE:
				break
		var room := Rect2i(cursor_x, band_y, room_width_px, room_depth_px)
		layout.rooms.append(room)
		var door_x := _carve_doorway_to_corridor(layout, rng, room, corridor_rect, rooms_above_corridor)
		room_metadata.append({
			"side": "top" if rooms_above_corridor else "bottom",
			"door_x": door_x,
		})
		cursor_x += room_width_px + TILE

# Возвращает door_x — позиция doorway по X, нужна для graph-сборки.
# -1 если doorway не рисуется (стены нет).
static func _carve_doorway_to_corridor(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	room: Rect2i,
	corridor_rect: Rect2i,
	room_above_corridor: bool,
) -> int:
	var door_width_px: int = DOORWAY_WIDTH_TILES * TILE
	var min_x: int = room.position.x + TILE
	var max_x: int = room.end.x - door_width_px - TILE
	if max_x <= min_x:
		max_x = min_x
	var door_x: int = rng.randi_range(min_x, max_x)
	var door_y: int
	var door_height: int
	if room_above_corridor:
		door_y = room.end.y
		door_height = corridor_rect.position.y - room.end.y
	else:
		door_y = corridor_rect.end.y
		door_height = room.position.y - corridor_rect.end.y
	if door_height <= 0:
		return -1
	layout.corridors.append(Rect2i(door_x, door_y, door_width_px, door_height))
	return door_x

# --- Wing (перпендикулярный коридор с 2-3 доп. комнатами) ------------------

static func _maybe_add_wing(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	room_metadata: Array,
	corridor_rect: Rect2i,
	width_px: int,
	height_px: int,
) -> void:
	# Нужны 4+ side-rooms в одном ряду, чтобы «взять одну» под wing-connector.
	# Выбираем комнату из top-row (чтобы wing уходил вверх).
	var top_indices: Array = []
	for i in room_metadata.size():
		if room_metadata[i].side == "top":
			top_indices.append(i)
	if top_indices.size() < 3:
		return
	# Берём среднюю top-комнату — wing будет читаться как «второй этаж».
	var host_idx: int = top_indices[top_indices.size() / 2]
	var host: Rect2i = layout.rooms[host_idx]
	# Wing corridor начинается от верха host. Направление — вверх.
	var wing_corridor_width: int = WING_CORRIDOR_WIDTH_TILES * TILE
	var wing_corridor_x: int = host.get_center().x - wing_corridor_width / 2
	# Wing rooms — 2 шт., справа от wing corridor.
	# Проверим, что для wing хватает высоты над host.
	var wing_room_depth: int = WING_DEPTH_TILES * TILE
	var wing_room_min_width: int = WING_MIN_WIDTH_TILES * TILE
	var wing_top_y: int = host.position.y - TILE - wing_room_depth
	if wing_top_y < TILE:
		# Нет места — bail out. Loop могут дать shortcut'ы.
		return
	var wing_corridor_top_y: int = wing_top_y + wing_room_depth
	var wing_corridor_height: int = host.position.y - wing_corridor_top_y - TILE
	if wing_corridor_height < TILE * 2:
		return
	# Wing corridor: тонкий, между wing rooms и host.
	# Не пересекает host — вешаем его над host, между wing rooms.
	layout.corridors.append(Rect2i(
		wing_corridor_x, wing_corridor_top_y,
		wing_corridor_width, wing_corridor_height,
	))
	# Doorway между wing corridor и host (короткая).
	# Wing corridor.end.y должно совпадать с host.position.y - TILE, а gap
	# = TILE. Кладём doorway в этот gap.
	var host_doorway_y: int = wing_corridor_top_y + wing_corridor_height
	var host_doorway_height: int = host.position.y - host_doorway_y
	if host_doorway_height > 0:
		var host_doorway_x: int = wing_corridor_x
		layout.corridors.append(Rect2i(
			host_doorway_x, host_doorway_y,
			wing_corridor_width, host_doorway_height,
		))

	# Пара wing-rooms по обе стороны от wing corridor.
	var wing_room_widths: Array = [
		rng.randi_range(WING_MIN_WIDTH_TILES, WING_MAX_WIDTH_TILES) * TILE,
		rng.randi_range(WING_MIN_WIDTH_TILES, WING_MAX_WIDTH_TILES) * TILE,
	]
	# Left wing room.
	var left_w: int = wing_room_widths[0]
	var left_x: int = wing_corridor_x - TILE - left_w
	if left_x >= TILE:
		var left_room := Rect2i(left_x, wing_top_y, left_w, wing_room_depth)
		layout.rooms.append(left_room)
		# Doorway wing corridor → left wing room. Вертикальный doorway
		# в стене между ними (общая стена = wing_corridor_x - TILE .. wing_corridor_x).
		var door_h: int = DOORWAY_WIDTH_TILES * TILE
		var door_y: int = wing_corridor_top_y + rng.randi_range(0, maxi(0, wing_corridor_height - door_h))
		layout.corridors.append(Rect2i(
			left_x + left_w, door_y,
			wing_corridor_x - (left_x + left_w), door_h,
		))
		room_metadata.append({
			"side": "wing_left",
			"door_x": left_x + left_w,
			"wing_corridor_x": wing_corridor_x,
			"host_idx": host_idx,
		})
	# Right wing room.
	var right_w: int = wing_room_widths[1]
	var right_x: int = wing_corridor_x + wing_corridor_width + TILE
	if right_x + right_w <= width_px - TILE:
		var right_room := Rect2i(right_x, wing_top_y, right_w, wing_room_depth)
		layout.rooms.append(right_room)
		var door_h: int = DOORWAY_WIDTH_TILES * TILE
		var door_y: int = wing_corridor_top_y + rng.randi_range(0, maxi(0, wing_corridor_height - door_h))
		layout.corridors.append(Rect2i(
			wing_corridor_x + wing_corridor_width, door_y,
			right_x - (wing_corridor_x + wing_corridor_width), door_h,
		))
		room_metadata.append({
			"side": "wing_right",
			"door_x": right_x,
			"wing_corridor_x": wing_corridor_x,
			"host_idx": host_idx,
		})

# --- Shortcut между смежными side-rooms в одном ряду -----------------------

static func _maybe_add_shortcut(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	room_metadata: Array,
) -> void:
	# Смежные top-top или bottom-bottom комнаты имеют общую вертикальную
	# стену — прошиваем doorway.
	# Собираем пары индексов, идущих подряд в одном ряду.
	var pairs: Array = []
	for i in range(room_metadata.size() - 1):
		if room_metadata[i].side != room_metadata[i + 1].side:
			continue
		var a: Rect2i = layout.rooms[i]
		var b: Rect2i = layout.rooms[i + 1]
		# Adjacent через 1-tile стену.
		if a.end.x + TILE == b.position.x:
			pairs.append([i, i + 1])
	if pairs.is_empty():
		return
	var pick: Array = pairs[rng.randi_range(0, pairs.size() - 1)]
	var idx_a: int = pick[0]
	var idx_b: int = pick[1]
	var a: Rect2i = layout.rooms[idx_a]
	var b: Rect2i = layout.rooms[idx_b]
	# Вертикальная общая стена: from x = a.end.x to b.position.x, gap = TILE.
	# Y-overlap:
	var y_lo: int = maxi(a.position.y, b.position.y)
	var y_hi: int = mini(a.end.y, b.end.y)
	if y_hi - y_lo < DOORWAY_WIDTH_TILES * TILE:
		return
	var door_h: int = DOORWAY_WIDTH_TILES * TILE
	var door_y: int = y_lo + rng.randi_range(0, y_hi - y_lo - door_h)
	layout.corridors.append(Rect2i(a.end.x, door_y, TILE, door_h))
	# Записываем shortcut в metadata — graph builder использует.
	room_metadata.append({
		"side": "shortcut",
		"a": idx_a,
		"b": idx_b,
	})

# --- Graph -----------------------------------------------------------------

static func _build_graph(layout: DungeonLayout, room_metadata: Array) -> RoomGraph:
	# Модель графа:
	# - Все top-row rooms образуют цепочку по возрастанию door_x
	#   (соседние по коридору = соседние в графе).
	# - То же самое для bottom-row.
	# - Wing rooms (left и right, если оба есть) связаны с host_idx
	#   через wing corridor. Left ↔ right тоже через тот же корридор.
	# - Кроме того, один room из top-chain и один из bottom-chain должны
	#   быть связаны — они физически на одном main corridor. Простейшая
	#   модель: соединяем крайние: top[0] ↔ bottom[0], top[-1] ↔ bottom[-1].
	#   Даёт loop (chain top + chain bottom + 2 vertical edges).
	# - Shortcut'ы добавляются напрямую.
	var graph := RoomGraph.new(layout.rooms.size())
	# Собираем top и bottom индексы в порядке metadata (совпадает с
	# порядком добавления rooms — layout.rooms[i] соответствует metadata[i]
	# для НЕ-wing metadata).
	var top_chain: Array = []
	var bottom_chain: Array = []
	var wing_indices: Array = []  # wing_left / wing_right room indices
	var host_idx: int = -1
	# ВНИМАНИЕ: room_metadata может содержать non-room entries (shortcut).
	# Пробегаем и берём только те, у которых есть layout.rooms[i].
	# Индекс комнаты = position в rooms (совпадает с порядком добавления).
	# Metadata синхронизирован: side="top"|"bottom" метки соответствуют
	# первым layout.rooms.size() записям. Wing rooms добавились позже.
	var room_count := layout.rooms.size()
	# Проходим первые room_count метаданных (по одному на room).
	for i in room_count:
		if i >= room_metadata.size():
			break
		var meta: Dictionary = room_metadata[i]
		var side: String = meta.side
		if side == "top":
			top_chain.append(i)
		elif side == "bottom":
			bottom_chain.append(i)
		elif side == "wing_left" or side == "wing_right":
			wing_indices.append(i)
			host_idx = int(meta.host_idx)
	# Chain top.
	for i in range(top_chain.size() - 1):
		graph.add_edge(top_chain[i], top_chain[i + 1])
	# Chain bottom.
	for i in range(bottom_chain.size() - 1):
		graph.add_edge(bottom_chain[i], bottom_chain[i + 1])
	# Cross-links top ↔ bottom: только по концам и середине.
	# Полный ladder-каждый-с-каждым делал все rooms degree 3 и убивал
	# dead-ends → chest placement bias терялся. 2-3 cross-link'а дают
	# 1-2 loops + внутренние rooms остаются degree 2, крайние top/bottom
	# получают degree 3 (branch), а некоторые middle rooms остаются
	# честными dead-ends в графе (нет cross-link, только chain соседи).
	# Для 2-row layout с 5+ rooms это баланс между «интересным» и
	# «читаемым»: loop проходит через оба ряда, но не все rooms
	# избыточно связаны.
	if not top_chain.is_empty() and not bottom_chain.is_empty():
		var cross_pairs: Array = _pick_cross_link_pairs(top_chain, bottom_chain, layout)
		for pair in cross_pairs:
			graph.add_edge(int(pair[0]), int(pair[1]))
	# Wing connections. Host uses wing corridor; wing rooms sit on both
	# sides of wing corridor. Simple model: host ↔ wing_left, host ↔ wing_right,
	# wing_left ↔ wing_right (через wing corridor).
	if host_idx >= 0 and not wing_indices.is_empty():
		for wi in wing_indices:
			graph.add_edge(host_idx, wi)
		if wing_indices.size() == 2:
			graph.add_edge(wing_indices[0], wing_indices[1])
	# Shortcut metadata (side == "shortcut") — прямое ребро a ↔ b.
	for meta in room_metadata:
		if meta.get("side", "") == "shortcut":
			graph.add_edge(int(meta.a), int(meta.b))
	return graph

# --- Утилита -------------------------------------------------------------

# Выбирает 2-3 cross-link пары (top ↔ bottom) — крайние и средняя.
# Оставляет большинство middle-rooms без cross-link, чтобы сохранить
# честные dead-ends для reward placement.
static func _pick_cross_link_pairs(
	top_chain: Array,
	bottom_chain: Array,
	layout: DungeonLayout,
) -> Array:
	var pairs: Array = []
	var top_first: int = top_chain[0]
	var bottom_first: int = _nearest_by_x(
		layout, bottom_chain, layout.rooms[top_first].get_center().x,
	)
	if bottom_first >= 0:
		pairs.append([top_first, bottom_first])
	if top_chain.size() >= 2 and bottom_chain.size() >= 2:
		var top_last: int = top_chain[top_chain.size() - 1]
		var bottom_last: int = _nearest_by_x(
			layout, bottom_chain, layout.rooms[top_last].get_center().x,
		)
		if bottom_last >= 0 and bottom_last != bottom_first:
			pairs.append([top_last, bottom_last])
	# Средняя пара — только если ≥ 5 rooms в каждой цепочке (даёт loop
	# через середину, не удваивая dead-end).
	if top_chain.size() >= 5 and bottom_chain.size() >= 5:
		var top_mid: int = top_chain[top_chain.size() / 2]
		var bottom_mid: int = _nearest_by_x(
			layout, bottom_chain, layout.rooms[top_mid].get_center().x,
		)
		if bottom_mid >= 0:
			pairs.append([top_mid, bottom_mid])
	return pairs

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
