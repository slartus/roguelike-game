extends GutTest

# Регресс для свиты Некроманта: композиция 3 melee + 2 ranged, арсенал
# без iron-варианта у melee, damage cap 3/2, отсутствие XP/gold/drops,
# first-shot delay у ranged, formation-spawn. Cм.
# `plans/necromancer-minion-rebalance-claude-plan.md`.

const BossScene = preload("res://scenes/enemies/boss.tscn")
const SkeletonArsenal = preload("res://scenes/enemies/skeleton_arsenal.gd")

class FakeFloor:
	extends Node2D
	var astar_grid: AStarGrid2D
	func _init(cols: int, rows: int) -> void:
		astar_grid = AStarGrid2D.new()
		astar_grid.region = Rect2i(0, 0, cols, rows)
		astar_grid.cell_size = Vector2(20, 20)
		astar_grid.update()
	func _ready() -> void:
		add_to_group("floor")

var _game_state_snapshot: Dictionary

func before_each() -> void:
	# Balance.scaled_* читает GameState.current_floor_number. С PR 4
	# Necromancer живёт на floor 15 (basement, третий босс). Тесты
	# симулируют реальный boss floor 15 — если снова случайно попадёт
	# iron sword в свиту, damage cap должен по-прежнему держать <=3.
	_game_state_snapshot = {
		"floor": GameState.current_floor_number,
	}
	GameState.current_floor_number = 15

func after_each() -> void:
	GameState.current_floor_number = _game_state_snapshot["floor"]

func _spawn_boss() -> Node:
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	return boss

func _spawn_player_and_floor() -> Node:
	var f := FakeFloor.new(200, 200)
	add_child_autofree(f)
	var p := Node2D.new()
	p.global_position = Vector2(600, 100)
	p.add_to_group("player")
	add_child_autofree(p)
	return p

# --- Композиция ------------------------------------------------------

func test_target_composition_is_three_melee_and_two_ranged() -> void:
	# Композиция объявлена константами класса — не хардкоджена в
	# отдельных числах в _summon_batch. Это гарантирует что если
	# кто-то поменяет SUMMON_MELEE_COUNT, батч подстроится.
	var boss = _spawn_boss()
	assert_eq(boss.SUMMON_MELEE_COUNT, 3, "3 melee minion в свите")
	assert_eq(boss.SUMMON_RANGED_COUNT, 2, "2 ranged minion в свите")
	assert_eq(boss.SUMMON_COUNT, 5,
		"общее число = melee + ranged, не превышает 5")

func test_first_summon_spawns_three_melee_and_two_ranged() -> void:
	_spawn_player_and_floor()
	var boss = _spawn_boss()
	boss.global_position = Vector2(400, 400)
	boss._target = get_tree().get_first_node_in_group("player")
	boss._summon_cooldown_timer = 0.0
	# PR 4: scheduler-state-machine — переход в SUMMON_CAST через APPROACH,
	# затем прокрутка cast'а до финала (spawn'а).
	boss._set_state(boss.State.APPROACH)
	boss._tick_approach(0.05)
	boss._tick_summon_cast(boss.SUMMON_CAST_DURATION + 0.1)
	assert_eq(boss._melee_minions.size(), 3)
	assert_eq(boss._ranged_minions.size(), 2)

func test_partial_composition_two_melee_two_ranged_summons_one_melee() -> void:
	# Пример из плана: 2 melee + 2 ranged → следующий summon = 1 melee.
	_spawn_player_and_floor()
	var boss = _spawn_boss()
	boss.global_position = Vector2(400, 400)
	boss._target = get_tree().get_first_node_in_group("player")
	for i in 2:
		var fake_m := Node2D.new()
		add_child_autofree(fake_m)
		boss._melee_minions.append(fake_m)
	for i in 2:
		var fake_r := Node2D.new()
		add_child_autofree(fake_r)
		boss._ranged_minions.append(fake_r)
	var initial_melee_count: int = boss._melee_minions.size()
	var initial_ranged_count: int = boss._ranged_minions.size()
	var spawned: int = boss._summon_batch()
	assert_eq(spawned, 1, "должно быть добавлено ровно 1 миньона")
	assert_eq(boss._melee_minions.size(), initial_melee_count + 1,
		"melee пополнилась ровно на 1")
	assert_eq(boss._ranged_minions.size(), initial_ranged_count,
		"ranged не тронута — квота уже полная")

