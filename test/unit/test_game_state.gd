extends GutTest

const DAGGER := preload("res://resources/weapons/dagger.tres")
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
	GameState.player_xp = 15
	GameState.player_level = 1
	GameState.player_max_health = 5
	GameState.player_health = 2
	GameState.award_xp(10)
	assert_eq(GameState.player_level, 2, "one level up")
	assert_eq(GameState.player_xp, 5, "leftover xp = 25 - 20 = 5")
	assert_eq(GameState.player_max_health, 6, "+1 max hp per level")
	assert_eq(GameState.player_health, 6, "full heal on level up")

func test_multiple_level_ups_from_big_xp_gain() -> void:
	GameState.player_xp = 0
	GameState.player_level = 1
	GameState.player_max_health = 5
	GameState.player_health = 5
	GameState.award_xp(45)
	assert_eq(GameState.player_level, 3, "45 xp = 2 level ups (40 xp used)")
	assert_eq(GameState.player_xp, 5, "5 xp left over")
	assert_eq(GameState.player_max_health, 7, "+2 max hp")

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
	assert_eq(GameState.equipped_weapon, DAGGER, "weapon resets to default")
	assert_eq(GameState.total_gold, 100, "gold survives run reset")

func test_award_gold_increments_total() -> void:
	GameState.total_gold = 10
	GameState.award_gold(15)
	assert_eq(GameState.total_gold, 25)

func test_award_gold_ignores_zero_and_negative() -> void:
	GameState.total_gold = 5
	GameState.award_gold(0)
	GameState.award_gold(-3)
	assert_eq(GameState.total_gold, 5)
