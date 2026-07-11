class_name DungeonFootprint
extends RefCounted

# Целевые размеры footprint по зонам. Envelope, не жёсткие rectangle'ы —
# генератор внутри может занять меньше, но не больше max_size.
#
# Пиксели (TILE_SIZE = 20). Значения соответствуют
# plans/03_larger_levels_and_layout_topology.md, секция «Целевые размеры».
# Каждая зона получает диапазон [min, max] и генератор берёт значение,
# зависящее от floor_number внутри зоны, чтобы более глубокие этажи
# в зоне были больше более ранних.

const _TILE: int = 20

# Прогрессия floor'а внутри зоны: [min, max] tiles по каждой оси.
# Значения выведены из pixel-envelope плана / 20 px.
const _ZONE_ENVELOPES := {
	"tower_top":    {"min": Vector2i(30, 20), "max": Vector2i(34, 23)},
	"residential":  {"min": Vector2i(34, 22), "max": Vector2i(38, 26)},
	"technical":    {"min": Vector2i(36, 24), "max": Vector2i(42, 28)},
	"lower_tower":  {"min": Vector2i(38, 26), "max": Vector2i(46, 32)},
	"basement":     {"min": Vector2i(41, 28), "max": Vector2i(48, 34)},
	"caves":        {"min": Vector2i(42, 30), "max": Vector2i(50, 36)},
}

# Fallback для неизвестной зоны — старый legacy размер, чтобы не крешить.
const _FALLBACK := {"min": Vector2i(20, 14), "max": Vector2i(40, 28)}

# Диапазон floor_number внутри зоны — с какого до какого этажа зона активна.
# Влияет на интерполяцию min..max footprint. Соответствует TowerZone.
const _ZONE_FLOOR_RANGES := {
	"tower_top":    Vector2i(1, 2),
	"residential":  Vector2i(3, 6),
	"technical":    Vector2i(7, 10),
	"lower_tower":  Vector2i(11, 14),
	"basement":     Vector2i(15, 18),
	"caves":        Vector2i(19, 30),  # 30 — верхняя оценка для progression
}

# Возвращает footprint в tiles для (zone, floor_number). Внутри зоны
# линейная интерполяция от min до max: первый этаж зоны — min,
# последний — max.
static func footprint_tiles_for_zone(zone: String, floor_number: int) -> Vector2i:
	var envelope: Dictionary = _ZONE_ENVELOPES.get(zone, _FALLBACK)
	var range_vec: Vector2i = _ZONE_FLOOR_RANGES.get(zone, Vector2i(1, 1))
	var floors_in_zone: int = maxi(1, range_vec.y - range_vec.x)
	var progress: float = 0.0
	if floors_in_zone > 0:
		progress = clampf(
			float(floor_number - range_vec.x) / float(floors_in_zone),
			0.0, 1.0,
		)
	var min_v: Vector2i = envelope["min"]
	var max_v: Vector2i = envelope["max"]
	return Vector2i(
		int(round(lerpf(min_v.x, max_v.x, progress))),
		int(round(lerpf(min_v.y, max_v.y, progress))),
	)

# Целевой pixel envelope для manual verification / docs / tests.
static func envelope_pixels(zone: String) -> Dictionary:
	var envelope: Dictionary = _ZONE_ENVELOPES.get(zone, _FALLBACK)
	var min_v: Vector2i = envelope["min"]
	var max_v: Vector2i = envelope["max"]
	return {
		"min": Vector2i(min_v.x * _TILE, min_v.y * _TILE),
		"max": Vector2i(max_v.x * _TILE, max_v.y * _TILE),
	}
