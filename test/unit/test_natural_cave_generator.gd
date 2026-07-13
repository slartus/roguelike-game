extends GutTest

# NaturalCaveGenerator — irregular chamber layout для caves zone.

const DungeonGeneratorScript = preload("res://scenes/dungeon/dungeon_generator.gd")

func _generate(seed_val: int, floor_num: int) -> DungeonLayout:
	var gen := DungeonGeneratorScript.new()
	return gen.generate(seed_val, floor_num, false)

func test_caves_zone_uses_natural_cave_archetype() -> void:
	var layout := _generate(101, 20)
	assert_eq(layout.floor_archetype, "caves_natural",
		"floor 20 (caves) → NaturalCaveGenerator")

func test_caves_have_multiple_chambers() -> void:
	# Plan: 5-9 chambers для средних+ этажей.
	var layout := _generate(202, 20)
	assert_gte(layout.rooms.size(), 3,
		"пещеры должны содержать несколько chambers (fallback ≥3)")

func test_caves_are_connected_via_graph() -> void:
	var layout := _generate(303, 21)
	assert_not_null(layout.room_graph)
	assert_true(layout.room_graph.is_graph_connected(),
		"все chambers должны быть достижимы через tunnels")

func test_caves_have_tunnels_between_chambers() -> void:
	var layout := _generate(404, 22)
	# Tunnels — corridors в layout. Их должно быть хотя бы столько же,
	# сколько edges в графе (обычно больше — 2 rect на L-shape).
	assert_gt(layout.corridors.size(), 0,
		"пещеры имеют tunnels")

func test_caves_have_at_least_one_alternate_connection() -> void:
	# Extra edges > 0 → на большинстве seeds минимум 1 loop.
	# Проверяем через cycle_count в графе для несколько seeds.
	var seeds_with_loop := 0
	for s in [11, 22, 33, 44, 55]:
		var layout := _generate(s, 22)
		if layout.room_graph != null and layout.room_graph.cycle_count() > 0:
			seeds_with_loop += 1
	assert_gte(seeds_with_loop, 3,
		"минимум на 3/5 seeds пещеры должны иметь loop (alternate connection)")

func test_caves_chambers_vary_in_size() -> void:
	# Blob chambers имеют разные размеры — большая пещера vs каверна.
	var layout := _generate(505, 22)
	var min_area := 99999999
	var max_area := 0
	for room in layout.rooms:
		var area: int = room.size.x * room.size.y
		min_area = mini(min_area, area)
		max_area = maxi(max_area, area)
	# Не строгое требование, но статистически большой vs малый = 1.5x+.
	assert_gt(max_area, min_area,
		"caves chambers имеют переменный размер")

func test_caves_deterministic_for_same_seed() -> void:
	var a := _generate(9999, 20)
	var b := _generate(9999, 20)
	assert_eq(a.rooms.size(), b.rooms.size())
	for i in a.rooms.size():
		assert_eq(a.rooms[i], b.rooms[i], "room %d стабилен" % i)
