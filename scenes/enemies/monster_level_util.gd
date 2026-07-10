class_name MonsterLevelUtil
extends RefCounted

# Общие правила effective monster level для обычных enemy families
# (melee/ranged/charger). Вынесено сюда, чтобы формулу не пришлось
# синхронизировать по трём отдельным скриптам.

static func effective_level(monster_level: int, elite_rank: int) -> int:
	# monster_level <= 0 → fallback на текущий этаж (backward compat со
	# сценами без явной настройки уровня). Иначе — используем заданный.
	var level := monster_level
	if level <= 0:
		level = GameState.current_floor_number
	return maxi(1, level + elite_rank)
