class_name MonsterSpawnTable
extends RefCounted

# Data-driven таблица обычных монстров с floor gating, весами и тегами.
# Не подключена ещё к Main — это чистый data layer + eligibility rules,
# готовый под интеграцию из отдельной подфичи.
#
# Каждый def обязан иметь поля:
# - id: String — уникальный идентификатор для логов / тестов
# - scene: PackedScene — что спавнить
# - min_floor, max_floor: int — floor gating (закрытый интервал)
# - weight: int — вес для weighted-random выбора; > 0 обязательно
# - threat: int — «стоимость» врага в room-aware budget; > 0
# - tags: Array[String] — «что это за монстр»: beast, undead, ranged...
# - room_tags: Array[String] — какие темы комнаты приветствуют этого врага
# - level_offset_min, level_offset_max: int — смещение monster_level от floor
# - elite_chance: float — базовый шанс champion (0..1)

const MONSTERS := [
	{
		"id": "small_slime",
		"scene": preload("res://scenes/enemies/small_slime.tscn"),
		"min_floor": 1,
		"max_floor": 8,
		"weight": 24,
		"threat": 1,
		"tags": ["beast", "swarm", "melee"],
		"room_tags": ["small", "medium", "large", "beast_den", "generic"],
		"level_offset_min": -1,
		"level_offset_max": 0,
		"elite_chance": 0.0,
	},
	{
		"id": "goblin",
		"scene": preload("res://scenes/enemies/goblin.tscn"),
		"min_floor": 1,
		"max_floor": 12,
		"weight": 18,
		"threat": 2,
		"tags": ["goblinoid", "melee", "fast"],
		"room_tags": ["small", "medium", "large", "goblin_camp", "generic"],
		"level_offset_min": -1,
		"level_offset_max": 1,
		"elite_chance": 0.03,
	},
	{
		"id": "skeleton",
		"scene": preload("res://scenes/enemies/skeleton.tscn"),
		"min_floor": 2,
		"max_floor": 999,
		"weight": 14,
		"threat": 2,
		"tags": ["undead", "melee", "variant"],
		"room_tags": ["medium", "large", "undead", "generic"],
		"level_offset_min": -1,
		"level_offset_max": 1,
		"elite_chance": 0.03,
	},
	{
		"id": "adult_slime",
		"scene": preload("res://scenes/enemies/enemy.tscn"),
		"min_floor": 3,
		"max_floor": 12,
		"weight": 8,
		"threat": 4,
		"tags": ["beast", "swarm_generator", "melee"],
		"room_tags": ["medium", "large", "beast_den", "generic"],
		"level_offset_min": 0,
		"level_offset_max": 1,
		"elite_chance": 0.04,
	},
	{
		"id": "orc",
		"scene": preload("res://scenes/enemies/orc.tscn"),
		"min_floor": 3,
		"max_floor": 999,
		"weight": 7,
		"threat": 4,
		"tags": ["goblinoid", "brute", "melee"],
		"room_tags": ["medium", "large", "goblin_camp", "dangerous", "generic"],
		"level_offset_min": 0,
		"level_offset_max": 1,
		"elite_chance": 0.05,
	},
	{
		"id": "spider",
		"scene": preload("res://scenes/enemies/charger.tscn"),
		"min_floor": 3,
		"max_floor": 14,
		"weight": 8,
		"threat": 4,
		"tags": ["beast", "charger", "control"],
		"room_tags": ["medium", "large", "beast_den", "generic"],
		"level_offset_min": 0,
		"level_offset_max": 1,
		"elite_chance": 0.04,
	},
	{
		"id": "zombie",
		"scene": preload("res://scenes/enemies/zombie.tscn"),
		"min_floor": 4,
		"max_floor": 999,
		"weight": 10,
		"threat": 4,
		"tags": ["undead", "tank", "poison", "control"],
		"room_tags": ["medium", "large", "undead", "dangerous", "generic"],
		"level_offset_min": 0,
		"level_offset_max": 1,
		"elite_chance": 0.05,
	},
	{
		"id": "skeleton_archer",
		"scene": preload("res://scenes/enemies/ranged_enemy.tscn"),
		"min_floor": 4,
		"max_floor": 999,
		"weight": 8,
		"threat": 3,
		"tags": ["undead", "ranged", "kiter"],
		"room_tags": ["medium", "large", "undead", "generic"],
		"level_offset_min": 0,
		"level_offset_max": 1,
		"elite_chance": 0.04,
	},
	{
		"id": "lich",
		"scene": preload("res://scenes/enemies/lich.tscn"),
		"min_floor": 7,
		"max_floor": 999,
		"weight": 3,
		"threat": 7,
		"tags": ["undead", "caster", "summoner", "ranged"],
		"room_tags": ["large", "undead", "dangerous"],
		"level_offset_min": 0,
		"level_offset_max": 1,
		"elite_chance": 0.06,
	},
]

