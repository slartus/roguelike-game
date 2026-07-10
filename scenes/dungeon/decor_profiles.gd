class_name DecorProfiles
extends RefCounted

# Тематические профили декора по (role, zone). Профиль возвращает
# Dictionary с массивами разрешённых типов декора для стен и пола.
# Floor.gd читает `layout.zone` и `room_infos[i].role`, находит tile
# внутри room'а и берёт профиль этой комнаты — если tile вне комнат
# (в коридоре / промежутке между rooms) → берётся zone-level профиль.
#
# Ключевой инвариант v1: cave/mold/crack/blood/candle style ограничен
# нижними зонами (lower_tower/basement/caves) и разрушенными ролями
# (ruined_room, cave_chamber). Верхние зоны (tower_top/residential/
# technical) не используют cave-only декор — иначе жилые этажи
# ощущаются как пещеры уже с floor 1.

# --- Типы декора (стабильные строки для контракта) --------------------------
const DECOR_MOLD := "mold"
const DECOR_CRACK := "crack"
const DECOR_BLOOD := "blood"
const DECOR_CANDLE := "candle"
# Placeholder'ы для верхних зон — фактических спрайтов пока нет,
# floor.gd может просто пропустить их или отрисовать простой цветной
# Polygon2D. Важно, что они существуют в контракте, чтобы docs и тесты
# могли на них смотреть.
const DECOR_BED := "bed"
const DECOR_WARDROBE := "wardrobe"
const DECOR_SMALL_TABLE := "small_table"
const DECOR_BOOKSHELF := "bookshelf"
const DECOR_RUG := "rug"
const DECOR_CHAIR := "chair"
const DECOR_CABINET := "cabinet"
const DECOR_PIPE := "pipe"
const DECOR_VALVE := "valve"
const DECOR_VENT := "vent"
const DECOR_SWITCH_BOX := "switch_box"
const DECOR_BOILER := "boiler"
const DECOR_MACHINE_BLOCK := "machine_block"
const DECOR_CABLE_BUNDLE := "cable_bundle"
const DECOR_CRATE := "crate"
const DECOR_BARREL := "barrel"
const DECOR_SACK := "sack"
const DECOR_SHELF := "shelf"
const DECOR_BROKEN_FURNITURE := "broken_furniture"
const DECOR_BONES := "bones"
const DECOR_STONE_RUBBLE := "stone_rubble"

# Все cave-only типы. Они запрещены в верхних зонах.
const CAVE_ONLY_DECOR := [DECOR_MOLD, DECOR_CRACK, DECOR_BLOOD, DECOR_CANDLE, DECOR_BONES, DECOR_STONE_RUBBLE]
# Верхние зоны — в них cave-only декор запрещён даже если роль (например
# ruined_room в tower_top) технически бы его предлагала. Ключевой
# инвариант M3: жилые/технические этажи не выглядят как пещеры.
const NO_CAVE_ZONES := ["tower_top", "residential", "technical"]

