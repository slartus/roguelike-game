class_name BossRegistry
extends RefCounted

# Data-driven mapping "floor number → BossDefinition". Заменяет прежний
# hardcoded `BOSS_SCENE = preload(...)` в Main.gd.
#
# На этом PR:
# - floor 5 → Necromancer (эксплицитная definition через floor_number=5);
# - floor 10 / 15 / 20 → Necromancer (временный fallback до PR 3–5,
#   когда появятся Rune Golem, Castellan-переехавший-с-5, Crystal Wyrm).
#
# Порядок роадмапы (см. plans/boss-roadmap-claude-plans/00_README_RUN_ORDER.md):
# PR 2 переносит Некроманта с 5-го этажа и ставит на 5 нового босса,
# PR 3 добавляет 10-й, PR 4 возвращает Некроманта на 15, PR 5 добавляет 20-й.
# До этого fallback гарантирует, что boss floor'ы не ломаются.
#
# Загружаем definitions лениво из preload'а .tres — это data, а не код,
# reviewer'у проще менять состав через инспектор.

const NECROMANCER_DEFINITION: Resource = preload("res://resources/bosses/necromancer_definition.tres")
const LEGACY_ARENA_PROFILE: Resource = preload("res://resources/bosses/legacy_arena_profile.tres")

# Boss floor'ы, для которых пока нет своей definition, но нужно провести
# босса. Полностью data-driven — если завтра появится босс на floor 7,
# он просто добавится через all_definitions() с floor_number=7, а если
# кому-то нужен fallback slot на 7 — добавляется сюда. Не magic constant.
const FALLBACK_BOSS_FLOORS: Array[int] = [10, 15, 20]

# Возвращает definition для boss floor'а. Для non-boss floor'а — null.
# Порядок разрешения:
# 1. Явная definition (any def where `floor_number == floor`).
# 2. Fallback: если floor в FALLBACK_BOSS_FLOORS и есть definition с
#    fallback_allowed = true — она подставляется.
# 3. Иначе — null.
static func definition_for_floor(floor_number: int) -> BossDefinition:
	if floor_number <= 0:
		return null
	# Явное совпадение — приоритет над fallback.
	for definition in all_definitions():
		if definition == null:
			continue
		if definition.floor_number == floor_number:
			return definition
	# Fallback slot?
	if not FALLBACK_BOSS_FLOORS.has(floor_number):
		return null
	for definition in all_definitions():
		if definition != null and definition.fallback_allowed:
			return definition
	return null

static func scene_for_floor(floor_number: int) -> PackedScene:
	var definition := definition_for_floor(floor_number)
	if definition == null:
		return null
	return definition.scene

static func arena_profile_for_floor(floor_number: int) -> BossArenaProfile:
	var definition := definition_for_floor(floor_number)
	if definition == null:
		return null
	# На этом этапе все definitions используют один legacy профиль
	# (600×400). После PR 2 каждый босс получит собственную арену.
	return LEGACY_ARENA_PROFILE

# Все зарегистрированные definitions. Используется тестами и будущей
# аналитикой ("сколько боссов запланировано в башне").
static func all_definitions() -> Array[BossDefinition]:
	var result: Array[BossDefinition] = []
	if NECROMANCER_DEFINITION != null:
		result.append(NECROMANCER_DEFINITION)
	return result
