extends GutTest

# Residential spine layout: центральный коридор, rooms по обе стороны.
# Используется для tower_top (floor 1-2) и residential (floor 3-6) зон.
# Boss floor 5 остаётся boss_arena независимо от zone.
#
# Ключевые инварианты:
# - floor 1/3 → floor_archetype = "residential_spine";
# - в layout.corridors есть main corridor + doorway'и от каждой комнаты;
# - player_start и exit_position — по разные концы коридора;
# - room_infos покрывают все rooms и хотя бы одна помечена entrance;
# - enemy_spawns не попадают в entrance / exit room / корридор;
# - детерминизм: одинаковый seed + floor → одинаковый набор rooms/start/exit.

const DungeonGeneratorScript = preload("res://scenes/dungeon/dungeon_generator.gd")

func _generate(seed_val: int, floor_num: int) -> DungeonLayout:
	var gen := DungeonGeneratorScript.new()
	return gen.generate(seed_val, floor_num, false)

func test_floor_1_uses_residential_spine() -> void:
	var layout := _generate(101, 1)
	assert_eq(layout.floor_archetype, "residential_spine")

func test_floor_3_uses_residential_spine() -> void:
	var layout := _generate(102, 3)
	assert_eq(layout.floor_archetype, "residential_spine")

func test_boss_floor_5_still_uses_boss_arena() -> void:
	var gen := DungeonGeneratorScript.new()
	var layout: DungeonLayout = gen.generate(103, 5, true)
	assert_eq(layout.floor_archetype, "boss_arena",
		"boss floor не должен переключаться на spine")

func test_spine_has_main_corridor() -> void:
	# Первый добавленный corridor — main corridor (широкий, полная ширина).
	# Остальные — doorway'и от комнат. Инвариант: main corridor существенно
	# шире чем doorway.
	var layout := _generate(200, 3)
	assert_gt(layout.corridors.size(), 0, "должен быть хотя бы 1 corridor")
	var main_corridor: Rect2i = layout.corridors[0]
	assert_gt(main_corridor.size.x, 100,
		"main corridor покрывает большую часть ширины этажа")

func test_spine_has_multiple_rooms() -> void:
	var layout := _generate(201, 3)
	assert_gte(layout.rooms.size(), 4,
		"residential spine должен создать хотя бы 4 комнаты (по 2 на ряд)")

func test_player_start_and_exit_are_distinct() -> void:
	var layout := _generate(202, 3)
	assert_ne(layout.player_start, layout.exit_position,
		"start и exit не должны совпадать")

func test_player_start_and_exit_are_at_corridor_ends() -> void:
	# Инвариант: start слева, exit справа (по X). Это делает движение
	# через этаж читаемым: игрок идёт слева направо.
	var layout := _generate(203, 3)
	assert_lt(layout.player_start.x, layout.exit_position.x,
		"start слева, exit справа")

func test_room_infos_populated_and_include_entrance() -> void:
	var layout := _generate(204, 3)
	assert_eq(layout.room_infos.size(), layout.rooms.size())
	var has_entrance := false
	for info in layout.room_infos:
		if info.role == RoomRoles.ROLE_ENTRANCE:
			has_entrance = true
	assert_true(has_entrance,
		"минимум одна комната должна получить entrance role")

func test_enemy_spawns_are_inside_rooms() -> void:
	# Регресс: враги в корридоре — нечестный старт. Все spawn'ы должны
	# попадать хотя бы в одну комнату.
	var layout := _generate(205, 3)
	assert_gt(layout.enemy_spawns.size(), 0,
		"должны быть enemy spawn'ы")
	for spawn in layout.enemy_spawns:
		var in_some_room := false
		for room in layout.rooms:
			if room.has_point(spawn):
				in_some_room = true
				break
		assert_true(in_some_room,
			"enemy spawn %s должен быть внутри какой-то комнаты" % spawn)

func test_deterministic_for_same_seed() -> void:
	var layout_a := _generate(9001, 3)
	var layout_b := _generate(9001, 3)
	assert_eq(layout_a.rooms.size(), layout_b.rooms.size())
	assert_eq(layout_a.player_start, layout_b.player_start)
	assert_eq(layout_a.exit_position, layout_b.exit_position)
	for i in layout_a.rooms.size():
		assert_eq(layout_a.rooms[i], layout_b.rooms[i],
			"room %d одинаковый для same seed" % i)

func test_different_seeds_produce_different_layouts() -> void:
	var layout_a := _generate(1, 3)
	var layout_b := _generate(9999, 3)
	# Хотя бы одна комната должна отличаться, иначе RNG не влияет.
	var any_diff := false
	for i in mini(layout_a.rooms.size(), layout_b.rooms.size()):
		if layout_a.rooms[i] != layout_b.rooms[i]:
			any_diff = true
			break
	assert_true(any_diff or layout_a.rooms.size() != layout_b.rooms.size(),
		"разные seeds → разные rooms")

func test_chest_only_on_floors_divisible_by_three() -> void:
	# CHEST_FLOOR_INTERVAL = 3. Floor 3 → chest, Floor 4 → нет.
	var layout_f3 := _generate(6001, 3)
	var layout_f4 := _generate(6002, 4)
	assert_gt(layout_f3.chest_positions.size(), 0,
		"floor 3 имеет сундук")
	assert_eq(layout_f4.chest_positions.size(), 0,
		"floor 4 без сундука")

func test_rooms_are_separated_from_main_corridor_by_wall() -> void:
	# Регресс: без 1-tile стены между room и main corridor doorway имеет
	# высоту 0 и не рисуется — комната открывается во всю ширину.
	for seed_val in [7001, 7002, 7003, 7004]:
		var layout := _generate(seed_val, 3)
		var main_corridor: Rect2i = layout.corridors[0]
		for room in layout.rooms:
			var above := room.end.y <= main_corridor.position.y
			var below := room.position.y >= main_corridor.end.y
			assert_true(above or below,
				"комната %s должна быть выше или ниже коридора %s (seed=%d)" % [room, main_corridor, seed_val])
			if above:
				var gap: int = main_corridor.position.y - room.end.y
				assert_gte(gap, 20,
					"gap выше коридора должен быть >=1 tile (got=%d, seed=%d)" % [gap, seed_val])
			else:
				var gap: int = room.position.y - main_corridor.end.y
				assert_gte(gap, 20,
					"gap ниже коридора должен быть >=1 tile (got=%d, seed=%d)" % [gap, seed_val])

func test_every_side_room_has_doorway_to_corridor() -> void:
	# Инвариант: у каждой боковой комнаты есть doorway-corridor rect,
	# соединяющий её с main corridor. Иначе комната недостижима.
	for seed_val in [7101, 7102, 7103, 7104]:
		var layout := _generate(seed_val, 3)
		var main_corridor: Rect2i = layout.corridors[0]
		var doorways: Array = []
		for i in range(1, layout.corridors.size()):
			doorways.append(layout.corridors[i])
		for room in layout.rooms:
			var connected := false
			for door: Rect2i in doorways:
				var touches_room := door.position.y == room.end.y or door.end.y == room.position.y
				var touches_corridor := door.end.y == main_corridor.position.y or door.position.y == main_corridor.end.y
				var x_overlap := door.position.x >= room.position.x and door.end.x <= room.end.x
				if touches_room and touches_corridor and x_overlap:
					connected = true
					break
			assert_true(connected,
				"у комнаты %s должен быть doorway в main corridor (seed=%d)" % [room, seed_val])

