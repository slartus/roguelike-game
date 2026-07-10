extends GutTest

# Room roles v1:
# - каждая rooms[i] получает room_info с role/zone/tags/danger;
# - start и exit получают entrance/exit_core;
# - chest room → treasure_room;
# - остальные роли берутся из ZONE_ROLE_POOL[zone];
# - danger суммируется по правилам зон и опасных ролей.

const DungeonGeneratorScript = preload("res://scenes/dungeon/dungeon_generator.gd")

func _generate(seed_val: int, floor_num: int, is_boss: bool = false) -> DungeonLayout:
	var gen := DungeonGeneratorScript.new()
	return gen.generate(seed_val, floor_num, is_boss)

func _roles(layout: DungeonLayout) -> Array:
	var out: Array = []
	for info in layout.room_infos:
		out.append(info.role)
	return out

func test_room_infos_size_matches_rooms_size() -> void:
	var layout := _generate(111, 3)
	assert_eq(layout.room_infos.size(), layout.rooms.size(),
		"по одному info на каждую комнату")

func test_each_info_has_required_keys() -> void:
	var layout := _generate(222, 5)
	for info in layout.room_infos:
		for key in ["room_index", "role", "zone", "tags", "danger"]:
			assert_true(info.has(key),
				"room_info должен содержать поле '%s'" % key)

func test_room_index_is_valid() -> void:
	var layout := _generate(333, 4)
	for info in layout.room_infos:
		assert_gte(int(info.room_index), 0)
		assert_lt(int(info.room_index), layout.rooms.size())

func test_start_room_role_is_entrance() -> void:
	var layout := _generate(444, 3)
	# Ищем комнату, содержащую player_start, и проверяем что её info.role
	# = entrance.
	for info in layout.room_infos:
		var room: Rect2i = layout.rooms[info.room_index]
		if room.has_point(layout.player_start):
			assert_eq(info.role, RoomRoles.ROLE_ENTRANCE,
				"start room должна быть entrance")
			assert_true(info.tags.has("entrance"),
				"entrance должен быть в tags")
			return
	assert_true(false, "не нашли room содержащую player_start")

func test_exit_room_role_is_exit_core() -> void:
	var layout := _generate(555, 3)
	for info in layout.room_infos:
		var room: Rect2i = layout.rooms[info.room_index]
		if room.has_point(layout.exit_position):
			assert_eq(info.role, RoomRoles.ROLE_EXIT_CORE)
			assert_true(info.tags.has("exit"))
			return
	assert_true(false, "не нашли room содержащую exit_position")

func test_chest_room_gets_treasure_role() -> void:
	# Floor 3 гарантированно имеет сундук (CHEST_FLOOR_INTERVAL=3).
	var layout := _generate(666, 3)
	assert_gt(layout.chest_positions.size(), 0, "floor 3 имеет chest")
	var chest_pos: Vector2i = layout.chest_positions[0]
	for info in layout.room_infos:
		var room: Rect2i = layout.rooms[info.room_index]
		if room.has_point(chest_pos):
			assert_eq(info.role, RoomRoles.ROLE_TREASURE_ROOM)
			assert_true(info.tags.has("treasure"))
			return

func test_residential_zone_generates_residential_roles() -> void:
	# Floor 3 → residential zone. Non-entrance/exit/treasure rooms
	# должны получать роли из residential pool.
	var layout := _generate(777, 3)
	var residential_roles := RoomRoles.ZONE_ROLE_POOL["residential"]
	var found_residential := false
	for info in layout.room_infos:
		if info.role in [RoomRoles.ROLE_ENTRANCE, RoomRoles.ROLE_EXIT_CORE, RoomRoles.ROLE_TREASURE_ROOM]:
			continue
		assert_true(residential_roles.has(info.role),
			"residential floor должен использовать residential-роли, актуально: %s" % info.role)
		found_residential = true
	assert_true(found_residential,
		"должна быть хотя бы одна не-entrance/exit/treasure комната")

func test_technical_zone_generates_technical_roles() -> void:
	var layout := _generate(888, 7)  # zone = technical
	var technical_roles := RoomRoles.ZONE_ROLE_POOL["technical"]
	for info in layout.room_infos:
		if info.role in [RoomRoles.ROLE_ENTRANCE, RoomRoles.ROLE_EXIT_CORE, RoomRoles.ROLE_TREASURE_ROOM]:
			continue
		assert_true(technical_roles.has(info.role),
			"technical zone: role %s не из pool" % info.role)

func test_caves_zone_generates_cave_roles() -> void:
	var layout := _generate(999, 19)  # zone = caves
	var cave_roles := RoomRoles.ZONE_ROLE_POOL["caves"]
	for info in layout.room_infos:
		if info.role in [RoomRoles.ROLE_ENTRANCE, RoomRoles.ROLE_EXIT_CORE, RoomRoles.ROLE_TREASURE_ROOM]:
			continue
		assert_true(cave_roles.has(info.role),
			"caves zone: role %s не из pool" % info.role)

func test_boss_arena_role() -> void:
	var layout := _generate(1010, 5, true)
	assert_gt(layout.room_infos.size(), 0)
	for info in layout.room_infos:
		assert_eq(info.role, RoomRoles.ROLE_BOSS_ARENA,
			"boss floor → все rooms boss_arena")

func test_danger_treasure_bumps() -> void:
	# treasure_room в residential zone → danger 1 (только treasure).
	assert_eq(RoomRoles.compute_danger(RoomRoles.ROLE_TREASURE_ROOM, "residential"), 1)

func test_danger_dangerous_zone_bumps() -> void:
	assert_gte(RoomRoles.compute_danger(RoomRoles.ROLE_SMALL_ROOM, "caves"), 1,
		"caves zone → +1 danger даже для нейтральной роли")

func test_danger_dangerous_role_bumps() -> void:
	assert_gte(RoomRoles.compute_danger(RoomRoles.ROLE_MACHINE_ROOM, "technical"), 1,
		"machine_room сама по себе опасна")

func test_danger_stacks_for_treasure_in_dangerous_zone() -> void:
	# treasure_room в caves: +1 (treasure) + +1 (caves zone) = 2.
	assert_eq(RoomRoles.compute_danger(RoomRoles.ROLE_TREASURE_ROOM, "caves"), 2)

func test_size_tag_small_medium_large() -> void:
	# 5000 < SMALL_AREA_THRESHOLD (6400) → small.
	# 10000 в диапазоне → medium.
	# 15000 > LARGE_AREA_THRESHOLD (12000) → large.
	assert_eq(RoomRoles.size_tag_for_area(5000), "small")
	assert_eq(RoomRoles.size_tag_for_area(10000), "medium")
	assert_eq(RoomRoles.size_tag_for_area(15000), "large")

func test_zone_in_info_matches_layout_zone() -> void:
	var layout := _generate(2020, 8)  # technical
	for info in layout.room_infos:
		assert_eq(info.zone, layout.zone,
			"info.zone должна совпадать с layout.zone")
