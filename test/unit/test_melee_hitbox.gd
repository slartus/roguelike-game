extends GutTest

# MeleeHitbox контракт:
# - configure() применяет damage/размер/rotation до _ready;
# - hitbox бьёт каждого enemy'а один раз за swing (не многократно);
# - через active_time hitbox перестаёт наносить урон;
# - через _visual_life (не меньше MIN_VISUAL_LIFE) — queue_free;
# - для melee_arc работает angular-filter (в секторе — бьёт, вне — нет);
# - для melee_thrust hitbox стоит перед игроком (rect offset на length/2);
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

func _make_wall(pos: Vector2, size: Vector2) -> StaticBody2D:
	# Стена = StaticBody2D + rect. Используется в LoS-регрессах.
	var wall := StaticBody2D.new()
	wall.global_position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	add_child_autofree(wall)
	return wall

func _spawn_arc_hitbox(
	source: Node2D,
	direction: Vector2,
	damage: int,
	length: float,
	life: float,
	arc_deg: float = 80.0,
) -> Node:
	var hb := HitboxScene.instantiate()
	hb.configure(source, direction, damage, length, 0.0, life, 0.0, "melee_arc", arc_deg)
	add_child_autofree(hb)
	return hb

func _spawn_thrust_hitbox(
	source: Node2D,
	direction: Vector2,
	damage: int,
	length: float,
	width: float,
	life: float,
) -> Node:
	var hb := HitboxScene.instantiate()
	hb.configure(source, direction, damage, length, width, life, 0.0, "melee_thrust", 0.0)
	add_child_autofree(hb)
	return hb

func test_short_sword_loads_and_has_expected_stats() -> void:
	assert_not_null(ShortSwordScene)
	assert_eq(ShortSwordScene.id, "short_sword")
	assert_eq(ShortSwordScene.style, "warrior")
	assert_eq(ShortSwordScene.attack_type, "melee_arc")
	assert_gt(ShortSwordScene.damage, 0)
	assert_gt(ShortSwordScene.hitbox_length, 0.0)
	assert_gt(ShortSwordScene.arc_degrees, 0.0,
		"arc-оружие обязано иметь arc_degrees > 0, иначе angular filter отсечёт всё")
	assert_gt(ShortSwordScene.active_time, 0.0)
	assert_eq(ShortSwordScene.display_name, "WEAPON_SHORT_SWORD")

func test_spear_loads_and_uses_thrust_type() -> void:
	assert_not_null(SpearScene)
	assert_eq(SpearScene.id, "spear")
	assert_eq(SpearScene.attack_type, "melee_thrust")
	assert_gt(SpearScene.hitbox_length, SpearScene.hitbox_width,
		"копьё должно быть длиннее чем шире (thrust reach)")
	assert_gt(SpearScene.attack_range, ShortSwordScene.attack_range,
		"копьё должно иметь больший range чем меч")

