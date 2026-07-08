extends GutTest

# Регресс на застревание врагов у стен.
# Melee (enemy.gd) — A* может вернуть пустой путь если start_cell лёг в
# solid ячейку (враг прижался к стене границей клетки), тогда fallback
# на _chase_direct упирается в стену навсегда. Ranged (ranged_enemy.gd)
# ходит только по прямой — стена между целью и врагом = вечный упор.
# Оба случая покрывает stuck-detection: после нескольких кадров с
# заглохшей velocity включается escape в перпендикулярном направлении.

const EnemyScene = preload("res://scenes/enemies/enemy.tscn")
const RangedScene = preload("res://scenes/enemies/ranged_enemy.tscn")

func test_melee_pick_escape_direction_is_perpendicular_to_target() -> void:
	var e = EnemyScene.instantiate()
	add_child_autofree(e)
	var toward := Vector2.RIGHT
	var escape: Vector2 = e._pick_escape_direction(toward)
	assert_almost_eq(escape.length(), 1.0, 0.01, "escape — unit vector")
	assert_almost_eq(toward.dot(escape), 0.0, 0.01,
		"escape должен быть перпендикулярен направлению на цель")

func test_melee_pick_escape_direction_falls_back_to_right_on_zero() -> void:
	var e = EnemyScene.instantiate()
	add_child_autofree(e)
	var escape: Vector2 = e._pick_escape_direction(Vector2.ZERO)
	assert_almost_eq(escape.length(), 1.0, 0.01,
		"escape корректен даже когда direction == ZERO")

func test_melee_stuck_state_triggers_escape_after_timeout() -> void:
	var e = EnemyScene.instantiate()
	add_child_autofree(e)
	# Симулируем «прижались к стене»: velocity сильно ниже speed * ratio.
	e.velocity = Vector2.ZERO
	var to_target := Vector2.RIGHT
	# Один тик — ещё не должен триггернуть.
	e._update_stuck_state(to_target, 0.1)
	assert_eq(e._escape_timer, 0.0,
		"один короткий кадр не должен триггерить escape")
	# После STUCK_TIMEOUT (0.25) escape должен включиться.
	e._update_stuck_state(to_target, 0.2)
	assert_gt(e._escape_timer, 0.0,
		"после STUCK_TIMEOUT escape_timer должен быть выставлен")
	assert_almost_eq(e._escape_direction.length(), 1.0, 0.01,
		"escape_direction — unit vector")

func test_melee_stuck_state_resets_when_moving_normally() -> void:
	var e = EnemyScene.instantiate()
	add_child_autofree(e)
	e.velocity = Vector2.ZERO
	# Копим stuck_timer.
	e._update_stuck_state(Vector2.RIGHT, 0.15)
	assert_gt(e._stuck_timer, 0.0)
	# Затем velocity стала нормальной — таймер должен сброситься.
	e.velocity = Vector2.RIGHT * e.speed
	e._update_stuck_state(Vector2.RIGHT, 0.05)
	assert_eq(e._stuck_timer, 0.0,
		"stuck_timer должен сбрасываться при нормальном движении")

func test_ranged_stuck_state_triggers_escape_when_intended_to_move() -> void:
	var e = RangedScene.instantiate()
	add_child_autofree(e)
	# Симулируем: пытались двигаться (intended_dir != 0), но velocity
	# после slide заглохла (прижались к стене).
	e.velocity = Vector2.ZERO
	e._update_stuck_state(Vector2.RIGHT, 0.2)
	e._update_stuck_state(Vector2.RIGHT, 0.2)
	assert_gt(e._escape_timer, 0.0,
		"ranged должен включить escape после STUCK_TIMEOUT")
	assert_almost_eq(e._escape_direction.length(), 1.0, 0.01)

func test_melee_pick_escape_direction_flips_side_on_repeat() -> void:
	# Если враг только что застревал и escape провалился — следующий
	# _pick_escape_direction обязан вернуть противоположную сторону,
	# чтобы не циклиться в тот же угол.
	var e = EnemyScene.instantiate()
	add_child_autofree(e)
	var first: Vector2 = e._pick_escape_direction(Vector2.RIGHT)
	var second: Vector2 = e._pick_escape_direction(Vector2.RIGHT)
	# Первое escape случайное, второе должно быть -first.
	assert_almost_eq(first.x + second.x, 0.0, 0.01,
		"второй escape при том же _last_escape_side должен быть противоположным")
	assert_almost_eq(first.y + second.y, 0.0, 0.01)

func test_ranged_stuck_state_does_not_trigger_when_intentionally_idle() -> void:
	# На ideal-range ranged штатно стоит (velocity=0, intended_dir=0).
	# Stuck-detection не должен ложно срабатывать.
	var e = RangedScene.instantiate()
	add_child_autofree(e)
	e.velocity = Vector2.ZERO
	for i in 10:
		e._update_stuck_state(Vector2.ZERO, 0.1)
	assert_eq(e._escape_timer, 0.0,
		"ranged на ideal-range не должен триггерить escape")
	assert_eq(e._stuck_timer, 0.0)
