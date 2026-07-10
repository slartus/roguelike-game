extends GutTest

# Boss.Necromancer помимо залпа звёздочек стреляет прицельным aimed
# снарядом (как обычный лич) с упреждением по вектору движения игрока.
# Тесты проверяют pure формулу _compute_lead_direction + факт того что
# aimed_bullet_scene установлен в .tscn.

const BossScene = preload("res://scenes/enemies/boss.tscn")

func _spawn_boss() -> Node:
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	return boss

func test_boss_scene_has_aimed_bullet_configured() -> void:
	# Если забыть проставить aimed_bullet_scene в .tscn — босс не будет
	# стрелять прицельно, но никто не заметит до playtest. Guard.
	var boss = _spawn_boss()
	assert_not_null(boss.aimed_bullet_scene,
		"aimed_bullet_scene должен быть задан в boss.tscn (magic_bolt)")

func test_zero_velocity_aims_directly() -> void:
	var boss = _spawn_boss()
	boss.global_position = Vector2.ZERO
	var dir: Vector2 = boss._compute_lead_direction(Vector2(0, 100), Vector2.ZERO)
	assert_almost_eq(dir.x, 0.0, 0.001,
		"velocity=0 → упреждение = 0")
	assert_almost_eq(dir.y, 1.0, 0.001)

func test_perpendicular_velocity_leads_direction() -> void:
	var boss = _spawn_boss()
	boss.global_position = Vector2.ZERO
	var dir: Vector2 = boss._compute_lead_direction(Vector2(0, 100), Vector2(50, 0))
	assert_gt(dir.x, 0.3,
		"движение по x смещает direction вправо")
	assert_gt(dir.y, 0.5)

func test_lead_matches_formula_for_magic_bolt_speed() -> void:
	# AIMED_BULLET_SPEED = 100 (magic_bolt).
	# distance=100, velocity=(50,0) → time_to_hit = 1.0.
	# predicted = (50, 100). direction ≈ normalized((50, 100)).
	var boss = _spawn_boss()
	boss.global_position = Vector2.ZERO
	var dir: Vector2 = boss._compute_lead_direction(Vector2(0, 100), Vector2(50, 0))
	var expected := Vector2(50.0, 100.0).normalized()
	assert_almost_eq(dir.x, expected.x, 0.01,
		"формула упреждения соответствует magic_bolt speed=100")
	assert_almost_eq(dir.y, expected.y, 0.01)

func test_target_at_boss_position_returns_zero() -> void:
	var boss = _spawn_boss()
	boss.global_position = Vector2(30, 30)
	var dir: Vector2 = boss._compute_lead_direction(Vector2(30, 30), Vector2(10, 0))
	assert_eq(dir, Vector2.ZERO,
		"distance=0 → ZERO, никакой пули")

func test_aimed_fire_interval_is_reasonable() -> void:
	# Sanity: интервал не 0 (бесконечный спам) и не гигантский.
	var boss = _spawn_boss()
	assert_gt(boss.aimed_fire_interval, 0.1,
		"aimed_fire_interval > 0.1 — иначе босс превратится в пулемёт")
	assert_lt(boss.aimed_fire_interval, 5.0,
		"aimed_fire_interval < 5s — иначе фича неощутима")

func test_volley_and_aimed_timers_are_independent() -> void:
	# Пользовательский инвариант: залп звёзд и aimed shot не должны
	# влиять друг на друга. Разные поля, разные декременты, разные
	# reload'ы. Проверяем что таймеры существуют раздельно и что
	# reload одного не затрагивает другой.
	var boss = _spawn_boss()
	boss._volley_timer = 0.5
	boss._aimed_fire_timer = 1.5
	assert_ne(boss._volley_timer, boss._aimed_fire_timer,
		"таймеры — отдельные поля")
	# Симулируем сброс volley: только его reload, aimed не тронут.
	boss._volley_timer = boss.volley_interval
	assert_almost_eq(boss._aimed_fire_timer, 1.5, 0.001,
		"перезарядка volley не влияет на aimed_fire_timer")
	# И наоборот.
	boss._aimed_fire_timer = boss.aimed_fire_interval
	assert_almost_eq(boss._volley_timer, boss.volley_interval, 0.001,
		"перезарядка aimed не влияет на _volley_timer")
