extends GutTest

# Necromancer помимо radial-залпа стреляет прицельным aimed-снарядом (как
# обычный лич) с упреждением по вектору движения игрока. После PR 4 aimed
# управляется scheduler-state-machine: AIMED_TELEGRAPH (0.45s) → fire →
# AIMED_RECOVERY (0.35s). Damage растёт от phase 1 (2) к phase 2/3 (3).
# Cadence: phase 1/2 = 1.8 s, phase 3 = 1.2 s.

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

func test_aimed_interval_shortens_in_phase_three() -> void:
	# Плановый инвариант: в phase 3 aimed cadence немного быстрее, но
	# damage per hit не увеличивается сверх phase 2 cap.
	var boss = _spawn_boss()
	boss.current_phase = 1
	assert_almost_eq(boss._aimed_interval_for_phase(), boss.AIMED_INTERVAL_PHASE1, 0.001)
	boss.current_phase = 2
	assert_almost_eq(boss._aimed_interval_for_phase(), boss.AIMED_INTERVAL_PHASE2, 0.001)
	boss.current_phase = 3
	assert_almost_eq(boss._aimed_interval_for_phase(), boss.AIMED_INTERVAL_PHASE3, 0.001,
		"phase 3 использует более короткий cooldown между aimed'ами")
	assert_lt(boss.AIMED_INTERVAL_PHASE3, boss.AIMED_INTERVAL_PHASE1,
		"phase 3 aimed interval < phase 1 aimed interval")

func test_aimed_damage_scales_up_at_phase_two_but_capped() -> void:
	# Плановый cap: aimed damage не выше 2–3 (не ваншот). Phase 1 = 2,
	# phase 2/3 = 3.
	var boss = _spawn_boss()
	boss.current_phase = 1
	assert_eq(boss._aimed_damage_for_phase(), boss.AIMED_BULLET_DAMAGE_PHASE1,
		"phase 1 aimed damage = мягкий cap 2")
	boss.current_phase = 2
	assert_eq(boss._aimed_damage_for_phase(), boss.AIMED_BULLET_DAMAGE_PHASE23,
		"phase 2 aimed damage = 3")
	boss.current_phase = 3
	assert_eq(boss._aimed_damage_for_phase(), boss.AIMED_BULLET_DAMAGE_PHASE23,
		"phase 3 aimed damage не превышает phase 2 (плановый инвариант «damage single-hit не растёт»)")
	assert_lte(boss.AIMED_BULLET_DAMAGE_PHASE23, 3,
		"aimed damage cap = 3 (плановый invariant)")
