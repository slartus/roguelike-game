class_name RoomDecorationPlanner
extends RefCounted

# Room-level planner для расстановки props. Работает над готовым
# DungeonLayout: для каждой комнаты собирает occupancy grid, резервирует
# критичные клетки (двери, entrance/exit, chest, спавны), выбирает
# композицию по роли/зоне и раскладывает props категории за категорией.
#
# Результат — `FloorPlan`: массив `Placement` (что и где поставить) плюс
# набор `blocked_cells` для AStar. Floor.gd инстанциирует placement plan
# уже после того, как известен полный список blocking cells — так
# гарантируется, что AI-пути и spawn-точки не окажутся внутри пропа.
#
# Инвариант детерминизма: RNG внутри planner'а сеется по
# `(tower_seed, floor_number, room_index, role, zone)`, отдельно от
# gameplay RNG (спавны монстров, drop pickup). Тот же seed → тот же
# набор пропов.

const TILE: int = 20

const _CATALOG := preload("res://scenes/dungeon/environment_prop_catalog.gd")
const _DEF := preload("res://scenes/dungeon/environment_prop_definition.gd")
const _ROLE := preload("res://scenes/dungeon/room_roles.gd")
const _ZONE := preload("res://scenes/dungeon/tower_zone.gd")

# --- Занятость клеток ---------------------------------------------------
const OCC_FREE: int = 0
const OCC_RESERVED: int = 1   # doorway, critical anchor, corridor route — нельзя blocking
const OCC_BLOCKED: int = 2    # занято блокирующим пропом (мебель) — footprint
const OCC_DECAL: int = 3      # занято floor_decal — проходимо, но нельзя другой decal
const OCC_WALL_SURFACE: int = 4  # у стены висит wall_surface — не мешает движению

# --- Composition per role -----------------------------------------------

# Порог blocking footprint (в долях площади комнаты) по роли — верхняя граница.
const DENSITY_LIMIT_PER_ROLE := {
	# Комбат-плотные — не заваливаем.
	_ROLE.ROLE_ENTRANCE: 0.08,
	_ROLE.ROLE_EXIT_CORE: 0.08,
	_ROLE.ROLE_BOSS_ARENA: 0.05,
	_ROLE.ROLE_TREASURE_ROOM: 0.12,
	# Жилые — средняя плотность.
	_ROLE.ROLE_BEDROOM: 0.20,
	_ROLE.ROLE_LIVING_ROOM: 0.20,
	_ROLE.ROLE_KITCHEN: 0.18,
	_ROLE.ROLE_STUDY: 0.20,
	_ROLE.ROLE_SMALL_ROOM: 0.12,
	# Хранилища.
	_ROLE.ROLE_STORAGE: 0.28,
	_ROLE.ROLE_WAREHOUSE: 0.28,
	# Технические.
	_ROLE.ROLE_MACHINE_ROOM: 0.25,
	_ROLE.ROLE_BOILER_ROOM: 0.25,
	_ROLE.ROLE_SWITCH_ROOM: 0.18,
	# Разрушенные.
	_ROLE.ROLE_RUINED_ROOM: 0.15,
	_ROLE.ROLE_BASEMENT_CELL: 0.15,
	_ROLE.ROLE_CAVE_CHAMBER: 0.18,
	_ROLE.ROLE_CORRIDOR: 0.05,
}
const DENSITY_LIMIT_DEFAULT: float = 0.15

# --- Placement и FloorPlan ---------------------------------------------

class Placement extends RefCounted:
	var def: EnvironmentPropDefinition
	var cell_origin: Vector2i        # абсолютная клетка (col, row) левого верха prop'а
	var footprint_cells: Vector2i    # копия для быстрой проверки
	var wall_side: StringName = &""  # только для wall_adjacent / wall_surface, иначе &""
	var room_index: int = -1

	func center_pixel() -> Vector2:
		# Центр bbox'а в пиксельных координатах floor'а. floor.gd
		# использует его как position спрайта.
		var origin_px := Vector2(cell_origin * TILE)
		var size_px := Vector2(footprint_cells * TILE)
		return origin_px + size_px * 0.5

