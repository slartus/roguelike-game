class_name DungeonLayout
extends RefCounted

# Чистая структура данных описывает этаж подземелья: комнаты, коридоры,
# точки старта/выхода и спавнов. Ничего не рендерит и не спавнит —
# это делает Floor.gd.

var rooms: Array[Rect2i] = []
var corridors: Array[Rect2i] = []
var player_start: Vector2i = Vector2i.ZERO
var exit_position: Vector2i = Vector2i.ZERO
var enemy_spawns: Array[Vector2i] = []
var chest_positions: Array[Vector2i] = []
var floor_bounds: Rect2i = Rect2i()
var is_boss_floor: bool = false
# Вертикальная зона мира башни (TowerZone.ZONE_*). Заполняется генератором.
# Определяет тематический декор, набор ролей комнат и позже — spawn table.
var zone: String = ""
# Конкретный тип генерации: legacy_bsp / residential_spine / technical_grid
# / boss_arena / basement_bsp / caves_natural.
var floor_archetype: String = ""
# Метаданные комнат в том же порядке, что и rooms. Каждый элемент —
# Dictionary с полями room_index / role / zone / tags / danger
# (см. `RoomRoles.assign_roles`). Пустой массив для legacy layouts,
# где роли ещё не проставлены (backward compat).
var room_infos: Array = []
# Граф смежности комнат по doorway'ям. Заполняется генератором в момент
# сборки layout — тесты и downstream-код читают отсюда, а не пытаются
# восстановить связность из corridors. Пустой (node_count=0) до генерации.
var room_graph: RoomGraph = null
# Индексы entrance/exit комнат — заполняются одновременно с
# player_start/exit_position. Позволяет пропустить room-lookup там,
# где генератор уже знает, какие комнаты стали входом и выходом.
var entrance_room_index: int = -1
var exit_room_index: int = -1
# Индексы комнат на shortest entrance→exit пути (включая концы).
# Пустой для boss floor / одиночной комнаты.
var critical_path_indices: Array = []
