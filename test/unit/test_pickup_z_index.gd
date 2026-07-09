extends GutTest

# Персонажи (Player, все Enemy'и, Boss) должны рисоваться поверх пикапов
# (сундук, сердечко, оружейный пикап), а не за ними.
#
# Реализация: у персонажей z_index = 1, у пикапов и всего окружения (пол,
# портал, стены) z_index = 0. Godot 2D CanvasItem рендерит по возрастанию
# z_index, поэтому персонажи всегда над пикапами и полом.
#
# Контракт проверяем именно как ОТНОСИТЕЛЬНЫЙ ordering, а не как «z_index
# конкретной ноды == 1» — чтобы тест не ломался при глобальном сдвиге шкалы.

const PlayerScene = preload("res://scenes/player/player.tscn")
const SlimeScene = preload("res://scenes/enemies/enemy.tscn")
const GoblinScene = preload("res://scenes/enemies/goblin.tscn")
const OrcScene = preload("res://scenes/enemies/orc.tscn")
const SkeletonScene = preload("res://scenes/enemies/skeleton.tscn")
const ZombieScene = preload("res://scenes/enemies/zombie.tscn")
const SpiderScene = preload("res://scenes/enemies/charger.tscn")
const ArcherScene = preload("res://scenes/enemies/ranged_enemy.tscn")
const LichScene = preload("res://scenes/enemies/lich.tscn")
const BossScene = preload("res://scenes/enemies/boss.tscn")

const ChestScene = preload("res://scenes/pickups/chest.tscn")
const HealthPickupScene = preload("res://scenes/pickups/health_pickup.tscn")
const WeaponPickupScene = preload("res://scenes/pickups/weapon_pickup.tscn")

func _instantiate(scene: PackedScene) -> Node2D:
	var n: Node2D = scene.instantiate()
	add_child_autofree(n)
	return n

func test_player_renders_above_all_pickups() -> void:
	var player := _instantiate(PlayerScene)
	var chest := _instantiate(ChestScene)
	var health := _instantiate(HealthPickupScene)
	var weapon := _instantiate(WeaponPickupScene)
	assert_gt(player.z_index, chest.z_index, "игрок должен быть поверх сундука")
	assert_gt(player.z_index, health.z_index, "игрок должен быть поверх сердечка")
	assert_gt(player.z_index, weapon.z_index, "игрок должен быть поверх оружейного пикапа")

func test_every_enemy_renders_above_pickups() -> void:
	# По одному представителю каждого типа: если у любого забыли z_index,
	# он будет виден "за" сундуком.
	var enemies := [
		["Slime", SlimeScene],
		["Goblin", GoblinScene],
		["Orc", OrcScene],
		["Skeleton", SkeletonScene],
		["Zombie", ZombieScene],
		["Spider", SpiderScene],
		["Archer", ArcherScene],
		["Lich", LichScene],
		["Boss", BossScene],
	]
	var chest := _instantiate(ChestScene)
	var health := _instantiate(HealthPickupScene)
	var weapon := _instantiate(WeaponPickupScene)
	for entry in enemies:
		var label: String = entry[0]
		var enemy := _instantiate(entry[1])
		assert_gt(enemy.z_index, chest.z_index, "%s должен быть поверх сундука" % label)
		assert_gt(enemy.z_index, health.z_index, "%s должен быть поверх сердечка" % label)
		assert_gt(enemy.z_index, weapon.z_index, "%s должен быть поверх оружейного пикапа" % label)

func test_pickups_stay_at_default_z_to_not_hide_under_floor() -> void:
	# Пол (Polygon2D в scenes/dungeon/floor.gd) рендерится с z_index = 0.
	# Если пикапу дать z_index < 0, он уйдёт под пол и станет невидимым.
	# Контракт: пикапы держатся ровно на default (0) — не выше и не ниже.
	var chest := _instantiate(ChestScene)
	var health := _instantiate(HealthPickupScene)
	var weapon := _instantiate(WeaponPickupScene)
	assert_eq(chest.z_index, 0, "сундук не должен уходить под z=0 (спрячется за полом)")
	assert_eq(health.z_index, 0, "сердечко не должно уходить под z=0")
	assert_eq(weapon.z_index, 0, "оружейный пикап не должен уходить под z=0")
