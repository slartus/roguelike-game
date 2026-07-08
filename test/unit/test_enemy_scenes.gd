extends GutTest

# Smoke-тесты для всех врагов: проверяем что каждая .tscn грузится,
# инстанциируется и её экспортированные параметры соответствуют
# документации (docs/gamedesign/enemies.md).

const MELEE_SPECS := {
	"res://scenes/enemies/enemy.tscn": {
		"max_health": 3, "speed": 35.0, "contact_damage": 1,
		"xp_reward": 5, "gold_reward": 1, "pickup_drop_chance": 0.15,
	},
	"res://scenes/enemies/goblin.tscn": {
		"max_health": 4, "speed": 55.0, "contact_damage": 2,
		"xp_reward": 6, "gold_reward": 2, "pickup_drop_chance": 0.15,
	},
	"res://scenes/enemies/orc.tscn": {
		"max_health": 8, "speed": 28.0, "contact_damage": 3,
		"xp_reward": 14, "gold_reward": 4, "pickup_drop_chance": 0.22,
	},
	# NB: raw @export values из .tscn. skeleton.gd::_ready увеличивает
	# contact_damage на weapon-bonus (см. skeleton_arsenal.gd), но тут
	# instance.free() без add_child — _ready не отработает, значения
	# остаются базовыми.
	"res://scenes/enemies/skeleton.tscn": {
		"max_health": 3, "speed": 50.0, "contact_damage": 2,
		"xp_reward": 7, "gold_reward": 2, "pickup_drop_chance": 0.15,
	},
	"res://scenes/enemies/zombie.tscn": {
		"max_health": 6, "speed": 22.0, "contact_damage": 3,
		"xp_reward": 11, "gold_reward": 3, "pickup_drop_chance": 0.2,
	},
}

const RANGED_SPECS := {
	"res://scenes/enemies/ranged_enemy.tscn": {
		"max_health": 2, "fire_interval": 1.5,
		"xp_reward": 7, "gold_reward": 2, "pickup_drop_chance": 0.15,
	},
	"res://scenes/enemies/lich.tscn": {
		"max_health": 3, "fire_interval": 1.0,
		"xp_reward": 12, "gold_reward": 4, "pickup_drop_chance": 0.18,
	},
}

const WEAPON_TRES_PATHS: Array[String] = [
	"res://resources/weapons/dagger.tres",
	"res://resources/weapons/pistol.tres",
	"res://resources/weapons/shotgun.tres",
]

const CHARGER_PATH := "res://scenes/enemies/charger.tscn"
const BOSS_PATH := "res://scenes/enemies/boss.tscn"

func _assert_exports(path: String, spec: Dictionary) -> void:
	var scene: PackedScene = load(path)
	assert_not_null(scene, "scene loads: %s" % path)
	var instance: Node = scene.instantiate()
	assert_not_null(instance, "scene instantiates: %s" % path)
	for key in spec.keys():
		var actual = instance.get(key)
		assert_eq(actual, spec[key], "%s.%s" % [path.get_file(), key])
	instance.free()

func test_melee_scenes_match_docs() -> void:
	for path in MELEE_SPECS.keys():
		_assert_exports(path, MELEE_SPECS[path])

func test_ranged_scenes_match_docs() -> void:
	for path in RANGED_SPECS.keys():
		_assert_exports(path, RANGED_SPECS[path])

func test_charger_scene_uses_default_stats() -> void:
	var scene: PackedScene = load(CHARGER_PATH)
	assert_not_null(scene)
	var instance: Node = scene.instantiate()
	assert_not_null(instance)
	# Spider ничего не переопределяет — все дефолты из charger.gd
	assert_eq(instance.max_health, 1)
	assert_eq(instance.charge_speed, 220.0)
	assert_eq(instance.wait_duration, 1.2)
	assert_eq(instance.charge_duration, 0.9)
	assert_eq(instance.xp_reward, 8)
	assert_eq(instance.gold_reward, 1)
	instance.free()

func test_boss_scene_uses_default_stats_and_has_bullet_scene() -> void:
	var scene: PackedScene = load(BOSS_PATH)
	assert_not_null(scene)
	var instance: Node = scene.instantiate()
	assert_not_null(instance)
	assert_eq(instance.max_health, 30)
	assert_eq(instance.speed, 25.0)
	assert_eq(instance.contact_damage, 3)
	assert_eq(instance.volley_interval, 2.0)
	assert_eq(instance.volley_count, 8)
	assert_eq(instance.xp_reward, 40)
	assert_eq(instance.gold_reward, 20)
	assert_not_null(instance.bullet_scene, "boss must have bullet_scene wired")
	instance.free()

func test_all_ranged_scenes_have_bullet_scene() -> void:
	for path in RANGED_SPECS.keys():
		var scene: PackedScene = load(path)
		var instance: Node = scene.instantiate()
		assert_not_null(instance.bullet_scene, "%s must have bullet_scene wired" % path.get_file())
		instance.free()

func test_every_enemy_script_declares_died_at_signal() -> void:
	# Портал телепортируется на точку смерти последнего врага —
	# если кто-то удалит died_at из одной сцены, portal fallback'нётся
	# на генератор-provided exit_position, что тихо ломает feature.
	var enemy_scenes := [
		"res://scenes/enemies/enemy.tscn",
		"res://scenes/enemies/goblin.tscn",
		"res://scenes/enemies/orc.tscn",
		"res://scenes/enemies/skeleton.tscn",
		"res://scenes/enemies/zombie.tscn",
		"res://scenes/enemies/charger.tscn",
		"res://scenes/enemies/ranged_enemy.tscn",
		"res://scenes/enemies/lich.tscn",
		"res://scenes/enemies/boss.tscn",
	]
	for path in enemy_scenes:
		var scene: PackedScene = load(path)
		var instance = scene.instantiate()
		assert_true(instance.has_signal("died_at"),
			"%s must declare died_at(position) signal" % path.get_file())
		instance.free()

func test_every_weapon_has_icon_texture() -> void:
	# Каждый .tres обязан иметь icon_texture — иначе WeaponPickup будет
	# без спрайта и игрок не поймёт что валяется.
	for path in WEAPON_TRES_PATHS:
		var weapon = load(path)
		assert_not_null(weapon, "weapon loads: %s" % path)
		assert_not_null(weapon.icon_texture, "%s must have icon_texture" % path.get_file())

func test_chest_scene_has_both_textures_wired() -> void:
	var scene: PackedScene = load("res://scenes/pickups/chest.tscn")
	var chest = scene.instantiate()
	assert_not_null(chest.closed_texture, "chest must have closed_texture")
	assert_not_null(chest.open_texture, "chest must have open_texture")
	chest.free()

func test_main_enemy_pool_contains_all_eight_regular_types() -> void:
	var main_script := load("res://scenes/main.gd")
	var pool = main_script.ENEMY_SCENES
	assert_eq(pool.size(), 8, "8 regular enemies in pool")
	var paths: Array = []
	for scene in pool:
		paths.append(scene.resource_path)
	var expected := [
		"res://scenes/enemies/enemy.tscn",
		"res://scenes/enemies/goblin.tscn",
		"res://scenes/enemies/orc.tscn",
		"res://scenes/enemies/skeleton.tscn",
		"res://scenes/enemies/zombie.tscn",
		"res://scenes/enemies/charger.tscn",
		"res://scenes/enemies/ranged_enemy.tscn",
		"res://scenes/enemies/lich.tscn",
	]
	for path in expected:
		assert_true(paths.has(path), "pool contains %s" % path)
