extends GutTest

# Схема WeaponResource v2:
# - identity поля id/style/attack_type/tier/tags добавлены;
# - helpers get_* возвращают новое поле или fallback на legacy;
# - существующие Dagger/Pistol/Shotgun продолжают загружаться и работать.

const DaggerScene = preload("res://resources/weapons/dagger.tres")
const PistolScene = preload("res://resources/weapons/pistol.tres")
const ShotgunScene = preload("res://resources/weapons/shotgun.tres")

func test_new_weapon_resource_has_safe_defaults() -> void:
	var w := WeaponResource.new()
	assert_eq(w.id, "unknown")
	assert_eq(w.style, "legacy")
	assert_eq(w.attack_type, "projectile")
	assert_eq(w.tier, 1)
	assert_eq(w.tags, [] as Array[String])
	assert_gt(w.damage, 0)
	assert_gt(w.get_attack_interval(), 0.0)

func test_new_fields_exist_on_resource() -> void:
	# Регресс: если кто-то удалит поле в .gd, .tres при загрузке упадёт с
	# "Invalid access" — но новые ресурсы ещё не созданы, поэтому явно
	# проверяем что поля есть на самом WeaponResource.
	var w := WeaponResource.new()
	assert_true("id" in w)
	assert_true("style" in w)
	assert_true("attack_type" in w)
	assert_true("tier" in w)
	assert_true("tags" in w)
	assert_true("attack_interval" in w)
	assert_true("attack_range" in w)
	assert_true("projectile_scene" in w)
	assert_true("projectile_speed" in w)
	assert_true("projectiles_per_attack" in w)
	assert_true("pierce" in w)
	assert_true("hitbox_width" in w)
	assert_true("hitbox_length" in w)
	assert_true("active_time" in w)
	assert_true("knockback" in w)
	assert_true("mana_cost" in w)

func test_get_attack_interval_falls_back_to_fire_interval() -> void:
	# У legacy attack_interval = 0 → helper возвращает fire_interval.
	var w := WeaponResource.new()
	w.fire_interval = 0.4
	w.attack_interval = 0.0
	assert_almost_eq(w.get_attack_interval(), 0.4, 0.0001)

func test_get_attack_interval_prefers_new_field_when_set() -> void:
	var w := WeaponResource.new()
	w.fire_interval = 0.4
	w.attack_interval = 0.1
	assert_almost_eq(w.get_attack_interval(), 0.1, 0.0001)

func test_get_projectile_speed_falls_back_to_bullet_speed() -> void:
	var w := WeaponResource.new()
	w.bullet_speed = 300.0
	w.projectile_speed = 0.0
	assert_almost_eq(w.get_projectile_speed(), 300.0, 0.0001)

func test_get_projectiles_per_attack_falls_back_to_bullets_per_shot() -> void:
	var w := WeaponResource.new()
	w.bullets_per_shot = 5
	w.projectiles_per_attack = 0
	assert_eq(w.get_projectiles_per_attack(), 5)

func test_get_projectile_lifetime_falls_back_to_bullet_lifetime() -> void:
	var w := WeaponResource.new()
	w.bullet_lifetime = 0.7
	w.projectile_lifetime = 0.0
	assert_almost_eq(w.get_projectile_lifetime(), 0.7, 0.0001)

func test_get_projectile_color_falls_back_to_bullet_color_when_projectile_default() -> void:
	# Shotgun-регресс: bullet_color=оранжевый, projectile_color=default.
	# Helper должен вернуть оранжевый — иначе Shotgun снаряды побелеют.
	var w := WeaponResource.new()
	w.bullet_color = Color(1.0, 0.55, 0.25, 1.0)
	# projectile_color остаётся дефолтным.
	assert_eq(w.get_projectile_color(), Color(1.0, 0.55, 0.25, 1.0),
		"legacy bullet_color возвращается через fallback")

func test_get_projectile_color_prefers_new_field_when_set() -> void:
	var w := WeaponResource.new()
	w.projectile_color = Color(0.5, 0.2, 0.8, 1.0)  # фиолетовый
	w.bullet_color = Color(1.0, 0.9, 0.3, 1.0)      # default yellow
	assert_eq(w.get_projectile_color(), Color(0.5, 0.2, 0.8, 1.0),
		"новый projectile_color приоритетнее legacy bullet_color")

func test_get_projectile_color_new_field_wins_even_over_non_default_legacy() -> void:
	# Регресс: если ресурс задал ОБА поля, приоритет у нового.
	var w := WeaponResource.new()
	w.projectile_color = Color(0.2, 0.8, 0.4, 1.0)  # зелёный (новый)
	w.bullet_color = Color(1.0, 0.5, 0.5, 1.0)      # красный (legacy)
	assert_eq(w.get_projectile_color(), Color(0.2, 0.8, 0.4, 1.0),
		"новое поле приоритетнее даже если legacy задан")

func test_dagger_resource_still_loads() -> void:
	assert_not_null(DaggerScene, "Dagger .tres должен загружаться (legacy)")
	assert_eq(DaggerScene.display_name, "WEAPON_DAGGER")
	assert_gt(DaggerScene.damage, 0)
	assert_gt(DaggerScene.get_attack_interval(), 0.0,
		"legacy weapons должны отдавать attack_interval через fallback")

func test_pistol_resource_still_loads() -> void:
	assert_not_null(PistolScene)
	assert_gt(PistolScene.get_projectiles_per_attack(), 0)

func test_shotgun_resource_still_loads() -> void:
	assert_not_null(ShotgunScene)
	# Shotgun выпускает несколько дробинок — projectiles_per_attack должен
	# отдавать корректное >1.
	assert_gt(ShotgunScene.get_projectiles_per_attack(), 1,
		"Shotgun должен иметь несколько снарядов")

func test_legacy_resources_have_default_style() -> void:
	# Legacy .tres не задаёт style — должен остаться "legacy" (дефолт).
	for weapon in [DaggerScene, PistolScene, ShotgunScene]:
		assert_eq(weapon.style, "legacy",
			"%s должен иметь style='legacy' (default для старых .tres)" % weapon.display_name)

func test_all_active_weapons_have_display_name_and_positive_damage() -> void:
	for weapon in [DaggerScene, PistolScene, ShotgunScene]:
		assert_ne(weapon.display_name, "", "display_name не пуст")
		assert_gt(weapon.damage, 0, "damage > 0")
		assert_gt(weapon.get_attack_interval(), 0.0, "attack interval > 0")

func test_tier_starts_at_one_or_higher() -> void:
	# Регресс: tier >= 1 инвариант.
	var w := WeaponResource.new()
	assert_gte(w.tier, 1)
	for weapon in [DaggerScene, PistolScene, ShotgunScene]:
		assert_gte(weapon.tier, 1)
