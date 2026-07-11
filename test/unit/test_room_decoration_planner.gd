extends GutTest

# Проверки RoomDecorationPlanner:
# - планировщик уважает reservations (клетки помечены и не заняты пропом);
# - detectministic: тот же seed → тот же placement plan;
# - decor RNG не влияет на gameplay RNG (DungeonGenerator);
# - blocking props попадают в blocked_cells;
# - signature prop правило для основных ролей;
# - props не выходят за room rect;
# - wall_adjacent касается разрешённой стены;
# - маленькая комната остаётся sparse.

const _PLANNER := preload("res://scenes/dungeon/room_decoration_planner.gd")
const _DEF := preload("res://scenes/dungeon/environment_prop_definition.gd")
const _CATALOG := preload("res://scenes/dungeon/environment_prop_catalog.gd")

const TILE := 20

func before_each() -> void:
	_CATALOG._reset_for_tests()

# --- Хелперы для сборки layout вручную -----------------------------------

func _make_room_layout(role: String, zone: String, room_cells: Rect2i) -> DungeonLayout:
	# Одна комната, одна информация. Без коридоров и других комнат —
	# минимальный layout для юнит-теста planner'а.
	var layout := DungeonLayout.new()
	var room := Rect2i(room_cells.position * TILE, room_cells.size * TILE)
	layout.rooms = [room]
	layout.corridors = []
	layout.zone = zone
	layout.floor_bounds = room
	layout.player_start = Vector2i(-1, -1)
	layout.exit_position = Vector2i(-1, -1)
	layout.room_infos = [{
		"room_index": 0,
		"role": role,
		"zone": zone,
		"tags": [],
		"danger": 0,
	}]
	return layout

# --- Тесты ---------------------------------------------------------------

func test_plan_places_bed_in_bedroom_of_sufficient_size() -> void:
	var layout := _make_room_layout("bedroom", "residential", Rect2i(Vector2i(0, 0), Vector2i(6, 6)))
	var plan := _PLANNER.plan_floor(layout, {}, 12345, 3)
	var ids := plan.placements.map(func(p): return p.def.id)
	assert_true(ids.has(_CATALOG.PROP_BED),
		"bedroom 6x6 должен получить bed. placements=%s" % [ids])

func test_plan_places_desk_or_bookshelf_in_study() -> void:
	var layout := _make_room_layout("study", "residential", Rect2i(Vector2i(0, 0), Vector2i(6, 6)))
	var plan := _PLANNER.plan_floor(layout, {}, 12345, 3)
	var ids := plan.placements.map(func(p): return p.def.id)
	assert_true(ids.has(_CATALOG.PROP_DESK) or ids.has(_CATALOG.PROP_BOOKSHELF),
		"study должен получить desk или bookshelf. placements=%s" % [ids])

func test_plan_places_signature_prop_in_machine_room() -> void:
	var layout := _make_room_layout("machine_room", "technical", Rect2i(Vector2i(0, 0), Vector2i(7, 7)))
	var plan := _PLANNER.plan_floor(layout, {}, 12345, 9)
	var ids := plan.placements.map(func(p): return p.def.id)
	assert_true(
		ids.has(_CATALOG.PROP_RUNE_ENGINE) or ids.has(_CATALOG.PROP_ALCHEMICAL_VAT),
		"machine_room должен получить fantasy машину. placements=%s" % [ids],
	)

func test_plan_places_boiler_in_boiler_room() -> void:
	var layout := _make_room_layout("boiler_room", "technical", Rect2i(Vector2i(0, 0), Vector2i(7, 7)))
	var plan := _PLANNER.plan_floor(layout, {}, 12345, 9)
	var ids := plan.placements.map(func(p): return p.def.id)
	assert_true(ids.has(_CATALOG.PROP_BOILER),
		"boiler_room должен получить boiler. placements=%s" % [ids])

func test_plan_places_stalagmite_in_cave_chamber() -> void:
	var layout := _make_room_layout("cave_chamber", "caves", Rect2i(Vector2i(0, 0), Vector2i(7, 7)))
	var plan := _PLANNER.plan_floor(layout, {}, 12345, 20)
	var ids := plan.placements.map(func(p): return p.def.id)
	assert_true(ids.has(_CATALOG.PROP_STALAGMITE) or ids.has(_CATALOG.PROP_MUSHROOM),
		"cave_chamber должен получить сталагмит или гриб. placements=%s" % [ids])

