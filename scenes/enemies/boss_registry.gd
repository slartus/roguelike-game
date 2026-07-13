class_name BossRegistry
extends RefCounted

# Data-driven mapping "floor number → BossDefinition". Заменяет прежний
# hardcoded `BOSS_SCENE = preload(...)` в Main.gd.
#
# После PR 3:
# - floor 5 → Castellan Armor (эксплицитная definition через floor_number=5);
# - floor 10 → Rune Golem (эксплицитная definition через floor_number=10);
# - floor 15 / 20 → Necromancer (временный fallback до PR 4–5, когда
#   Necromancer переедет на 15 и появится Crystal Wyrm на 20).
#
# Порядок роадмапы (см. plans/boss-roadmap-claude-plans/00_README_RUN_ORDER.md):
# PR 2 ставит Castellan Armor на 5-й этаж и снимает Некроманта с явного
# слота (его definition остаётся живой только как fallback);
# PR 3 добавляет 10-й (Rune Golem); PR 4 возвращает Некроманта на 15
# (fallback выключится); PR 5 добавляет 20-й (Crystal Wyrm).
#
# Загружаем definitions лениво из preload'а .tres — это data, а не код,
# reviewer'у проще менять состав через инспектор.

const CASTELLAN_ARMOR_DEFINITION: Resource = preload("res://resources/bosses/castellan_armor_definition.tres")
const RUNE_GOLEM_DEFINITION: Resource = preload("res://resources/bosses/rune_golem_definition.tres")
const NECROMANCER_DEFINITION: Resource = preload("res://resources/bosses/necromancer_definition.tres")
const LEGACY_ARENA_PROFILE: Resource = preload("res://resources/bosses/legacy_arena_profile.tres")
const CASTELLAN_HALL_ARENA_PROFILE: Resource = preload("res://resources/bosses/castellan_hall_arena.tres")
const RUNE_ENGINE_CHAMBER_ARENA_PROFILE: Resource = preload("res://resources/bosses/rune_engine_chamber_arena.tres")

# Boss floor'ы, для которых пока нет своей definition, но нужно провести
# босса. Полностью data-driven — если завтра появится босс на floor 7,
# он просто добавится через all_definitions() с floor_number=7, а если
# кому-то нужен fallback slot на 7 — добавляется сюда. Не magic constant.
# После PR 3: floor 10 занял Rune Golem, но fallback list не сокращаем —
# Necromancer продолжает обслуживать 15/20, а 10 в списке всё ещё нужен
# как явное признание «этот floor — boss floor» (Rune Golem резолвится
# как explicit через шаг 1, fallback шаг 2 просто не срабатывает).
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
	# Резолвим arena profile по `arena_profile_id` definition'а. Каждый
	# босс с PR 2 может иметь свой профиль; неизвестный id — fallback на
	# legacy 600×400, чтобы старые definitions не сломались.
	match definition.arena_profile_id:
		&"castellan_hall":
			return CASTELLAN_HALL_ARENA_PROFILE
		&"rune_engine_chamber":
			return RUNE_ENGINE_CHAMBER_ARENA_PROFILE
		_:
			return LEGACY_ARENA_PROFILE

# Все зарегистрированные definitions. Используется тестами и будущей
# аналитикой ("сколько боссов запланировано в башне").
static func all_definitions() -> Array[BossDefinition]:
	var result: Array[BossDefinition] = []
	if CASTELLAN_ARMOR_DEFINITION != null:
		result.append(CASTELLAN_ARMOR_DEFINITION)
	if RUNE_GOLEM_DEFINITION != null:
		result.append(RUNE_GOLEM_DEFINITION)
	if NECROMANCER_DEFINITION != null:
		result.append(NECROMANCER_DEFINITION)
	return result
