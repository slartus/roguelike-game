class_name UpgradeOfferGenerator
extends RefCounted

# Генератор «выбор 1 из 3» карт для upgrade level (M4).
#
# Инварианты:
# - Одинаковый (tower_seed, player_level, offer_counter) → одинаковый offer.
# - В offer'е никогда нет дубликатов карт.
# - Карты, набранные до max_stacks, из pool исключаются.
# - Предпочтение текущему weapon.style, но off-style тоже могут выпасть
#   (иначе билд негде брать).
# - Если хотя бы одна general-карта eligible — минимум одна попадёт.
# - Rarity весит weighted-random выбор: common 100, uncommon 35, rare 10.
# - Если eligible < 3, offer может быть короче — не крешит.

const OFFER_SIZE := 3

const RARITY_WEIGHTS := {
	"common": 100,
	"uncommon": 35,
	"rare": 10,
}

# Основной API. Возвращает Array[PlayerUpgradeResource] (может быть короче
# OFFER_SIZE, если eligible cards меньше).
static func generate_offer(
	context: Dictionary,
	current_stacks: Dictionary,
) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _compute_seed(context)
	var eligible: Array = PlayerUpgradeLibrary.get_eligible_upgrades(current_stacks)
	# Фильтр по attack_type текущего оружия. Карта с required_attack_types
	# и/или excluded_attack_types становится «мёртвой» для несовместимого
	# оружия — генератор её вообще не предлагает, чтобы игрок не тратил
	# слот на бесполезный бонус (например, sweeping_blade для копья).
	var current_attack_type: String = String(context.get("current_weapon_attack_type", ""))
	eligible = _filter_by_attack_type(eligible, current_attack_type)
	if eligible.is_empty():
		return []

	# Разделяем на текущий-style / general / off-style для инъекции
	# приоритетов на первых 2 слотах.
	var current_style: String = String(context.get("current_weapon_style", ""))
	var style_pool: Array = []
	var general_pool: Array = []
	var off_style_pool: Array = []
	for upgrade in eligible:
		if upgrade.style == "":
			general_pool.append(upgrade)
		elif upgrade.style == current_style:
			style_pool.append(upgrade)
		else:
			off_style_pool.append(upgrade)

	var offer: Array = []
	var used_ids := {}

	# Slot 1: prefer current-style (если есть eligible). Иначе general.
	if not style_pool.is_empty():
		var pick := _weighted_pick(style_pool, rng)
		if pick != null:
			offer.append(pick)
			used_ids[pick.id] = true
	elif not general_pool.is_empty():
		var pick := _weighted_pick(general_pool, rng)
		if pick != null:
			offer.append(pick)
			used_ids[pick.id] = true

	# Slot 2: prefer general (если ещё не взяли).
	var general_remaining: Array = _filter_out_used(general_pool, used_ids)
	if not general_remaining.is_empty():
		var pick := _weighted_pick(general_remaining, rng)
		if pick != null:
			offer.append(pick)
			used_ids[pick.id] = true

	# Slot 3+: любой из оставшихся eligible.
	while offer.size() < OFFER_SIZE:
		var remaining: Array = _filter_out_used(eligible, used_ids)
		if remaining.is_empty():
			break
		var pick := _weighted_pick(remaining, rng)
		if pick == null:
			break
		offer.append(pick)
		used_ids[pick.id] = true

	return offer

# Seed: tower_seed × 100003 + level × 9176 + offer_counter × 31337.
# Такой набор простых чисел даёт разное распределение для соседних
# (level, counter) значений — offer'ы не «залипают» на одном рулоне.
static func _compute_seed(context: Dictionary) -> int:
	var tower: int = int(context.get("tower_seed", 0))
	var level: int = int(context.get("player_level", 1))
	var counter: int = int(context.get("offer_counter", 0))
	return tower * 100003 + level * 9176 + counter * 31337 + 1337

# Weighted-random выбор одной карты. Возвращает null если pool пустой.
static func _weighted_pick(pool: Array, rng: RandomNumberGenerator) -> PlayerUpgradeResource:
	if pool.is_empty():
		return null
	var total_weight: int = 0
	for upgrade in pool:
		total_weight += _weight_for_rarity(upgrade.rarity)
	if total_weight <= 0:
		return pool[0]
	var roll: int = rng.randi_range(1, total_weight)
	var acc: int = 0
	for upgrade in pool:
		acc += _weight_for_rarity(upgrade.rarity)
		if roll <= acc:
			return upgrade
	return pool.back()

static func _weight_for_rarity(rarity: String) -> int:
	return int(RARITY_WEIGHTS.get(rarity, 100))

static func _filter_out_used(pool: Array, used_ids: Dictionary) -> Array:
	var out: Array = []
	for upgrade in pool:
		if not used_ids.has(upgrade.id):
			out.append(upgrade)
	return out

# Убирает карты, чей required_attack_types не покрывает current, либо чей
# excluded_attack_types покрывает current. Пустой current (нет оружия)
# считается совместимым со всеми — иначе игрок без weapon вообще ничего
# не увидит.
static func _filter_by_attack_type(pool: Array, current_attack_type: String) -> Array:
	if current_attack_type == "":
		return pool
	var out: Array = []
	for upgrade in pool:
		if upgrade.required_attack_types.size() > 0 \
				and not upgrade.required_attack_types.has(current_attack_type):
			continue
		if upgrade.excluded_attack_types.has(current_attack_type):
			continue
		out.append(upgrade)
	return out
