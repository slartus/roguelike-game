extends GutTest

const DungeonGeneratorClass = preload("res://scenes/dungeon/dungeon_generator.gd")

var _gen

func before_each() -> void:
	_gen = DungeonGeneratorClass.new()

# --- Footprint scaling ---------------------------------------------------

func test_footprint_scales_with_floor() -> void:
	assert_lt(_gen.footprint_tiles_for_floor(1).x, _gen.footprint_tiles_for_floor(10).x,
		"deeper floors have larger footprint")
	assert_lte(_gen.footprint_tiles_for_floor(30).x, 40,
		"footprint capped at 40 tiles wide")
	assert_lte(_gen.footprint_tiles_for_floor(30).y, 28,
		"footprint capped at 28 tiles tall")

func test_deeper_floors_have_more_rooms_than_shallow() -> void:
	var floor_1 = _gen.generate(42, 1, false)
	var floor_10 = _gen.generate(42, 10, false)
	assert_gt(floor_10.rooms.size(), floor_1.rooms.size(),
		"tower widens as you descend")

# --- Boss floor invariants (unchanged) ----------------------------------

func test_boss_floor_has_single_room_and_no_doorways() -> void:
	var layout = _gen.generate(42, 5, true)
	assert_eq(layout.rooms.size(), 1)
	assert_eq(layout.corridors.size(), 0)
	assert_eq(layout.enemy_spawns.size(), 0)
	assert_eq(layout.chest_positions.size(), 0)
	assert_true(layout.is_boss_floor)

# --- Player start / exit ------------------------------------------------

func test_player_start_is_in_top_left_room() -> void:
	# Top-left = argmin(position.x + position.y)
	var layout = _gen.generate(42, 4, false)
	var target := layout.rooms[0]
	for room in layout.rooms:
		if room.position.x + room.position.y < target.position.x + target.position.y:
			target = room
	assert_true(target.has_point(layout.player_start),
		"player_start %s not inside top-left room %s" % [layout.player_start, target])

func test_exit_is_in_bottom_right_room() -> void:
	# Bottom-right = argmax(end.x + end.y)
	var layout = _gen.generate(42, 4, false)
	var target := layout.rooms[0]
	for room in layout.rooms:
		if room.end.x + room.end.y > target.end.x + target.end.y:
			target = room
	assert_true(target.has_point(layout.exit_position),
		"exit %s not inside bottom-right room %s" % [layout.exit_position, target])

# --- Enemy spawns -------------------------------------------------------

func test_all_enemy_spawns_are_inside_some_room() -> void:
	var layout = _gen.generate(42, 4, false)
	for spawn in layout.enemy_spawns:
		var inside := false
		for room in layout.rooms:
			if room.has_point(spawn):
				inside = true
				break
		assert_true(inside, "enemy spawn %s not inside any room" % spawn)

func test_no_enemy_spawns_in_start_or_exit_room() -> void:
	var layout = _gen.generate(42, 4, false)
	var start_room := layout.rooms[0]
	for room in layout.rooms:
		if room.position.x + room.position.y < start_room.position.x + start_room.position.y:
			start_room = room
	var exit_room := layout.rooms[0]
	for room in layout.rooms:
		if room.end.x + room.end.y > exit_room.end.x + exit_room.end.y:
			exit_room = room
	for spawn in layout.enemy_spawns:
		assert_false(start_room.has_point(spawn), "no spawns in start room")
		assert_false(exit_room.has_point(spawn), "no spawns in exit room")

# --- Chest --------------------------------------------------------------

func test_chest_only_on_floor_multiples_of_three() -> void:
	assert_eq(_gen.generate(42, 1, false).chest_positions.size(), 0)
	assert_eq(_gen.generate(42, 2, false).chest_positions.size(), 0)
	assert_eq(_gen.generate(42, 3, false).chest_positions.size(), 1)
	assert_eq(_gen.generate(42, 4, false).chest_positions.size(), 0)
	assert_eq(_gen.generate(42, 6, false).chest_positions.size(), 1)

# --- Determinism --------------------------------------------------------

func test_same_seed_produces_identical_layout() -> void:
	var a = _gen.generate(42, 4, false)
	var b = _gen.generate(42, 4, false)
	assert_eq(a.rooms.size(), b.rooms.size())
	for i in a.rooms.size():
		assert_eq(a.rooms[i], b.rooms[i], "room %d matches" % i)
	assert_eq(a.corridors, b.corridors, "corridors match")
	assert_eq(a.player_start, b.player_start)
	assert_eq(a.exit_position, b.exit_position)
	assert_eq(a.enemy_spawns, b.enemy_spawns)

func test_different_seeds_produce_different_layouts() -> void:
	var a = _gen.generate(42, 4, false)
	var b = _gen.generate(999, 4, false)
	# BSP splits с разным seed дают разные leaf-rooms
	var differs := false
	if a.rooms.size() != b.rooms.size():
		differs = true
	else:
		for i in a.rooms.size():
			if a.rooms[i] != b.rooms[i]:
				differs = true
				break
	assert_true(differs, "different seeds should produce different layouts")

# --- Bounds & normalization --------------------------------------------

func test_layout_is_normalized_to_origin() -> void:
	var layout = _gen.generate(42, 5, false)
	assert_eq(layout.floor_bounds.position, Vector2i.ZERO)
	for room in layout.rooms:
		assert_gte(room.position.x, 0)
		assert_gte(room.position.y, 0)

func test_floor_bounds_contain_all_rooms_and_doorways() -> void:
	var layout = _gen.generate(42, 4, false)
	for room in layout.rooms:
		assert_true(layout.floor_bounds.encloses(room),
			"room %s not enclosed by bounds %s" % [room, layout.floor_bounds])
	for corridor in layout.corridors:
		assert_true(layout.floor_bounds.encloses(corridor),
			"doorway %s not enclosed by bounds %s" % [corridor, layout.floor_bounds])

