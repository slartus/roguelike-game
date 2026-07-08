extends GutTest

# Тесты kiting-поведения Ranged-врагов (Skeleton Archer, Lich).
#
# Проверяем что velocity после _physics_process корректно указывает
# в сторону игрока (dist > preferred_range), в противоположную
# сторону (dist < min_range) или нулевая (в диапазоне).

const RangedScene = preload("res://scenes/enemies/ranged_enemy.tscn")
const LichScene = preload("res://scenes/enemies/lich.tscn")

func _create_fake_player(pos: Vector2) -> Node2D:
	var p := Node2D.new()
	p.global_position = pos
	p.add_to_group("player")
	add_child_autofree(p)
	return p

func test_ranged_moves_toward_player_when_beyond_preferred_range() -> void:
	_create_fake_player(Vector2(180, 0))   # dist 180 > preferred 160
	var enemy = RangedScene.instantiate()
	enemy.global_position = Vector2.ZERO
	add_child_autofree(enemy)
	# Direct вызов надёжнее чем await physics_frame в GUT.
	enemy._physics_process(0.016)
	assert_gt(enemy.velocity.x, 0.0,
		"Skeleton Archer должен идти к игроку когда dist > preferred_range (180 > 160)")

func test_ranged_retreats_when_within_min_range() -> void:
	_create_fake_player(Vector2(50, 0))    # dist 50 < min 100
	var enemy = RangedScene.instantiate()
	enemy.global_position = Vector2.ZERO
	add_child_autofree(enemy)
	enemy._physics_process(0.016)
	assert_lt(enemy.velocity.x, 0.0,
		"Skeleton Archer должен отступать когда dist < min_range (50 < 100)")

func test_ranged_stands_still_in_preferred_band() -> void:
	_create_fake_player(Vector2(130, 0))   # 100 <= 130 <= 160
	var enemy = RangedScene.instantiate()
	enemy.global_position = Vector2.ZERO
	add_child_autofree(enemy)
	enemy._physics_process(0.016)
	assert_eq(enemy.velocity, Vector2.ZERO,
		"Skeleton Archer стоит когда dist в [min_range, preferred_range]")

func test_lich_kites_at_closer_range_than_archer() -> void:
	# Lich имеет preferred_range = 130 (vs archer 160) — держится ближе.
	var lich = LichScene.instantiate()
	var archer = RangedScene.instantiate()
	assert_lt(lich.preferred_range, archer.preferred_range,
		"Lich preferred_range должен быть меньше archer")
	assert_lt(lich.min_range, archer.min_range,
		"Lich min_range должен быть меньше archer")
	lich.free()
	archer.free()

func test_ranged_ranges_are_consistent() -> void:
	# Инвариант: min < preferred, speed > 0 для обеих сцен.
	for scene in [RangedScene, LichScene]:
		var e = scene.instantiate()
		assert_lt(e.min_range, e.preferred_range,
			"%s min_range < preferred_range" % scene.resource_path)
		assert_gt(e.speed, 0.0,
			"%s speed > 0" % scene.resource_path)
		e.free()

func test_ranged_does_not_shoot_outside_perception() -> void:
	# Игрок вне perception (200) — timer не должен тикать / стрелять.
	_create_fake_player(Vector2(500, 0))   # 500 > 200
	var enemy = RangedScene.instantiate()
	enemy.global_position = Vector2.ZERO
	add_child_autofree(enemy)
	var timer_before = enemy._fire_timer
	enemy._physics_process(0.016)
	# Timer должен остаться прежним (не декрементился)
	assert_eq(enemy._fire_timer, timer_before,
		"fire_timer не должен убывать когда игрок вне perception")
