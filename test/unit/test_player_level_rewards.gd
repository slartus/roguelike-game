extends GutTest

# Hybrid level rhythm (M3):
# - level 2 → +1 max HP;
# - level 3 → без HP, но upgrade_choice_requested;
# - level 4 → +1 max HP;
# - level 5 → upgrade queue;
# - full heal на любом level-up;
# - multi-level up за один award_xp собирает все upgrade levels в очередь.

var _snapshot: Dictionary

func before_each() -> void:
	_snapshot = {
		"level": GameState.player_level,
		"xp": GameState.player_xp,
		"max_hp": GameState.player_max_health,
		"hp": GameState.player_health,
		"stacks": GameState.player_upgrade_stacks.duplicate(),
		"pending": GameState.pending_upgrade_levels.duplicate(),
		"offer_counter": GameState.upgrade_offer_counter,
	}
	# Стартовые значения для теста.
	GameState.player_level = 1
	GameState.player_xp = 0
	GameState.player_max_health = 5
	GameState.player_health = 5
	GameState.pending_upgrade_levels = []

func after_each() -> void:
	GameState.player_level = _snapshot.level
	GameState.player_xp = _snapshot.xp
	GameState.player_max_health = _snapshot.max_hp
	GameState.player_health = _snapshot.hp
	GameState.player_upgrade_stacks = _snapshot.stacks
	GameState.pending_upgrade_levels = _snapshot.pending
	GameState.upgrade_offer_counter = _snapshot.offer_counter

func test_is_hp_reward_level_even_only() -> void:
	assert_true(GameState.is_hp_reward_level(2))
	assert_true(GameState.is_hp_reward_level(4))
	assert_false(GameState.is_hp_reward_level(3))
	assert_false(GameState.is_hp_reward_level(5))
	assert_false(GameState.is_hp_reward_level(1),
		"level 1 — стартовое, не level-up")

func test_is_upgrade_reward_level_odd_from_three() -> void:
	assert_true(GameState.is_upgrade_reward_level(3))
	assert_true(GameState.is_upgrade_reward_level(5))
	assert_false(GameState.is_upgrade_reward_level(2))
	assert_false(GameState.is_upgrade_reward_level(1))

func test_level_2_grants_max_hp() -> void:
	# 1 → 2: need 7 XP.
	GameState.award_xp(7)
	assert_eq(GameState.player_level, 2)
	assert_eq(GameState.player_max_health, 6,
		"level 2 → +1 max_health")
	assert_eq(GameState.player_health, 6, "full heal")

func test_level_3_queues_upgrade_but_no_hp() -> void:
	watch_signals(GameState)
	# 1→2 = 7 XP, 2→3 = 19 XP. Всего 26.
	GameState.player_max_health = 6  # уже с +1 после level 2
	GameState.player_level = 2
	GameState.player_health = 6
	GameState.award_xp(19)  # 2→3
	assert_eq(GameState.player_level, 3)
	assert_eq(GameState.player_max_health, 6,
		"level 3 НЕ должен добавлять HP")
	assert_eq(GameState.player_health, 6, "full heal на card level")
	assert_signal_emitted(GameState, "upgrade_choice_requested")
	assert_true(GameState.pending_upgrade_levels.has(3),
		"level 3 добавлен в очередь выбора")

func test_level_4_grants_max_hp_no_upgrade() -> void:
	watch_signals(GameState)
	GameState.player_level = 3
	GameState.player_max_health = 6
	GameState.player_health = 6
	# 3→4 = 37 XP.
	GameState.award_xp(37)
	assert_eq(GameState.player_level, 4)
	assert_eq(GameState.player_max_health, 7,
		"level 4 → +1 max_health")
	assert_signal_not_emitted(GameState, "upgrade_choice_requested",
		"чётный уровень не должен эмитить upgrade choice")

func test_level_5_queues_upgrade() -> void:
	watch_signals(GameState)
	GameState.player_level = 4
	GameState.player_max_health = 7
	GameState.player_health = 7
	# 4→5 = 61 XP.
	GameState.award_xp(61)
	assert_eq(GameState.player_level, 5)
	assert_eq(GameState.player_max_health, 7,
		"level 5 не добавляет HP")
	assert_signal_emitted(GameState, "upgrade_choice_requested")
	assert_true(GameState.pending_upgrade_levels.has(5))

func test_multi_level_up_queues_all_upgrade_levels() -> void:
	# Одним XP-hit'ом можно перепрыгнуть 1→3 и получить level 3 в очередь.
	# 1→2 = 7, 2→3 = 19. Всего 26.
	watch_signals(GameState)
	GameState.award_xp(26)
	assert_eq(GameState.player_level, 3)
	assert_true(GameState.pending_upgrade_levels.has(3),
		"multi-level-up тоже ставит upgrade level в очередь")

func test_multi_level_up_to_5_queues_both_3_and_5() -> void:
	# 1→2 = 7, 2→3 = 19, 3→4 = 37, 4→5 = 61. Всего 124 XP.
	watch_signals(GameState)
	GameState.award_xp(124)
	assert_eq(GameState.player_level, 5)
	assert_true(GameState.pending_upgrade_levels.has(3),
		"level 3 в очереди")
	assert_true(GameState.pending_upgrade_levels.has(5),
		"level 5 в очереди")

func test_xp_changed_still_emits() -> void:
	watch_signals(GameState)
	GameState.award_xp(5)
	assert_signal_emitted(GameState, "xp_changed")

func test_hp_grows_half_as_often() -> void:
	# После level 5 max_hp должен быть 5 (base) + 2 (levels 2 и 4) = 7.
	GameState.player_level = 1
	GameState.player_max_health = 5
	GameState.player_health = 5
	GameState.award_xp(124)  # → level 5
	assert_eq(GameState.player_max_health, 7,
		"5 base + 2 (levels 2 и 4) = 7 max_health")