class FloorPlan extends RefCounted:
	var placements: Array = []    # Array[Placement]
	var blocked_cells: Dictionary = {}  # Vector2i (col, row) → true, для AStar

# --- Основной API -------------------------------------------------------

static func plan_floor(
	layout: DungeonLayout,
	reservations: Dictionary,
	tower_seed: int,
	floor_number: int,
) -> FloorPlan:
	# reservations: Dictionary Vector2i(col, row) → true, критичные клетки
	# уже посчитанные Floor.gd (player start, exit, chest, enemy spawns
	# и doorway anchors). Planner дополняет своими corridor route
	# reservations внутри каждой комнаты и не пишет обратно во внешний
	# словарь — floor.gd видит только blocked_cells (blocking props).
	var plan := FloorPlan.new()
	# Global-state для gameplay pass: сколько раз каждый prop_id уже
	# размещён на всём этаже. Проверяется в _try_place_gameplay_prop
	# против def.max_per_floor.
	var floor_counts: Dictionary = {}
	for room_index in layout.rooms.size():
		_plan_room(plan, layout, room_index, reservations, tower_seed, floor_number, floor_counts)
	return plan

# --- Планирование одной комнаты -----------------------------------------

static func _plan_room(
	plan: FloorPlan,
	layout: DungeonLayout,
	room_index: int,
	external_reservations: Dictionary,
	tower_seed: int,
	floor_number: int,
	floor_counts: Dictionary = {},
) -> void:
	var room: Rect2i = layout.rooms[room_index]
	var room_cells := _rect_to_cells(room)
	if room_cells.size.x <= 0 or room_cells.size.y <= 0:
		return

	var role_key := _role_of(layout, room_index)
	var zone_key := StringName(layout.zone)

	# Слишком маленькие комнаты — только decals, никакой мебели.
	var is_tiny := room_cells.size.x < 3 or room_cells.size.y < 3

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for_room(tower_seed, floor_number, room_index, role_key, zone_key)

	# Строим local grid для данной комнаты. free везде, кроме reservations.
	var grid: Dictionary = _build_local_grid(room_cells, external_reservations)

	# Anchor cells для doorways — уже включены в external_reservations,
	# но нужны отдельным списком для connectivity check.
	var door_cells := _room_door_cells(room, layout.corridors)
	# Резервируем клетки corridor'а внутри room (если doorway частично
	# заходит в room rect) и клетки клиренса перед doorway.
	_reserve_door_clearance(grid, room_cells, door_cells)

	# Corridor route: между всеми парами door anchors — L-путь, эти клетки
	# защищаются от blocking.
	_reserve_corridor_routes(grid, room_cells, door_cells)

	# Entry/Exit rooms получают увеличенный combat radius вокруг critical
	# anchor'ов. Это уже сделано через external_reservations, если Floor.gd
	# передал clear zone — планировщик здесь просто уважает уже занятое.

	# Порядок placement: signature → wall-adjacent → large → floor → wall
	# surface → decals. Blocking placement всегда проверяет connectivity.
	var placements: Array = []
	var blocked_area_cells: int = 0
	var room_area_cells: int = room_cells.size.x * room_cells.size.y
	var density_limit: float = DENSITY_LIMIT_PER_ROLE.get(String(role_key), DENSITY_LIMIT_DEFAULT)
	var blocking_budget: int = int(floor(room_area_cells * density_limit))

	if not is_tiny:
		# Signature prop — характерный объект комнаты. Пытаемся поставить.
		var signature_result := _place_signature(
			grid, room_cells, role_key, zone_key, rng, door_cells, room_index,
		)
		if signature_result != null:
			placements.append(signature_result)
			blocked_area_cells += _footprint_area(signature_result)

		# Wall-adjacent (шкафы, стеллажи, verstack).
		blocked_area_cells = _place_category_until_budget(
			placements, grid, room_cells, role_key, zone_key, rng,
			door_cells, room_index, _DEF.CATEGORY_WALL_ADJACENT_PROP,
			blocked_area_cells, blocking_budget,
		)

		# Large props (котёл, рунический двигатель, sтaлагмит).
		blocked_area_cells = _place_category_until_budget(
			placements, grid, room_cells, role_key, zone_key, rng,
			door_cells, room_index, _DEF.CATEGORY_LARGE_PROP,
			blocked_area_cells, blocking_budget,
		)

		# Floor props (столы, стулья, ящики, бочки).
		blocked_area_cells = _place_category_until_budget(
			placements, grid, room_cells, role_key, zone_key, rng,
			door_cells, room_index, _DEF.CATEGORY_FLOOR_PROP,
			blocked_area_cells, blocking_budget,
		)

	# Wall surfaces (картины, трубы, вентили, цепи) — non-blocking.
	_place_non_blocking(
		placements, grid, room_cells, role_key, zone_key, rng,
		door_cells, room_index, _DEF.CATEGORY_WALL_SURFACE,
	)

	# Floor decals (ковёр, кости, щебень, корни, решётка) — non-blocking.
	_place_non_blocking(
		placements, grid, room_cells, role_key, zone_key, rng,
		door_cells, room_index, _DEF.CATEGORY_FLOOR_DECAL,
	)

	# Gameplay pass (PR4): destructibles / hazards / lore идут последним,
	# после того как декоративный слой уже занял grid. Отдельный pass
	# использует бюджет max_per_room / max_per_floor вместо density limit,
	# потому что gameplay-пропы редкие по своей природе.
	if not is_tiny:
		_place_gameplay_props(
			placements, grid, room_cells, role_key, zone_key, rng,
			door_cells, room_index, floor_counts, layout,
		)

	for p in placements:
		var placement: Placement = p
		plan.placements.append(placement)
		if placement.def.blocks_movement:
			for offset_x in placement.footprint_cells.x:
				for offset_y in placement.footprint_cells.y:
					var cell: Vector2i = placement.cell_origin + Vector2i(offset_x, offset_y)
					plan.blocked_cells[cell] = true