func test_deterministic_same_seed_same_plan() -> void:
	var layout1 := _make_room_layout("bedroom", "residential", Rect2i(Vector2i(0, 0), Vector2i(6, 6)))
	var layout2 := _make_room_layout("bedroom", "residential", Rect2i(Vector2i(0, 0), Vector2i(6, 6)))
	var plan_a := _PLANNER.plan_floor(layout1, {}, 42, 3)
	var plan_b := _PLANNER.plan_floor(layout2, {}, 42, 3)
	assert_eq(plan_a.placements.size(), plan_b.placements.size(),
		"тот же seed → одинаковое число placements")
	for i in plan_a.placements.size():
		assert_eq(plan_a.placements[i].def.id, plan_b.placements[i].def.id,
			"placement %d id должен совпадать" % i)
		assert_eq(plan_a.placements[i].cell_origin, plan_b.placements[i].cell_origin,
			"placement %d origin должен совпадать" % i)

func test_different_seed_produces_different_plan() -> void:
	# Смена seed должна менять хотя бы что-то (иначе planner не
	# использует seed).
	var layout := _make_room_layout("living_room", "residential", Rect2i(Vector2i(0, 0), Vector2i(7, 7)))
	var plan_a := _PLANNER.plan_floor(layout, {}, 100, 4)
	var plan_b := _PLANNER.plan_floor(layout, {}, 500, 4)
	var ids_a := plan_a.placements.map(func(p): return "%s@%s" % [p.def.id, p.cell_origin])
	var ids_b := plan_b.placements.map(func(p): return "%s@%s" % [p.def.id, p.cell_origin])
	assert_ne(ids_a, ids_b, "разные seed → разные placements. a=%s b=%s" % [ids_a, ids_b])

func test_reserved_cells_not_occupied_by_blocking_props() -> void:
	var layout := _make_room_layout("bedroom", "residential", Rect2i(Vector2i(0, 0), Vector2i(6, 6)))
	# Резервируем центр комнаты.
	var reserved: Dictionary = {}
	reserved[Vector2i(3, 3)] = true
	reserved[Vector2i(3, 4)] = true
	var plan := _PLANNER.plan_floor(layout, reserved, 12345, 3)
	for placement in plan.placements:
		if not placement.def.blocks_movement:
			continue
		for offset_x in placement.footprint_cells.x:
			for offset_y in placement.footprint_cells.y:
				var cell: Vector2i = placement.cell_origin + Vector2i(offset_x, offset_y)
				assert_false(reserved.has(cell),
					"blocking prop %s занял reserved cell %s" % [placement.def.id, cell])

func test_blocked_cells_reflect_blocking_props() -> void:
	var layout := _make_room_layout("machine_room", "technical", Rect2i(Vector2i(0, 0), Vector2i(7, 7)))
	var plan := _PLANNER.plan_floor(layout, {}, 999, 9)
	# Каждый blocking placement footprint = blocked_cells.
	var expected: int = 0
	for placement in plan.placements:
		if placement.def.blocks_movement:
			expected += placement.footprint_cells.x * placement.footprint_cells.y
	assert_eq(plan.blocked_cells.size(), expected,
		"blocked_cells должен покрывать все footprint'ы blocking props")

func test_props_stay_inside_room_rect() -> void:
	var room_rect := Rect2i(Vector2i(2, 3), Vector2i(6, 6))
	var layout := _make_room_layout("living_room", "residential", room_rect)
	var plan := _PLANNER.plan_floor(layout, {}, 77, 4)
	for placement in plan.placements:
		var origin: Vector2i = placement.cell_origin
		var end := origin + placement.footprint_cells
		assert_true(origin.x >= room_rect.position.x,
			"prop %s origin.x < room.x (%d < %d)" % [placement.def.id, origin.x, room_rect.position.x])
		assert_true(origin.y >= room_rect.position.y,
			"prop %s origin.y < room.y (%d < %d)" % [placement.def.id, origin.y, room_rect.position.y])
		assert_true(end.x <= room_rect.position.x + room_rect.size.x,
			"prop %s end.x > room.end.x" % placement.def.id)
		assert_true(end.y <= room_rect.position.y + room_rect.size.y,
			"prop %s end.y > room.end.y" % placement.def.id)

