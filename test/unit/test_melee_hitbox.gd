extends GutTest

# MeleeHitbox контракт:
# - configure() применяет damage/размер/rotation до _ready;
# - hitbox бьёт каждого enemy'а один раз за swing (не многократно);
# - через active_time hitbox сам queue_free;
# - short_sword.tres и spear.tres корректно грузятся и типизированы.

const HitboxScene = preload("res://scenes/player/melee_hitbox.tscn")
const ShortSwordScene = preload("res://resources/weapons/short_sword.tres")
const SpearScene = preload("res://resources/weapons/spear.tres")

# Fake target — CharacterBody2D в группе enemy с методом take_damage.
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

func _make_owner_player() -> Node2D:
	var p := CharacterBody2D.new()
	p.global_position = Vector2.ZERO
	add_child_autofree(p)
	return p

func _spawn_hitbox(source: Node2D, direction: Vector2, damage: int, length: float, width: float, life: float) -> Node:
	# PackedScene.instantiate() возвращает Node, а class_name MeleeHitbox
	# — только скрипт. Не типизируем возвращаемое значение узко, иначе
	# Godot ругается на assign 'Area2D' → 'melee_hitbox.gd'.
	var hb := HitboxScene.instantiate()
	hb.configure(source, direction, damage, length, width, life, 0.0)
	add_child_autofree(hb)
	return hb

func test_short_sword_loads_and_has_expected_stats() -> void:
	assert_not_null(ShortSwordScene)
	assert_eq(ShortSwordScene.id, "short_sword")
	assert_eq(ShortSwordScene.style, "warrior")
	assert_eq(ShortSwordScene.attack_type, "melee_arc")
	assert_gt(ShortSwordScene.damage, 0)
	assert_gt(ShortSwordScene.hitbox_length, 0.0)
	assert_gt(ShortSwordScene.hitbox_width, 0.0)
	assert_gt(ShortSwordScene.active_time, 0.0)
	assert_eq(ShortSwordScene.display_name, "WEAPON_SHORT_SWORD")

func test_spear_loads_and_uses_thrust_type() -> void:
	assert_not_null(SpearScene)
	assert_eq(SpearScene.id, "spear")
	assert_eq(SpearScene.attack_type, "melee_thrust")
	assert_gt(SpearScene.hitbox_length, SpearScene.hitbox_width,
		"copье должно быть длиннее чем шире (thrust reach)")
	assert_gt(SpearScene.attack_range, ShortSwordScene.attack_range,
		"копьё должно иметь больший range чем меч")

func test_hitbox_damages_enemy_inside_area() -> void:
	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(20, 0)
	add_child_autofree(enemy)
	var source := _make_owner_player()
	_spawn_hitbox(source, Vector2.RIGHT, 3, 40.0, 24.0, 0.2)
	# await 2 кадра — _ready + call_deferred('_apply_initial_overlap').
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(enemy.hits_received, 1,
		"hitbox должен ударить enemy один раз (initial overlap)")
	assert_eq(enemy.hp, 7, "hp = 10 - 3")

func test_hitbox_does_not_double_hit_same_enemy() -> void:
	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(20, 0)
	add_child_autofree(enemy)
	var source := _make_owner_player()
	_spawn_hitbox(source, Vector2.RIGHT, 3, 40.0, 24.0, 0.2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Прогоняем ещё несколько кадров — hitbox не должен ударить ещё.
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(enemy.hits_received, 1,
		"один swing = один удар, не пульсирует")

func test_hitbox_queues_free_after_active_time() -> void:
	var source := _make_owner_player()
	var hb := _spawn_hitbox(source, Vector2.RIGHT, 1, 30.0, 20.0, 0.03)
	# active_time = 0.03s, _physics_process тикается ~60Hz. Даём с запасом.
	await get_tree().create_timer(0.1).timeout
	assert_false(is_instance_valid(hb),
		"hitbox должен быть freed после active_time")

func test_hitbox_ignores_player_group() -> void:
	# Регресс: hitbox не бьёт самого игрока (даже если тот в overlap).
	var enemy_like_player := FakeEnemy.new()
	enemy_like_player.global_position = Vector2(10, 0)
	enemy_like_player.add_to_group("player")
	# Умышленно оставим также в enemy — тест защищает от того, чтобы
	# игрок случайно попал под damage.
	add_child_autofree(enemy_like_player)
	var source := _make_owner_player()
	_spawn_hitbox(source, Vector2.RIGHT, 5, 40.0, 24.0, 0.15)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(enemy_like_player.hits_received, 0,
		"hitbox не должен бить группу player")

func test_hitbox_positioned_in_front_of_source() -> void:
	# Регресс: box смещается вдоль direction на length/2. Иначе игрок бил
	# бы «внутрь себя», а не перед собой.
	var source := _make_owner_player()
	source.global_position = Vector2(100, 100)
	var hb := _spawn_hitbox(source, Vector2.RIGHT, 1, 40.0, 20.0, 0.15)
	assert_almost_eq(hb.global_position.x, 120.0, 0.5,
		"hitbox центр = source + direction × length/2 = 100 + 20 = 120")
	assert_almost_eq(hb.global_position.y, 100.0, 0.5)
