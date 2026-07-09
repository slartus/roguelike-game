extends GutTest

# Ranged-враги (Skeleton Archer, Lich) в состоянии «игрок вне
# perception» должны бродить, а не стоять столбом. Контракт:
# - _wander_direction устанавливается ненулевым при первом тике;
# - velocity получает direction * speed * wander_speed_ratio (< speed);
# - fire_timer НЕ убывает (стрельба только при активной цели);
# - при отсутствии игрока (в группе нет player) — тоже бродим.

const RangedScene = preload("res://scenes/enemies/ranged_enemy.tscn")

func _create_fake_player(pos: Vector2) -> Node2D:
	var p := Node2D.new()
	p.global_position = pos
	p.add_to_group("player")
	add_child_autofree(p)
	return p

func test_ranged_wanders_when_player_far_beyond_perception() -> void:
	# perception=200. Игрок на 500 — вне видимости.
	_create_fake_player(Vector2(500, 0))
	var enemy = RangedScene.instantiate()
	enemy.global_position = Vector2.ZERO
	add_child_autofree(enemy)
	enemy._physics_process(0.016)
	assert_ne(enemy.velocity, Vector2.ZERO,
		"когда игрок вне perception, ranged должен бродить, а не стоять")
	# Скорость приглушённая (< speed).
	assert_lt(enemy.velocity.length(), enemy.speed,
		"wander-скорость должна быть меньше speed (wander_speed_ratio=0.4)")

func test_ranged_wanders_when_no_player_in_scene() -> void:
	# Игрока нет в группе — _find_player возвращает null,
	# ranged должен бродить, а не стоять.
	var enemy = RangedScene.instantiate()
	enemy.global_position = Vector2.ZERO
	add_child_autofree(enemy)
	enemy._physics_process(0.016)
	assert_ne(enemy._wander_direction, Vector2.ZERO,
		"без игрока _wander_direction должно быть выбрано")

func test_wander_fire_timer_does_not_tick() -> void:
	# Регресс: раньше test_ranged_does_not_shoot_outside_perception
	# проверял velocity=0 и fire_timer стабильный. Теперь velocity
	# ненулевая (бродим), но fire_timer всё равно НЕ должен убывать —
	# стреляем только при активной цели.
	_create_fake_player(Vector2(500, 0))
	var enemy = RangedScene.instantiate()
	enemy.global_position = Vector2.ZERO
	add_child_autofree(enemy)
	var timer_before: float = enemy._fire_timer
	enemy._physics_process(0.016)
	assert_eq(enemy._fire_timer, timer_before,
		"fire_timer не должен убывать в wander-режиме")

func test_pick_wander_direction_is_unit_vector() -> void:
	var enemy = RangedScene.instantiate()
	add_child_autofree(enemy)
	enemy._pick_wander_direction()
	assert_almost_eq(enemy._wander_direction.length(), 1.0, 0.001,
		"_wander_direction должно быть единичным вектором")