# --- BSP-specific invariants (новые тесты) -----------------------------

func test_rooms_vary_in_size() -> void:
	var layout = _gen.generate(42, 7, false)
	var min_area := 999999
	var max_area := 0
	for room in layout.rooms:
		var area: int = room.size.x * room.size.y
		min_area = mini(min_area, area)
		max_area = maxi(max_area, area)
	assert_gte(max_area, min_area * 2,
		"largest room should be at least 2x smallest (varied sizes)")

func test_all_rooms_reachable_via_doorways() -> void:
	var layout = _gen.generate(42, 4, false)
	# BFS от rooms[0] через corridor-соседей
	var visited := _bfs_reachable_rooms(layout, 0)
	assert_eq(visited.size(), layout.rooms.size(),
		"all rooms must be connected via doorways (MST guarantees this)")

func test_start_reaches_exit_via_doorways() -> void:
	var layout = _gen.generate(42, 4, false)
	# Найти start_room_idx и exit_room_idx
	var start_idx := 0
	var exit_idx := 0
	for i in range(1, layout.rooms.size()):
		if layout.rooms[i].position.x + layout.rooms[i].position.y < layout.rooms[start_idx].position.x + layout.rooms[start_idx].position.y:
			start_idx = i
		if layout.rooms[i].end.x + layout.rooms[i].end.y > layout.rooms[exit_idx].end.x + layout.rooms[exit_idx].end.y:
			exit_idx = i
	var visited := _bfs_reachable_rooms(layout, start_idx)
	assert_true(visited.has(exit_idx),
		"exit room must be reachable from start room via doorways")

func test_has_cycles_on_floor_4_plus() -> void:
	# С 25% extra edges должны быть циклы: corridors.size() > rooms.size() - 1
	var layout = _gen.generate(42, 7, false)
	if layout.rooms.size() >= 4:
		assert_gt(layout.corridors.size(), layout.rooms.size() - 1,
			"25%% extra edges should create at least one cycle beyond the MST tree")

func test_some_adjacent_rooms_have_no_doorway_on_floor_7() -> void:
	# С extra_ratio 0.25 остаётся часть смежных пар без прохода.
	var layout = _gen.generate(42, 7, false)
	if layout.rooms.size() < 4:
		return
	# Считаем сколько пар комнат смежны (share wall >= MIN_SHARED_WALL)
	# и сколько из них имеют doorway.
	var shared_pairs := 0
	for i in layout.rooms.size():
		for j in range(i + 1, layout.rooms.size()):
			if _rooms_share_wall(layout.rooms[i], layout.rooms[j]):
				shared_pairs += 1
	assert_gt(shared_pairs, layout.corridors.size(),
		"some adjacent rooms should not have doorway (residential feel)")

# --- Test helpers -------------------------------------------------------

func _bfs_reachable_rooms(layout, start_idx: int) -> Array:
	# Возвращает список индексов комнат, достижимых от start_idx через
	# corridors (doorways).
	var visited := [start_idx]
	var queue := [start_idx]
	while queue.size() > 0:
		var current: int = queue.pop_front()
		var current_room: Rect2i = layout.rooms[current]
		# Найти всех соседей: другие rooms, у которых есть shared wall
		# И между ними есть corridor в этой стене.
		for j in layout.rooms.size():
			if j in visited:
				continue
			var other_room: Rect2i = layout.rooms[j]
			if not _rooms_share_wall(current_room, other_room):
				continue
			# Проверить есть ли corridor в общей стене
			if not _has_corridor_between(current_room, other_room, layout.corridors):
				continue
			visited.append(j)
			queue.append(j)
	return visited

func _rooms_share_wall(a: Rect2i, b: Rect2i) -> bool:
	var wall_t := DungeonGeneratorClass.WALL_THICKNESS
	var min_share := DungeonGeneratorClass.MIN_SHARED_WALL
	# Вертикальные
	if a.end.x + wall_t == b.position.x or b.end.x + wall_t == a.position.x:
		var lo: int = maxi(a.position.y, b.position.y)
		var hi: int = mini(a.end.y, b.end.y)
		if hi - lo >= min_share:
			return true
	# Горизонтальные
	if a.end.y + wall_t == b.position.y or b.end.y + wall_t == a.position.y:
		var lo: int = maxi(a.position.x, b.position.x)
		var hi: int = mini(a.end.x, b.end.x)
		if hi - lo >= min_share:
			return true
	return false

func _has_corridor_between(a: Rect2i, b: Rect2i, corridors: Array) -> bool:
	var wall_t := DungeonGeneratorClass.WALL_THICKNESS
	# Вертикальная стена между A и B
	var wall_x := -1
	if a.end.x + wall_t == b.position.x:
		wall_x = a.end.x
	elif b.end.x + wall_t == a.position.x:
		wall_x = b.end.x
	if wall_x >= 0:
		var y_lo: int = maxi(a.position.y, b.position.y)
		var y_hi: int = mini(a.end.y, b.end.y)
		for c in corridors:
			if c.position.x == wall_x and c.position.y >= y_lo and c.end.y <= y_hi:
				return true
	# Горизонтальная стена между A и B
	var wall_y := -1
	if a.end.y + wall_t == b.position.y:
		wall_y = a.end.y
	elif b.end.y + wall_t == a.position.y:
		wall_y = b.end.y
	if wall_y >= 0:
		var x_lo: int = maxi(a.position.x, b.position.x)
		var x_hi: int = mini(a.end.x, b.end.x)
		for c in corridors:
			if c.position.y == wall_y and c.position.x >= x_lo and c.end.x <= x_hi:
				return true
	return false
