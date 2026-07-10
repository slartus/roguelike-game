class_name ResidentialSpineGenerator
extends RefCounted

# Residential spine layout — план здания с центральным коридором и
# комнатами по обе стороны. Используется для tower_top и residential zone.
# Игрок движется через coridor от одного конца к другому, комнаты
# разветвляются как жилые/служебные помещения.
#
# Форма:
# +---------------------------------------+
# | room1 | room2 | room3 | room4 | room5 |
# |--D------D-------D-------D-------D-----|
# |                                       |
# |            main corridor              |
# |                                       |
# |--D------D-------D-------D-------D-----|
# | room6 | room7 | room8 | room9 | room10|
# +---------------------------------------+
#
# У каждой боковой комнаты — doorway в corridor. Player_start — центр
# левого конца corridor, exit — центр правого конца. Комнаты — Rect2i
# в пиксельных координатах (TILE = 20 px).

const TILE: int = 20
const CORRIDOR_WIDTH_TILES: int = 3            # 60 px — комфортная ширина
const ROOM_MIN_WIDTH_TILES: int = 4            # 80 px минимум
const ROOM_MAX_WIDTH_TILES: int = 8            # 160 px максимум
const ROOM_MIN_DEPTH_TILES: int = 4            # глубина от коридора наружу
const ROOM_MAX_DEPTH_TILES: int = 6
const DOORWAY_WIDTH_TILES: int = 2             # 40 px как в legacy
const ENEMY_SPAWN_MARGIN: int = 22
const CHEST_FLOOR_INTERVAL: int = 3

# Основной entry point. Возвращает "raw" DungeonLayout без coord-нормализации
# и bounds — их применит DungeonGenerator тем же способом, что и для legacy.
static func generate(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	floor_number: int,
	footprint_tiles: Vector2i,
) -> void:
	# 1. Footprint. Убеждаемся что вход/выход и коридор влезают.
	var width_px: int = footprint_tiles.x * TILE
	var height_px: int = footprint_tiles.y * TILE

	# 2. Corridor в вертикальной середине.
	var corridor_height: int = CORRIDOR_WIDTH_TILES * TILE
	var corridor_y: int = (height_px - corridor_height) / 2
	var corridor_rect := Rect2i(0, corridor_y, width_px, corridor_height)
	layout.corridors.append(corridor_rect)

	# 3. Нарезаем rooms сверху и снизу. Слева-направо, пока хватает места.
	# Между низом верхнего ряда и верхом коридора (симметрично снизу)
	# резервируем 1 tile для стены, в которую пробивается doorway. Без этой
	# прослойки комнаты сливаются с коридором в открытые альковы — двери
	# визуально пропадают.
	var top_band_height: int = corridor_y - TILE - TILE
	var bottom_band_height: int = height_px - (corridor_y + corridor_height) - TILE - TILE
	if top_band_height < ROOM_MIN_DEPTH_TILES * TILE:
		top_band_height = ROOM_MIN_DEPTH_TILES * TILE
	if bottom_band_height < ROOM_MIN_DEPTH_TILES * TILE:
		bottom_band_height = ROOM_MIN_DEPTH_TILES * TILE

	_carve_row_of_rooms(
		layout, rng,
		width_px, TILE, top_band_height,
		true,  # rooms сверху → дверной проём снизу (в коридор)
		corridor_rect,
	)
	_carve_row_of_rooms(
		layout, rng,
		width_px, corridor_y + corridor_height + TILE, bottom_band_height,
		false,  # rooms снизу → дверной проём сверху
		corridor_rect,
	)

	# 4. Player start и exit — концы коридора.
	# Смещаем немного внутрь чтобы не стоять «на стене».
	layout.player_start = Vector2i(
		corridor_rect.position.x + TILE + TILE / 2,
		corridor_rect.get_center().y,
	)
	layout.exit_position = Vector2i(
		corridor_rect.end.x - TILE - TILE / 2,
		corridor_rect.get_center().y,
	)

	# 5. Enemy spawns во всех комнатах.
	for room in layout.rooms:
		if room.has_point(layout.player_start) or room.has_point(layout.exit_position):
			continue
		_add_enemy_spawns(layout, room, rng, 2, 3)

	# 6. Chest на этажах кратных CHEST_FLOOR_INTERVAL — в случайной middle room.
	if floor_number % CHEST_FLOOR_INTERVAL == 0 and layout.rooms.size() > 0:
		var chest_room_idx: int = rng.randi_range(0, layout.rooms.size() - 1)
		var chest_room: Rect2i = layout.rooms[chest_room_idx]
		var offset := Vector2i(rng.randi_range(-20, 20), rng.randi_range(-20, 20))
		layout.chest_positions.append(chest_room.get_center() + offset)

