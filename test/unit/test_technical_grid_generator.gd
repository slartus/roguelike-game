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

func test_floor_11_uses_ruined_bsp_for_lower_tower() -> void:
	# floor 11 = lower_tower zone. После M6 архетип — ruined_bsp,
	# что физически всё ещё BSP, но помечен читаемым именем.
	var layout := _generate(104, 11)
	assert_eq(layout.floor_archetype, "ruined_bsp")

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

func test_start_and_exit_are_far_by_graph_distance() -> void:
	# PR3: entrance/exit ставятся по BFS-фарвест паре среди достаточно
	# больших комнат. Для technical v2 (два rail + machine rooms между) это
	# может уводить их в maintenance rooms на разных сторонах, не
	# обязательно к концам X-оси.
	var layout := _generate(202, 7)
	assert_ne(layout.entrance_room_index, layout.exit_room_index,
		"entrance и exit — разные комнаты")
	assert_ne(layout.player_start, layout.exit_position,
		"start и exit не совпадают")
	var hops: int = layout.room_graph.shortest_path_length(
		layout.entrance_room_index, layout.exit_room_index,
	)
	assert_gte(hops, 3,
		"entrance/exit на графовой дистанции >= 3 hops (technical v2)")

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

func test_technical_v2_has_two_parallel_rails() -> void:
	# PR3: technical grid v2 → два параллельных main corridor rects
	# (top rail, bottom rail). Оба покрывают почти всю ширину этажа и
	# идут на разной Y-координате.
	var layout := _generate(7001, 8)
	assert_gte(layout.corridors.size(), 2, "минимум 2 rail-корридора")
	var top_rail: Rect2i = layout.corridors[0]
	var bottom_rail: Rect2i = layout.corridors[1]
	assert_gt(top_rail.size.x, 100, "top rail покрывает большую часть ширины")
	assert_gt(bottom_rail.size.x, 100, "bottom rail тоже покрывает большую часть ширины")
	assert_lt(top_rail.position.y, bottom_rail.position.y,
		"top rail расположен выше bottom rail")
	assert_ne(top_rail.position.y, bottom_rail.position.y,
		"rail'ы на разной Y-координате")

func test_every_room_is_reachable_via_graph() -> void:
	# PR3: инвариант связности проверяется через layout.room_graph, а не
	# через ручной поиск doorway'ев (в v2 doorways появляются между
	# machine rooms и обоими rail'ами — старая логика их не описывает).
	for seed_val in [7101, 7102, 7103, 7104]:
		var layout := _generate(seed_val, 8)
		assert_not_null(layout.room_graph, "layout.room_graph должен быть построен")
		assert_true(layout.room_graph.is_graph_connected(),
			"все комнаты technical v2 должны быть достижимы (seed=%d)" % seed_val)
		# Никакая комната не должна быть изолирована — degree >= 1.
		for i in layout.rooms.size():
			var neighbours = layout.room_graph.adjacency[i]
			assert_gte(neighbours.size(), 1,
				"комната %d не должна быть изолирована (seed=%d)" % [i, seed_val])

