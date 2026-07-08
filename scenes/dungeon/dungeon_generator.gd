class_name DungeonGenerator
extends RefCounted

# Детерминированный генератор этажей "башни".
#
# Лор: игрок телепортируется на верхний этаж башни. Каждый следующий
# этаж (глубже в башню) — расширенная версия предыдущего. На верхних
# этажах маленькая планировка 2×2 комнаты; чем глубже, тем больше
# grid растёт.
#
# Форма планировки — квадратный grid комнат, соприкасающихся стенами
# толщиной WALL_THICKNESS. В общей стене между соседями пробит
# дверной проём шириной DOORWAY_WIDTH. Никаких длинных коридоров —
# только грид и проходы. (Длинные тоннели-подвалы — задел на будущее.)
#
# Размер grid:
#   floor 1-3   → 2×2  ( 4 rooms)
#   floor 4-6   → 3×3  ( 9 rooms)
#   floor 7-9   → 4×4  (16 rooms)
#   floor 10-12 → 5×5  (25 rooms), кап
#
# Boss-этажи (floor_number % 5 == 0) — одна большая арена, старый
# генератор boss floor. См. `_generate_boss_floor`.
#
# Все координаты нормализуются: floor_bounds.position = (0, 0).

const ROOM_SIZE: Vector2i = Vector2i(140, 100)
const WALL_THICKNESS: int = 20     # 1 tile — совпадает с TILE_SIZE в floor.gd
const DOORWAY_WIDTH: int = 40      # 2 tile проём
const DOORWAY_MARGIN: int = 20     # отступ проёма от угла комнаты
const FLOOR_PADDING: int = 60
const ENEMY_SPAWN_MARGIN: int = 22
const MIN_GRID: int = 2
const MAX_GRID: int = 5
const CHEST_FLOOR_INTERVAL: int = 3
const BOSS_ROOM_SIZE: Vector2i = Vector2i(600, 400)

func generate(seed: int, floor_number: int, is_boss: bool) -> DungeonLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var layout := DungeonLayout.new()
	layout.is_boss_floor = is_boss
	if is_boss:
		_generate_boss_floor(layout)
	else:
		_generate_tower_floor(layout, rng, floor_number)
	_compute_bounds(layout)
	_normalize(layout)
	return layout

# Grid dimension по номеру этажа. Растёт по +1 каждые 3 этажа, кап MAX_GRID.
func grid_dim_for_floor(floor_number: int) -> int:
	return clampi(MIN_GRID + (floor_number - 1) / 3, MIN_GRID, MAX_GRID)

func _generate_tower_floor(layout: DungeonLayout, rng: RandomNumberGenerator, floor_number: int) -> void:
	var grid_dim := grid_dim_for_floor(floor_number)
	var cell_step := Vector2i(ROOM_SIZE.x + WALL_THICKNESS, ROOM_SIZE.y + WALL_THICKNESS)

	# Разместить комнаты по grid (порядок: row-major, row 0 сверху)
	var rooms_by_cell: Dictionary = {}
	for row in grid_dim:
		for col in grid_dim:
			var pos := Vector2i(col * cell_step.x, row * cell_step.y)
			var rect := Rect2i(pos, ROOM_SIZE)
			layout.rooms.append(rect)
			rooms_by_cell[Vector2i(col, row)] = rect

	# Дверные проёмы в общих стенах между соседями по grid
	for row in grid_dim:
		for col in grid_dim:
			var cell := Vector2i(col, row)
			var room: Rect2i = rooms_by_cell[cell]
			var right_cell := Vector2i(col + 1, row)
			if rooms_by_cell.has(right_cell):
				var y_slack: int = maxi(1, room.size.y - 2 * DOORWAY_MARGIN - DOORWAY_WIDTH)
				var y_start: int = room.position.y + DOORWAY_MARGIN + rng.randi_range(0, y_slack)
				layout.corridors.append(Rect2i(
					Vector2i(room.end.x, y_start),
					Vector2i(WALL_THICKNESS, DOORWAY_WIDTH),
				))
			var down_cell := Vector2i(col, row + 1)
			if rooms_by_cell.has(down_cell):
				var x_slack: int = maxi(1, room.size.x - 2 * DOORWAY_MARGIN - DOORWAY_WIDTH)
				var x_start: int = room.position.x + DOORWAY_MARGIN + rng.randi_range(0, x_slack)
				layout.corridors.append(Rect2i(
					Vector2i(x_start, room.end.y),
					Vector2i(DOORWAY_WIDTH, WALL_THICKNESS),
				))

	# Точка телепортации — верхняя левая комната (мы прыгнули с верха башни)
	var start_room: Rect2i = rooms_by_cell[Vector2i(0, 0)]
	# Выход — нижняя правая (спуск глубже в башню)
	var exit_room: Rect2i = rooms_by_cell[Vector2i(grid_dim - 1, grid_dim - 1)]
	layout.player_start = start_room.get_center()
	layout.exit_position = exit_room.get_center()

	# Спавн врагов во всех комнатах, кроме стартовой и exit
	for room in layout.rooms:
		if room == start_room or room == exit_room:
			continue
		_add_enemy_spawns(layout, room, rng, 2, 3)

	# Сундук — в случайной middle комнате каждые CHEST_FLOOR_INTERVAL этажей
	if floor_number % CHEST_FLOOR_INTERVAL == 0:
		var middle_rooms: Array[Rect2i] = []
		for room in layout.rooms:
			if room == start_room or room == exit_room:
				continue
			middle_rooms.append(room)
		if middle_rooms.size() > 0:
			var chest_room: Rect2i = middle_rooms[rng.randi_range(0, middle_rooms.size() - 1)]
			layout.chest_positions.append(chest_room.get_center() + Vector2i(rng.randi_range(-20, 20), rng.randi_range(-20, 20)))

func _generate_boss_floor(layout: DungeonLayout) -> void:
	var room := Rect2i(Vector2i.ZERO, BOSS_ROOM_SIZE)
	layout.rooms.append(room)
	layout.player_start = Vector2i(BOSS_ROOM_SIZE.x / 6, BOSS_ROOM_SIZE.y / 2)
	layout.exit_position = Vector2i(BOSS_ROOM_SIZE.x * 5 / 6, BOSS_ROOM_SIZE.y / 2)

func _add_enemy_spawns(layout: DungeonLayout, room: Rect2i, rng: RandomNumberGenerator, min_count: int, max_count: int) -> void:
	var count := rng.randi_range(min_count, max_count)
	var x_range: int = maxi(1, room.size.x - ENEMY_SPAWN_MARGIN * 2)
	var y_range: int = maxi(1, room.size.y - ENEMY_SPAWN_MARGIN * 2)
	for i in count:
		var x: int = room.position.x + ENEMY_SPAWN_MARGIN + rng.randi_range(0, x_range)
		var y: int = room.position.y + ENEMY_SPAWN_MARGIN + rng.randi_range(0, y_range)
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
