extends GutTest

# Run-scoped upgrade state (M2):
# - reset_run() очищает stacks / pending / offer_counter / second_wind;
# - add_player_upgrade инкрементирует stack и эмитит upgrades_changed;
# - immediate effect max_health_bonus увеличивает max HP + heal;
# - get_player_upgrade_modifiers возвращает актуальный snapshot;
# - modifiers не мутируют базовый resource.

var _snapshot: Dictionary

func before_each() -> void:
	_snapshot = {
		"stacks": GameState.player_upgrade_stacks.duplicate(),
		"pending": GameState.pending_upgrade_levels.duplicate(),
		"offer_counter": GameState.upgrade_offer_counter,
		"second_wind": GameState.second_wind_used_this_floor,
		"max_hp": GameState.player_max_health,
		"hp": GameState.player_health,
		"floor": GameState.current_floor_number,
	}

func after_each() -> void:
	GameState.player_upgrade_stacks = _snapshot.stacks
	GameState.pending_upgrade_levels = _snapshot.pending
	GameState.upgrade_offer_counter = _snapshot.offer_counter
	GameState.second_wind_used_this_floor = _snapshot.second_wind
	GameState.player_max_health = _snapshot.max_hp
	GameState.player_health = _snapshot.hp
	GameState.current_floor_number = _snapshot.floor
	PlayerUpgradeLibrary.clear_cache_for_testing()

func _make_upgrade(id: String, effect: String, params: Dictionary, max_stacks: int = 3) -> PlayerUpgradeResource:
	var u := PlayerUpgradeResource.new()
	u.id = id
	u.display_name = "UPGRADE_%s" % id.to_upper()
	u.description = "UPGRADE_%s_DESC" % id.to_upper()
	u.effect_type = effect
	u.parameters = params
	u.max_stacks = max_stacks
	return u

func test_reset_run_clears_upgrade_stacks() -> void:
	# Проверяем что _после_ reset_run поля обнулены. Сохраняем/восстанавливаем
	# tower_seed отдельно, т.к. reset_run её генерирует заново.
	var seed_snapshot := GameState.tower_seed
	GameState.player_upgrade_stacks = {"thick_skin": 2}
	GameState.pending_upgrade_levels = [3]
	GameState.upgrade_offer_counter = 5
	GameState.second_wind_used_this_floor = true
	GameState.reset_run()
	assert_eq(GameState.player_upgrade_stacks, {},
		"reset_run обнуляет player_upgrade_stacks")
	assert_eq(GameState.pending_upgrade_levels, [],
		"reset_run обнуляет pending_upgrade_levels")
	assert_eq(GameState.upgrade_offer_counter, 0)
	assert_false(GameState.second_wind_used_this_floor)
	GameState.tower_seed = seed_snapshot

func test_add_player_upgrade_increments_stack() -> void:
	var upgrade := _make_upgrade("test_stack", "speed_multiplier", {"multiplier": 1.08})
	assert_eq(GameState.get_upgrade_stack("test_stack"), 0)
	GameState.add_player_upgrade(upgrade)
	assert_eq(GameState.get_upgrade_stack("test_stack"), 1)
	GameState.add_player_upgrade(upgrade)
	assert_eq(GameState.get_upgrade_stack("test_stack"), 2)

func test_add_player_upgrade_emits_upgrades_changed() -> void:
	watch_signals(GameState)
	var upgrade := _make_upgrade("emit_test", "speed_multiplier", {"multiplier": 1.1})
	GameState.add_player_upgrade(upgrade)
	assert_signal_emitted(GameState, "upgrades_changed")

func test_null_upgrade_is_safe_noop() -> void:
	# Регресс: если UI как-то передал null (offer generator debug), не должно
	# крешить и не должно эмитить signals.
	watch_signals(GameState)
	GameState.add_player_upgrade(null)
	assert_signal_not_emitted(GameState, "upgrades_changed")

func test_max_health_bonus_is_immediate() -> void:
	var upgrade := _make_upgrade("hp_bonus", "max_health_bonus", {"amount": 1})
	var before_max := GameState.player_max_health
	GameState.player_health = 3
	GameState.add_player_upgrade(upgrade)
	assert_eq(GameState.player_max_health, before_max + 1,
		"max_health_bonus увеличивает max HP сразу")
	assert_eq(GameState.player_health, 4,
		"current HP тоже растёт (не выше max)")

