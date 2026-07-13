extends GutTest

# Проверяем что resource-описания боссов (BossDefinition) валидны и
# соответствуют плану PR 1: id уникальны, scene задана, floor не 0,
# fallback флаги корректны.

const NecromancerDefinition: Resource = preload("res://resources/bosses/necromancer_definition.tres")

func test_necromancer_definition_has_stable_id() -> void:
	assert_eq(NecromancerDefinition.id, &"necromancer",
		"id должен быть стабильным StringName для аналитики и тестов")

func test_necromancer_definition_has_i18n_key_not_raw_string() -> void:
	# UPPER_SNAKE_CASE = сигнал i18n-ключа, не raw «Некромант».
	var key := String(NecromancerDefinition.display_name_key)
	assert_eq(key, key.to_upper(),
		"display_name_key должен быть UPPER_SNAKE_CASE i18n-ключом")
	assert_true(key.begins_with("ENEMY_"),
		"i18n-ключ босса стартует с ENEMY_")

func test_necromancer_definition_has_valid_scene() -> void:
	assert_not_null(NecromancerDefinition.scene,
		"BossDefinition.scene обязательна")
	var instance = NecromancerDefinition.scene.instantiate()
	add_child_autofree(instance)
	assert_true(instance is BossBase,
		"инстанс сцены должен наследовать BossBase")

func test_necromancer_definition_targets_floor_five() -> void:
	assert_eq(NecromancerDefinition.floor_number, 5,
		"на этом PR некромант — первый босс на 5 этаже")

func test_necromancer_fallback_allowed_for_higher_boss_floors() -> void:
	# До PR 3–5 некромант служит fallback'ом для 10/15/20 — они
	# получат своих боссов позже.
	assert_true(NecromancerDefinition.fallback_allowed,
		"fallback_allowed = true до внедрения боссов PR 3–5")