func test_partial_composition_three_melee_zero_ranged_summons_two_ranged() -> void:
	_spawn_player_and_floor()
	var boss = _spawn_boss()
	boss.global_position = Vector2(400, 400)
	boss._target = get_tree().get_first_node_in_group("player")
	for i in 3:
		var fake_m := Node2D.new()
		add_child_autofree(fake_m)
		boss._melee_minions.append(fake_m)
	var spawned: int = boss._summon_batch()
	assert_eq(spawned, 2, "должно быть добавлено 2 ranged'а")
	assert_eq(boss._melee_minions.size(), 3, "melee не тронута")
	assert_eq(boss._ranged_minions.size(), 2, "ranged восполнилась до 2")

func test_full_composition_summons_nothing() -> void:
	_spawn_player_and_floor()
	var boss = _spawn_boss()
	boss._target = get_tree().get_first_node_in_group("player")
	for i in 3:
		var f := Node2D.new()
		add_child_autofree(f)
		boss._melee_minions.append(f)
	for i in 2:
		var f := Node2D.new()
		add_child_autofree(f)
		boss._ranged_minions.append(f)
	var spawned: int = boss._summon_batch()
	assert_eq(spawned, 0, "все квоты полные — 0 spawn'ов")

# --- Melee profile ---------------------------------------------------

func test_necromancer_melee_pool_has_no_iron_variants() -> void:
	# Iron sword + Balance.scaled_damage на floor 5 давал 6-7 damage,
	# что ваншотило игрока на стартовых 5 HP. В свиту iron не попадает.
	for v in SkeletonArsenal.NECROMANCER_MINION_MELEE:
		var key: String = v["display_key"]
		assert_false(key.ends_with("_IRON"),
			"iron-вариант в свите: %s" % key)

func test_necromancer_melee_pool_has_expected_weights() -> void:
	# 50/35/15 = 100 (нормированное). План фиксирует эти веса как
	# «unarmed доминирует, wooden_dagger часто, wooden_sword редко».
	var weights_by_key: Dictionary = {}
	for v in SkeletonArsenal.NECROMANCER_MINION_MELEE:
		weights_by_key[v["display_key"]] = v["weight"]
	assert_almost_eq(weights_by_key["ENEMY_SKELETON_UNARMED"], 0.50, 0.001)
	assert_almost_eq(weights_by_key["ENEMY_SKELETON_DAGGER_WOOD"], 0.35, 0.001)
	assert_almost_eq(weights_by_key["ENEMY_SKELETON_SWORD_WOOD"], 0.15, 0.001)
	var total: float = 0.0
	for v in SkeletonArsenal.NECROMANCER_MINION_MELEE:
		total += v["weight"]
	assert_almost_eq(total, 1.00, 0.001,
		"сумма весов должна быть 1.00 (нормированные)")

func test_necromancer_melee_variants_stay_within_damage_cap() -> void:
	# Скелет базовый contact_damage = 2 (из skeleton.tscn). После
	# добавления damage_bonus итог не должен превышать max_damage = 3.
	# Тест проверяет это на уровне пула — независимо от Balance.
	const SKELETON_BASE_CONTACT_DAMAGE: int = 2
	const MELEE_CAP: int = 3
	for v in SkeletonArsenal.NECROMANCER_MINION_MELEE:
		var total: int = SKELETON_BASE_CONTACT_DAMAGE + int(v["damage_bonus"])
		assert_lte(total, MELEE_CAP,
			"%s даёт итоговый damage %d > cap %d" %
			[v["display_key"], total, MELEE_CAP])

func test_summoned_melee_configured_to_level_one_no_farm() -> void:
	# После configure_summon() у скелета monster_level = 1, xp/gold = 0,
	# pickup выключен. Это ДО add_child()/_ready(); тестируем состояние
	# профиля через отдельный boss-instance.
	var boss = _spawn_boss()
	var profile = boss._build_melee_profile()
	assert_eq(profile.monster_level, 1,
		"summon melee должен быть на tier 1, не boss floor")
	assert_eq(profile.elite_rank, 0,
		"summon melee не может быть champion/elite")
	assert_false(profile.grants_xp, "нет XP за фарм миньонов")
	assert_false(profile.grants_gold, "нет gold за фарм миньонов")
	assert_false(profile.grants_drops, "нет drops с миньонов")
	assert_eq(profile.max_damage, 3, "cap = 3 damage")

func test_summoned_melee_temperament_never_aggressive() -> void:
	# aggressive поднимает speed×1.12 и cooldown×0.85 — в бою со свитой
	# из 3 melee и залпами босса это добивает игрока. Пул профиля
	# явно исключает aggressive.
	var boss = _spawn_boss()
	var profile = boss._build_melee_profile()
	assert_false(profile.allowed_temperaments.has(CreatureTemperament.AGGRESSIVE),
		"aggressive должен быть исключён из allowed_temperaments")
	assert_ne(profile.temperament_id, CreatureTemperament.AGGRESSIVE,
		"выбранный temperament_id не может быть aggressive")

