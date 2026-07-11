extends GutTest

# Контракт extended melee-reach в enemy.gd:
# - если attack_radius > 0 и target внутри радиуса — наносится урон
#   даже без физического касания (touch-ветка не сработала);
# - если attack_radius = 0 — reach отключён (только touch);
# - сигнал attack_played эмиттится при каждом успешном ударе;
# - cooldown блокирует повторный урон в течение contact_cooldown.
#
# Тесты идут через enemy.gd напрямую (не skeleton.tscn), чтобы не
# тянуть Balance/GameState scaling — здесь важна геометрия reach,
# а не итоговое число урона.

const EnemyScript = preload("res://scenes/enemies/enemy.gd")

class FakePlayer:
	extends Node2D
	var last_damage: int = 0
	var hit_count: int = 0
	func take_damage(amount: int, _context: DamageContext = null) -> void:
		last_damage = amount
		hit_count += 1

func _spawn_enemy_with_target(attack_radius: float, target_pos: Vector2):
	# Enemy — CharacterBody2D; для теста добавляем в дерево, чтобы у
	# него был доступ к сигналам и таймерам. _physics_process не
	# нужен — дёргаем _handle_player_contact напрямую.
	var enemy = CharacterBody2D.new()
	enemy.set_script(EnemyScript)
	enemy.attack_radius = attack_radius
	enemy.contact_damage = 5
	enemy.contact_cooldown = 0.6
	add_child_autofree(enemy)
	var target = FakePlayer.new()
	target.global_position = target_pos
	add_child_autofree(target)
	enemy._target = target
	return {"enemy": enemy, "target": target}

func test_reach_hits_when_target_inside_radius() -> void:
	var ctx = _spawn_enemy_with_target(20.0, Vector2(15, 0))
	ctx["enemy"]._handle_player_contact()
	assert_eq(ctx["target"].hit_count, 1,
		"меч с reach=20 бьёт цель на расстоянии 15px")
	# Не сравниваем с точным числом: Balance.scaled_damage в _ready
	# домножает contact_damage на floor-scaling, а GameState.current_floor_number
	# может измениться другим тестом. Достаточно факта нанесённого урона.
	assert_gt(ctx["target"].last_damage, 0)

func test_reach_misses_when_target_outside_radius() -> void:
	var ctx = _spawn_enemy_with_target(20.0, Vector2(30, 0))
	ctx["enemy"]._handle_player_contact()
	assert_eq(ctx["target"].hit_count, 0,
		"цель за пределами reach не получает урон")

func test_zero_radius_disables_reach() -> void:
	var ctx = _spawn_enemy_with_target(0.0, Vector2(5, 0))
	ctx["enemy"]._handle_player_contact()
	assert_eq(ctx["target"].hit_count, 0,
		"attack_radius=0 → reach выключен даже если цель рядом")

func test_reach_emits_attack_played_signal() -> void:
	var ctx = _spawn_enemy_with_target(20.0, Vector2(10, 0))
	var received: Array = []
	ctx["enemy"].attack_played.connect(func(pos): received.append(pos))
	ctx["enemy"]._handle_player_contact()
	assert_eq(received.size(), 1, "сигнал attack_played эмиттится раз при ударе")
	assert_eq(received[0], Vector2(10, 0), "передана позиция цели")

func test_reach_respects_contact_cooldown() -> void:
	var ctx = _spawn_enemy_with_target(20.0, Vector2(10, 0))
	ctx["enemy"]._handle_player_contact()
	# Второй вызов сразу после первого — cooldown не истёк.
	ctx["enemy"]._handle_player_contact()
	assert_eq(ctx["target"].hit_count, 1,
		"cooldown блокирует повторный reach-удар до истечения contact_cooldown")

func test_reach_blocked_by_wall_between_enemy_and_target() -> void:
	# Регресс: reach-удар (skeleton'ий меч) через distance-check доставал
	# игрока за стеной. Теперь LoS-check отсекает такой удар — игрок
	# может укрыться за углом даже если формально в attack_radius.
	var ctx = _spawn_enemy_with_target(30.0, Vector2(20, 0))
	var wall := StaticBody2D.new()
	wall.global_position = Vector2(10, 0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(6, 30)
	shape.shape = rect
	wall.add_child(shape)
	add_child_autofree(wall)
	await get_tree().physics_frame
	ctx["enemy"]._handle_player_contact()
	assert_eq(ctx["target"].hit_count, 0,
		"стена между врагом и игроком должна блокировать reach-удар")

func test_skeleton_lunge_animation_hooked_on_attack() -> void:
	# Скелет подписан на attack_played и создаёт tween — визуальный
	# feedback замаха. Проверяем что подписка есть.
	var scene: PackedScene = load("res://scenes/enemies/skeleton.tscn")
	var skeleton = scene.instantiate()
	add_child_autofree(skeleton)
	await get_tree().process_frame
	assert_true(skeleton.attack_played.get_connections().size() > 0,
		"skeleton.gd должен подписаться на attack_played в _ready")