# --- Category placement -------------------------------------------------

static func _place_signature(
	grid: Dictionary,
	room_cells: Rect2i,
	role_key: StringName,
	zone_key: StringName,
	rng: RandomNumberGenerator,
	door_cells: Array,
	room_index: int,
) -> Placement:
	# Signature — «характерный» prop роли: bed для bedroom, boiler для
	# boiler_room. Проходим приоритетные категории по очереди, внутри
	# каждой сортируем кандидатов по weight (desc) — так «signature»
	# гарантированно выбирается по замыслу дизайна, а не по алфавиту.
	# Если ни один prop категории не поставился (все не влезли или
	# ломали связность) — проваливаемся в следующую категорию. Это
	# позволяет комнате с невлезающей кроватью получить хотя бы стол
	# как signature.
	var signature_categories := [
		_DEF.CATEGORY_WALL_ADJACENT_PROP,
		_DEF.CATEGORY_LARGE_PROP,
		_DEF.CATEGORY_FLOOR_PROP,
	]
	for category in signature_categories:
		var candidates := _sort_by_weight_desc(
			_CATALOG.filter(zone_key, role_key, room_cells.size, category),
		)
		for def in candidates:
			var d: EnvironmentPropDefinition = def
			var placement := _try_place_prop(grid, room_cells, d, rng, door_cells, room_index)
			if placement != null:
				return placement
	return null

static func _place_category_until_budget(
	placements: Array,
	grid: Dictionary,
	room_cells: Rect2i,
	role_key: StringName,
	zone_key: StringName,
	rng: RandomNumberGenerator,
	door_cells: Array,
	room_index: int,
	category: StringName,
	blocked_area_cells: int,
	blocking_budget: int,
) -> int:
	var current := blocked_area_cells
	var attempts := 0
	var max_attempts := 12  # не больше 12 попыток на категорию — защита от бесконечного цикла
	while current < blocking_budget and attempts < max_attempts:
		attempts += 1
		var candidates := _filter_and_sort(
			_CATALOG.filter(zone_key, role_key, room_cells.size, category),
			role_key,
		)
		if candidates.is_empty():
			return current
		var def: EnvironmentPropDefinition = _pick_weighted(candidates, rng)
		var placement := _try_place_prop(grid, room_cells, def, rng, door_cells, room_index)
		if placement == null:
			continue
		placements.append(placement)
		current += _footprint_area(placement)
	return current

