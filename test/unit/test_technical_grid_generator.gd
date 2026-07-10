extends GutTest

# Technical grid: служебный этаж (zone = technical, floor 7-10).
# Отличается от residential_spine большими комнатами и узким корридором.

const DungeonGeneratorScript = preload("res://scenes/dungeon/dungeon_generator.gd")

func _generate(seed_val: int, floor_num: int) -> DungeonLayout:
	var gen := DungeonGeneratorScript.new()
	return gen.generate(seed_val, floor_num, false)

func test_floor_7_uses_technical_grid() -> void:
	var layout := _generate(101, 7)
	assert_eq(layout.floor_archetype, "technical_grid",
		"floor 7 → technical zone → technical_grid архетип")

func test_floor_10_uses_technical_grid() -> void:
	var layout := _generate(102, 8)  # избегаем boss floor 10
	assert_eq(layout.floor_archetype, "technical_grid")

func test_boss_floor_10_still_uses_boss_arena() -> void:
	var gen := DungeonGeneratorScript.new()
	var layout: DungeonLayout = gen.generate(103, 10, true)
	assert_eq(layout.floor_archetype, "boss_arena",
		"boss floor 10 не переключается на technical_grid")

func test_floor_11_falls_back_to_legacy_bsp() -> void:
	# floor 11 = lower_tower zone — вне M5, всё ещё legacy.
	var layout := _generate(104, 11)
	assert_eq(layout.floor_archetype, "legacy_bsp")

func test_technical_layout_has_service_corridor() -> void:
	# Main corridor должен занимать значительную ширину этажа.
	var layout := _generate(200, 7)
	assert_gt(layout.corridors.size(), 0)
	var main_corridor: Rect2i = layout.corridors[0]
	assert_gt(main_corridor.size.x, 100,
		"service corridor покрывает большую часть ширины")

func test_technical_has_multiple_rooms() -> void:
	var layout := _generate(201, 7)
	assert_gte(layout.rooms.size(), 4,
		"technical grid должен иметь минимум 4 комнаты")

func test_start_and_exit_at_opposite_ends() -> void:
	var layout := _generate(202, 7)
	assert_lt(layout.player_start.x, layout.exit_position.x,
		"start слева, exit справа — читаемое движение через служебный этаж")

func test_room_infos_include_technical_roles() -> void:
	# Хотя бы одна комната должна получить одну из technical ролей
	# (machine_room / boiler_room / switch_room / storage / corridor).
	var layout := _generate(203, 7)
	var technical_pool: Array = RoomRoles.ZONE_ROLE_POOL["technical"]
	var found_technical := false
	for info in layout.room_infos:
		if technical_pool.has(info.role):
			found_technical = true
			break
	assert_true(found_technical,
		"должна быть хотя бы одна technical-role комната")

func test_deterministic_for_same_seed() -> void:
	var layout_a := _generate(3003, 8)
	var layout_b := _generate(3003, 8)
	assert_eq(layout_a.rooms.size(), layout_b.rooms.size())
	assert_eq(layout_a.player_start, layout_b.player_start)
	for i in layout_a.rooms.size():
		assert_eq(layout_a.rooms[i], layout_b.rooms[i])

func test_enemy_spawns_in_rooms_not_corridor() -> void:
	var layout := _generate(4004, 8)
	assert_gt(layout.enemy_spawns.size(), 0)
	for spawn in layout.enemy_spawns:
		var in_room := false
		for room in layout.rooms:
			if room.has_point(spawn):
				in_room = true
				break
		assert_true(in_room,
			"spawn %s должен быть в комнате, а не в служебном коридоре" % spawn)

func test_technical_decor_profile_not_cave() -> void:
	# Регресс M3 + M5: technical этаж не должен получить mold/candle/crack.
	# Проверяем через decor profile для одной из ролей.
	var profile := DecorProfiles.decor_profile_for_room(
		RoomRoles.ROLE_MACHINE_ROOM, TowerZone.ZONE_TECHNICAL)
	var all_types: Array = []
	all_types.append_array(profile.floor)
	all_types.append_array(profile.wall)
	for cave in DecorProfiles.CAVE_ONLY_DECOR:
		assert_false(all_types.has(cave),
			"technical machine_room НЕ должен иметь cave-декор %s" % cave)
