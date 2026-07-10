extends GutTest

# WorldZones — заготовка abstraction под будущие миры.
# WORLD_TOWER — единственный реализованный, возвращает TowerZone.
# Unknown world должен корректно fallback'ать, а не крешить.

func test_world_tower_constant_is_defined() -> void:
	assert_eq(WorldZones.WORLD_TOWER, "tower")

func test_world_tower_returns_tower_zones() -> void:
	# Sanity: тот же результат что и TowerZone напрямую.
	for floor_num in [1, 3, 7, 12, 16, 20]:
		assert_eq(
			WorldZones.get_zone_for_world(WorldZones.WORLD_TOWER, floor_num),
			TowerZone.get_tower_zone(floor_num),
			"world_tower должен использовать TowerZone для floor %d" % floor_num,
		)

func test_unknown_world_falls_back_to_tower_and_does_not_crash() -> void:
	# Регресс: неизвестное world_id не должно крешить генератор.
	var zone := WorldZones.get_zone_for_world("mountain", 5)
	assert_ne(zone, "", "unknown world не должен возвращать пустую строку")