func test_wall_adjacent_prop_touches_wall() -> void:
	var room_rect := Rect2i(Vector2i(0, 0), Vector2i(6, 6))
	var layout := _make_room_layout("bedroom", "residential", room_rect)
	var plan := _PLANNER.plan_floor(layout, {}, 12345, 3)
	for placement in plan.placements:
		var d: EnvironmentPropDefinition = placement.def
		if not d.is_wall_adjacent():
			continue
		var origin := placement.cell_origin
		var end := origin + placement.footprint_cells
		var touches_wall := (
			origin.x == room_rect.position.x
			or origin.y == room_rect.position.y
			or end.x == room_rect.position.x + room_rect.size.x
			or end.y == room_rect.position.y + room_rect.size.y
		)
		assert_true(touches_wall,
			"wall_adjacent %s должен касаться стены (origin=%s, end=%s, room=%s)" % [d.id, origin, end, room_rect])

func test_wall_surface_prop_touches_wall() -> void:
	var room_rect := Rect2i(Vector2i(0, 0), Vector2i(6, 6))
	var layout := _make_room_layout("living_room", "residential", room_rect)
	var plan := _PLANNER.plan_floor(layout, {}, 12345, 4)
	for placement in plan.placements:
		var d: EnvironmentPropDefinition = placement.def
		if not d.is_wall_surface():
			continue
		var origin := placement.cell_origin
		var end := origin + placement.footprint_cells
		var touches_wall := (
			origin.x == room_rect.position.x
			or origin.y == room_rect.position.y
			or end.x == room_rect.position.x + room_rect.size.x
			or end.y == room_rect.position.y + room_rect.size.y
		)
		assert_true(touches_wall,
			"wall_surface %s должен касаться стены" % d.id)

func test_small_room_remains_sparse() -> void:
	# 2x2 room — только decals или ничего. Blocking мебель не должен появляться.
	var layout := _make_room_layout("small_room", "residential", Rect2i(Vector2i(0, 0), Vector2i(2, 2)))
	var plan := _PLANNER.plan_floor(layout, {}, 12345, 3)
	for placement in plan.placements:
		assert_false(placement.def.blocks_movement,
			"маленькая комната не должна получать blocking prop %s" % placement.def.id)

func test_boss_arena_not_filled_with_blocking_props() -> void:
	# Boss арена достаточно большая, но роль boss_arena блокировать не даём.
	var layout := _make_room_layout("boss_arena", "residential", Rect2i(Vector2i(0, 0), Vector2i(30, 20)))
	layout.is_boss_floor = true
	var plan := _PLANNER.plan_floor(layout, {}, 12345, 5)
	var blocking_area := 0
	for placement in plan.placements:
		if placement.def.blocks_movement:
			blocking_area += placement.footprint_cells.x * placement.footprint_cells.y
	var room_area: int = 30 * 20
	var ratio: float = float(blocking_area) / float(room_area)
	assert_lt(ratio, 0.10, "boss_arena должна оставаться свободной (blocking ratio=%f)" % ratio)

func test_decor_rng_does_not_affect_gameplay_generator() -> void:
	# Инвариант M3: cosmetic decor RNG не сдвигает stream DungeonGenerator'а.
	# Прогоняем один и тот же tower_seed через DungeonGenerator и сравниваем
	# layout'ы с планировщиком и без.
	var DungeonGeneratorClass := preload("res://scenes/dungeon/dungeon_generator.gd")
	var gen1 := DungeonGeneratorClass.new()
	var layout_a := gen1.generate(777, 3, false)
	# Prep planner (использует RNG для placement) — не должен затронуть новый gen.
	var _plan := _PLANNER.plan_floor(layout_a, {}, 777, 3)
	var gen2 := DungeonGeneratorClass.new()
	var layout_b := gen2.generate(777, 3, false)
	assert_eq(layout_a.rooms.size(), layout_b.rooms.size(),
		"planner не должен менять число rooms в новом gen с тем же seed")
	for i in layout_a.rooms.size():
		assert_eq(layout_a.rooms[i], layout_b.rooms[i],
			"planner не должен менять room[%d] в новом gen" % i)
	assert_eq(layout_a.player_start, layout_b.player_start,
		"planner не должен сдвигать player_start")
	assert_eq(layout_a.exit_position, layout_b.exit_position,
		"planner не должен сдвигать exit")