func test_arc_hitbox_hits_enemy_in_front_within_sector() -> void:
	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(20, 0)
	add_child_autofree(enemy)
	var source := _make_owner_player()
	_spawn_arc_hitbox(source, Vector2.RIGHT, 3, 40.0, 0.2, 80.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(enemy.hits_received, 1,
		"arc hitbox бьёт enemy прямо по направлению атаки")
	assert_eq(enemy.hp, 7, "hp = 10 - 3")

func test_arc_hitbox_does_not_hit_enemy_perpendicular_to_direction() -> void:
	# Регресс: enemy на 90° от направления атаки внутри радиуса, но снаружи
	# арки 80° → не должен получить урон. Раньше hitbox был прямоугольным
	# и мог случайно задеть перпендикулярного врага.
	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(0, 20)
	add_child_autofree(enemy)
	var source := _make_owner_player()
	_spawn_arc_hitbox(source, Vector2.RIGHT, 3, 40.0, 0.2, 80.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(enemy.hits_received, 0,
		"enemy на 90° вне сектора 80° — не должен быть задет")

func test_arc_hitbox_does_not_hit_enemy_behind_source() -> void:
	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(-20, 0)
	add_child_autofree(enemy)
	var source := _make_owner_player()
	_spawn_arc_hitbox(source, Vector2.RIGHT, 3, 40.0, 0.2, 80.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(enemy.hits_received, 0,
		"enemy за спиной (180°) не должен получать урон, даже если в радиусе")

func test_arc_hitbox_does_not_hit_enemy_beyond_radius() -> void:
	var enemy := FakeEnemy.new()
	# Прямо по направлению, но за радиусом hitbox'а.
	enemy.global_position = Vector2(60, 0)
	add_child_autofree(enemy)
	var source := _make_owner_player()
	_spawn_arc_hitbox(source, Vector2.RIGHT, 3, 40.0, 0.2, 80.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(enemy.hits_received, 0,
		"enemy за радиусом сектора не должен быть задет")

func test_arc_hitbox_wide_sector_hits_side_enemy() -> void:
	# С аркой 200° перпендикулярный enemy уже попадает в сектор.
	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(0, 15)
	add_child_autofree(enemy)
	var source := _make_owner_player()
	_spawn_arc_hitbox(source, Vector2.RIGHT, 2, 40.0, 0.2, 200.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(enemy.hits_received, 1,
		"с широким сектором 200° перпендикулярный enemy попадает в дугу")

func test_arc_hitbox_positioned_at_source_not_offset() -> void:
	# Регресс: arc-hitbox стоит В игроке (сектор круга «расходится» от него),
	# не в length/2 вперёд. Иначе angular-filter считал бы угол от неверной
	# точки и вырезал бы неправильные тела.
	var source := _make_owner_player()
	source.global_position = Vector2(100, 100)
	var hb := _spawn_arc_hitbox(source, Vector2.RIGHT, 1, 40.0, 0.2, 80.0)
	assert_almost_eq(hb.global_position.x, 100.0, 0.5,
		"arc hitbox global_position совпадает с source (сектор идёт из игрока)")
	assert_almost_eq(hb.global_position.y, 100.0, 0.5)

func test_thrust_hitbox_positioned_in_front_of_source() -> void:
	# thrust — прямоугольник перед игроком: центр на source + direction × length/2.
	var source := _make_owner_player()
	source.global_position = Vector2(100, 100)
	var hb := _spawn_thrust_hitbox(source, Vector2.RIGHT, 1, 40.0, 20.0, 0.15)
	assert_almost_eq(hb.global_position.x, 120.0, 0.5,
		"thrust hitbox центр = source + direction × length/2 = 100 + 20 = 120")
	assert_almost_eq(hb.global_position.y, 100.0, 0.5)

func test_thrust_hitbox_damages_enemy_in_narrow_box() -> void:
	# thrust: длинный узкий rect. Enemy прямо по линии → hit, enemy сбоку — нет.
	var enemy_forward := FakeEnemy.new()
	enemy_forward.global_position = Vector2(20, 0)
	add_child_autofree(enemy_forward)
	var enemy_side := FakeEnemy.new()
	# Далеко в сторону от узкого копья (width=10, значит боковой предел ±5).
	enemy_side.global_position = Vector2(20, 20)
	add_child_autofree(enemy_side)
	var source := _make_owner_player()
	_spawn_thrust_hitbox(source, Vector2.RIGHT, 2, 50.0, 10.0, 0.2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(enemy_forward.hits_received, 1, "enemy на линии копья — задет")
	assert_eq(enemy_side.hits_received, 0,
		"enemy сбоку от узкого копья не должен получать урон")

func test_hitbox_does_not_double_hit_same_enemy() -> void:
	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(20, 0)
	add_child_autofree(enemy)
	var source := _make_owner_player()
	_spawn_arc_hitbox(source, Vector2.RIGHT, 3, 40.0, 0.2, 80.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(enemy.hits_received, 1,
		"один swing = один удар, не пульсирует")

func test_hitbox_queues_free_after_visual_life() -> void:
	# active_time = 0.03s, visual тянется дольше (MIN_VISUAL_LIFE = 0.16),
	# но total < 0.25s. Даём с запасом.
	var source := _make_owner_player()
	var hb := _spawn_arc_hitbox(source, Vector2.RIGHT, 1, 30.0, 0.03, 80.0)
	await get_tree().create_timer(0.25).timeout
	assert_false(is_instance_valid(hb),
		"hitbox должен быть freed после _visual_life (≥ MIN_VISUAL_LIFE)")

func test_hitbox_ignores_player_group() -> void:
	# Регресс: hitbox не бьёт самого игрока (даже если тот в overlap).
	var enemy_like_player := FakeEnemy.new()
	enemy_like_player.global_position = Vector2(10, 0)
	enemy_like_player.add_to_group("player")
	# Умышленно оставим также в enemy — тест защищает от того, чтобы
	# игрок случайно попал под damage.
	add_child_autofree(enemy_like_player)
	var source := _make_owner_player()
	_spawn_arc_hitbox(source, Vector2.RIGHT, 5, 40.0, 0.15, 80.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(enemy_like_player.hits_received, 0,
		"hitbox не должен бить группу player")

func test_arc_hitbox_does_not_hit_enemy_through_wall() -> void:
	# Регресс: без LoS-фильтра arc-хитбокс (Area2D overlap) бил врагов
	# за стеной, потому что overlap чисто геометрический. Теперь LoS-check
	# отсекает такие удары.
	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(30, 0)
	add_child_autofree(enemy)
	_make_wall(Vector2(15, 0), Vector2(6, 40))
	var source := _make_owner_player()
	_spawn_arc_hitbox(source, Vector2.RIGHT, 3, 60.0, 0.2, 80.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(enemy.hits_received, 0,
		"стена между игроком и врагом должна блокировать arc-удар")

func test_thrust_hitbox_does_not_hit_enemy_through_wall() -> void:
	# То же самое для thrust: длинный узкий прямоугольник геометрически
	# накрывает врага за стеной, но LoS должен отсечь.
	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(40, 0)
	add_child_autofree(enemy)
	_make_wall(Vector2(20, 0), Vector2(6, 30))
	var source := _make_owner_player()
	_spawn_thrust_hitbox(source, Vector2.RIGHT, 2, 60.0, 20.0, 0.2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(enemy.hits_received, 0,
		"стена перед врагом должна блокировать thrust-удар")

func test_arc_hitbox_direction_up_hits_enemy_above() -> void:
	# Регресс: при direction UP (0, -1) angular filter должен ловить врагов
	# выше игрока, а не только справа. Проверяем что rotation Area2D
	# корректно ориентирует локальный +X на направление атаки.
	var enemy := FakeEnemy.new()
	enemy.global_position = Vector2(0, -20)
	add_child_autofree(enemy)
	var source := _make_owner_player()
	_spawn_arc_hitbox(source, Vector2.UP, 2, 40.0, 0.2, 80.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(enemy.hits_received, 1,
		"arc с direction UP должен бить врага над игроком")
