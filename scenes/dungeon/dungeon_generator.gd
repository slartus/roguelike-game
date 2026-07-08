class_name DungeonGenerator
extends RefCounted

# Детерминированный генератор этажей подземелья.
#
# Алгоритм:
# 1. Число комнат = clamp(MIN_ROOMS + floor_number/2, MIN_ROOMS, MAX_ROOMS).
# 2. Комнаты выстраиваются в цепочку: каждая следующая правее (60%)
#    или ниже (40%) предыдущей с зазором ROOM_GAP.
# 3. Между соседями по цепочке — L-образный коридор (горизонтальный
#    сегмент + вертикальный).
# 4. Player стартует в центре первой комнаты, exit — в центре последней.
# 5. Enemy spawn'ы — в средних комнатах (2-3) и в последней (1-2).
# 6. Chest — 1 штука в случайной средней комнате, только если
#    floor_number % 3 == 0.
# 7. Boss-этаж — одна большая арена, exit сразу.
# 8. Все координаты нормализуются: floor_bounds.position = (0, 0).

const ROOM_MIN_SIZE: Vector2i = Vector2i(140, 100)
const ROOM_MAX_SIZE: Vector2i = Vector2i(210, 150)
const ROOM_GAP_MIN: int = 80
const ROOM_GAP_MAX: int = 140
const CORRIDOR_WIDTH: int = 24
const FLOOR_PADDING: int = 60
const ENEMY_SPAWN_MARGIN: int = 22
const MIN_ROOMS: int = 4
const MAX_ROOMS: int = 9
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
		_generate_regular_floor(layout, rng, floor_number)
	_compute_bounds(layout)
	_normalize(layout)
	return layout

func _generate_regular_floor(layout: DungeonLayout, rng: RandomNumberGenerator, floor_number: int) -> void:
	var room_count := clampi(MIN_ROOMS + floor_number / 2, MIN_ROOMS, MAX_ROOMS)
	var pos := Vector2i.ZERO
	for i in room_count:
		var size := Vector2i(
			rng.randi_range(ROOM_MIN_SIZE.x, ROOM_MAX_SIZE.x),
			rng.randi_range(ROOM_MIN_SIZE.y, ROOM_MAX_SIZE.y),
		)
		layout.rooms.append(Rect2i(pos, size))
		if i < room_count - 1:
			var horizontal := rng.randf() < 0.6
			var gap := rng.randi_range(ROOM_GAP_MIN, ROOM_GAP_MAX)
			if horizontal:
				pos = Vector2i(pos.x + size.x + gap, pos.y + rng.randi_range(-40, 40))
			else:
				pos = Vector2i(pos.x + rng.randi_range(-40, 40), pos.y + size.y + gap)
	for i in room_count - 1:
		_add_corridor(layout, layout.rooms[i], layout.rooms[i + 1])
	layout.player_start = layout.rooms[0].get_center()
	layout.exit_position = layout.rooms[-1].get_center()
	for i in range(1, room_count - 1):
		_add_enemy_spawns(layout, layout.rooms[i], rng, 2, 3)
	if room_count >= 2:
		_add_enemy_spawns(layout, layout.rooms[room_count - 1], rng, 1, 2)
	if floor_number % CHEST_FLOOR_INTERVAL == 0 and room_count > 2:
		var chest_room_idx := rng.randi_range(1, room_count - 2)
		var chest_room := layout.rooms[chest_room_idx]
		layout.chest_positions.append(chest_room.get_center() + Vector2i(rng.randi_range(-30, 30), rng.randi_range(-30, 30)))

func _generate_boss_floor(layout: DungeonLayout) -> void:
	var room := Rect2i(Vector2i.ZERO, BOSS_ROOM_SIZE)
	layout.rooms.append(room)
	layout.player_start = Vector2i(BOSS_ROOM_SIZE.x / 6, BOSS_ROOM_SIZE.y / 2)
	layout.exit_position = Vector2i(BOSS_ROOM_SIZE.x * 5 / 6, BOSS_ROOM_SIZE.y / 2)

func _add_corridor(layout: DungeonLayout, from_room: Rect2i, to_room: Rect2i) -> void:
	var from_center := from_room.get_center()
	var to_center := to_room.get_center()
	var half_w: int = CORRIDOR_WIDTH / 2
	var h_min_x: int = mini(from_center.x, to_center.x)
	var h_max_x: int = maxi(from_center.x, to_center.x)
	var horizontal := Rect2i(
		Vector2i(h_min_x, from_center.y - half_w),
		Vector2i(h_max_x - h_min_x + CORRIDOR_WIDTH, CORRIDOR_WIDTH),
	)
	var v_min_y: int = mini(from_center.y, to_center.y)
	var v_max_y: int = maxi(from_center.y, to_center.y)
	var vertical := Rect2i(
		Vector2i(to_center.x - half_w, v_min_y),
		Vector2i(CORRIDOR_WIDTH, v_max_y - v_min_y + CORRIDOR_WIDTH),
	)
	if horizontal.size.x > 0 and horizontal.size.y > 0:
		layout.corridors.append(horizontal)
	if vertical.size.x > 0 and vertical.size.y > 0:
		layout.corridors.append(vertical)

func _add_enemy_spawns(layout: DungeonLayout, room: Rect2i, rng: RandomNumberGenerator, min_count: int, max_count: int) -> void:
	var count := rng.randi_range(min_count, max_count)
	var x_range := maxi(1, room.size.x - ENEMY_SPAWN_MARGIN * 2)
	var y_range := maxi(1, room.size.y - ENEMY_SPAWN_MARGIN * 2)
	for i in count:
		var x := room.position.x + ENEMY_SPAWN_MARGIN + rng.randi_range(0, x_range)
		var y := room.position.y + ENEMY_SPAWN_MARGIN + rng.randi_range(0, y_range)
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