static func _place_non_blocking(
	placements: Array,
	grid: Dictionary,
	room_cells: Rect2i,
	role_key: StringName,
	zone_key: StringName,
	rng: RandomNumberGenerator,
	door_cells: Array,
	room_index: int,
	category: StringName,
) -> void:
	# Non-blocking категории (wall_surface, floor_decal) без connectivity check —
	# они не мешают движению. Ставим до 1 экземпляра на 6 free cells.
	var candidates := _filter_and_sort(
		_CATALOG.filter(zone_key, role_key, room_cells.size, category),
		role_key,
	)
	if candidates.is_empty():
		return
	var free_cells := _count_free_cells(grid)
	var placement_budget := maxi(1, free_cells / 6)
	var attempts := 0
	var max_attempts := placement_budget * 3
	var placed := 0
	while placed < placement_budget and attempts < max_attempts:
		attempts += 1
		var def: EnvironmentPropDefinition = _pick_weighted(candidates, rng)
		var placement := _try_place_prop(grid, room_cells, def, rng, door_cells, room_index)
		if placement != null:
			placements.append(placement)
			placed += 1

# --- Gameplay pass (PR4) ------------------------------------------------

# Gameplay-role → уровень допустимых hazards. Комнаты entrance/exit_core /
# boss_arena / treasure_room не должны получать hazards.
const _NO_HAZARD_ROLES: Array[String] = [
	_ROLE.ROLE_ENTRANCE,
	_ROLE.ROLE_EXIT_CORE,
	_ROLE.ROLE_BOSS_ARENA,
	_ROLE.ROLE_TREASURE_ROOM,
	_ROLE.ROLE_CORRIDOR,
]

# Максимум gameplay props (всех типов) на одну комнату — hard cap
# поверх per-prop max_per_room.
const _GAMEPLAY_PROPS_PER_ROOM_CAP: int = 4

static func _place_gameplay_props(
	placements: Array,
	grid: Dictionary,
	room_cells: Rect2i,
	role_key: StringName,
	zone_key: StringName,
	rng: RandomNumberGenerator,
	door_cells: Array,
	room_index: int,
	floor_counts: Dictionary,
	layout: DungeonLayout,
) -> void:
	# Собираем кандидатов gameplay-props из каталога — только категория
	# INTERACTIVE, отфильтрованная по zone/role/room_size.
	var candidates := _filter_and_sort(
		_CATALOG.filter(zone_key, role_key, room_cells.size, _DEF.CATEGORY_INTERACTIVE),
		role_key,
	)
	if candidates.is_empty():
		return
	# Фильтруем hazards из «запрещённых» ролей и запретной 1-й / последней
	# комнаты — в MVP entrance/exit/boss/treasure не получают hazard'ов.
	var filtered: Array = []
	var role_str: String = String(role_key)
	var is_hazard_free_room: bool = _NO_HAZARD_ROLES.has(role_str)
	# Первая и последняя комнаты — где расположены player_start и exit —
	# тоже без hazards, даже если роль не в списке (для robustness).
	var is_boundary_room: bool = _is_boundary_room(room_index, layout)
	for def in candidates:
		var d: EnvironmentPropDefinition = def
		if d.is_hazard():
			if is_hazard_free_room or is_boundary_room:
				continue
			# Hazards не ставятся рядом с дверями — держим distance 2 cell.
			# Проверка потом при выборе origin, здесь просто пропускаем.
		filtered.append(d)
	if filtered.is_empty():
		return
	# per-room room_counts: сколько раз prop_id уже стоит в этой комнате.
	var room_counts: Dictionary = {}
	var placed_gameplay: int = 0
	var attempts: int = 0
	var max_attempts: int = filtered.size() * 4
	while placed_gameplay < _GAMEPLAY_PROPS_PER_ROOM_CAP and attempts < max_attempts:
		attempts += 1
		var def: EnvironmentPropDefinition = _pick_weighted(filtered, rng)
		if not _gameplay_budget_available(def, room_counts, floor_counts):
			continue
		var placement := _try_place_gameplay_prop(
			def, grid, room_cells, rng, door_cells, room_index,
		)
		if placement == null:
			continue
		placements.append(placement)
		room_counts[def.id] = int(room_counts.get(def.id, 0)) + 1
		floor_counts[def.id] = int(floor_counts.get(def.id, 0)) + 1
		placed_gameplay += 1

