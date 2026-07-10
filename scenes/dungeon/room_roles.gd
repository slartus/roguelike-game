class_name RoomRoles
extends RefCounted

# Назначение семантики комнатам — role (что это за помещение),
# tags (свойства для будущего spawn/декора), danger (стоимость в
# room-aware spawn budget).
#
# Роли определяются постфактум по layout: start/exit получают
# entrance/exit_core, chest-room → treasure_room, остальным даётся
# роль из пула зоны с учётом размера комнаты. Danger суммируется
# по правилам v1 (см. `compute_danger`).
#
# Dictionary-схема одного room_info:
#   {
#     "room_index": int,
#     "role": String,
#     "zone": String,
#     "tags": Array[String],
#     "danger": int,
#   }

# --- Все роли v1 (стабильный контракт для тестов и spawn table) ------------
const ROLE_ENTRANCE := "entrance"
const ROLE_EXIT_CORE := "exit_core"
const ROLE_CORRIDOR := "corridor"
const ROLE_SMALL_ROOM := "small_room"
const ROLE_STORAGE := "storage"
const ROLE_BEDROOM := "bedroom"
const ROLE_LIVING_ROOM := "living_room"
const ROLE_STUDY := "study"
const ROLE_KITCHEN := "kitchen"
const ROLE_MACHINE_ROOM := "machine_room"
const ROLE_BOILER_ROOM := "boiler_room"
const ROLE_SWITCH_ROOM := "switch_room"
const ROLE_WAREHOUSE := "warehouse"
const ROLE_RUINED_ROOM := "ruined_room"
const ROLE_BASEMENT_CELL := "basement_cell"
const ROLE_CAVE_CHAMBER := "cave_chamber"
const ROLE_TREASURE_ROOM := "treasure_room"
const ROLE_BOSS_ARENA := "boss_arena"

# Пулы ролей по зонам. Small_room и storage — универсальный fallback
# для «серых» комнат зон, где явные роли ещё не покрывают все rooms.
const ZONE_ROLE_POOL := {
	"tower_top": [ROLE_STUDY, ROLE_STORAGE, ROLE_RUINED_ROOM, ROLE_SMALL_ROOM],
	"residential": [ROLE_BEDROOM, ROLE_LIVING_ROOM, ROLE_KITCHEN, ROLE_STUDY, ROLE_STORAGE, ROLE_SMALL_ROOM],
	"technical": [ROLE_MACHINE_ROOM, ROLE_BOILER_ROOM, ROLE_SWITCH_ROOM, ROLE_STORAGE, ROLE_CORRIDOR],
	"lower_tower": [ROLE_WAREHOUSE, ROLE_STORAGE, ROLE_RUINED_ROOM, ROLE_SMALL_ROOM],
	"basement": [ROLE_BASEMENT_CELL, ROLE_STORAGE, ROLE_RUINED_ROOM],
	"caves": [ROLE_CAVE_CHAMBER, ROLE_RUINED_ROOM],
}

# Размеры (в пикселях): small < 6400 = ~4×4 tiles, large > 12000 = ~6×6.
# Между ними — medium. Пороги подобраны под текущий MIN_ROOM_TILES=4 и
# MAX_ROOM_TILES=10 (тайл 20px → 80..200 px по стороне).
const SMALL_AREA_THRESHOLD := 6400
const LARGE_AREA_THRESHOLD := 12000

# Роли, которые сами по себе делают комнату опасной (техника, разрушения,
# пещерные монстры) — прибавка к danger в v1.
const DANGEROUS_ROLES := [
	ROLE_MACHINE_ROOM,
	ROLE_BOILER_ROOM,
	ROLE_RUINED_ROOM,
	ROLE_CAVE_CHAMBER,
]

# Зоны, которые в целом опасны — вклад +1 к danger независимо от роли.
const DANGEROUS_ZONES := ["lower_tower", "basement", "caves"]

# --- Основной API -----------------------------------------------------------

# Возвращает Array[Dictionary] — по одному info на каждую комнату из layout.
# rng инжектится, чтобы выбор роли из ZONE_ROLE_POOL был детерминирован.
static func assign_roles(
	layout: DungeonLayout,
	rng: RandomNumberGenerator,
) -> Array:
	var infos: Array = []
	if layout.is_boss_floor:
		# Boss арена — одна комната, роль фиксирована.
		for i in layout.rooms.size():
			infos.append(_build_info(i, ROLE_BOSS_ARENA, layout.zone, layout.rooms[i]))
		return infos

	var start_idx := _find_room_containing(layout.rooms, layout.player_start)
	var exit_idx := _find_room_containing(layout.rooms, layout.exit_position)
	var chest_indices := _find_chest_rooms(layout.rooms, layout.chest_positions)

	for i in layout.rooms.size():
		var role: String
		if i == start_idx:
			role = ROLE_ENTRANCE
		elif i == exit_idx:
			role = ROLE_EXIT_CORE
		elif chest_indices.has(i):
			role = ROLE_TREASURE_ROOM
		else:
			role = _pick_role_from_zone(layout.zone, rng)
		infos.append(_build_info(i, role, layout.zone, layout.rooms[i]))
	return infos

# Публичное — для тестов и room-aware spawn (M-плана MonsterSpawnTable).
static func compute_danger(role: String, zone: String) -> int:
	var danger := 0
	if role == ROLE_TREASURE_ROOM:
		danger += 1
	if DANGEROUS_ZONES.has(zone):
		danger += 1
	if DANGEROUS_ROLES.has(role):
		danger += 1
	return danger

static func size_tag_for_area(area: int) -> String:
	if area < SMALL_AREA_THRESHOLD:
		return "small"
	if area > LARGE_AREA_THRESHOLD:
		return "large"
	return "medium"

# --- Внутренние ------------------------------------------------------------

static func _build_info(room_index: int, role: String, zone: String, room: Rect2i) -> Dictionary:
	var area: int = room.size.x * room.size.y
	var tags: Array = [zone, size_tag_for_area(area)]
	if role == ROLE_TREASURE_ROOM:
		tags.append("treasure")
	if role == ROLE_ENTRANCE:
		tags.append("entrance")
	if role == ROLE_EXIT_CORE:
		tags.append("exit")
	return {
		"room_index": room_index,
		"role": role,
		"zone": zone,
		"tags": tags,
		"danger": compute_danger(role, zone),
	}

static func _pick_role_from_zone(zone: String, rng: RandomNumberGenerator) -> String:
	var pool: Array = ZONE_ROLE_POOL.get(zone, [ROLE_SMALL_ROOM])
	if pool.is_empty():
		return ROLE_SMALL_ROOM
	return pool[rng.randi_range(0, pool.size() - 1)]

static func _find_room_containing(rooms: Array[Rect2i], point: Vector2i) -> int:
	for i in rooms.size():
		if rooms[i].has_point(point):
			return i
	# Fallback: если точка чуть выпала из room (края) — вернём ближайшую по
	# центру, чтобы не крешить и не разлаживать role assignment.
	var best_idx := 0
	var best_dist := INF
	for i in rooms.size():
		var d: float = (Vector2(rooms[i].get_center()) - Vector2(point)).length_squared()
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx

static func _find_chest_rooms(rooms: Array[Rect2i], chest_positions: Array[Vector2i]) -> Array:
	var indices: Array = []
	for chest_pos in chest_positions:
		var idx := _find_room_containing(rooms, chest_pos)
		if not indices.has(idx):
			indices.append(idx)
	return indices
