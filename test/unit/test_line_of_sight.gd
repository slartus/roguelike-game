extends GutTest

# Контракт LineOfSight.is_clear:
# - без стены — clear (можно бить/видеть);
# - есть стена (StaticBody2D) между from и to — заблокировано;
# - Area2D (pickup, другая паутина) не считаются препятствиями;
# - world_2d == null — fail-open, чтобы тесты без физики не ломались;
# - `exclude` действительно пропускает указанные тела и не считает их стеной.

func _make_wall(pos: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.global_position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	add_child_autofree(wall)
	return wall

func _world() -> World2D:
	return get_tree().root.world_2d

func test_no_wall_returns_clear() -> void:
	await get_tree().physics_frame
	assert_true(
		LineOfSight.is_clear(_world(), Vector2(0, 0), Vector2(100, 0)),
		"без стен между двумя точками LoS должен быть свободен"
	)

func test_wall_between_blocks() -> void:
	_make_wall(Vector2(50, 0), Vector2(10, 40))
	await get_tree().physics_frame
	assert_false(
		LineOfSight.is_clear(_world(), Vector2(0, 0), Vector2(100, 0)),
		"стена между from и to должна блокировать LoS"
	)

func test_wall_off_line_does_not_block() -> void:
	# Стена выше линии луча — не должна перекрывать.
	_make_wall(Vector2(50, 60), Vector2(10, 10))
	await get_tree().physics_frame
	assert_true(
		LineOfSight.is_clear(_world(), Vector2(0, 0), Vector2(100, 0)),
		"стена в стороне от луча не должна блокировать LoS"
	)

func test_null_world_returns_clear() -> void:
	# Fail-open: без world_2d считаем «видно», иначе тесты без физики
	# начнут ложно проваливать damage-контракт.
	assert_true(
		LineOfSight.is_clear(null, Vector2(0, 0), Vector2(100, 0)),
		"null world_2d → fail-open"
	)

func test_area2d_does_not_block() -> void:
	# Pickup'ы и другие Area2D — не физическая стена. collide_with_areas=false
	# в query, поэтому Area2D игнорируется даже если пересекает линию.
	var area := Area2D.new()
	area.global_position = Vector2(50, 0)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 20.0
	shape.shape = circle
	area.add_child(shape)
	add_child_autofree(area)
	await get_tree().physics_frame
	assert_true(
		LineOfSight.is_clear(_world(), Vector2(0, 0), Vector2(100, 0)),
		"Area2D не должна блокировать LoS — только StaticBody2D"
	)

func test_exclude_ignores_own_body() -> void:
	# Симулируем «враг с мечом» — StaticBody2D на пути, но она сам источник
	# луча (exclude). Не должна блокировать.
	var self_body := _make_wall(Vector2(10, 0), Vector2(5, 5))
	await get_tree().physics_frame
	assert_true(
		LineOfSight.is_clear(
			_world(), Vector2(0, 0), Vector2(100, 0), [self_body.get_rid()]
		),
		"exclude должен пропускать собственный body"
	)