static func _gameplay_budget_available(
	def: EnvironmentPropDefinition,
	room_counts: Dictionary,
	floor_counts: Dictionary,
) -> bool:
	if def.max_per_room > 0:
		var room_count: int = int(room_counts.get(def.id, 0))
		if room_count >= def.max_per_room:
			return false
	if def.max_per_floor > 0:
		var floor_count: int = int(floor_counts.get(def.id, 0))
		if floor_count >= def.max_per_floor:
			return false
	return true

static func _try_place_gameplay_prop(
	def: EnvironmentPropDefinition,
	grid: Dictionary,
	room_cells: Rect2i,
	rng: RandomNumberGenerator,
	door_cells: Array,
	room_index: int,
) -> Placement:
	# Тот же placement primitive, что для декоративных props — но с
	# дополнительной проверкой connectivity для blocking gameplay props.
	# Hazards дополнительно проверяют что не стоят на doorway cell'е.
	var candidate_origins: Array = _candidate_origins(def, room_cells)
	_shuffle(candidate_origins, rng)
	for origin in candidate_origins:
		if not _can_place(def, origin, grid):
			continue
		if def.is_hazard() and _is_near_door(origin, def.footprint_cells, door_cells, 1):
			continue
		if def.blocks_movement:
			if not _would_keep_connected(grid, room_cells, origin, def.footprint_cells, door_cells):
				continue
		var occ_kind: int = OCC_BLOCKED if def.blocks_movement else OCC_FREE
		# Non-blocking gameplay props (пока таких нет, но контракт готов)
		# должны хотя бы не позволять поверх ставить другой prop.
		if not def.blocks_movement:
			occ_kind = OCC_DECAL
		_mark_footprint(grid, origin, def.footprint_cells, occ_kind)
		var placement := Placement.new()
		placement.def = def
		placement.cell_origin = origin
		placement.footprint_cells = def.footprint_cells
		placement.wall_side = _wall_side_of(origin, def.footprint_cells, room_cells)
		placement.room_index = room_index
		return placement
	return null

static func _is_near_door(
	origin: Vector2i,
	footprint: Vector2i,
	door_cells: Array,
	radius: int,
) -> bool:
	# Есть ли door_cell в квадрате [origin - radius, origin + footprint + radius]?
	# Простой bounding-box test — hazards не должны блокировать doorway.
	if door_cells.is_empty():
		return false
	for offset_x in range(-radius, footprint.x + radius):
		for offset_y in range(-radius, footprint.y + radius):
			var cell: Vector2i = origin + Vector2i(offset_x, offset_y)
			if door_cells.has(cell):
				return true
	return false

static func _is_boundary_room(room_index: int, layout: DungeonLayout) -> bool:
	# Первая и последняя room в списке — обычно entrance / exit-core.
	# Даже если роль не выставлена, geometrically именно эти комнаты
	# держат player_start / exit_position.
	if room_index == 0:
		return true
	if layout != null and room_index == layout.rooms.size() - 1:
		return true
	return false

# --- Placement primitive ------------------------------------------------

static func _try_place_prop(
	grid: Dictionary,
	room_cells: Rect2i,
	def: EnvironmentPropDefinition,
	rng: RandomNumberGenerator,
	door_cells: Array,
	room_index: int,
) -> Placement:
	# Генерируем candidate origins по category. Пробуем по одному, первое
	# успешное — placement. blocking props дополнительно проверяют что не
	# ломают связность door_cells.
	var candidate_origins: Array = _candidate_origins(def, room_cells)
	_shuffle(candidate_origins, rng)
	for origin in candidate_origins:
		if not _can_place(def, origin, grid):
			continue
		# Для blocking prop'ов — pre-check connectivity.
		if def.blocks_movement:
			if not _would_keep_connected(grid, room_cells, origin, def.footprint_cells, door_cells):
				continue
		# Success — фиксируем в grid и возвращаем Placement.
		var occ_kind: int = OCC_FREE
		if def.is_floor_decal():
			occ_kind = OCC_DECAL
		elif def.is_wall_surface():
			occ_kind = OCC_WALL_SURFACE
		else:
			occ_kind = OCC_BLOCKED
		_mark_footprint(grid, origin, def.footprint_cells, occ_kind)
		var placement := Placement.new()
		placement.def = def
		placement.cell_origin = origin
		placement.footprint_cells = def.footprint_cells
		placement.wall_side = _wall_side_of(origin, def.footprint_cells, room_cells)
		placement.room_index = room_index
		return placement
	return null

