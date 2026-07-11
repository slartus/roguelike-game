extends GutTest

# Проверки интеграции planner'а с Floor.gd и AStar:
# - blocked_cells пробрасываются в AStarGrid2D через set_point_solid;
# - все двери одной комнаты связаны через свободные клетки после placement;
# - decals не изменяют AStar solid статус;
# - existing dungeon tests остаются зелёными (см. test_dungeon_generator.gd).

const _PLANNER := preload("res://scenes/dungeon/room_decoration_planner.gd")
const _CATALOG := preload("res://scenes/dungeon/environment_prop_catalog.gd")
const _FLOOR_SCENE: PackedScene = preload("res://scenes/dungeon/floor.tscn")

const TILE := 20

var _snapshot: Dictionary

func before_each() -> void:
	_CATALOG._reset_for_tests()
	_snapshot = {
		"floor": GameState.current_floor_number,
		"seed": GameState.tower_seed,
	}

func after_each() -> void:
	GameState.current_floor_number = _snapshot["floor"]
	GameState.tower_seed = _snapshot["seed"]

# --- Integration через Floor scene --------------------------------------

func test_astar_marks_blocking_prop_cells_as_solid() -> void:
	# Инстанциируем реальный Floor: он вызовет planner, поставит props
	# и построит AStar. blocked_cells должны совпасть с solid points.
	# Guard: на floor 4 (residential) BSP гарантированно даёт 3+ комнаты,
	# в которых planner расставит blocking мебель — если blocked_cells
	# пустой, тест не был бы информативен.
	GameState.tower_seed = 20250711
	GameState.current_floor_number = 4  # residential zone → жилые
	var floor_node = _FLOOR_SCENE.instantiate()
	add_child_autofree(floor_node)
	await get_tree().process_frame
	assert_not_null(floor_node.floor_plan, "floor_plan должен быть построен в _ready")
	assert_not_null(floor_node.astar_grid, "astar_grid должен быть построен")
	assert_gt(floor_node.floor_plan.blocked_cells.size(), 0,
		"на residential floor 4 planner должен разместить хотя бы один blocking prop")
	for cell in floor_node.floor_plan.blocked_cells.keys():
		if not floor_node.astar_grid.region.has_point(cell):
			continue
		assert_true(floor_node.astar_grid.is_point_solid(cell),
			"AStar не отметил blocking prop cell %s как solid" % cell)

func test_astar_leaves_decal_cells_walkable() -> void:
	# Клетки decals (floor_decal) не должны быть solid — иначе враги не
	# смогут пройти через ковёр или кости.
	GameState.tower_seed = 20250711
	GameState.current_floor_number = 4
	var floor_node = _FLOOR_SCENE.instantiate()
	add_child_autofree(floor_node)
	await get_tree().process_frame
	# Основной инвариант — ни один декал не имеет blocks_movement. Даже
	# если на конкретном floor'е декалы не появились в placements, catalog
	# сам должен гарантировать это свойство. Проверяем и placements, и
	# catalog — так тест не становится silent-green при отсутствии decals
	# на конкретном layout.
	for placement in floor_node.floor_plan.placements:
		if not placement.def.is_floor_decal():
			continue
		assert_false(placement.def.blocks_movement,
			"floor_decal %s был помечен как blocks_movement" % placement.def.id)
		for offset_x in placement.footprint_cells.x:
			for offset_y in placement.footprint_cells.y:
				var cell: Vector2i = placement.cell_origin + Vector2i(offset_x, offset_y)
				assert_false(floor_node.floor_plan.blocked_cells.has(cell),
					"decal cell %s не должна быть в blocked_cells" % cell)
	# Catalog-level инвариант: все определения категории FLOOR_DECAL
	# non-blocking. Даже если ни одного декала на этом floor'е нет,
	# контракт каталога проверен.
	var _DEF := preload("res://scenes/dungeon/environment_prop_definition.gd")
	var _CATALOG := preload("res://scenes/dungeon/environment_prop_catalog.gd")
	var decal_defs_checked := 0
	for def in _CATALOG.all_definitions():
		var d: EnvironmentPropDefinition = def
		if d.category != _DEF.CATEGORY_FLOOR_DECAL:
			continue
		decal_defs_checked += 1
		assert_false(d.blocks_movement,
			"floor_decal definition %s не должен иметь blocks_movement" % d.id)
	assert_gt(decal_defs_checked, 0,
		"каталог должен содержать хотя бы один floor_decal")

func test_all_doors_of_room_remain_connected() -> void:
	# Основной инвариант: планировщик не должен перекрыть маршрут между
	# двумя дверьми одной комнаты. Проверяем через реальный layout — берём
	# первую комнату с 2+ door anchors.
	GameState.tower_seed = 987654
	GameState.current_floor_number = 5
	var DungeonGeneratorClass := preload("res://scenes/dungeon/dungeon_generator.gd")
	var gen := DungeonGeneratorClass.new()
	var layout: DungeonLayout = gen.generate(GameState.tower_seed, GameState.current_floor_number, false)
	var reservations: Dictionary = {}
	var plan := _PLANNER.plan_floor(layout, reservations, GameState.tower_seed, GameState.current_floor_number)
	# Для каждой комнаты вычисляем anchors и проверяем BFS-connectivity.
	for room_index in layout.rooms.size():
		var room: Rect2i = layout.rooms[room_index]
		var doors := _room_door_cells_for_test(room, layout.corridors)
		if doors.size() < 2:
			continue
		assert_true(_bfs_check(room, doors, plan.blocked_cells),
			"комната %d потеряла связность между doorway cells %s" % [room_index, doors])

# --- BFS-helper для теста -------------------------------------------------

func _room_door_cells_for_test(room: Rect2i, corridors: Array[Rect2i]) -> Array:
	# Копия внутренней логики RoomDecorationPlanner._room_door_cells —
	# нужна тесту для независимой проверки.
	var room_cells := Rect2i(room.position / TILE, room.size / TILE)
	var anchors: Array = []
	for corridor in corridors:
		var corr_cells := Rect2i(corridor.position / TILE, corridor.size / TILE)
		for cy in range(corr_cells.position.y, corr_cells.position.y + corr_cells.size.y):
			for cx in range(corr_cells.position.x, corr_cells.position.x + corr_cells.size.x):
				for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var neighbor: Vector2i = Vector2i(cx, cy) + offset
					if _cell_in_rect(neighbor, room_cells):
						if not anchors.has(neighbor):
							anchors.append(neighbor)
	return anchors

func _cell_in_rect(cell: Vector2i, rect_cells: Rect2i) -> bool:
	if cell.x < rect_cells.position.x or cell.x >= rect_cells.position.x + rect_cells.size.x:
		return false
	if cell.y < rect_cells.position.y or cell.y >= rect_cells.position.y + rect_cells.size.y:
		return false
	return true

func _bfs_check(room: Rect2i, doors: Array, blocked: Dictionary) -> bool:
	# BFS от doors[0] к остальным. Все anchors должны быть достижимы.
	var room_cells := Rect2i(room.position / TILE, room.size / TILE)
	var visited: Dictionary = {}
	visited[doors[0]] = true
	var queue: Array = [doors[0]]
	while queue.size() > 0:
		var cell: Vector2i = queue.pop_front()
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next_cell: Vector2i = cell + offset
			if visited.has(next_cell):
				continue
			if not _cell_in_rect(next_cell, room_cells) and not doors.has(next_cell):
				continue
			if blocked.has(next_cell):
				continue
			visited[next_cell] = true
			queue.append(next_cell)
	for door in doors:
		if not visited.has(door):
			return false
	return true
