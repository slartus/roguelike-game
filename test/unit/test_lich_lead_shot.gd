extends GutTest

# Lich._compute_lead_direction — pure формула упреждения. Тесты не
# трогают _shoot целиком (там get_tree().current_scene = null в GUT),
# а проверяют только расчёт направления по target position + velocity.
#
# Формула: time_to_hit = distance / BULLET_SPEED_FOR_LEAD (110).
# predicted = target_pos + target_velocity * time_to_hit.
# direction = (predicted - lich.pos).normalized().

const LichScene = preload("res://scenes/enemies/lich.tscn")

func _spawn_lich() -> Node:
	var lich = LichScene.instantiate()
	add_child_autofree(lich)
	return lich

func test_zero_velocity_aims_directly_at_target() -> void:
	# velocity=0 — direction смотрит прямо в target position.
	var lich = _spawn_lich()
	lich.global_position = Vector2.ZERO
	var dir: Vector2 = lich._compute_lead_direction(Vector2(0, 100), Vector2.ZERO)
	assert_almost_eq(dir.x, 0.0, 0.001,
		"velocity=0 — direction.x = 0 (без упреждения)")
	assert_almost_eq(dir.y, 1.0, 0.001,
		"velocity=0 — direction.y = 1 (прямо на юг)")

func test_perpendicular_velocity_offsets_direction() -> void:
	# Игрок южнее (0, 100), движется вправо со скоростью 50.
	# Без упреждения direction (0, 1). С упреждением direction смещён вправо.
	var lich = _spawn_lich()
	lich.global_position = Vector2.ZERO
	var dir: Vector2 = lich._compute_lead_direction(Vector2(0, 100), Vector2(50, 0))
	assert_gt(dir.x, 0.3,
		"movement по x → direction.x значительно положителен")
	assert_gt(dir.y, 0.5,
		"y-составляющая всё ещё доминирует (игрок не улетает быстрее пули)")

func test_lead_matches_predicted_position() -> void:
	# distance=100, bullet_speed=110, velocity=(50,0)
	# → time_to_hit = 100/110 ≈ 0.9091
	# → predicted = (0 + 50*0.9091, 100) ≈ (45.45, 100)
	# → direction ≈ (0.414, 0.910)
	var lich = _spawn_lich()
	lich.global_position = Vector2.ZERO
	var dir: Vector2 = lich._compute_lead_direction(Vector2(0, 100), Vector2(50, 0))
	var expected_predicted := Vector2(50.0 * (100.0 / 110.0), 100.0)
	var expected_dir := expected_predicted.normalized()
	assert_almost_eq(dir.x, expected_dir.x, 0.01,
		"direction.x соответствует формуле")
	assert_almost_eq(dir.y, expected_dir.y, 0.01,
		"direction.y соответствует формуле")

func test_target_at_lich_position_returns_zero() -> void:
	# Guard: target совпадает с лицом → нет смысла стрелять.
	var lich = _spawn_lich()
	lich.global_position = Vector2(50, 50)
	var dir: Vector2 = lich._compute_lead_direction(Vector2(50, 50), Vector2(10, 0))
	assert_eq(dir, Vector2.ZERO,
		"distance=0 → возвращаем ZERO, _shoot не создаст пулю")

func test_velocity_towards_lich_shortens_lead() -> void:
	# Игрок движется НА лича — lead должен всё равно попадать в направлении
	# игрока, потому что predicted позиция окажется ближе к лицу.
	var lich = _spawn_lich()
	lich.global_position = Vector2.ZERO
	# Игрок в (100, 0), движется в (-40, 0) — к лицу.
	var dir: Vector2 = lich._compute_lead_direction(Vector2(100, 0), Vector2(-40, 0))
	assert_almost_eq(dir.x, 1.0, 0.001,
		"direction всё равно правый (на игрока), y=0 (позиция на линии)")
	assert_almost_eq(dir.y, 0.0, 0.001)
