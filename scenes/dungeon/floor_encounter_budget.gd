class_name FloorEncounterBudget
extends RefCounted

# Per-room spawn budget: сколько врагов положить в комнату при генерации
# этажа. Заменяет старую логику «2..3 в каждой не-entrance/exit комнате»
# — эти цифры плохо масштабируются, когда footprint и rooms.size растут.
#
# Формула v1 (простая, тестируемая):
#   1. Основа — площадь комнаты (px²) → area_slots (60×60 на слот).
#   2. Роль комнаты: entrance/exit_core → 0; treasure_room → на 1 меньше
#      (награда важнее опасности), но 0 если dead-end (см. rewards).
#   3. Danger tier (RoomRoles.compute_danger): +1 за уровень (макс +2).
#   4. Optional/dead-end флаг: -1 (уменьшаем threat в наградных комнатах,
#      если это explicitly reward — иначе слегка сокращаем базу).
#   5. Верхний cap на этаж: `floor_cap(zone, floor_number)` — не даёт
#      просадить FPS на больших этажах zone=basement/caves.
#
# Всё детерминистично относительно rng: budget сам rng не дёргает, он
# только считает max. Внутри budget-max генератор сам rng-ит фактическое
# количество спавнов (2..budget_max) — это сохраняет привычный random
# feel и не ломает старый seed-контракт на местном уровне.

# --- Константы ---------------------------------------------------------------

const _AREA_PER_SLOT: int = 3600  # 60×60 px как в legacy _add_enemy_spawns
const _MAX_PER_ROOM: int = 5      # никакая комната не получит больше 5
const _MIN_ROOM_AREA_FOR_SPAWN: int = 3200  # <4x4 tile → 0 врагов (алькова)

# Верхний cap этажа по zone. Не хотим 40 врагов на глубоком basement.
const _FLOOR_CAP := {
	"tower_top":   14,
	"residential": 18,
	"technical":   20,
	"lower_tower": 24,
	"basement":    26,
	"caves":       28,
}

# --- Публичный API ------------------------------------------------------------

# Максимум врагов для одной комнаты. Не сам rng-роллит счётчик —
# генератор берёт rng.randi_range(min_count, budget) и решает.
#
# room_info — Dictionary с полями role/danger/tags (см. RoomRoles.assign_roles).
# is_critical_path — комната на shortest entrance→exit пути.
# distance_from_entrance — hops (int). -1 если не связано.
static func room_budget(
	room: Rect2i,
	room_info: Dictionary,
	floor_number: int,
	is_critical_path: bool,
	distance_from_entrance: int,
) -> int:
	var role: String = room_info.get("role", "")
	# Entrance / exit / boss арена — всегда 0. Boss спавнится в main.gd
	# напрямую; entrance должен быть safe zone для входа игрока.
	if role == RoomRoles.ROLE_ENTRANCE or role == RoomRoles.ROLE_EXIT_CORE:
		return 0
	if role == RoomRoles.ROLE_BOSS_ARENA:
		return 0
	var area: int = room.size.x * room.size.y
	if area < _MIN_ROOM_AREA_FOR_SPAWN:
		# Небольшие альковы — 0 врагов. Дизайн-choice: маленькая комната
		# читается как чулан, а не как encounter room.
		return 0
	# Base: 1..3 в зависимости от площади.
	var base: int = clampi(area / _AREA_PER_SLOT, 1, 3)
	# Danger tier — +danger.
	var danger: int = int(room_info.get("danger", 0))
	base += mini(danger, 2)
	# Optional / dead-end → -1 (даём немного «покоя» тем, кто ищет reward).
	# Флаг «optional_reward» ставит room_role assigner v2 после prop planner.
	var tags = room_info.get("tags", [])
	if tags is Array and (tags.has("optional_reward") or tags.has("dead_end")):
		base -= 1
	# Treasure room — снижаем на 1: игрок платит меньшим risk за chest.
	if role == RoomRoles.ROLE_TREASURE_ROOM:
		base -= 1
	# Дальность от entrance: чем глубже, тем немного больше — но не сильно.
	# Каждые 3 хопа → +1, кап при +2.
	if distance_from_entrance > 0:
		base += mini(distance_from_entrance / 3, 2)
	# Critical path — умеренно, чтобы главный маршрут был проходным
	# (не «bulldozer»). Ограничим 3.
	if is_critical_path:
		base = mini(base, 3)
	# Финальные бордюры.
	base = clampi(base, 0, _MAX_PER_ROOM)
	return base

# Общий cap этажа. Возвращает hard-limit — генератор должен обрезать
# суммарный набор spawn'ов, если после сложения по всем комнатам вышло больше.
static func floor_cap(zone: String, floor_number: int) -> int:
	var base_cap: int = _FLOOR_CAP.get(zone, 20)
	# Немного растёт с floor'ом внутри зоны (deeper → hairier). +1 за 3 этажа.
	return base_cap + floor_number / 3