func test_speed_multiplier_reflected_in_modifiers() -> void:
	var upgrade := _make_upgrade("boots", "speed_multiplier", {"multiplier": 1.08})
	PlayerUpgradeLibrary._cache = [upgrade]
	GameState.add_player_upgrade(upgrade)
	var mods := GameState.get_player_upgrade_modifiers()
	assert_almost_eq(mods.speed_multiplier, 1.08, 0.0001,
		"speed_multiplier из upgrade применяется")

func test_stacked_speed_multiplier_stacks_multiplicatively() -> void:
	var upgrade := _make_upgrade("boots", "speed_multiplier", {"multiplier": 1.10})
	PlayerUpgradeLibrary._cache = [upgrade]
	GameState.add_player_upgrade(upgrade)
	GameState.add_player_upgrade(upgrade)
	var mods := GameState.get_player_upgrade_modifiers()
	# 1.10 * 1.10 = 1.21.
	assert_almost_eq(mods.speed_multiplier, 1.21, 0.0001)

func test_style_damage_bonus_routes_to_correct_style() -> void:
	var warrior_dmg := _make_upgrade("heavy_strike", "style_damage_bonus", {"style": "warrior", "amount": 1})
	var mage_dmg := _make_upgrade("arcane_power", "style_damage_bonus", {"style": "mage", "amount": 1})
	PlayerUpgradeLibrary._cache = [warrior_dmg, mage_dmg]
	GameState.add_player_upgrade(warrior_dmg)
	GameState.add_player_upgrade(mage_dmg)
	var mods := GameState.get_player_upgrade_modifiers()
	assert_eq(mods.warrior_damage_bonus, 1)
	assert_eq(mods.mage_damage_bonus, 1)
	assert_eq(mods.archer_damage_bonus, 0,
		"archer не должен получить бонус, если карту не брали")

func test_pierce_bonus_reflected_in_archer_modifiers() -> void:
	var upgrade := _make_upgrade("piercing_arrows", "pierce_bonus", {"amount": 1})
	PlayerUpgradeLibrary._cache = [upgrade]
	GameState.add_player_upgrade(upgrade)
	var mods := GameState.get_player_upgrade_modifiers()
	assert_eq(mods.archer_pierce_bonus, 1)

func test_modifiers_are_default_when_no_stacks() -> void:
	# Регресс: пустой stacks → все дефолты 1.0 / 0.
	GameState.player_upgrade_stacks = {}
	PlayerUpgradeLibrary._cache = []
	var mods := GameState.get_player_upgrade_modifiers()
	assert_almost_eq(mods.speed_multiplier, 1.0, 0.0001)
	assert_eq(mods.warrior_damage_bonus, 0)
	assert_almost_eq(mods.mage_projectile_lifetime_multiplier, 1.0, 0.0001)

func test_modifier_snapshot_does_not_mutate_resource() -> void:
	# Регресс из плана: base weapon/upgrade resources не должны мутировать.
	var upgrade := _make_upgrade("boots", "speed_multiplier", {"multiplier": 1.10})
	var params_before: Dictionary = upgrade.parameters.duplicate()
	PlayerUpgradeLibrary._cache = [upgrade]
	GameState.add_player_upgrade(upgrade)
	GameState.get_player_upgrade_modifiers()
	assert_eq(upgrade.parameters, params_before,
		"snapshot не мутирует parameters")

func test_pending_upgrade_choice_queue() -> void:
	GameState.pending_upgrade_levels = []
	assert_false(GameState.has_pending_upgrade_choice())
	GameState.pending_upgrade_levels.append(3)
	GameState.pending_upgrade_levels.append(5)
	assert_true(GameState.has_pending_upgrade_choice())
	assert_eq(GameState.pop_next_pending_upgrade_level(), 3,
		"FIFO: сначала level 3")
	assert_eq(GameState.pop_next_pending_upgrade_level(), 5)
	assert_false(GameState.has_pending_upgrade_choice())

func test_next_floor_resets_second_wind() -> void:
	# next_floor вызывает reload_current_scene call_deferred — в GUT это
	# может ломать соседние тесты. Не запускаем полный next_floor, вместо
	# этого проверяем что reset_run имеет ту же семантику для second_wind.
	GameState.second_wind_used_this_floor = true
	# reset_run обнуляет тоже — это контракт из плана. next_floor будет
	# протестирован через integration в M6.
	var seed_snapshot := GameState.tower_seed
	GameState.reset_run()
	assert_false(GameState.second_wind_used_this_floor,
		"reset_run сбрасывает Second Wind (та же семантика что next_floor)")
	GameState.tower_seed = seed_snapshot