static func _candidate_origins(
	def: EnvironmentPropDefinition,
	room_cells: Rect2i,
) -> Array:
	# Для wall-adjacent / wall-surface — только клетки у стены.
	# Для floor / large / decal — любые клетки в room, где prop влезает.
	var result: Array = []
	var min_x: int = room_cells.position.x
	var max_x: int = room_cells.position.x + room_cells.size.x - def.footprint_cells.x
	var min_y: int = room_cells.position.y
	var max_y: int = room_cells.position.y + room_cells.size.y - def.footprint_cells.y
	if max_x < min_x or max_y < min_y:
		return result
	if def.is_wall_adjacent() or def.is_wall_surface():
		# Top row: origin.y = min_y.
		for x in range(min_x, max_x + 1):
			result.append(Vector2i(x, min_y))
		# Bottom row: origin.y = max_y (prop нижней стороной у стены).
		for x in range(min_x, max_x + 1):
			result.append(Vector2i(x, max_y))
		# Left col: origin.x = min_x.
		for y in range(min_y, max_y + 1):
			result.append(Vector2i(min_x, y))
		# Right col: origin.x = max_x.
		for y in range(min_y, max_y + 1):
			result.append(Vector2i(max_x, y))
	else:
		for y in range(min_y, max_y + 1):
			for x in range(min_x, max_x + 1):
				result.append(Vector2i(x, y))
	return result

static func _can_place(
	def: EnvironmentPropDefinition,
	origin: Vector2i,
	grid: Dictionary,
) -> bool:
	# Проверка что все клетки footprint'а — свободны. Для floor_decal
	# разрешено ставить на FREE только (не поверх другого decal / blocked
	# / reserved).
	for offset_x in def.footprint_cells.x:
		for offset_y in def.footprint_cells.y:
			var cell := origin + Vector2i(offset_x, offset_y)
			if not grid.has(cell):
				return false
			if grid[cell] != OCC_FREE:
				return false
	# Дополнительный clearance — резервируем свободные клетки вокруг,
	# если def требует. В M2 не требуем clearance у footprint'а, чтобы не
	# сильно ограничивать placement — оставляем для будущего расширения.
	return true

static func _mark_footprint(
	grid: Dictionary,
	origin: Vector2i,
	footprint: Vector2i,
	occ_kind: int,
) -> void:
	for offset_x in footprint.x:
		for offset_y in footprint.y:
			var cell := origin + Vector2i(offset_x, offset_y)
			grid[cell] = occ_kind

# --- Connectivity check ------------------------------------------------

static func _would_keep_connected(
	grid: Dictionary,
	room_cells: Rect2i,
	blocking_origin: Vector2i,
	blocking_footprint: Vector2i,
	door_cells: Array,
) -> bool:
	# Копию делаем упрощённо: сохраняем оригинальные значения занятости
	# только для клеток footprint'а, ставим их временно в OCC_BLOCKED,
	# после проверки — восстанавливаем.
	if door_cells.size() <= 1:
		return true
	var saved: Array = []
	for offset_x in blocking_footprint.x:
		for offset_y in blocking_footprint.y:
			var cell: Vector2i = blocking_origin + Vector2i(offset_x, offset_y)
			saved.append([cell, grid[cell]])
			grid[cell] = OCC_BLOCKED
	var connected := _all_doors_connected(grid, room_cells, door_cells)
	for entry in saved:
		grid[entry[0]] = entry[1]
	return connected

