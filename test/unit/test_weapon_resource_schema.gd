extends GutTest

# Схема WeaponResource после fantasy roster overhaul:
# - identity поля id/style/attack_type/tier/tags — обязательны у всех .tres;
# - Pistol/Shotgun удалены; Dagger мигрировал в melee_arc warrior;
# - legacy fallback fields (fire_interval, bullet_*, bullets_per_shot)
#   удалены — все оружия задают современные поля напрямую.

const DaggerScene = preload("res://resources/weapons/dagger.tres")
const ShortSwordScene = preload("res://resources/weapons/short_sword.tres")
const SpearScene = preload("res://resources/weapons/spear.tres")
const ShortBowScene = preload("res://resources/weapons/short_bow.tres")
const CrossbowScene = preload("res://resources/weapons/crossbow.tres")
const WandScene = preload("res://resources/weapons/wand.tres")
const StaffScene = preload("res://resources/weapons/apprentice_staff.tres")

const ACTIVE_WEAPONS: Array = [
	DaggerScene, ShortSwordScene, SpearScene,
	ShortBowScene, CrossbowScene,
	WandScene, StaffScene,
]

func test_new_weapon_resource_has_safe_defaults() -> void:
	var w := WeaponResource.new()
	assert_eq(w.id, "unknown")
	# Дефолт style теперь — warrior, потому что legacy style удалён.
	assert_eq(w.style, "warrior")
	assert_eq(w.attack_type, "melee_arc")
	assert_eq(w.tier, 1)
	assert_eq(w.tags, [] as Array[String])
	assert_gt(w.damage, 0)
	assert_gt(w.get_attack_interval(), 0.0)

func test_new_fields_exist_on_resource() -> void:
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

func test_legacy_fallback_fields_removed() -> void:
	# После fantasy overhaul legacy fields больше не существуют.
	# WeaponResource не должен принимать fire_interval / bullet_* /
	# bullets_per_shot — все .tres задают новые поля напрямую.
	var w := WeaponResource.new()
	assert_false("fire_interval" in w, "legacy fire_interval должен быть удалён")
	assert_false("bullet_speed" in w, "legacy bullet_speed должен быть удалён")
	assert_false("bullet_lifetime" in w, "legacy bullet_lifetime должен быть удалён")
	assert_false("bullet_color" in w, "legacy bullet_color должен быть удалён")
	assert_false("bullets_per_shot" in w, "legacy bullets_per_shot должен быть удалён")

func test_get_attack_interval_returns_new_field() -> void:
	var w := WeaponResource.new()
	w.attack_interval = 0.1
	assert_almost_eq(w.get_attack_interval(), 0.1, 0.0001)

func test_get_projectile_speed_returns_new_field() -> void:
	var w := WeaponResource.new()
	w.projectile_speed = 300.0
	assert_almost_eq(w.get_projectile_speed(), 300.0, 0.0001)

func test_get_projectiles_per_attack_returns_new_field() -> void:
	var w := WeaponResource.new()
	w.projectiles_per_attack = 3
	assert_eq(w.get_projectiles_per_attack(), 3)

func test_get_projectile_lifetime_returns_new_field() -> void:
	var w := WeaponResource.new()
	w.projectile_lifetime = 0.7
	assert_almost_eq(w.get_projectile_lifetime(), 0.7, 0.0001)

func test_get_projectile_color_returns_new_field() -> void:
	var w := WeaponResource.new()
	w.projectile_color = Color(0.5, 0.2, 0.8, 1.0)
	assert_eq(w.get_projectile_color(), Color(0.5, 0.2, 0.8, 1.0))

# --- Roster invariants ---

func test_all_active_weapons_have_unique_ids() -> void:
	var seen: Dictionary = {}
	for weapon in ACTIVE_WEAPONS:
		assert_false(seen.has(weapon.id),
			"weapon id '%s' повторяется" % weapon.id)
		seen[weapon.id] = true

func test_all_active_weapons_have_explicit_identity() -> void:
	for weapon in ACTIVE_WEAPONS:
		assert_ne(weapon.id, "unknown",
			"%s должен явно задать id" % weapon.display_name)
		assert_true(weapon.style in ["warrior", "archer", "mage"],
			"%s.style должен быть fantasy-стилем, а не '%s'" % [weapon.display_name, weapon.style])
		assert_true(weapon.attack_type in [
			"melee_arc", "melee_thrust", "projectile", "spell_projectile", "spell_area",
		], "%s.attack_type должен быть валиден" % weapon.display_name)
		assert_gt(weapon.tags.size(), 0,
			"%s должен иметь непустые tags" % weapon.display_name)

func test_dagger_migrated_to_melee_arc_warrior() -> void:
	assert_eq(DaggerScene.id, "dagger")
	assert_eq(DaggerScene.style, "warrior")
	assert_eq(DaggerScene.attack_type, "melee_arc")

func test_all_active_weapons_have_display_name_and_positive_damage() -> void:
	for weapon in ACTIVE_WEAPONS:
		assert_ne(weapon.display_name, "", "display_name не пуст")
		assert_gt(weapon.damage, 0, "damage > 0")
		assert_gt(weapon.get_attack_interval(), 0.0, "attack interval > 0")

func test_tier_starts_at_one_or_higher() -> void:
	for weapon in ACTIVE_WEAPONS:
		assert_gte(weapon.tier, 1)
