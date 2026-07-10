extends GutTest

# Upgrade data model (M1):
# - PlayerUpgradeResource имеет корректные defaults;
# - PlayerUpgradeLibrary валидирует все resources;
# - get_eligible_upgrades фильтрует по max_stacks;
# - в M1 UPGRADE_PATHS пустой — конкретные карты добавятся в M6/M7.

func test_default_upgrade_has_safe_defaults() -> void:
	var upgrade := PlayerUpgradeResource.new()
	assert_eq(upgrade.id, "unknown")
	assert_eq(upgrade.rarity, "common")
	assert_eq(upgrade.max_stacks, 1)
	assert_eq(upgrade.style, "", "по default — general upgrade")
	assert_true(upgrade.display_name.begins_with("UPGRADE_"))
	assert_true(upgrade.description.begins_with("UPGRADE_"))

func test_upgrade_has_configurable_fields() -> void:
	var upgrade := PlayerUpgradeResource.new()
	upgrade.id = "thick_skin"
	upgrade.max_stacks = 3
	upgrade.style = "warrior"
	upgrade.effect_type = "max_health_bonus"
	upgrade.parameters = {"amount": 1}
	upgrade.tags = ["defense"]
	assert_eq(upgrade.id, "thick_skin")
	assert_eq(upgrade.max_stacks, 3)
	assert_eq(upgrade.style, "warrior")
	assert_eq(upgrade.effect_type, "max_health_bonus")
	assert_eq(upgrade.parameters.amount, 1)
	assert_eq(upgrade.tags, ["defense"])

func test_library_has_valid_constants() -> void:
	# Регресс: кто-то не удалит "warrior" из VALID_STYLES.
	assert_true(PlayerUpgradeLibrary.VALID_STYLES.has(""), "general = empty style")
	for style in ["warrior", "archer", "mage"]:
		assert_true(PlayerUpgradeLibrary.VALID_STYLES.has(style),
			"style '%s' должен быть валиден" % style)
	assert_true(PlayerUpgradeLibrary.VALID_RARITIES.has("common"))
	assert_true(PlayerUpgradeLibrary.VALID_RARITIES.has("uncommon"))
	assert_true(PlayerUpgradeLibrary.VALID_RARITIES.has("rare"))

func test_library_recognizes_general_effect_types() -> void:
	# General M6 карты.
	for effect in ["max_health_bonus", "speed_multiplier", "potion_heal_bonus", "second_wind"]:
		assert_true(PlayerUpgradeLibrary.KNOWN_EFFECT_TYPES.has(effect),
			"general effect_type '%s' должен быть в KNOWN_EFFECT_TYPES" % effect)

func test_library_recognizes_style_effect_types() -> void:
	# Style M7 карты.
	for effect in ["style_damage_bonus", "pierce_bonus", "melee_range_multiplier"]:
		assert_true(PlayerUpgradeLibrary.KNOWN_EFFECT_TYPES.has(effect),
			"style effect_type '%s' должен быть в KNOWN_EFFECT_TYPES" % effect)

func test_validate_all_returns_no_errors_on_empty_library() -> void:
	# В M1 UPGRADE_PATHS пустой — validate ничего не находит.
	PlayerUpgradeLibrary.clear_cache_for_testing()
	var errors := PlayerUpgradeLibrary.validate_all()
	assert_eq(errors.size(), 0,
		"без карт validate возвращает пустой список: %s" % [errors])

func test_get_all_upgrades_returns_registered_cards() -> void:
	# После M6 general карты уже в UPGRADE_PATHS.
	PlayerUpgradeLibrary.clear_cache_for_testing()
	var all_upgrades := PlayerUpgradeLibrary.get_all_upgrades()
	assert_gte(all_upgrades.size(), 6,
		"M6 добавил 6 general cards минимум")

func test_get_eligible_excludes_maxed_stacks() -> void:
	# Симулируем: карта max_stacks=2, current_stacks={"foo": 2} → выпадает.
	var upgrade := PlayerUpgradeResource.new()
	upgrade.id = "foo"
	upgrade.max_stacks = 2
	# Инжектим напрямую в кеш через _cache — только для теста.
	PlayerUpgradeLibrary._cache = [upgrade]
	var eligible := PlayerUpgradeLibrary.get_eligible_upgrades({"foo": 2})
	assert_eq(eligible.size(), 0, "maxed карта не eligible")
	eligible = PlayerUpgradeLibrary.get_eligible_upgrades({"foo": 1})
	assert_eq(eligible.size(), 1, "недо-maxed карта всё ещё eligible")
	PlayerUpgradeLibrary.clear_cache_for_testing()

func test_get_upgrade_by_id_returns_null_for_missing() -> void:
	PlayerUpgradeLibrary.clear_cache_for_testing()
	assert_null(PlayerUpgradeLibrary.get_upgrade_by_id("nonexistent"))

func test_validate_all_flags_bad_id() -> void:
	var bad := PlayerUpgradeResource.new()
	# id остаётся "unknown" по default → должен быть flagged.
	PlayerUpgradeLibrary._cache = [bad]
	var errors := PlayerUpgradeLibrary.validate_all()
	assert_gt(errors.size(), 0,
		"upgrade без явного id должен быть flagged")
	PlayerUpgradeLibrary.clear_cache_for_testing()

func test_validate_all_flags_duplicate_ids() -> void:
	var a := PlayerUpgradeResource.new()
	a.id = "dup"
	a.display_name = "UPGRADE_DUP"
	a.description = "UPGRADE_DUP_DESC"
	a.effect_type = "max_health_bonus"
	var b := PlayerUpgradeResource.new()
	b.id = "dup"
	b.display_name = "UPGRADE_DUP"
	b.description = "UPGRADE_DUP_DESC"
	b.effect_type = "max_health_bonus"
	PlayerUpgradeLibrary._cache = [a, b]
	var errors := PlayerUpgradeLibrary.validate_all()
	var found_dup := false
	for e in errors:
		if e.contains("duplicate"):
			found_dup = true
	assert_true(found_dup, "duplicate id должен быть flagged")
	PlayerUpgradeLibrary.clear_cache_for_testing()

func test_validate_all_flags_unknown_effect_type() -> void:
	var upgrade := PlayerUpgradeResource.new()
	upgrade.id = "test"
	upgrade.display_name = "UPGRADE_TEST"
	upgrade.description = "UPGRADE_TEST_DESC"
	upgrade.effect_type = "nonexistent_effect"
	PlayerUpgradeLibrary._cache = [upgrade]
	var errors := PlayerUpgradeLibrary.validate_all()
	var found := false
	for e in errors:
		if e.contains("unknown effect_type"):
			found = true
	assert_true(found, "unknown effect_type должен быть flagged")
	PlayerUpgradeLibrary.clear_cache_for_testing()
