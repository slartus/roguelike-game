extends GutTest

const DungeonGeneratorClass = preload("res://scenes/dungeon/dungeon_generator.gd")

var _gen

func before_each() -> void:
	_gen = DungeonGeneratorClass.new()

func test_floor_1_has_min_rooms() -> void:
	var layout = _gen.generate(42, 1, false)
	assert_eq(layout.rooms.size(), DungeonGeneratorClass.MIN_ROOMS)

func test_deeper_floors_scale_room_count_up_to_max() -> void:
	var layout_1 = _gen.generate(42, 1, false)
	var layout_10 = _gen.generate(42, 10, false)
	assert_gt(layout_10.rooms.size(), layout_1.rooms.size(),
		"floor 10 should have more rooms than floor 1")
	assert_lte(layout_10.rooms.size(), DungeonGeneratorClass.MAX_ROOMS,
		"room count capped at MAX_ROOMS")

func test_regular_floor_has_corridors_between_all_rooms() -> void:
	var layout = _gen.generate(42, 4, false)
	# Каждая пара соседей даёт минимум 1 сегмент коридора (L может дать 2)
	assert_gte(layout.corridors.size(), layout.rooms.size() - 1)

func test_boss_floor_has_single_room_and_no_corridors() -> void:
	var layout = _gen.generate(42, 5, true)
	assert_eq(layout.rooms.size(), 1)
	assert_eq(layout.corridors.size(), 0)
	assert_eq(layout.enemy_spawns.size(), 0)
	assert_eq(layout.chest_positions.size(), 0)
	assert_true(layout.is_boss_floor)

func test_player_start_is_inside_first_room() -> void:
	var layout = _gen.generate(42, 3, false)
	assert_true(layout.rooms[0].has_point(layout.player_start),
		"player_start %s not inside first room %s" % [layout.player_start, layout.rooms[0]])

func test_exit_is_inside_last_room() -> void:
	var layout = _gen.generate(42, 3, false)
	assert_true(layout.rooms[-1].has_point(layout.exit_position),
		"exit_position %s not inside last room %s" % [layout.exit_position, layout.rooms[-1]])

func test_all_enemy_spawns_are_inside_some_room() -> void:
	var layout = _gen.generate(42, 4, false)
	for spawn in layout.enemy_spawns:
		var inside := false
		for room in layout.rooms:
			if room.has_point(spawn):
				inside = true
				break
		assert_true(inside, "enemy spawn %s not inside any room" % spawn)

func test_no_enemy_spawns_in_start_room() -> void:
	var layout = _gen.generate(42, 4, false)
	for spawn in layout.enemy_spawns:
		assert_false(layout.rooms[0].has_point(spawn),
			"enemy spawn %s inside start room" % spawn)

func test_chest_only_on_floor_multiples_of_three() -> void:
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
		assert_eq(a.rooms[i], b.rooms[i], "room %d matches" % i)
	assert_eq(a.player_start, b.player_start)
	assert_eq(a.exit_position, b.exit_position)
	assert_eq(a.enemy_spawns, b.enemy_spawns)

func test_different_seeds_produce_different_layouts() -> void:
	var a = _gen.generate(42, 4, false)
	var b = _gen.generate(999, 4, false)
	var differs := false
	if a.rooms.size() != b.rooms.size():
		differs = true
	else:
		for i in a.rooms.size():
			if a.rooms[i] != b.rooms[i]:
				differs = true
				break
	assert_true(differs, "different seeds should produce different layouts")

func test_layout_is_normalized_to_origin() -> void:
	var layout = _gen.generate(42, 5, false)
	assert_eq(layout.floor_bounds.position, Vector2i.ZERO,
		"floor_bounds should start at (0,0) after normalize")
	for room in layout.rooms:
		assert_gte(room.position.x, 0)
		assert_gte(room.position.y, 0)
	for spawn in layout.enemy_spawns:
		assert_gte(spawn.x, 0)
		assert_gte(spawn.y, 0)

func test_floor_bounds_contain_all_rooms_and_corridors() -> void:
	var layout = _gen.generate(42, 4, false)
	for room in layout.rooms:
		assert_true(layout.floor_bounds.encloses(room),
			"room %s not enclosed by bounds %s" % [room, layout.floor_bounds])
	for corridor in layout.corridors:
		assert_true(layout.floor_bounds.encloses(corridor),
			"corridor %s not enclosed by bounds %s" % [corridor, layout.floor_bounds])
