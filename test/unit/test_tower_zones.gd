extends GutTest

# TowerZone определяет вертикальную зону мира башни по номеру этажа.
# Границы: 1-2 tower_top, 3-6 residential, 7-10 technical, 11-14 lower_tower,
# 15-18 basement, 19+ caves. DungeonGenerator заполняет layout.zone и
# layout.floor_archetype на каждой генерации.

const DungeonGeneratorScript = preload("res://scenes/dungeon/dungeon_generator.gd")

func test_floor_1_is_tower_top() -> void:
	assert_eq(TowerZone.get_tower_zone(1), TowerZone.ZONE_TOWER_TOP)

func test_floor_2_is_tower_top() -> void:
	assert_eq(TowerZone.get_tower_zone(2), TowerZone.ZONE_TOWER_TOP)

func test_floor_3_is_residential() -> void:
	assert_eq(TowerZone.get_tower_zone(3), TowerZone.ZONE_RESIDENTIAL)

func test_floor_6_is_residential() -> void:
	assert_eq(TowerZone.get_tower_zone(6), TowerZone.ZONE_RESIDENTIAL)

func test_floor_7_is_technical() -> void:
	assert_eq(TowerZone.get_tower_zone(7), TowerZone.ZONE_TECHNICAL)

func test_floor_10_is_technical() -> void:
	assert_eq(TowerZone.get_tower_zone(10), TowerZone.ZONE_TECHNICAL)

func test_floor_11_is_lower_tower() -> void:
	assert_eq(TowerZone.get_tower_zone(11), TowerZone.ZONE_LOWER_TOWER)

func test_floor_15_is_basement() -> void:
	assert_eq(TowerZone.get_tower_zone(15), TowerZone.ZONE_BASEMENT)

func test_floor_19_is_caves() -> void:
	assert_eq(TowerZone.get_tower_zone(19), TowerZone.ZONE_CAVES)

func test_deep_floor_stays_in_caves() -> void:
	# Регресс: очень глубокий этаж не должен возвращать пустую строку /
	# уходить за пределы enum.
	for floor_num in [25, 50, 100]:
		assert_eq(TowerZone.get_tower_zone(floor_num), TowerZone.ZONE_CAVES,
			"floor %d должен оставаться в caves" % floor_num)

func test_all_zones_constant_covers_full_enum() -> void:
	# Регресс: если кто-то добавит новую зону в скрипт, но забудет в ALL_ZONES,
	# итерации в тестах / spawn tables пропустят её.
	assert_eq(TowerZone.ALL_ZONES.size(), 6, "6 зон в v1")
	for zone in TowerZone.ALL_ZONES:
		assert_ne(zone, "", "нет пустых элементов")

func test_regular_floor_generation_fills_zone_and_archetype() -> void:
	# После M4 residential zone идёт через residential_spine архетип.
	# Легаси BSP теперь только для нижних зон (см. M6).
	var gen := DungeonGeneratorScript.new()
	var layout: DungeonLayout = gen.generate(12345, 3, false)
	assert_eq(layout.zone, TowerZone.ZONE_RESIDENTIAL,
		"floor 3 → residential zone в metadata")
	assert_eq(layout.floor_archetype, "residential_spine",
		"M4: residential zone использует spine архетип")

func test_legacy_bsp_still_used_for_lower_zones() -> void:
	# Регресс: пока не M6, нижние зоны (lower_tower и глубже) должны
	# продолжать генерироваться через legacy BSP.
	var gen := DungeonGeneratorScript.new()
	var layout: DungeonLayout = gen.generate(2020, 12, false)  # zone = lower_tower
	assert_eq(layout.floor_archetype, "legacy_bsp")

func test_boss_floor_gets_boss_arena_archetype_but_still_has_zone() -> void:
	var gen := DungeonGeneratorScript.new()
	var layout: DungeonLayout = gen.generate(9999, 5, true)
	assert_eq(layout.floor_archetype, "boss_arena",
		"boss этаж помечен как boss_arena")
	# Zone должен быть выставлен даже для boss — для будущего thematic decor.
	assert_eq(layout.zone, TowerZone.get_tower_zone(5),
		"boss floor сохраняет zone metadata (тоже residential тут)")

func test_zone_reflects_floor_number_after_generation() -> void:
	# Через API DungeonGenerator убеждаемся что zone соответствует floor:
	# floor 1 → tower_top, floor 8 → technical, floor 20 → caves.
	var gen := DungeonGeneratorScript.new()
	var floors_and_zones := [
		[1, TowerZone.ZONE_TOWER_TOP],
		[8, TowerZone.ZONE_TECHNICAL],
		[20, TowerZone.ZONE_CAVES],
	]
	for pair in floors_and_zones:
		var layout: DungeonLayout = gen.generate(555, pair[0], false)
		assert_eq(layout.zone, pair[1],
			"floor %d генерируется со zone %s" % [pair[0], pair[1]])
