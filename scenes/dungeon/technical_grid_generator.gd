class_name TechnicalGridGenerator
extends RefCounted

# Technical grid layout — служебные этажи (zone = technical, floor 7-10).
# Отличается от residential_spine тем, что:
# - main corridor уже (2 tiles) — служебный коридор, не жилая галерея;
# - комнаты крупнее (шире и глубже) — машинные/щитовые/склады;
# - несколько маленьких service closets между большими комнатами.
#
# Схема остаётся spine-подобной, чтобы сохранить читаемое движение
# слева-направо через этаж, но текстура ролей и размеров отличается.
# Пока сложные grid-layout (2 корридора) не реализуем — план явно
# допускает начать с одного корридора и разной геометрии комнат.

const TILE: int = 20
const CORRIDOR_WIDTH_TILES: int = 2         # 40 px — узкий служебный
const LARGE_ROOM_WIDTH_TILES: int = 8       # 160 px — машинные/склады
const LARGE_ROOM_MAX_WIDTH_TILES: int = 12  # 240 px — большая машинная
const SMALL_CLOSET_WIDTH_TILES: int = 3     # 60 px — узкий closet
const ROOM_MIN_DEPTH_TILES: int = 5         # 100 px — глубже residential
const ROOM_MAX_DEPTH_TILES: int = 7         # 140 px
const DOORWAY_WIDTH_TILES: int = 2
const ENEMY_SPAWN_MARGIN: int = 22
const CHEST_FLOOR_INTERVAL: int = 3
# Шанс что очередная комната в ряду будет small_closet, а не большой залой.
# Дает служебный feel: пара крупных машин + пара маленьких щитков.
const SMALL_CLOSET_CHANCE: float = 0.35

static func generate(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	floor_number: int,
	footprint_tiles: Vector2i,
) -> void:
	var width_px: int = footprint_tiles.x * TILE
	var height_px: int = footprint_tiles.y * TILE

	# Service corridor уже, чем residential — узкий проход между машинами.
	var corridor_height: int = CORRIDOR_WIDTH_TILES * TILE
	var corridor_y: int = (height_px - corridor_height) / 2
	var corridor_rect := Rect2i(0, corridor_y, width_px, corridor_height)
	layout.corridors.append(corridor_rect)

	# Оставляем по 1 tile стены между комнатами и коридором — иначе
	# doorway имеет высоту 0, в общей стене нет ни двери, ни стены,
	# комнаты «сливаются» с коридором.
	var top_band_height: int = corridor_y - TILE - TILE
	var bottom_band_height: int = height_px - (corridor_y + corridor_height) - TILE - TILE
	if top_band_height < ROOM_MIN_DEPTH_TILES * TILE:
		top_band_height = ROOM_MIN_DEPTH_TILES * TILE
	if bottom_band_height < ROOM_MIN_DEPTH_TILES * TILE:
		bottom_band_height = ROOM_MIN_DEPTH_TILES * TILE

	_carve_row_of_rooms(
		layout, rng,
		width_px, TILE, top_band_height,
		true,
		corridor_rect,
	)
	_carve_row_of_rooms(
		layout, rng,
		width_px, corridor_y + corridor_height + TILE, bottom_band_height,
		false,
		corridor_rect,
	)

	layout.player_start = Vector2i(
		corridor_rect.position.x + TILE + TILE / 2,
		corridor_rect.get_center().y,
	)
	layout.exit_position = Vector2i(
		corridor_rect.end.x - TILE - TILE / 2,
		corridor_rect.get_center().y,
	)

	# Enemy spawns во всех rooms кроме entrance/exit.
	for room in layout.rooms:
		if room.has_point(layout.player_start) or room.has_point(layout.exit_position):
			continue
		_add_enemy_spawns(layout, room, rng, 2, 3)

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
	var room_depth_tiles: int = clampi(
		int(band_depth_px / TILE),
		ROOM_MIN_DEPTH_TILES,
		ROOM_MAX_DEPTH_TILES,
	)
	var room_depth_px: int = room_depth_tiles * TILE
	if rooms_above_corridor:
		# Оставляем 1 tile под doorway между низом комнат и верхом коридора.
		band_y = corridor_rect.position.y - TILE - room_depth_px

	var cursor_x: int = TILE
	var end_x: int = total_width_px - TILE
	while cursor_x + SMALL_CLOSET_WIDTH_TILES * TILE <= end_x:
		# Выбор: small closet или большая машинная.
		var is_closet: bool = rng.randf() < SMALL_CLOSET_CHANCE
		var room_width_tiles: int
		if is_closet:
			room_width_tiles = SMALL_CLOSET_WIDTH_TILES
		else:
			room_width_tiles = rng.randi_range(LARGE_ROOM_WIDTH_TILES, LARGE_ROOM_MAX_WIDTH_TILES)
		var room_width_px: int = room_width_tiles * TILE
		if cursor_x + room_width_px > end_x:
			room_width_px = end_x - cursor_x
			if room_width_px < SMALL_CLOSET_WIDTH_TILES * TILE:
				break
		var room := Rect2i(cursor_x, band_y, room_width_px, room_depth_px)
		layout.rooms.append(room)
		_carve_doorway_to_corridor(layout, rng, room, corridor_rect, rooms_above_corridor)
		cursor_x += room_width_px + TILE

static func _carve_doorway_to_corridor(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
	room: Rect2i,
	corridor_rect: Rect2i,
	room_above_corridor: bool,
) -> void:
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
