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
# / boss_arena / basement_bsp / caves_bsp. Пока используется BSP-путь для
# всех non-boss этажей; новые архетипы приходят в M4-6.
var floor_archetype: String = ""