static func _all_doors_connected(
	grid: Dictionary,
	room_cells: Rect2i,
	door_cells: Array,
) -> bool:
	# BFS от первого door cell — все остальные должны быть достижимы через
	# клетки, которые не OCC_BLOCKED (reserved, decal, wall_surface, free —
	# все проходимы физически). AI ходит через AStar по 20px клеткам, blocking
	# footprint ставит solid, всё остальное — passable.
	if door_cells.is_empty():
		return true
	var start: Vector2i = door_cells[0]
	var visited: Dictionary = {}
	visited[start] = true
	var queue: Array = [start]
	while queue.size() > 0:
		var cell: Vector2i = queue.pop_front()
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next_cell: Vector2i = cell + offset
			if visited.has(next_cell):
				continue
			# Разрешаем ходить в пределах room + door_cells (двери могут быть
			# чуть за room boundary — corridor cell).
			if not room_cells.has_point(next_cell) and not _is_door_cell(next_cell, door_cells):
				continue
			if grid.has(next_cell) and grid[next_cell] == OCC_BLOCKED:
				continue
			visited[next_cell] = true
			queue.append(next_cell)
	for cell in door_cells:
		if not visited.has(cell):
			return false
	return true

static func _is_door_cell(cell: Vector2i, door_cells: Array) -> bool:
	for door in door_cells:
		if door == cell:
			return true
	return false

# --- Reservations -------------------------------------------------------

static func _build_local_grid(
	room_cells: Rect2i,
	external_reservations: Dictionary,
) -> Dictionary:
	var grid: Dictionary = {}
	for y in range(room_cells.position.y, room_cells.position.y + room_cells.size.y):
		for x in range(room_cells.position.x, room_cells.position.x + room_cells.size.x):
			var cell := Vector2i(x, y)
			grid[cell] = OCC_RESERVED if external_reservations.has(cell) else OCC_FREE
	return grid

static func _room_door_cells(
	room: Rect2i,
	corridors: Array[Rect2i],
) -> Array:
	# Клетки внутри room, смежные с corridor cells. Используются как
	# «anchor'ы» для connectivity и как reserved (planner не ставит на них
	# blocking).
	var room_cells := _rect_to_cells(room)
	var anchors: Array = []
	for corridor in corridors:
		var corr_cells := _rect_to_cells(corridor)
		for cy in range(corr_cells.position.y, corr_cells.position.y + corr_cells.size.y):
			for cx in range(corr_cells.position.x, corr_cells.position.x + corr_cells.size.x):
				for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var neighbor: Vector2i = Vector2i(cx, cy) + offset
					if _cell_in_rect(neighbor, room_cells):
						if not anchors.has(neighbor):
							anchors.append(neighbor)
	return anchors

static func _reserve_door_clearance(
	grid: Dictionary,
	room_cells: Rect2i,
	door_cells: Array,
) -> void:
	# Doorway anchors + одна клетка вглубь room — не занимать blocking.
	for door in door_cells:
		grid[door] = OCC_RESERVED
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var clear: Vector2i = door + offset
			if _cell_in_rect(clear, room_cells):
				if grid.get(clear, -1) == OCC_FREE:
					grid[clear] = OCC_RESERVED

static func _reserve_corridor_routes(
	grid: Dictionary,
	room_cells: Rect2i,
	door_cells: Array,
) -> void:
	# Между всеми парами door anchors — L-путь. Клетки на пути помечаем
	# RESERVED, чтобы blocking props не легли на маршрут. Это добавляет
	# запас на connectivity — connectivity check делает то же самое ещё
	# раз, но здесь мы явно сохраняем «главную дорожку».
	if door_cells.size() < 2:
		return
	for i in door_cells.size():
		for j in range(i + 1, door_cells.size()):
			_reserve_l_path(grid, room_cells, door_cells[i], door_cells[j])

static func _reserve_l_path(
	grid: Dictionary,
	room_cells: Rect2i,
	from_cell: Vector2i,
	to_cell: Vector2i,
) -> void:
	# Горизонтальный отрезок, затем вертикальный.
	var x := from_cell.x
	var y := from_cell.y
	var target_x := to_cell.x
	var target_y := to_cell.y
	while x != target_x:
		var cell := Vector2i(x, y)
		if _cell_in_rect(cell, room_cells) and grid.get(cell, -1) == OCC_FREE:
			grid[cell] = OCC_RESERVED
		x += 1 if x < target_x else -1
	while y != target_y:
		var cell := Vector2i(x, y)
		if _cell_in_rect(cell, room_cells) and grid.get(cell, -1) == OCC_FREE:
			grid[cell] = OCC_RESERVED
		y += 1 if y < target_y else -1

