extends GutTest

# Тесты формул баланса. Смотрят на конкретные числа — если кто-то
# поменяет базовые константы, тест сразу подсветит расхождение
# с документацией и Pokemon Medium Fast reference.

func test_total_xp_pokemon_medium_fast_curve() -> void:
	# L^3 — каноническая формула Medium Fast.
	assert_eq(Balance.total_xp_for_level(1), 1)
	assert_eq(Balance.total_xp_for_level(2), 8)
	assert_eq(Balance.total_xp_for_level(3), 27)
	assert_eq(Balance.total_xp_for_level(5), 125)
	assert_eq(Balance.total_xp_for_level(10), 1000)

func test_xp_to_next_level_matches_cubic_delta() -> void:
	# (L+1)^3 - L^3 = 3L^2 + 3L + 1
	assert_eq(Balance.xp_to_next_level(1), 7, "L1 -> L2: 8 - 1 = 7")
	assert_eq(Balance.xp_to_next_level(2), 19, "L2 -> L3: 27 - 8 = 19")
	assert_eq(Balance.xp_to_next_level(3), 37, "L3 -> L4: 64 - 27 = 37")
	assert_eq(Balance.xp_to_next_level(4), 61)
	assert_eq(Balance.xp_to_next_level(5), 91)
	assert_eq(Balance.xp_to_next_level(10), 331)

func test_scaled_hp_at_floor_1_equals_base() -> void:
	assert_eq(Balance.scaled_hp(10, 1), 10, "floor 1 = base")

func test_scaled_hp_grows_linearly_per_floor() -> void:
	# 10 * (1 + 0.12 * (2 - 1)) = 11.2 -> 11
	assert_eq(Balance.scaled_hp(10, 2), 11)
	# 10 * (1 + 0.12 * 4) = 14.8 -> 15
	assert_eq(Balance.scaled_hp(10, 5), 15)
	# 10 * (1 + 0.12 * 9) = 20.8 -> 21
	assert_eq(Balance.scaled_hp(10, 10), 21)

func test_scaled_damage_uses_10_percent_curve() -> void:
	assert_eq(Balance.scaled_damage(2, 1), 2)
	# 2 * (1 + 0.10 * 4) = 2.8 -> 3
	assert_eq(Balance.scaled_damage(2, 5), 3)
	# 2 * (1 + 0.10 * 9) = 3.8 -> 4
	assert_eq(Balance.scaled_damage(2, 10), 4)

func test_scaled_xp_reward_uses_15_percent_curve() -> void:
	assert_eq(Balance.scaled_xp_reward(5, 1), 5)
	# 5 * (1 + 0.15 * 4) = 8.0 -> 8
	assert_eq(Balance.scaled_xp_reward(5, 5), 8)

func test_scaled_gold_reward_uses_20_percent_curve() -> void:
	assert_eq(Balance.scaled_gold_reward(1, 1), 1)
	# 1 * (1 + 0.20 * 4) = 1.8 -> 2
	assert_eq(Balance.scaled_gold_reward(1, 5), 2)
	# 1 * (1 + 0.20 * 9) = 2.8 -> 3
	assert_eq(Balance.scaled_gold_reward(1, 10), 3)

func test_scaling_never_returns_below_one() -> void:
	# Даже если базовый 0 и floor 1 — min 1.
	assert_eq(Balance.scaled_hp(0, 1), 1)
	assert_eq(Balance.scaled_damage(0, 1), 1)
	assert_eq(Balance.scaled_xp_reward(0, 1), 1)
	assert_eq(Balance.scaled_gold_reward(0, 1), 1)