static func get_all_defs() -> Array:
	return MONSTERS

# Возвращает подходящих под текущий floor + room_tags. Приоритет отдаётся
# def, у которых room_tags пересекаются с переданными; если совпадений нет —
# fallback на всех, кто gate-подходит по floor.
static func get_eligible_defs(floor_number: int, room_tags: Array = []) -> Array:
	var floor_ok: Array = []
	for def in MONSTERS:
		if def.min_floor <= floor_number and floor_number <= def.max_floor:
			if def.weight > 0 and def.threat > 0:
				floor_ok.append(def)
	if room_tags.is_empty():
		return floor_ok
	var tagged: Array = []
	for def in floor_ok:
		for room_tag in room_tags:
			if def.room_tags.has(room_tag):
				tagged.append(def)
				break
	if tagged.is_empty():
		return floor_ok
	return tagged

# Weighted-random по весам. Детерминирован при одинаковом seed и порядке
# defs. Возвращает {} если defs пустой.
static func choose_weighted(defs: Array, rng: RandomNumberGenerator) -> Dictionary:
	if defs.is_empty():
		return {}
	var total_weight: int = 0
	for def in defs:
		total_weight += int(def.weight)
	if total_weight <= 0:
		return {}
	# randi_range inclusive на обоих концах; веса — целые, поэтому
	# roll в [1..total] равновероятно попадает в любой из weight-слотов.
	var roll := rng.randi_range(1, total_weight)
	var acc: int = 0
	for def in defs:
		acc += int(def.weight)
		if roll <= acc:
			return def
	# Не должно случиться — total_weight >= 1 и acc пройдёт все def'ы.
	return defs.back()

# Возвращает monster_level с учётом текущего floor, room_danger и
# случайного offset из [level_offset_min, level_offset_max].
static func roll_monster_level(
	floor_number: int,
	def: Dictionary,
	room_danger: int,
	rng: RandomNumberGenerator,
) -> int:
	var level := floor_number
	level += room_danger
	var lo := int(def.level_offset_min)
	var hi := int(def.level_offset_max)
	if lo > hi:
		lo = hi
	level += rng.randi_range(lo, hi)
	return maxi(1, level)

# Elite rank: 0=normal, 1=champion, 2=elite. Elite (2) появляется только
# с floor 10+ и с меньшим шансом (0.25 × chance). Champion (1) — обычный
# random roll от chance.
static func roll_elite_rank(
	floor_number: int,
	def: Dictionary,
	room_danger: int,
	rng: RandomNumberGenerator,
) -> int:
	var chance := float(def.elite_chance)
	chance += float(room_danger) * 0.03
	chance += float(maxi(0, floor_number - 6)) * 0.005
	if floor_number >= 10 and rng.randf() < chance * 0.25:
		return 2
	if rng.randf() < chance:
		return 1
	return 0
