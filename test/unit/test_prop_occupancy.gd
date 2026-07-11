extends GutTest

# Проверки occupancy grid внутри RoomDecorationPlanner:
# - doorway cells не заняты blocking пропом;
# - entrance/exit clear-zone уважается;
# - chest reservation уважается;
# - enemy spawn reservation уважается;
# - blocking props не пересекаются друг с другом;
# - density не превышает role-specific limit;
# - decal props ставятся, но не блокируют движение.

const _PLANNER := preload("res://scenes/dungeon/room_decoration_planner.gd")
const _CATALOG := preload("res://scenes/dungeon/environment_prop_catalog.gd")
const _DEF := preload("res://scenes/dungeon/environment_prop_definition.gd")

const TILE := 20

func before_each() -> void:
	_CATALOG._reset_for_tests()

func _make_layout_with_corridor(role: String, zone: String) -> DungeonLayout:
	# Комната 8x6 клеток + коридор 2x1, входящий в левую стену.
	var layout := DungeonLayout.new()
	var room_rect := Rect2i(Vector2i(2 * TILE, 0), Vector2i(8 * TILE, 6 * TILE))
	var corridor_rect := Rect2i(Vector2i(0, 2 * TILE), Vector2i(2 * TILE, TILE))
	layout.rooms = [room_rect]
	layout.corridors = [corridor_rect]
	layout.zone = zone
	layout.floor_bounds = Rect2i(Vector2i.ZERO, Vector2i(10 * TILE, 6 * TILE))
	layout.player_start = Vector2i(3 * TILE, 3 * TILE)
	layout.exit_position = Vector2i(9 * TILE, 5 * TILE)
	layout.room_infos = [{
		"room_index": 0,
		"role": role,
		"zone": zone,
		"tags": [],
		"danger": 0,
	}]
	return layout

func test_doorway_cells_not_blocked_by_props() -> void:
	# Doorway anchor должен остаться проходимым: BFS от anchor к центру
	# комнаты не должен упереться в blocking prop прямо на anchor'е.
	var layout := _make_layout_with_corridor("bedroom", "residential")
	var plan := _PLANNER.plan_floor(layout, {}, 12345, 3)
	# Doorway anchor: cell (2, 2) — левый верхний угол room совпадает
	# с corridor exit. Проверим что ни один blocking prop не занял
	# эту клетку.
	var anchor := Vector2i(2, 2)
	assert_false(plan.blocked_cells.has(anchor),
		"doorway anchor не должен быть blocking. blocked=%s" % [plan.blocked_cells.keys()])

func test_entrance_clear_radius_reserved() -> void:
	var layout := _make_layout_with_corridor("bedroom", "residential")
	# Симулируем Floor.gd: player_start=cell(3, 3), radius 2 → 5x5 клеток.
	var reservations: Dictionary = {}
	var center := Vector2i(3, 3)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			reservations[center + Vector2i(dx, dy)] = true
	var plan := _PLANNER.plan_floor(layout, reservations, 12345, 3)
	# Каждый blocked cell не должен быть в reservation.
	for cell in plan.blocked_cells.keys():
		assert_false(reservations.has(cell),
			"blocking prop занял reserved cell рядом с player_start: %s" % cell)

func test_chest_reservation_not_occupied() -> void:
	var layout := _make_layout_with_corridor("storage", "residential")
	layout.chest_positions = [Vector2i(5 * TILE, 3 * TILE)]
	var reservations: Dictionary = {}
	reservations[Vector2i(5, 3)] = true
	var plan := _PLANNER.plan_floor(layout, reservations, 12345, 4)
	assert_false(plan.blocked_cells.has(Vector2i(5, 3)),
		"chest cell не должен быть занят blocking prop'ом")

func test_enemy_spawn_reservation_not_occupied() -> void:
	var layout := _make_layout_with_corridor("storage", "residential")
	layout.enemy_spawns = [Vector2i(7 * TILE, 4 * TILE)]
	var reservations: Dictionary = {}
	reservations[Vector2i(7, 4)] = true
	var plan := _PLANNER.plan_floor(layout, reservations, 12345, 4)
	assert_false(plan.blocked_cells.has(Vector2i(7, 4)),
		"enemy spawn не должен быть занят blocking prop'ом")

func test_blocking_props_do_not_overlap() -> void:
	var layout := _make_layout_with_corridor("storage", "residential")
	var plan := _PLANNER.plan_floor(layout, {}, 12345, 4)
	var seen: Dictionary = {}
	for placement in plan.placements:
		if not placement.def.blocks_movement:
			continue
		for offset_x in placement.footprint_cells.x:
			for offset_y in placement.footprint_cells.y:
				var cell: Vector2i = placement.cell_origin + Vector2i(offset_x, offset_y)
				assert_false(seen.has(cell),
					"cell %s занята дважды (второй prop: %s)" % [cell, placement.def.id])
				seen[cell] = placement.def.id

func test_density_does_not_exceed_role_limit() -> void:
	# Bedroom 20% cap.
	var room_size := Vector2i(6, 6)
	var layout := DungeonLayout.new()
	layout.rooms = [Rect2i(Vector2i.ZERO, room_size * TILE)]
	layout.corridors = []
	layout.zone = "residential"
	layout.floor_bounds = Rect2i(Vector2i.ZERO, room_size * TILE)
	layout.player_start = Vector2i(-1, -1)
	layout.exit_position = Vector2i(-1, -1)
	layout.room_infos = [{
		"room_index": 0,
		"role": "bedroom",
		"zone": "residential",
		"tags": [],
		"danger": 0,
	}]
	var plan := _PLANNER.plan_floor(layout, {}, 12345, 3)
	var blocking_area := 0
	for placement in plan.placements:
		if placement.def.blocks_movement:
			blocking_area += placement.footprint_cells.x * placement.footprint_cells.y
	var room_area: int = room_size.x * room_size.y
	var ratio: float = float(blocking_area) / float(room_area)
	# Bedroom limit = 0.20 в DENSITY_LIMIT_PER_ROLE, допуск ±5% на округление.
	assert_lte(ratio, 0.25, "bedroom blocking density=%f превышает лимит" % ratio)

func test_decals_do_not_block_movement() -> void:
	var layout := _make_layout_with_corridor("bedroom", "residential")
	var plan := _PLANNER.plan_floor(layout, {}, 12345, 3)
	for placement in plan.placements:
		if not placement.def.is_floor_decal():
			continue
		assert_false(placement.def.blocks_movement,
			"floor_decal %s не должен блокировать движение" % placement.def.id)
		# Cells decal'а не должны быть в blocked_cells.
		for offset_x in placement.footprint_cells.x:
			for offset_y in placement.footprint_cells.y:
				var cell: Vector2i = placement.cell_origin + Vector2i(offset_x, offset_y)
				assert_false(plan.blocked_cells.has(cell),
					"decal cell %s не должна быть в blocked_cells" % cell)
