extends GutTest

# Статистические / инвариантные метрики этажей после PR3.
# Проверяют, что топология и footprint соответствуют плану на репрезентативном
# наборе seed'ов. Мы намеренно используем небольшой N (12-20 seeds) —
# CI не должен взрываться от Godot startup времени.

const DungeonGeneratorScript = preload("res://scenes/dungeon/dungeon_generator.gd")

const SEEDS: Array = [1, 42, 100, 314, 777, 1024, 2020, 3141, 5000, 9999, 12345, 65535]

func _generate(seed_val: int, floor_num: int) -> DungeonLayout:
	var gen := DungeonGeneratorScript.new()
	return gen.generate(seed_val, floor_num, false)

# --- Общие инварианты по всем seeds -----------------------------------------

func test_all_floors_are_graph_connected() -> void:
	for zone_floor in [
		[1, "tower_top"], [4, "residential"], [8, "technical"],
		[12, "lower_tower"], [16, "basement"], [21, "caves"],
	]:
		for seed_val in SEEDS.slice(0, 6):
			var layout := _generate(seed_val, zone_floor[0])
			if layout.rooms.size() < 2:
				continue
			assert_true(layout.room_graph.is_graph_connected(),
				"floor %s seed %d must be connected" % [zone_floor[1], seed_val])

func test_entrance_reaches_exit_via_graph_path() -> void:
	for zone_floor in [4, 8, 12, 21]:
		for seed_val in SEEDS.slice(0, 6):
			var layout := _generate(seed_val, zone_floor)
			if layout.rooms.size() < 2:
				continue
			var path := layout.room_graph.shortest_path(
				layout.entrance_room_index, layout.exit_room_index,
			)
			assert_gt(path.size(), 0,
				"floor %d seed %d: entrance reaches exit" % [zone_floor, seed_val])

# --- Размеры footprint ------------------------------------------------------

func test_first_residential_floor_wider_than_viewport() -> void:
	# floor 3 (residential min) должен быть шире одного viewport (640).
	# Меряем longest_footprint_side.
	var layout := _generate(SEEDS[0], 3)
	var side := DungeonMetrics.longest_footprint_side(layout)
	assert_gt(side, 640,
		"первый residential floor заметно больше viewport (640 px)")

func test_deeper_floors_have_larger_walkable_area() -> void:
	# average(walkable_area on floor 3) < average(on floor 15).
	var early_total := 0
	var late_total := 0
	for s in SEEDS.slice(0, 8):
		early_total += DungeonMetrics.walkable_area(_generate(s, 3))
		late_total += DungeonMetrics.walkable_area(_generate(s, 15))
	assert_lt(early_total, late_total,
		"глубокий этаж имеет больше walkable area в среднем")

# --- Топология --------------------------------------------------------------

func test_residential_floors_produce_at_least_one_branch_on_average() -> void:
	# Spine v2 добавляет wing → минимум 1 vertex с degree >= 3 на половине
	# seeds. Мягкий stat-check.
	var count_with_branch := 0
	for s in SEEDS:
		var layout := _generate(s, 4)
		if layout.room_graph != null and layout.room_graph.branch_count() >= 1:
			count_with_branch += 1
	assert_gte(count_with_branch, SEEDS.size() / 2,
		"residential floors имеют >= 1 branch на большинстве seeds")

func test_technical_floors_have_loops_on_most_seeds() -> void:
	var count_with_loop := 0
	for s in SEEDS.slice(0, 8):
		var layout := _generate(s, 8)
		if layout.room_graph != null and layout.room_graph.cycle_count() >= 1:
			count_with_loop += 1
	assert_gte(count_with_loop, 4,
		"technical grid v2 имеет loop на >= 4/8 seeds")

func test_entrance_exit_hops_meet_minimum() -> void:
	# Residential zone_min_hops = 4. Проверяем > 2 (мягко).
	for s in SEEDS.slice(0, 6):
		var layout := _generate(s, 4)
		if layout.rooms.size() < 2:
			continue
		var hops: int = layout.room_graph.shortest_path_length(
			layout.entrance_room_index, layout.exit_room_index,
		)
		assert_gt(hops, 2,
			"residential seed %d: hops > 2" % s)

# --- Reward placement -------------------------------------------------------

func test_chest_lands_in_room_that_becomes_treasure_role() -> void:
	# Regression на порядок pipeline'а: chest ставится ДО assign_roles,
	# и после этого room помечается treasure_room.
	for s in SEEDS.slice(0, 6):
		var layout := _generate(s, 3)
		if layout.chest_positions.is_empty():
			continue
		var chest_pos: Vector2i = layout.chest_positions[0]
		var found_treasure := false
		for info in layout.room_infos:
			var room: Rect2i = layout.rooms[info.room_index]
			if room.has_point(chest_pos) and info.role == RoomRoles.ROLE_TREASURE_ROOM:
				found_treasure = true
				break
		assert_true(found_treasure,
			"seed %d floor 3: chest room должен получить treasure_room role" % s)

# --- Determinism ------------------------------------------------------------

func test_layout_reproducible_across_runs() -> void:
	for zone_floor in [3, 8, 12, 21]:
		var a := _generate(4242, zone_floor)
		var b := _generate(4242, zone_floor)
		assert_eq(a.rooms.size(), b.rooms.size(),
			"floor %d: rooms count reproducible" % zone_floor)
		assert_eq(a.player_start, b.player_start,
			"floor %d: player_start reproducible" % zone_floor)
		assert_eq(a.exit_position, b.exit_position,
			"floor %d: exit_position reproducible" % zone_floor)