# --- Профили по ролям -----------------------------------------------------
# floor: типы декора, ставящиеся на пол.
# wall: типы декора, ставящиеся на стены.
const ROLE_PROFILES := {
	"bedroom": {"floor": [DECOR_RUG, DECOR_SMALL_TABLE], "wall": [DECOR_BED, DECOR_WARDROBE]},
	"living_room": {"floor": [DECOR_RUG, DECOR_SMALL_TABLE, DECOR_CHAIR], "wall": [DECOR_CABINET, DECOR_BOOKSHELF]},
	"kitchen": {"floor": [DECOR_SMALL_TABLE, DECOR_CHAIR], "wall": [DECOR_CABINET, DECOR_SHELF]},
	"study": {"floor": [DECOR_SMALL_TABLE, DECOR_CHAIR], "wall": [DECOR_BOOKSHELF, DECOR_CABINET]},
	"small_room": {"floor": [DECOR_CHAIR], "wall": [DECOR_CABINET]},
	"storage": {"floor": [DECOR_CRATE, DECOR_BARREL, DECOR_SACK], "wall": [DECOR_SHELF]},
	"warehouse": {"floor": [DECOR_CRATE, DECOR_BARREL], "wall": [DECOR_SHELF]},
	"machine_room": {"floor": [DECOR_MACHINE_BLOCK, DECOR_VALVE], "wall": [DECOR_PIPE, DECOR_CABLE_BUNDLE]},
	"boiler_room": {"floor": [DECOR_BOILER, DECOR_VALVE], "wall": [DECOR_PIPE, DECOR_VENT]},
	"switch_room": {"floor": [DECOR_SWITCH_BOX], "wall": [DECOR_CABLE_BUNDLE, DECOR_VENT]},
	"corridor": {"floor": [], "wall": [DECOR_PIPE, DECOR_VENT]},
	"basement_cell": {"floor": [DECOR_CRACK, DECOR_STONE_RUBBLE], "wall": [DECOR_MOLD, DECOR_CANDLE]},
	"ruined_room": {"floor": [DECOR_CRACK, DECOR_BROKEN_FURNITURE, DECOR_STONE_RUBBLE], "wall": [DECOR_MOLD, DECOR_CANDLE]},
	"cave_chamber": {"floor": [DECOR_CRACK, DECOR_STONE_RUBBLE, DECOR_BONES, DECOR_BLOOD], "wall": [DECOR_MOLD]},
	"treasure_room": {"floor": [DECOR_CRATE, DECOR_RUG], "wall": [DECOR_CANDLE, DECOR_SHELF]},
	"entrance": {"floor": [], "wall": []},
	"exit_core": {"floor": [], "wall": []},
	"boss_arena": {"floor": [], "wall": []},
}

# Fallback для комнаты без явного профиля — берём zone-level.
const ZONE_FALLBACK_PROFILES := {
	"tower_top": {"floor": [], "wall": []},
	"residential": {"floor": [], "wall": []},
	"technical": {"floor": [], "wall": [DECOR_PIPE]},
	"lower_tower": {"floor": [DECOR_CRACK], "wall": [DECOR_MOLD]},
	"basement": {"floor": [DECOR_CRACK, DECOR_STONE_RUBBLE], "wall": [DECOR_MOLD, DECOR_CANDLE]},
	"caves": {"floor": [DECOR_CRACK, DECOR_STONE_RUBBLE, DECOR_BLOOD], "wall": [DECOR_MOLD]},
}

# --- API -------------------------------------------------------------------

static func decor_profile_for_room(role: String, zone: String) -> Dictionary:
	# Явный role profile приоритетнее zone fallback. Ruined_room и
	# т.п. cave-содержащие роли могут попасть в верхние зоны из ZONE_ROLE_POOL —
	# в этом случае фильтруем cave-only декор, иначе жилой этаж внезапно
	# покроется мхом и трещинами.
	var raw: Dictionary = ROLE_PROFILES.get(role, ZONE_FALLBACK_PROFILES.get(zone, {"floor": [], "wall": []}))
	if not NO_CAVE_ZONES.has(zone):
		return raw
	return _strip_cave_only(raw)

static func _strip_cave_only(profile: Dictionary) -> Dictionary:
	var stripped := {"floor": [], "wall": []}
	for decor in profile.get("floor", []):
		if not CAVE_ONLY_DECOR.has(decor):
			stripped.floor.append(decor)
	for decor in profile.get("wall", []):
		if not CAVE_ONLY_DECOR.has(decor):
			stripped.wall.append(decor)
	return stripped

# Fallback для tile вне rooms (коридоры, промежутки между комнатами):
# берём zone-level профиль без role-специфики.
static func decor_profile_for_zone(zone: String) -> Dictionary:
	return ZONE_FALLBACK_PROFILES.get(zone, {"floor": [], "wall": []})

# Проверка что декор допустим в данной комнате: используется в тестах
# и integration-фильтре floor.gd, чтобы cave-only не проскочил в
# residential.
static func is_decor_allowed_in_room(decor_type: String, role: String, zone: String) -> bool:
	var profile := decor_profile_for_room(role, zone)
	var all_allowed: Array = []
	all_allowed.append_array(profile.get("floor", []))
	all_allowed.append_array(profile.get("wall", []))
	return all_allowed.has(decor_type)
