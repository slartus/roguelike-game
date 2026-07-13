extends GutTest

# BossRegistry — единый data-driven mapping "floor → BossDefinition".
# После PR 1 все boss floor'ы (5, 10, 15, 20) резолвятся через registry,
# без hardcoded preload в Main.gd.

func test_floor_five_has_explicit_definition() -> void:
	var definition := BossRegistry.definition_for_floor(5)
	assert_not_null(definition, "floor 5 обязан иметь boss definition")
	assert_eq(definition.id, &"necromancer",
		"5 этаж — некромант (до PR 2)")

func test_boss_floors_ten_fifteen_twenty_have_definitions() -> void:
	# До PR 3–5 fallback возвращает Некроманта, но definition должна быть.
	for floor in [10, 15, 20]:
		var definition := BossRegistry.definition_for_floor(floor)
		assert_not_null(definition,
			"boss floor %d должен резолвиться через fallback" % floor)

func test_non_boss_floors_return_null() -> void:
	for floor in [1, 2, 3, 4, 6, 7, 11, 19]:
		var definition := BossRegistry.definition_for_floor(floor)
		assert_null(definition,
			"non-boss floor %d не должен резолвиться" % floor)

func test_zero_and_negative_floors_return_null_safely() -> void:
	assert_null(BossRegistry.definition_for_floor(0),
		"floor 0 → null (граница)")
	assert_null(BossRegistry.definition_for_floor(-5),
		"отрицательный floor → null безопасно")

func test_scene_for_floor_returns_packed_scene() -> void:
	var scene := BossRegistry.scene_for_floor(5)
	assert_not_null(scene, "scene_for_floor(5) обязан вернуть PackedScene")
	assert_true(scene is PackedScene, "тип должен быть PackedScene")

func test_scene_for_non_boss_floor_returns_null() -> void:
	assert_null(BossRegistry.scene_for_floor(3),
		"non-boss floor → нет scene")

func test_arena_profile_for_boss_floor_is_legacy() -> void:
	var profile := BossRegistry.arena_profile_for_floor(5)
	assert_not_null(profile, "у boss floor должен быть arena profile")
	assert_eq(profile.id, &"legacy_600x400",
		"на PR 1 все боссы делят legacy profile")
	assert_eq(profile.size, Vector2i(600, 400),
		"legacy arena — 600×400 (сохраняем текущий размер)")

func test_all_definitions_returns_registered_bosses() -> void:
	var definitions := BossRegistry.all_definitions()
	assert_gt(definitions.size(), 0, "хотя бы один босс зарегистрирован")

func test_all_definitions_have_unique_ids() -> void:
	var seen: Dictionary = {}
	for definition in BossRegistry.all_definitions():
		assert_false(seen.has(definition.id),
			"boss id %s должен быть уникальным" % [definition.id])
		seen[definition.id] = true

func test_registered_floors_are_unique() -> void:
	# Explicit floor mapping (без fallback) должен быть уникальным —
	# два босса на один этаж = ambiguous resolution.
	var seen: Dictionary = {}
	for definition in BossRegistry.all_definitions():
		var floor: int = definition.floor_number
		if floor <= 0:
			continue
		assert_false(seen.has(floor),
			"boss floor %d не может быть занят двумя definitions" % floor)
		seen[floor] = true

func test_all_definitions_have_valid_scenes() -> void:
	# Guard от опечаток в .tres: если scene удалили — тест сразу подсветит.
	for definition in BossRegistry.all_definitions():
		assert_not_null(definition.scene,
			"BossDefinition '%s' должна иметь непустую scene" % [definition.id])
