extends GutTest

# Archer оружия (Short Bow, Crossbow) и pierce механика.
# - Short Bow: быстрый, damage=1, spread 2°, без pierce;
# - Crossbow: медленный, damage=3, no spread, pierce=1;
# - projectile с pierce=0 удаляется после первого попадания;
# - projectile с pierce=1 переживает первое попадание и умирает после второго.

const ShortBowRes = preload("res://resources/weapons/short_bow.tres")
const CrossbowRes = preload("res://resources/weapons/crossbow.tres")
const BulletScene = preload("res://scenes/bullets/bullet.tscn")

class FakeEnemy:
	extends CharacterBody2D
	var hp: int = 10
	var hits_received: int = 0
	func _ready() -> void:
		add_to_group("enemy")
		var shape := CircleShape2D.new()
		shape.radius = 6.0
		var cs := CollisionShape2D.new()
		cs.shape = shape
		add_child(cs)
	func take_damage(amount: int) -> void:
		hp -= amount
		hits_received += 1

func test_short_bow_loads_and_has_archer_style() -> void:
	assert_not_null(ShortBowRes)
	assert_eq(ShortBowRes.id, "short_bow")
	assert_eq(ShortBowRes.style, "archer")
	assert_eq(ShortBowRes.attack_type, "projectile")
	assert_eq(ShortBowRes.pierce, 0, "лук стандартный, без pierce")
	assert_gt(ShortBowRes.projectile_speed, 0.0)
	assert_gt(ShortBowRes.get_attack_interval(), 0.0)

func test_crossbow_loads_and_pierces() -> void:
	assert_not_null(CrossbowRes)
	assert_eq(CrossbowRes.id, "crossbow")
	assert_eq(CrossbowRes.style, "archer")
	assert_eq(CrossbowRes.attack_type, "projectile")
	assert_gte(CrossbowRes.pierce, 1, "арбалет должен пробивать хотя бы 1")

func test_crossbow_more_damage_than_short_bow() -> void:
	# Не строгий инвариант, но соответствует дизайну M4: crossbow медленнее,
	# но больнее.
	assert_gt(CrossbowRes.damage, ShortBowRes.damage)
	assert_gt(CrossbowRes.get_attack_interval(), ShortBowRes.get_attack_interval())

func test_projectile_no_pierce_deletes_on_first_hit() -> void:
	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(20, 0)
	add_child_autofree(enemy)
	var bullet := BulletScene.instantiate()
	bullet.apply_weapon(ShortBowRes)  # pierce = 0
	bullet.global_position = Vector2(20, 0)
	add_child_autofree(bullet)
	# Ждём physics tick + idle-frame — queue_free() удаляет узел не мгновенно,
	# а в конце текущего idle-frame.
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	assert_eq(enemy.hits_received, 1, "первое попадание засчитано")
	assert_false(is_instance_valid(bullet),
		"pierce=0 → удаляется после первого hit")

func test_projectile_pierce_one_survives_first_hit_and_dies_on_second() -> void:
	# Два врага рядом на пути пули. Pierce=1 → первый получает hit, пуля
	# живёт; второй получает hit, пуля queue_free.
	var enemy_a := FakeEnemy.new()
	enemy_a.global_position = Vector2(20, 0)
	add_child_autofree(enemy_a)
	var enemy_b := FakeEnemy.new()
	enemy_b.global_position = Vector2(40, 0)
	add_child_autofree(enemy_b)
	var bullet := BulletScene.instantiate()
	bullet.apply_weapon(CrossbowRes)  # pierce = 1
	bullet.global_position = Vector2(20, 0)
	bullet.direction = Vector2.RIGHT
	add_child_autofree(bullet)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# После первого физкадра пуля попала в enemy_a и осталась жива.
	assert_eq(enemy_a.hits_received, 1, "enemy A получил hit")
	assert_true(is_instance_valid(bullet),
		"pierce=1 → пуля выжила после первого hit")
	# Даём пуле долететь до enemy_b (за N физкадров при speed=300 px/s).
	# 20px разница / 300px/s ≈ 66ms → 4 physics-кадра при 60Hz.
	for _i in 8:
		await get_tree().physics_frame
	assert_eq(enemy_b.hits_received, 1, "enemy B получил hit")
	# После второго hit pierce_remaining исчерпан → queue_free.
	await get_tree().physics_frame
	assert_false(is_instance_valid(bullet),
		"pierce исчерпан после второго hit — пуля удалена")

func test_bullet_apply_weapon_reads_pierce_from_resource() -> void:
	var bullet := BulletScene.instantiate()
	bullet.apply_weapon(CrossbowRes)
	add_child_autofree(bullet)
	assert_eq(bullet.pierce, 1,
		"bullet.pierce должен быть скопирован из crossbow.tres")

func test_bullet_pierce_defaults_to_zero_for_legacy_weapon() -> void:
	# Legacy Dagger не задаёт pierce → default 0.
	var dagger: WeaponResource = preload("res://resources/weapons/dagger.tres")
	var bullet := BulletScene.instantiate()
	bullet.apply_weapon(dagger)
	add_child_autofree(bullet)
	assert_eq(bullet.pierce, 0,
		"legacy dagger без pierce → default 0, обратная совместимость")