# --- Ranged profile --------------------------------------------------

func test_necromancer_ranged_pool_uses_80_20_split() -> void:
	var weights_by_key: Dictionary = {}
	for v in SkeletonArsenal.NECROMANCER_MINION_RANGED:
		weights_by_key[v["display_key"]] = v["weight"]
	assert_almost_eq(weights_by_key["ENEMY_SKELETON_ARCHER_WOOD"], 0.80, 0.001)
	assert_almost_eq(weights_by_key["ENEMY_SKELETON_ARCHER_IRON"], 0.20, 0.001)

func test_summoned_ranged_profile_matches_plan() -> void:
	var boss = _spawn_boss()
	var profile = boss._build_ranged_profile()
	assert_eq(profile.monster_level, 1)
	assert_eq(profile.elite_rank, 0)
	assert_false(profile.grants_xp)
	assert_false(profile.grants_gold)
	assert_false(profile.grants_drops)
	assert_eq(profile.max_damage, 2, "arrow damage cap = 2")
	assert_almost_eq(profile.first_attack_delay, 1.0, 0.001,
		"первый выстрел не раньше 1 s после появления")
	assert_almost_eq(profile.fire_interval_override, 2.1, 0.001,
		"reloading редкий: 2.1 s")

func test_summoned_ranged_temperament_never_aggressive() -> void:
	var boss = _spawn_boss()
	var profile = boss._build_ranged_profile()
	assert_false(profile.allowed_temperaments.has(CreatureTemperament.AGGRESSIVE),
		"aggressive у archer'а сокращает fire_interval — плотный обстрел")
	assert_ne(profile.temperament_id, CreatureTemperament.AGGRESSIVE)

# --- Formation -------------------------------------------------------

func test_melee_anchors_are_in_front_of_boss_toward_player() -> void:
	# forward = boss → player. Melee-slot'ы имеют forward-компоненту > 0,
	# то есть каждый slot ближе к игроку, чем boss.
	_spawn_player_and_floor()
	var boss = _spawn_boss()
	boss.global_position = Vector2(100, 100)
	boss._target = get_tree().get_first_node_in_group("player")
	var boss_pos: Vector2 = boss.global_position
	var target_pos: Vector2 = boss._target.global_position
	var forward: Vector2 = (target_pos - boss_pos).normalized()
	for slot in 3:
		var pos: Vector2 = boss._pick_melee_position(slot)
		var offset: Vector2 = pos - boss_pos
		assert_gt(offset.dot(forward), 0.0,
			"melee slot %d должен быть перед боссом (в сторону игрока)" % slot)

func test_ranged_anchors_are_on_flanks_behind_boss() -> void:
	# forward = boss → player. Ranged slot'ы имеют forward-компоненту < 0
	# (сзади боссу относительно игрока) И положительный |right| offset.
	_spawn_player_and_floor()
	var boss = _spawn_boss()
	boss.global_position = Vector2(100, 100)
	boss._target = get_tree().get_first_node_in_group("player")
	var boss_pos: Vector2 = boss.global_position
	var target_pos: Vector2 = boss._target.global_position
	var forward: Vector2 = (target_pos - boss_pos).normalized()
	var right: Vector2 = forward.orthogonal()
	for slot in 2:
		var pos: Vector2 = boss._pick_ranged_position(slot)
		var offset: Vector2 = pos - boss_pos
		assert_lt(offset.dot(forward), 0.0,
			"ranged slot %d должен быть позади босса относительно игрока" % slot)
		assert_gt(absf(offset.dot(right)), 30.0,
			"ranged slot %d должен быть на фланге (|right| > 30 px)" % slot)

func test_ranged_slots_are_on_opposite_sides() -> void:
	# Слева и справа: два ranged'а не должны наложиться друг на друга
	# или встать на одной линии.
	_spawn_player_and_floor()
	var boss = _spawn_boss()
	boss.global_position = Vector2(100, 100)
	boss._target = get_tree().get_first_node_in_group("player")
	var boss_pos: Vector2 = boss.global_position
	var target_pos: Vector2 = boss._target.global_position
	var forward: Vector2 = (target_pos - boss_pos).normalized()
	var right: Vector2 = forward.orthogonal()
	var slot_0_pos: Vector2 = boss._pick_ranged_position(0)
	var slot_1_pos: Vector2 = boss._pick_ranged_position(1)
	var slot_0: Vector2 = slot_0_pos - boss_pos
	var slot_1: Vector2 = slot_1_pos - boss_pos
	assert_lt(slot_0.dot(right) * slot_1.dot(right), 0.0,
		"два ranged'а должны быть по разные стороны (произведение right-компонент < 0)")
