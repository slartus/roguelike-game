extends GutTest

const SHORT_SWORD := preload("res://resources/weapons/short_sword.tres")
const PISTOL := preload("res://resources/weapons/pistol.tres")

var _snapshot: Dictionary

func before_each() -> void:
	_snapshot = {
		"floor": GameState.current_floor_number,
		"max_hp": GameState.player_max_health,
		"hp": GameState.player_health,
		"weapon": GameState.equipped_weapon,
		"level": GameState.player_level,
		"xp": GameState.player_xp,
		"gold": GameState.total_gold,
	}

func after_each() -> void:
	GameState.current_floor_number = _snapshot["floor"]
	GameState.player_max_health = _snapshot["max_hp"]
	GameState.player_health = _snapshot["hp"]
	GameState.equipped_weapon = _snapshot["weapon"]
	GameState.player_level = _snapshot["level"]
	GameState.player_xp = _snapshot["xp"]
	GameState.total_gold = _snapshot["gold"]

func test_award_xp_increases_current_xp() -> void:
	GameState.player_xp = 0
	GameState.player_level = 1
	GameState.award_xp(5)
	assert_eq(GameState.player_xp, 5)
	assert_eq(GameState.player_level, 1)

func test_award_xp_ignores_zero_and_negative() -> void:
	GameState.player_xp = 3
	GameState.award_xp(0)
	assert_eq(GameState.player_xp, 3)
	GameState.award_xp(-5)
	assert_eq(GameState.player_xp, 3)

func test_award_xp_triggers_level_up_when_threshold_crossed() -> void:
	# Pokemon Medium Fast: L1 -> L2 = 7 XP.
	GameState.player_xp = 5
	GameState.player_level = 1
	GameState.player_max_health = 5
	GameState.player_health = 2
	GameState.award_xp(3)
	assert_eq(GameState.player_level, 2, "one level up at 7 XP")
	assert_eq(GameState.player_xp, 1, "leftover xp = 8 - 7 = 1")
	assert_eq(GameState.player_max_health, 6, "+1 max hp per level")
	assert_eq(GameState.player_health, 6, "full heal on level up")

func test_multiple_level_ups_from_big_xp_gain() -> void:
	# L1 -> L2 нужно 7, L2 -> L3 нужно 19. Итого 26 покрывает 2 уровня.
	# После M3 (hybrid rhythm): level 2 → +1 HP, level 3 → без HP.
	GameState.player_xp = 0
	GameState.player_level = 1
	GameState.player_max_health = 5
	GameState.player_health = 5
	GameState.pending_upgrade_levels = []
	GameState.award_xp(30)
	assert_eq(GameState.player_level, 3, "30 xp = 2 level ups (26 xp used)")
	assert_eq(GameState.player_xp, 4, "4 xp left over")
	assert_eq(GameState.player_max_health, 6,
		"+1 max hp (только level 2 даёт HP, level 3 — карту)")

func test_reset_run_clears_run_state_but_keeps_gold() -> void:
	GameState.current_floor_number = 5
	GameState.player_level = 3
	GameState.player_xp = 12
	GameState.player_max_health = 8
	GameState.player_health = 2
	GameState.equipped_weapon = PISTOL
	GameState.total_gold = 100
	GameState.reset_run()
	assert_eq(GameState.current_floor_number, 1)
	assert_eq(GameState.player_level, 1)
	assert_eq(GameState.player_xp, 0)
	assert_eq(GameState.player_max_health, GameState.DEFAULT_MAX_HEALTH)
	assert_eq(GameState.player_health, GameState.DEFAULT_MAX_HEALTH)
	assert_eq(GameState.equipped_weapon, SHORT_SWORD, "weapon resets to default (fantasy start)")
	assert_eq(GameState.total_gold, 100, "gold survives run reset")

func test_reset_run_generates_new_tower_seed() -> void:
	# tower_seed должен смениться после reset_run (случайная выборка).
	# Гоняем несколько раз чтобы отсечь редкий случай коллизии.
	var initial_seed := GameState.tower_seed
	var changed := false
	for i in 5:
		GameState.reset_run()
		if GameState.tower_seed != initial_seed:
			changed = true
			break
	assert_true(changed, "reset_run must roll a new tower_seed")

func test_tower_seed_is_in_positive_int_range() -> void:
	GameState.reset_run()
	assert_gte(GameState.tower_seed, 0)
	assert_lte(GameState.tower_seed, 2147483647,
		"tower_seed fits in a 32-bit signed positive int")

func test_award_gold_increments_total() -> void:
	GameState.total_gold = 10
	GameState.award_gold(15)
	assert_eq(GameState.total_gold, 25)

func test_award_gold_ignores_zero_and_negative() -> void:
	GameState.total_gold = 5
	GameState.award_gold(0)
	GameState.award_gold(-3)
	assert_eq(GameState.total_gold, 5)