static func _carve_row_of_rooms(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	total_width_px: int,
	band_y: int,
	band_depth_px: int,
	rooms_above_corridor: bool,
	corridor_rect: Rect2i,
) -> void:
	# Room depth chose в пределах band_depth. Комнаты в ряду делят band_depth
	# одной высотой для аккуратного рисунка.
	var room_depth_tiles: int = clampi(
		int(band_depth_px / TILE),
		ROOM_MIN_DEPTH_TILES,
		ROOM_MAX_DEPTH_TILES,
	)
	var room_depth_px: int = room_depth_tiles * TILE
	if rooms_above_corridor:
		# Верхний ряд: комнаты прижаты к 1-tile стене под коридором.
		# room.end.y == corridor.position.y - TILE — оставляем ровно один
		# tile под doorway.
		band_y = corridor_rect.position.y - TILE - room_depth_px

	var cursor_x: int = TILE  # 1 tile отступ слева
	var end_x: int = total_width_px - TILE
	while cursor_x + ROOM_MIN_WIDTH_TILES * TILE <= end_x:
		var room_width_tiles: int = rng.randi_range(ROOM_MIN_WIDTH_TILES, ROOM_MAX_WIDTH_TILES)
		var room_width_px: int = room_width_tiles * TILE
		# Не выйти за правый край
		if cursor_x + room_width_px > end_x:
			room_width_px = end_x - cursor_x
			if room_width_px < ROOM_MIN_WIDTH_TILES * TILE:
				break
		var room := Rect2i(cursor_x, band_y, room_width_px, room_depth_px)
		layout.rooms.append(room)
		# Doorway в corridor: пробиваем 2-tile проём в общей стене.
		_carve_doorway_to_corridor(layout, rng, room, corridor_rect, rooms_above_corridor)
		# Сдвиг: комната + 1 tile стена между.
		cursor_x += room_width_px + TILE

static func _carve_doorway_to_corridor(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	room: Rect2i,
	corridor_rect: Rect2i,
	room_above_corridor: bool,
) -> void:
	# Doorway — маленький corridor rect, соединяющий room с main corridor.
	# Позиция по X — случайная в пределах внутренней части комнаты.
	var door_width_px: int = DOORWAY_WIDTH_TILES * TILE
	var min_x: int = room.position.x + TILE
	var max_x: int = room.end.x - door_width_px - TILE
	if max_x <= min_x:
		# Комната слишком узкая для inset — приклеиваем doorway к левому краю.
		max_x = min_x
	var door_x: int = rng.randi_range(min_x, max_x)
	var door_y: int
	var door_height: int
	if room_above_corridor:
		# Проем сверху коридора → между низом комнаты и верхом коридора.
		door_y = room.end.y
		door_height = corridor_rect.position.y - room.end.y
	else:
		# Проем снизу коридора.
		door_y = corridor_rect.end.y
		door_height = room.position.y - corridor_rect.end.y
	# Если стены между комнатой и коридором нет (комнаты примыкают), не
	# рисуем doorway — они уже соединены.
	if door_height <= 0:
		return
	layout.corridors.append(Rect2i(door_x, door_y, door_width_px, door_height))

static func _add_enemy_spawns(
	layout: DungeonLayout,
	room: Rect2i,
	rng: RandomNumberGenerator,
	min_spawns: int,
	max_spawns: int,
) -> void:
	var count: int = rng.randi_range(min_spawns, max_spawns)
	for _i in count:
		var x: int = rng.randi_range(
			room.position.x + ENEMY_SPAWN_MARGIN,
			room.end.x - ENEMY_SPAWN_MARGIN,
		)
		var y: int = rng.randi_range(
			room.position.y + ENEMY_SPAWN_MARGIN,
			room.end.y - ENEMY_SPAWN_MARGIN,
		)
		layout.enemy_spawns.append(Vector2i(x, y))
