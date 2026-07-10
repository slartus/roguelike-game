extends GutTest

# DecorProfiles v1:
# - decor_profile_for_room по role/zone возвращает correct floor/wall списки;
# - cave-only декор (mold/crack/blood/candle/bones/stone_rubble) не
#   допускается в верхних зонах (residential/technical/tower_top);
# - fallback на zone-профиль когда role не в ROLE_PROFILES;
# - в нижних зонах cave декор разрешён.

func test_bedroom_profile_uses_residential_decor() -> void:
	var profile := DecorProfiles.decor_profile_for_room("bedroom", "residential")
	var all_types: Array = []
	all_types.append_array(profile.floor)
	all_types.append_array(profile.wall)
	# Ключевые residential предметы должны быть.
	assert_true(all_types.has(DecorProfiles.DECOR_BED),
		"bedroom должен содержать bed")
	# И cave-only не должно быть.
	for cave_decor in DecorProfiles.CAVE_ONLY_DECOR:
		assert_false(all_types.has(cave_decor),
			"bedroom НЕ должен содержать cave-only декор %s" % cave_decor)

func test_machine_room_profile_uses_technical_decor() -> void:
	var profile := DecorProfiles.decor_profile_for_room("machine_room", "technical")
	var all_types: Array = []
	all_types.append_array(profile.floor)
	all_types.append_array(profile.wall)
	assert_true(all_types.has(DecorProfiles.DECOR_MACHINE_BLOCK) or all_types.has(DecorProfiles.DECOR_PIPE),
		"machine_room должен содержать pipe или machine_block")
	for cave_decor in DecorProfiles.CAVE_ONLY_DECOR:
		assert_false(all_types.has(cave_decor),
			"machine_room НЕ должен содержать cave-only декор %s" % cave_decor)

func test_cave_chamber_profile_allows_cave_decor() -> void:
	var profile := DecorProfiles.decor_profile_for_room("cave_chamber", "caves")
	var all_types: Array = []
	all_types.append_array(profile.floor)
	all_types.append_array(profile.wall)
	# В cave-chamber хотя бы один тип из cave-only набора должен быть —
	# иначе визуал пещеры теряется.
	var has_cave := false
	for cave_decor in DecorProfiles.CAVE_ONLY_DECOR:
		if all_types.has(cave_decor):
			has_cave = true
			break
	assert_true(has_cave, "cave_chamber должен использовать cave-декор")

func test_residential_zone_fallback_has_no_cave_decor() -> void:
	# Комната неизвестной роли в residential zone → zone fallback.
	# Он не должен предлагать mold/crack/candle.
	var profile := DecorProfiles.decor_profile_for_zone("residential")
	var all_types: Array = []
	all_types.append_array(profile.floor)
	all_types.append_array(profile.wall)
	for cave_decor in DecorProfiles.CAVE_ONLY_DECOR:
		assert_false(all_types.has(cave_decor),
			"residential zone fallback НЕ должен содержать %s" % cave_decor)

func test_tower_top_zone_fallback_has_no_cave_decor() -> void:
	var profile := DecorProfiles.decor_profile_for_zone("tower_top")
	var all_types: Array = []
	all_types.append_array(profile.floor)
	all_types.append_array(profile.wall)
	for cave_decor in DecorProfiles.CAVE_ONLY_DECOR:
		assert_false(all_types.has(cave_decor),
			"tower_top zone fallback НЕ должен содержать %s" % cave_decor)

func test_caves_zone_fallback_allows_cave_decor() -> void:
	var profile := DecorProfiles.decor_profile_for_zone("caves")
	var all_types: Array = []
	all_types.append_array(profile.floor)
	all_types.append_array(profile.wall)
	var has_cave := false
	for cave_decor in DecorProfiles.CAVE_ONLY_DECOR:
		if all_types.has(cave_decor):
			has_cave = true
			break
	assert_true(has_cave, "caves zone fallback должен предлагать cave декор")

func test_unknown_role_falls_back_to_zone_profile() -> void:
	# Не зарегистрированная роль в residential zone → zone fallback,
	# не пустой хардкод.
	var profile := DecorProfiles.decor_profile_for_room("nonexistent_role", "residential")
	var fallback := DecorProfiles.decor_profile_for_zone("residential")
	assert_eq(profile.floor, fallback.floor)
	assert_eq(profile.wall, fallback.wall)

func test_is_decor_allowed_positive_case() -> void:
	assert_true(DecorProfiles.is_decor_allowed_in_room(
		DecorProfiles.DECOR_BED, "bedroom", "residential"),
		"bed разрешён в bedroom")

func test_is_decor_allowed_negative_case_cave_in_residential() -> void:
	assert_false(DecorProfiles.is_decor_allowed_in_room(
		DecorProfiles.DECOR_MOLD, "bedroom", "residential"),
		"mold НЕ разрешён в bedroom (residential)")

func test_entrance_and_exit_have_empty_profiles() -> void:
	# Регресс: у выхода/входа декор пустой, чтобы не блокировать критические
	# точки start/exit визуально.
	var entrance := DecorProfiles.decor_profile_for_room("entrance", "residential")
	var exit_core := DecorProfiles.decor_profile_for_room("exit_core", "residential")
	assert_true(entrance.floor.is_empty() and entrance.wall.is_empty(),
		"entrance профиль пустой")
	assert_true(exit_core.floor.is_empty() and exit_core.wall.is_empty(),
		"exit_core профиль пустой")

func test_treasure_room_profile_hints_at_loot() -> void:
	# treasure_room должен визуально отличаться — минимум наличие crate/candle.
	var profile := DecorProfiles.decor_profile_for_room("treasure_room", "residential")
	var all_types: Array = []
	all_types.append_array(profile.floor)
	all_types.append_array(profile.wall)
	assert_true(all_types.has(DecorProfiles.DECOR_CRATE) or all_types.has(DecorProfiles.DECOR_CANDLE),
		"treasure_room должен визуально сигналить о сокровищах")
