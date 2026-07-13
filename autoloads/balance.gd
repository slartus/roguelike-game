extends Node

# ============================================================================
# BALANCE_VERSION инкрементируется при любом изменении числового баланса
# (константы hp/damage scaling, xp-кривая, weapon .tres, upgrade .tres,
# spawn table). Analytics включает эту версию в каждое событие,
# чтобы local-reports pipeline мог сравнивать runs с одинаковым балансом.
# Не менять без обновления docs/engineering/analytics.md.
const BALANCE_VERSION: int = 1

# ============================================================================
# Формулы прогрессии и scaling монстров.
#
# Никакого самопала: числа взяты из канонических RPG-источников.
#
# XP-кривая игрока — Pokémon "Medium Fast" growth group:
#   total_xp_for_level(L) = L^3
# Источник: https://bulbapedia.bulbagarden.net/wiki/Experience — Gen III+.
# Плавный рост, играбельная кривая для roguelike-забега на 10-20 минут.
#
# Base statы монстров задаются в .tscn каждой сцены. Их значения
# заимствованы у D&D 5e Monster Manual (SRD), нормализованные примерно
# к 1/5 от исходных HP (в roguelike игрок хрупок).
#
# Scaling per floor — линейный, вдохновлён WoW Classic mob-level table
# (~10-15% рост stats на уровень). Экспонента даёт слишком крутой grind
# на глубоких этажах, линейка — предсказуемее и легче тюнится.
# ============================================================================

# --- Player XP curve (Pokemon Medium Fast) --------------------------------

func total_xp_for_level(level: int) -> int:
	# Общее XP, накопленное до достижения указанного уровня.
	return level * level * level

func xp_to_next_level(current_level: int) -> int:
	# XP, нужное чтобы перейти с current_level на current_level+1.
	# = (L+1)^3 - L^3 = 3L^2 + 3L + 1.
	var next := current_level + 1
	return next * next * next - current_level * current_level * current_level

# --- Monster scaling per floor --------------------------------------------

const HP_SCALING_PER_FLOOR: float = 0.12
const DAMAGE_SCALING_PER_FLOOR: float = 0.10
const XP_REWARD_SCALING_PER_FLOOR: float = 0.15
const GOLD_REWARD_SCALING_PER_FLOOR: float = 0.20

func scaled_hp(base: int, floor_num: int) -> int:
	return maxi(1, roundi(base * (1.0 + HP_SCALING_PER_FLOOR * (floor_num - 1))))

func scaled_damage(base: int, floor_num: int) -> int:
	return maxi(1, roundi(base * (1.0 + DAMAGE_SCALING_PER_FLOOR * (floor_num - 1))))

func scaled_xp_reward(base: int, floor_num: int) -> int:
	return maxi(1, roundi(base * (1.0 + XP_REWARD_SCALING_PER_FLOOR * (floor_num - 1))))

func scaled_gold_reward(base: int, floor_num: int) -> int:
	return maxi(1, roundi(base * (1.0 + GOLD_REWARD_SCALING_PER_FLOOR * (floor_num - 1))))
