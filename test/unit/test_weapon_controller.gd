extends GutTest

# WeaponController — единая точка атаки. Проверяем:
# - try_attack(null, ...) — no-op / false;
# - projectile weapon создаёт нужное количество снарядов;
# - несколько projectiles со spread не крешит;
# - cooldown блокирует повторную атаку;
# - после cooldown атака снова возможна;
# - Player делегирует атаку через контроллер без ошибок.

const BulletScene = preload("res://scenes/bullets/bullet.tscn")
const WeaponControllerScript = preload("res://scenes/player/weapon_controller.gd")

func _make_projectile_weapon(count: int, spread_deg: float = 0.0) -> WeaponResource:
	var w := WeaponResource.new()
	w.id = "test_ranged"
	w.style = "archer"
	w.attack_type = "projectile"
	w.damage = 1
	w.attack_interval = 0.5
	w.projectile_speed = 200.0
	w.projectile_lifetime = 0.8
	w.projectiles_per_attack = count
	w.spread_angle_deg = spread_deg
	return w

func _make_controller() -> WeaponController:
	# WeaponController requires owner_player. Делаем fake через простой Node2D.
	var owner_player := CharacterBody2D.new()
	owner_player.global_position = Vector2.ZERO
	add_child_autofree(owner_player)
	var wc: WeaponController = WeaponControllerScript.new()
	wc.default_projectile_scene = BulletScene
	owner_player.add_child(wc)
	wc.setup(owner_player)
	return wc

func _count_bullets_globally() -> int:
	# WeaponController кладёт пули в `get_tree().current_scene`, а в тестах
	# им может быть GUT root, а не наш локальный parent. Рекурсивный обход
	# всего дерева ловит их независимо от места.
	return _count_recursively(get_tree().root)

func _count_recursively(node: Node) -> int:
	var n := 0
	if node.has_method("apply_weapon"):
		n += 1
	for child in node.get_children():
		n += _count_recursively(child)
	return n

func _free_all_bullets() -> void:
	# Освобождаем осиротевшие пули между тестами — иначе следующий тест
	# насчитает и старые тоже.
	for child in get_tree().root.get_children():
		if child.has_method("apply_weapon"):
			child.queue_free()
		else:
			for grandchild in child.get_children():
				if grandchild.has_method("apply_weapon"):
					grandchild.queue_free()

func after_each() -> void:
	_free_all_bullets()

func test_try_attack_returns_false_for_null_weapon() -> void:
	var wc = _make_controller()
	assert_false(wc.try_attack(null, Vector2(10, 0)),
		"null weapon → false, no-op")

func test_projectile_attack_spawns_expected_count() -> void:
	var wc := _make_controller()
	var weapon := _make_projectile_weapon(3, 20.0)
	var before := _count_bullets_globally()
	var attacked := wc.try_attack(weapon, Vector2(100, 0))
	assert_true(attacked, "projectile attack должен пройти")
	var after := _count_bullets_globally()
	assert_eq(after - before, 3,
		"3 projectile должны появиться в дереве")

func test_spread_multiple_projectiles_does_not_crash() -> void:
	var wc = _make_controller()
	var weapon := _make_projectile_weapon(5, 40.0)
	# Просто убеждаемся что не крешит и cooldown встал.
	var ok := wc.try_attack(weapon, Vector2(50, 50))
	assert_true(ok)
	assert_false(wc.is_ready(), "cooldown встал")

func test_cooldown_blocks_second_attack_within_interval() -> void:
	var wc = _make_controller()
	var weapon := _make_projectile_weapon(1)
	assert_true(wc.try_attack(weapon, Vector2(1, 0)))
	# Второй сразу — заблокирован.
	assert_false(wc.try_attack(weapon, Vector2(1, 0)),
		"второй attack до истечения cooldown — false")

func test_cooldown_expires_and_next_attack_succeeds() -> void:
	var wc = _make_controller()
	var weapon := _make_projectile_weapon(1)
	weapon.attack_interval = 0.05
	assert_true(wc.try_attack(weapon, Vector2(1, 0)))
	# Прокрутим _process руками — так же как реальный game loop.
	wc._process(0.1)
	assert_true(wc.is_ready(), "cooldown должен истечь после 0.1s")
	assert_true(wc.try_attack(weapon, Vector2(1, 0)),
		"второй attack после cooldown — true")

func test_process_mode_inherits_pause() -> void:
	# Регресс: WeaponController должен паузиться вместе с игровой сценой.
	# Node по умолчанию имеет process_mode = INHERIT, а SceneTree.paused=true
	# останавливает такие узлы. Убеждаемся что дефолт не изменён руками —
	# иначе cooldown продолжал бы тикать во время паузы, и игрок мог бы
	# «стрелять из будущего» после снятия паузы.
	var wc := _make_controller()
	assert_eq(wc.process_mode, Node.PROCESS_MODE_INHERIT,
		"WeaponController должен паузиться вместе с игровой сценой")

func test_zero_direction_target_returns_false() -> void:
	var wc = _make_controller()
	var weapon := _make_projectile_weapon(1)
	# Target совпадает с owner_player position (0,0).
	assert_false(wc.try_attack(weapon, Vector2.ZERO),
		"нулевое направление — no-op")

func test_melee_types_return_false_until_m3() -> void:
	var wc = _make_controller()
	var w := WeaponResource.new()
	w.attack_type = "melee_arc"
	w.attack_interval = 0.5
	# M2 не реализует melee — вернуть false, cooldown не выставлять.
	assert_false(wc.try_attack(w, Vector2(1, 0)),
		"melee_arc → false в M2 (stub)")
	assert_true(wc.is_ready(),
		"cooldown НЕ должен встать на failed atаку — иначе игрок в M3 залипнет")

func test_no_projectile_scene_and_no_default_returns_false_and_no_cooldown() -> void:
	# Регресс: если weapon.projectile_scene не задан И default пуст, атака
	# должна вернуть false и НЕ ставить cooldown. Иначе игрок «залипает»:
	# cooldown идёт, но пуль нет и понять почему сложно.
	var owner_player := CharacterBody2D.new()
	add_child_autofree(owner_player)
	var wc: WeaponController = WeaponControllerScript.new()
	# default_projectile_scene НЕ выставляем.
	owner_player.add_child(wc)
	wc.setup(owner_player)
	var weapon := _make_projectile_weapon(1)
	# weapon.projectile_scene тоже null (не выставили).
	var attacked := wc.try_attack(weapon, Vector2(10, 0))
	assert_false(attacked, "без scene → false")
	assert_true(wc.is_ready(),
		"cooldown НЕ должен встать на failed атаке — иначе игрок залипнет")

func test_setup_stores_owner_player() -> void:
	# Регресс: setup() выставляет owner_player, без него try_attack молча
	# фейлит на первой же строке.
	var wc: WeaponController = WeaponControllerScript.new()
	add_child_autofree(wc)
	assert_false(wc.try_attack(_make_projectile_weapon(1), Vector2(1, 0)),
		"без setup() — false (owner_player == null)")