# --- Хелперы ---------------------------------------------------------

static func _rect_to_cells(rect: Rect2i) -> Rect2i:
	# Rect в пикселях → Rect в клетках (кол-во клеток по каждой оси).
	return Rect2i(rect.position / TILE, rect.size / TILE)

static func _cell_in_rect(cell: Vector2i, rect_cells: Rect2i) -> bool:
	# Rect2i.has_point возвращает true для края size, поэтому проверяем
	# явно через position + size включая границы.
	if cell.x < rect_cells.position.x or cell.x >= rect_cells.position.x + rect_cells.size.x:
		return false
	if cell.y < rect_cells.position.y or cell.y >= rect_cells.position.y + rect_cells.size.y:
		return false
	return true

static func _role_of(layout: DungeonLayout, room_index: int) -> StringName:
	for info in layout.room_infos:
		if int(info.get("room_index", -1)) == room_index:
			return StringName(String(info.get("role", "")))
	return &""

static func _seed_for_room(
	tower_seed: int,
	floor_number: int,
	room_index: int,
	role_key: StringName,
	zone_key: StringName,
) -> int:
	# Простая, но детерминированная свёртка — исключает совпадение с
	# gameplay RNG (dungeon_generator = tower_seed*100003 + floor;
	# floor.gd cosmetic = seed*31 + 7). Формула зависит от role/zone для
	# устойчивости при regeneration'е.
	var role_hash := String(role_key).hash()
	var zone_hash := String(zone_key).hash()
	var raw: int = (
		tower_seed * 2654435761
		+ floor_number * 40503
		+ room_index * 92821
		+ role_hash * 314159
		+ zone_hash * 27183
	)
	# Гарантируем положительный int64 → int в GDScript.
	return absi(raw) + 1

static func _footprint_area(placement: Placement) -> int:
	return placement.footprint_cells.x * placement.footprint_cells.y

static func _wall_side_of(
	origin: Vector2i,
	footprint: Vector2i,
	room_cells: Rect2i,
) -> StringName:
	if origin.y == room_cells.position.y:
		return _DEF.WALL_SIDE_TOP
	if origin.x == room_cells.position.x:
		return _DEF.WALL_SIDE_LEFT
	if origin.x + footprint.x == room_cells.position.x + room_cells.size.x:
		return _DEF.WALL_SIDE_RIGHT
	if origin.y + footprint.y == room_cells.position.y + room_cells.size.y:
		return _DEF.WALL_SIDE_BOTTOM
	return &""

static func _count_free_cells(grid: Dictionary) -> int:
	var count := 0
	for value in grid.values():
		if value == OCC_FREE:
			count += 1
	return count

static func _filter_and_sort(
	defs: Array,
	role_key: StringName,
) -> Array:
	# Стабильный порядок для детерминизма — сортируем по id.
	var sorted := defs.duplicate()
	sorted.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return sorted

static func _sort_by_weight_desc(defs: Array) -> Array:
	# Для signature — тяжёлые пропы первыми (bed weight=3 перед wardrobe
	# weight=2 в bedroom). Tie-break по id для детерминизма — иначе одинаковые
	# weight'ы дают разный порядок между запусками.
	var sorted := defs.duplicate()
	sorted.sort_custom(func(a, b):
		if a.weight != b.weight:
			return a.weight > b.weight
		return String(a.id) < String(b.id)
	)
	return sorted

static func _pick_weighted(
	defs: Array,
	rng: RandomNumberGenerator,
) -> EnvironmentPropDefinition:
	# Guard: пустой массив → null. Внешние callsite'ы предохранены,
	# но метод-контракт защищаем — иначе randi_range(0, -1) даёт error.
	if defs.is_empty():
		return null
	var total := 0
	for d in defs:
		total += maxi(1, d.weight)
	var roll: int = rng.randi_range(0, total - 1)
	var acc := 0
	for d in defs:
		acc += maxi(1, d.weight)
		if roll < acc:
			return d
	return defs[0]

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
