class_name WorldZones
extends RefCounted

# Заготовка abstraction слоя под будущие миры. Пока реализован только
# WORLD_TOWER — весь код текущего забега опирается на TowerZone напрямую.
# Этот helper даёт единую точку для будущих миров (гора, дерево и т.п.),
# чтобы GameState / DungeonGenerator / spawn table могли переключаться
# по world_id без переписывания каждого места.
#
# **Не реализуем сейчас** mountain / tree / другие миры — только контракт.

const WORLD_TOWER := "tower"

# Возвращает zone для (world, floor). Неизвестный world → tower fallback.
static func get_zone_for_world(world_id: String, floor_number: int) -> String:
	match world_id:
		WORLD_TOWER:
			return TowerZone.get_tower_zone(floor_number)
	# Fallback: неизвестный world не должен крешить генератор — просто
	# ведём себя как башня. Debug-логика может добавить push_warning позже.
	return TowerZone.get_tower_zone(floor_number)
