extends GutTest

# Monster level scaling у обычных enemy families.
# monster_level = 0 → fallback на GameState.current_floor_number (backward compat).
# monster_level > 0 → используется как effective level независимо от текущего этажа.
# elite_rank прибавляется к effective level (champion +1, elite +2).
# configure_spawn(level, elite) должен вызываться ДО add_child, иначе _ready
# уже применит scaling к дефолтному monster_level.

const MeleeSlimeScene = preload("res://scenes/enemies/enemy.tscn")
const RangedArcherScene = preload("res://scenes/enemies/ranged_enemy.tscn")
const LichScene = preload("res://scenes/enemies/lich.tscn")
const ChargerScene = preload("res://scenes/enemies/charger.tscn")

var _floor_snapshot: int

func before_each() -> void:
	_floor_snapshot = GameState.current_floor_number

func after_each() -> void:
	GameState.current_floor_number = _floor_snapshot

func _instantiate_and_configure(scene: PackedScene, level: int, elite: int = 0) -> Node:
	var enemy := scene.instantiate()
	enemy.configure_spawn(level, elite)
	add_child_autofree(enemy)
	return enemy

func test_melee_effective_level_falls_back_to_floor_when_zero() -> void:
	GameState.current_floor_number = 7
	var enemy := MeleeSlimeScene.instantiate()
	add_child_autofree(enemy)
	assert_eq(enemy.get_effective_monster_level(), 7,
		"monster_level=0 → берётся GameState.current_floor_number")

func test_melee_effective_level_uses_configured_level_ignoring_floor() -> void:
	GameState.current_floor_number = 12
	var enemy := _instantiate_and_configure(MeleeSlimeScene, 1)
	assert_eq(enemy.get_effective_monster_level(), 1,
		"configured monster_level переопределяет floor scaling")

func test_melee_configured_level_scales_hp() -> void:
	GameState.current_floor_number = 1
	# Base HP слайма = 3. На level 5 = scaled_hp(3, 5) = round(3 * (1 + 0.12*4)) = 4.
	var expected_hp := Balance.scaled_hp(3, 5)
	var enemy := _instantiate_and_configure(MeleeSlimeScene, 5)
	assert_eq(enemy.max_health, expected_hp,
		"HP скейлится от monster_level=5, а не от floor=1")

func test_melee_elite_rank_bumps_effective_level_by_one() -> void:
	GameState.current_floor_number = 1
	var enemy := _instantiate_and_configure(MeleeSlimeScene, 3, 1)
	assert_eq(enemy.get_effective_monster_level(), 4,
		"elite_rank=1 добавляет +1 к effective level")

func test_melee_elite_rank_two_bumps_effective_level_by_two() -> void:
	GameState.current_floor_number = 1
	var enemy := _instantiate_and_configure(MeleeSlimeScene, 3, 2)
	assert_eq(enemy.get_effective_monster_level(), 5,
		"elite_rank=2 добавляет +2 к effective level")

func test_effective_level_never_below_one() -> void:
	# configure_spawn клампит level в maxi(1, level), а fallback тоже гарантирует min 1.
	# Проверим все паразитные пути:
	# 1. configure_spawn(0) → monster_level = 1.
	GameState.current_floor_number = 1
	var enemy := _instantiate_and_configure(MeleeSlimeScene, 0)
	assert_true(enemy.get_effective_monster_level() >= 1,
		"configure_spawn(0) не должен ронять effective level ниже 1")
	# 2. configure_spawn(-5) → тоже клампится к 1.
	var enemy_neg := _instantiate_and_configure(MeleeSlimeScene, -5)
	assert_true(enemy_neg.get_effective_monster_level() >= 1,
		"configure_spawn(-5) должен клампиться в 1")
	# 3. monster_level=0 при floor=1 тоже возвращает 1 минимум.
	var enemy2 := MeleeSlimeScene.instantiate()
	add_child_autofree(enemy2)
	assert_true(enemy2.get_effective_monster_level() >= 1,
		"fallback на floor=1 даёт минимум 1")
	# 4. Direct field mutation с отрицательным monster_level → clamped через maxi.
	var enemy_direct := MeleeSlimeScene.instantiate()
	add_child_autofree(enemy_direct)
	enemy_direct.monster_level = -10
	enemy_direct.elite_rank = 0
	assert_true(enemy_direct.get_effective_monster_level() >= 1,
		"прямая мутация monster_level = -10 должна клампиться через maxi")

func test_charger_effective_level_falls_back_to_floor() -> void:
	# Charger (Spider) — отдельная категория обычных врагов, тот же контракт.
	GameState.current_floor_number = 4
	var spider := ChargerScene.instantiate()
	add_child_autofree(spider)
	assert_eq(spider.get_effective_monster_level(), 4)

func test_charger_configured_level_scales_hp() -> void:
	GameState.current_floor_number = 1
	# Base HP паука = 1. На level 6 = scaled_hp(1, 6) остаётся 1 из-за maxi(1, ...),
	# поэтому лучше проверить xp — там base=8, что даст различимую цифру.
	var expected_xp := Balance.scaled_xp_reward(8, 6)
	var spider := _instantiate_and_configure(ChargerScene, 6)
	assert_eq(spider.xp_reward, expected_xp,
		"XP паука скейлится от monster_level, а не от floor")

func test_charger_elite_rank_bumps_effective_level() -> void:
	GameState.current_floor_number = 1
	var spider := _instantiate_and_configure(ChargerScene, 3, 2)
	assert_eq(spider.get_effective_monster_level(), 5)

func test_ranged_effective_level_falls_back_to_floor() -> void:
	GameState.current_floor_number = 5
	var enemy := RangedArcherScene.instantiate()
	add_child_autofree(enemy)
	assert_eq(enemy.get_effective_monster_level(), 5)

func test_ranged_configured_level_scales_hp() -> void:
	GameState.current_floor_number = 1
	# Base HP лучника = 2. На level 4 = scaled_hp(2, 4).
	var expected_hp := Balance.scaled_hp(2, 4)
	var enemy := _instantiate_and_configure(RangedArcherScene, 4)
	assert_eq(enemy.max_health, expected_hp,
		"HP ranged скейлится от monster_level, а не от floor")

func test_ranged_elite_rank_bumps_effective_level() -> void:
	GameState.current_floor_number = 1
	var enemy := _instantiate_and_configure(RangedArcherScene, 2, 1)
	assert_eq(enemy.get_effective_monster_level(), 3)

func test_lich_effective_level_uses_ranged_path() -> void:
	# Lich extends ranged_enemy — тот же get_effective_monster_level из base.
	GameState.current_floor_number = 1
	var lich := _instantiate_and_configure(LichScene, 8, 1)
	assert_eq(lich.get_effective_monster_level(), 9,
		"Lich через inherited ranged path получает корректный effective level")

func test_configure_spawn_before_ready_takes_effect() -> void:
	# Регресс-тест: configure_spawn ДО add_child должен реально повлиять на _ready scaling.
	GameState.current_floor_number = 1
	var enemy := MeleeSlimeScene.instantiate()
	enemy.configure_spawn(10, 0)
	add_child_autofree(enemy)
	# level 10 гораздо больше floor 1 — scaled HP заметно выше базового 3.
	assert_gt(enemy.max_health, 3,
		"scaling должен применить level=10, а не остаться на base=3")
