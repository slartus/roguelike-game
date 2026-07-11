extends GutTest

# Регистр EnvironmentVisualProfiles: покрытие всех известных zone,
# fallback для неизвестной zone и валидность обязательных полей
# профиля (default/corridor/wall материалы существуют в каталоге).

const KNOWN_ZONES := [
	&"tower_top",
	&"residential",
	&"technical",
	&"lower_tower",
	&"basement",
	&"caves",
]

func test_all_tower_zones_have_profile() -> void:
	# Каждая zone из TowerZone.ALL_ZONES обязана иметь профиль. Если
	# TowerZone добавит zone, а EnvironmentVisualProfiles забудет —
	# тест поймает несовпадение.
	for zone_str in TowerZone.ALL_ZONES:
		var zone := StringName(String(zone_str))
		assert_true(
			EnvironmentVisualProfiles.has_zone(zone),
			"zone '%s' должна иметь EnvironmentVisualProfile" % zone,
		)

func test_unknown_zone_falls_back_to_tower_top() -> void:
	var unknown := &"unknown_zone_never_registered"
	var profile := EnvironmentVisualProfiles.for_zone(unknown)
	assert_not_null(profile, "unknown zone должна вернуть fallback profile")
	assert_eq(
		profile.id, &"tower_top",
		"fallback идёт в tower_top",
	)

func test_all_profiles_have_valid_default_materials() -> void:
	# Каждый профиль обязан ссылаться на материалы, реально
	# зарегистрированные в каталоге. Опечатка в ID тут словится.
	for zone in KNOWN_ZONES:
		var profile := EnvironmentVisualProfiles.for_zone(zone)
		assert_true(
			EnvironmentMaterialCatalog.has_material(profile.default_floor_material),
			"zone %s default_floor_material %s не найден в каталоге" % [
				zone, profile.default_floor_material,
			],
		)
		assert_true(
			EnvironmentMaterialCatalog.has_material(profile.corridor_floor_material),
			"zone %s corridor_floor_material %s не найден" % [
				zone, profile.corridor_floor_material,
			],
		)
		assert_true(
			EnvironmentMaterialCatalog.has_material(profile.default_wall_material),
			"zone %s default_wall_material %s не найден" % [
				zone, profile.default_wall_material,
			],
		)

func test_role_overrides_reference_valid_materials() -> void:
	for zone in KNOWN_ZONES:
		var profile := EnvironmentVisualProfiles.for_zone(zone)
		for role_key in profile.room_role_floor_overrides.keys():
			var mat_id: StringName = profile.room_role_floor_overrides[role_key]
			assert_true(
				EnvironmentMaterialCatalog.has_material(mat_id),
				"zone %s role %s floor override %s невалиден" % [zone, role_key, mat_id],
			)
		for role_key in profile.room_role_wall_overrides.keys():
			var mat_id: StringName = profile.room_role_wall_overrides[role_key]
			assert_true(
				EnvironmentMaterialCatalog.has_material(mat_id),
				"zone %s role %s wall override %s невалиден" % [zone, role_key, mat_id],
			)

func test_zone_ids_match_profile_id_field() -> void:
	# Ключ в реестре == profile.id — иначе `for_zone(profile.id)` вернёт
	# не то, что положили.
	for zone in KNOWN_ZONES:
		var profile := EnvironmentVisualProfiles.for_zone(zone)
		assert_eq(profile.id, zone, "profile.id для %s должен совпадать с ключом" % zone)

func test_all_zones_returns_full_set() -> void:
	var zones := EnvironmentVisualProfiles.all_zones()
	for zone in KNOWN_ZONES:
		assert_true(zones.has(zone), "all_zones должен содержать %s" % zone)
