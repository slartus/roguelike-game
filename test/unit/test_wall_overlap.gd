extends GutTest

# Стены толщиной 2+ tile имеют «cap» — верхний ряд, у которого своя
# текстура-«козырёк», но такая же коллизия, как у solid. Игрок и мобы не
# должны заходить в нижние стены снизу вверх. Тесты проверяют:
# - _wall_kind_at правильно классифицирует cap vs solid;
# - в реальном layout встречается хотя бы один cap tile;
# - _walls_root содержит только StaticBody2D (для обоих видов), без «голых»
#   Polygon2D — иначе cap-клетка окажется без коллизии;
# - AStarGrid pathfinding помечает cap tiles solid наравне с solid.

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

func test_astar_marks_cap_tiles_as_solid() -> void:
	# Cap-tile solid для pathfinding — коллизия у него есть, AI должен
	# обходить её так же, как обычную стену. Иначе AI пойдёт «сквозь»
	# нижнюю кромку, ткнётся в StaticBody2D и застрянет.
	var f = _spawn_floor()
	await get_tree().process_frame
	var bounds = f.layout.floor_bounds
	var cols = int(ceil(float(bounds.size.x) / f.TILE_SIZE))
	var rows = int(ceil(float(bounds.size.y) / f.TILE_SIZE))
	var checked_any := false
	for row in rows:
		for col in cols:
			if f._wall_kind_at(col, row) == "cap":
				assert_true(f.astar_grid.is_point_solid(Vector2i(col, row)),
					"cap tile @(%d,%d) должен быть solid в astar_grid" % [col, row])
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

func test_release_prop_cells_keeps_cap_solid_in_astar() -> void:
	# Инвариант: cap-клетка не разблокируется в AStar даже если рядом
	# «разрушили» проп, чей footprint включал эту клетку. Иначе AI пойдёт
	# сквозь визуальный «козырёк» стены. В живом коде planner не сажает
	# пропы на wall-клетки — инвариант проверяется на инъекцию fake plan.
	var PlannerScript = load("res://scenes/dungeon/room_decoration_planner.gd")
	var f = _spawn_floor()
	await get_tree().process_frame
	var bounds = f.layout.floor_bounds
	var cols = int(ceil(float(bounds.size.x) / f.TILE_SIZE))
	var rows = int(ceil(float(bounds.size.y) / f.TILE_SIZE))
	var cap_cell := Vector2i(-1, -1)
	for row in rows:
		for col in cols:
			if f._wall_kind_at(col, row) == "cap":
				cap_cell = Vector2i(col, row)
				break
		if cap_cell.x >= 0:
			break
	assert_true(cap_cell.x >= 0, "должен быть хотя бы один cap tile")
	assert_true(f.astar_grid.is_point_solid(cap_cell),
		"предусловие: cap_cell должна быть solid в AStar")
	var placement = PlannerScript.Placement.new()
	placement.cell_origin = cap_cell
	placement.footprint_cells = Vector2i(1, 1)
	var fake_plan = PlannerScript.FloorPlan.new()
	fake_plan.placements = [placement]
	fake_plan.blocked_cells = {cap_cell: true}
	f.floor_plan = fake_plan
	f._release_prop_cells(0)
	assert_true(f.astar_grid.is_point_solid(cap_cell),
		"cap_cell должна остаться solid в AStar после разрушения пропа")

func test_walls_root_contains_only_static_bodies() -> void:
	# И solid, и cap теперь оборачиваются в StaticBody2D + CollisionShape2D.
	# «Голых» Polygon2D в WallsRoot быть не должно — это означало бы стену
	# без коллизии, в которую можно зайти снизу.
	var f = _spawn_floor()
	await get_tree().process_frame
	var body_count := 0
	var bare_visual_count := 0
	for child in f._walls_root.get_children():
		if child is StaticBody2D:
			body_count += 1
		elif child is Polygon2D:
			bare_visual_count += 1
	assert_gt(body_count, 0,
		"должна быть хотя бы одна стена (StaticBody2D)")
	assert_eq(bare_visual_count, 0,
		"в WallsRoot не должно быть «голых» Polygon2D — все стены с коллизией")
