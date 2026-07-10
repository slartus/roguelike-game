class_name TowerZone
extends RefCounted

# Вертикальные зоны мира башни. Игрок стартует наверху и спускается вниз:
# tower_top → residential → technical → lower_tower → basement → caves.
# Пещерный стиль намеренно уходит в поздние этажи — верхние должны
# ощущаться архитектурно (жильё, служебные помещения), а не как пещеры.
#
# Границы (v1 не финальный баланс, а читаемая шкала):
#   floor 1-2   → tower_top
#   floor 3-6   → residential
#   floor 7-10  → technical
#   floor 11-14 → lower_tower
#   floor 15-18 → basement
#   floor 19+   → caves

const ZONE_TOWER_TOP := "tower_top"
const ZONE_RESIDENTIAL := "residential"
const ZONE_TECHNICAL := "technical"
const ZONE_LOWER_TOWER := "lower_tower"
const ZONE_BASEMENT := "basement"
const ZONE_CAVES := "caves"

# Все zones в порядке спуска — для тестов и iterations.
const ALL_ZONES := [
	ZONE_TOWER_TOP,
	ZONE_RESIDENTIAL,
	ZONE_TECHNICAL,
	ZONE_LOWER_TOWER,
	ZONE_BASEMENT,
	ZONE_CAVES,
]

static func get_tower_zone(floor_number: int) -> String:
	if floor_number <= 2:
		return ZONE_TOWER_TOP
	if floor_number <= 6:
		return ZONE_RESIDENTIAL
	if floor_number <= 10:
		return ZONE_TECHNICAL
	if floor_number <= 14:
		return ZONE_LOWER_TOWER
	if floor_number <= 18:
		return ZONE_BASEMENT
	return ZONE_CAVES
