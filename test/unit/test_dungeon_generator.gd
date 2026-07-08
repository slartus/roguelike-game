extends GutTest

const DungeonGeneratorClass = preload("res://scenes/dungeon/dungeon_generator.gd")

var _gen

func before_each() -> void:
	_gen = DungeonGeneratorClass.new()

func test_floor_1_is_2x2_grid() -> void:
	var layout = _gen.generate(42, 1, false)
	assert_eq(layout.rooms.size(), 4, "2x2 grid = 4 rooms")
	assert_eq(_gen.grid_dim_for_floor(1), 2)

func test_grid_grows_every_three_floors() -> void:
	assert_eq(_gen.grid_dim_for_floor(3), 2)
	assert_eq(_gen.grid_dim_for_floor(4), 3, "floor 4 = 3x3")
	assert_eq(_gen.grid_dim_for_floor(7), 4)
	assert_eq(_gen.grid_dim_for_floor(10), 5)
	assert_eq(_gen.grid_dim_for_floor(20), DungeonGeneratorClass.MAX_GRID,
		"grid capped at MAX_GRID")

func test_regular_floor_has_doorway_connectors_between_all_grid_neighbours() -> void:
	# Для NxN grid ожидаем N*(N-1) горизонтальных + N*(N-1) вертикальных = 2*N*(N-1)
	var layout = _gen.generate(42, 4, false)
	var n := _gen.grid_dim_for_floor(4)
	assert_eq(layout.corridors.size(), 2 * n * (n - 1),
		"3x3 grid → 12 connectors (6 horizontal + 6 vertical)")

func test_boss_floor_has_single_room_and_no_doorways() -> void:
	var layout = _gen.generate(42, 5, true)
	assert_eq(layout.rooms.size(), 1)
	assert_eq(layout.corridors.size(), 0)
	assert_eq(layout.enemy_spawns.size(), 0)
	assert_eq(layout.chest_positions.size(), 0)
	assert_true(layout.is_boss_floor)

func test_player_start_is_top_left_room() -> void:
	var layout = _gen.generate(42, 4, false)
	# Верхняя левая комната — та, у которой минимальные x и y position
	var top_left: Rect2i = layout.rooms[0]
	for room in layout.rooms:
		if room.position.x < top_left.position.x or room.position.y < top_left.position.y:
			top_left = room
	assert_true(top_left.has_point(layout.player_start),
		"player teleports into top-left room (тop of the tower)")

func test_exit_is_bottom_right_room() -> void:
	var layout = _gen.generate(42, 4, false)
	var bottom_right: Rect2i = layout.rooms[0]
	for room in layout.rooms:
		if room.end.x > bottom_right.end.x or room.end.y > bottom_right.end.y:
			bottom_right = room
	assert_true(bottom_right.has_point(layout.exit_position),
		"exit leads deeper into the tower (bottom-right)")

func test_enemy_spawns_are_inside_some_room() -> void:
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
		if room.position.x < start_room.position.x or (room.position.x == start_room.position.x and room.position.y < start_room.position.y):
			start_room = room
	var exit_room := layout.rooms[0]
	for room in layout.rooms:
		if room.get_center().distance_to(layout.exit_position) < exit_room.get_center().distance_to(layout.exit_position):
			exit_room = room
	for spawn in layout.enemy_spawns:
		assert_false(start_room.has_point(spawn), "no spawns in start room")
		assert_false(exit_room.has_point(spawn), "no spawns in exit room")

func test_chest_only_on_multiples_of_three() -> void:
	assert_eq(_gen.generate(42, 1, false).chest_positions.size(), 0)
	assert_eq(_gen.generate(42, 2, false).chest_positions.size(), 0)
	assert_eq(_gen.generate(42, 3, false).chest_positions.size(), 1)
	assert_eq(_gen.generate(42, 4, false).chest_positions.size(), 0)
	assert_eq(_gen.generate(42, 6, false).chest_positions.size(), 1)

func test_same_seed_produces_identical_layout() -> void:
	var a = _gen.generate(42, 4, false)
	var b = _gen.generate(42, 4, false)
	assert_eq(a.rooms.size(), b.rooms.size())
	for i in a.rooms.size():
		assert_eq(a.rooms[i], b.rooms[i])
	assert_eq(a.corridors, b.corridors)
	assert_eq(a.player_start, b.player_start)
	assert_eq(a.exit_position, b.exit_position)
	assert_eq(a.enemy_spawns, b.enemy_spawns)

func test_different_seeds_produce_different_doorway_positions() -> void:
	# Rooms в grid одинаковые (позиции детерминированы grid layout),
	# но doorway offsets меняются с seed.
	var a = _gen.generate(42, 4, false)
	var b = _gen.generate(999, 4, false)
	var differs := false
	for i in mini(a.corridors.size(), b.corridors.size()):
		if a.corridors[i] != b.corridors[i]:
			differs = true
			break
	assert_true(differs, "different seeds should produce different doorway placement")

func test_layout_is_normalized_to_origin() -> void:
	var layout = _gen.generate(42, 4, false)
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

func test_deeper_floors_have_more_rooms_than_shallow() -> void:
	var floor_1 = _gen.generate(42, 1, false)
	var floor_10 = _gen.generate(42, 10, false)
	assert_gt(floor_10.rooms.size(), floor_1.rooms.size(),
		"tower widens as you descend")
