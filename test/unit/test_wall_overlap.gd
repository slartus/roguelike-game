extends GutTest

# Стены толщиной 2+ tile имеют «cap» — верхний ряд без коллизии, чтобы
# персонаж и враги могли зайти под визуальную верхушку сверху вниз на
# 1 tile (эффект глубины top-down). Тесты проверяют:
# - _wall_kind_at правильно классифицирует cap vs solid;
# - в реальном layout встречается хотя бы один cap tile;
# - _walls_root содержит смесь StaticBody2D (solid) и «голых» Polygon2D (cap);
# - AStarGrid pathfinding помечает cap tiles проходимыми.

const FloorScene = preload("res://scenes/dungeon/floor.tscn")

func _spawn_floor():
	# Floor рассчитывает layout из GameState.tower_seed. Устанавливаем
	# известный seed чтобы тест был детерминированным.
	GameState.tower_seed = 42
	GameState.current_floor_number = 4
	var floor_node = FloorScene.instantiate()
	add_child_autofree(floor_node)
	return floor_node

func test_wall_kind_at_returns_cap_for_top_row_of_thick_wall() -> void:
	var f = _spawn_floor()
	await get_tree().process_frame
	# Ищем любой tile который классифицируется как cap: сверху floor,
	# снизу wall. Толстые (2+ tile) стены встречаются при inset=2 на этаже 4.
	var bounds = f.layout.floor_bounds
	var cols = int(ceil(float(bounds.size.x) / f.TILE_SIZE))
	var rows = int(ceil(float(bounds.size.y) / f.TILE_SIZE))
	var found_cap := false
	for row in rows:
		for col in cols:
			if f._wall_kind_at(col, row) == "cap":
				found_cap = true
				# Проверить инвариант: сверху — не wall (floor), снизу — wall.
				var above := Vector2i(col * f.TILE_SIZE + f.TILE_SIZE / 2, (row - 1) * f.TILE_SIZE + f.TILE_SIZE / 2)
				var below := Vector2i(col * f.TILE_SIZE + f.TILE_SIZE / 2, (row + 1) * f.TILE_SIZE + f.TILE_SIZE / 2)
				assert_false(f._is_wall_at(above),
					"cap tile @(%d,%d): tile сверху должен быть floor" % [col, row])
				assert_true(f._is_wall_at(below),
					"cap tile @(%d,%d): tile снизу должен быть wall" % [col, row])
				break
		if found_cap:
			break
	assert_true(found_cap,
		"на floor 4 должна встречаться хотя бы одна 2+ tile стена с cap")

func test_astar_marks_cap_tiles_as_walkable() -> void:
	# Cap-tile проходим для pathfinding — иначе враги-ranged не смогут
	# «зайти» под кромку так же как игрок.
	var f = _spawn_floor()
	await get_tree().process_frame
	var bounds = f.layout.floor_bounds
	var cols = int(ceil(float(bounds.size.x) / f.TILE_SIZE))
	var rows = int(ceil(float(bounds.size.y) / f.TILE_SIZE))
	var checked_any := false
	for row in rows:
		for col in cols:
			if f._wall_kind_at(col, row) == "cap":
				assert_false(f.astar_grid.is_point_solid(Vector2i(col, row)),
					"cap tile @(%d,%d) должен быть проходим в astar_grid" % [col, row])
				checked_any = true
	assert_true(checked_any,
		"должен встретиться хотя бы один cap tile для проверки")

func test_astar_marks_solid_walls_as_solid() -> void:
	# Обычные (solid) wall tiles должны блокировать pathfinding.
	var f = _spawn_floor()
	await get_tree().process_frame
	var bounds = f.layout.floor_bounds
	var cols = int(ceil(float(bounds.size.x) / f.TILE_SIZE))
	var rows = int(ceil(float(bounds.size.y) / f.TILE_SIZE))
	for row in rows:
		for col in cols:
			if f._wall_kind_at(col, row) == "solid":
				assert_true(f.astar_grid.is_point_solid(Vector2i(col, row)),
					"solid wall @(%d,%d) должен быть solid в astar" % [col, row])
				return
	fail_test("должен встретиться хотя бы один solid wall для проверки")

func test_walls_root_contains_both_bodies_and_bare_visuals() -> void:
	# Cap-тайлы рендерятся как «голый» Polygon2D (без body), solid-тайлы
	# — как StaticBody2D с child Polygon2D.
	var f = _spawn_floor()
	await get_tree().process_frame
	var has_body := false
	var has_bare_visual := false
	for child in f._walls_root.get_children():
		if child is StaticBody2D:
			has_body = true
		elif child is Polygon2D:
			has_bare_visual = true
	assert_true(has_body,
		"solid стены должны быть StaticBody2D")
	assert_true(has_bare_visual,
		"cap tiles должны быть чистыми Polygon2D в _walls_root")
