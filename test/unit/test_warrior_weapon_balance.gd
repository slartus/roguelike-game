extends GutTest

# Role invariants и балансовые расчёты warrior-оружия после fantasy overhaul.
#
# Dagger — melee_arc, минимальный reach, fastest interval, лучший приход от
# flat damage;
# Short Sword — melee_arc, средний профиль, лучший base DPS;
# Spear — melee_thrust, длинный reach, безопасность, средний DPS.

const DaggerRes = preload("res://resources/weapons/dagger.tres")
const ShortSwordRes = preload("res://resources/weapons/short_sword.tres")
const SpearRes = preload("res://resources/weapons/spear.tres")

const HeavyStrike = preload("res://resources/upgrades/warrior/heavy_strike.tres")
const LongReach = preload("res://resources/upgrades/warrior/long_reach.tres")
const Pushback = preload("res://resources/upgrades/warrior/pushback.tres")
const SweepingBlade = preload("res://resources/upgrades/warrior/sweeping_blade.tres")

var _weapon_snapshot: WeaponResource
var _stacks_snapshot: Dictionary

func before_each() -> void:
	_weapon_snapshot = GameState.equipped_weapon
	_stacks_snapshot = GameState.player_upgrade_stacks.duplicate(true)

func after_each() -> void:
	GameState.equipped_weapon = _weapon_snapshot
	GameState.player_upgrade_stacks = _stacks_snapshot
	# Тесты sweeping_blade подменяют library cache — чистим гарантированно
	# даже если предыдущий тест упал до inline cleanup.
	PlayerUpgradeLibrary.clear_cache_for_testing()

# --- Role: reach / arc / knockback ordering ---

func test_reach_ordering_dagger_lt_sword_lt_spear() -> void:
	assert_lt(DaggerRes.hitbox_length, ShortSwordRes.hitbox_length,
		"dagger должен иметь меньший reach, чем sword")
	assert_lt(ShortSwordRes.hitbox_length, SpearRes.hitbox_length,
		"sword должен иметь меньший reach, чем spear")

func test_arc_ordering_dagger_lt_sword() -> void:
	# Dagger — узкая дуга; Sword — шире.
	assert_lt(DaggerRes.arc_degrees, ShortSwordRes.arc_degrees,
		"dagger arc должен быть уже, чем sword arc")

func test_knockback_ordering_dagger_lt_spear_lt_sword() -> void:
	# Dagger — слабый knockback. Sword — heavy hit. Spear — средний
	# (толчок за счёт длины древка, но не как sword).
	assert_lt(DaggerRes.knockback, SpearRes.knockback,
		"dagger knockback < spear")
	assert_lt(SpearRes.knockback, ShortSwordRes.knockback,
		"spear knockback < sword")

# --- Base DPS ordering ---

func _base_dps(weapon: WeaponResource) -> float:
	return float(weapon.damage) / weapon.get_attack_interval()

func test_base_dps_sword_highest_spear_middle_dagger_lowest() -> void:
	var dagger_dps := _base_dps(DaggerRes)
	var sword_dps := _base_dps(ShortSwordRes)
	var spear_dps := _base_dps(SpearRes)
	assert_gt(sword_dps, spear_dps,
		"base DPS: sword выше spear (%.2f vs %.2f)" % [sword_dps, spear_dps])
	assert_gt(spear_dps, dagger_dps,
		"base DPS: spear выше dagger (%.2f vs %.2f)" % [spear_dps, dagger_dps])

# --- Heavy Strike balance ---

func _dps_with_heavy_strike_max(weapon: WeaponResource) -> float:
	# Heavy Strike добавляет +1 damage за стак, max 3 → +3 к базовому damage.
	GameState.player_upgrade_stacks = {"heavy_strike": HeavyStrike.max_stacks}
	var mods := GameState.get_player_upgrade_modifiers()
	var stats := WeaponStats.compute(weapon, mods)
	return float(stats.damage) / stats.attack_interval

func test_max_heavy_strike_dagger_can_exceed_sword_but_not_by_more_than_10_percent() -> void:
	# Целевая картина: с 3 стаками Heavy Strike кинжал наиболее эффективен
	# по чистому DPS, но не более чем на 10 процентов превосходит меч. Плата —
	# короткий reach и слабый knockback.
	var dagger_dps := _dps_with_heavy_strike_max(DaggerRes)
	var sword_dps := _dps_with_heavy_strike_max(ShortSwordRes)
	var ratio := dagger_dps / sword_dps
	assert_gt(dagger_dps, sword_dps,
		"с 3x Heavy Strike dagger обгоняет sword (dagger=%s, sword=%s)"
			% [dagger_dps, sword_dps])
	assert_lte(ratio, 1.10,
		"dagger не должен обгонять sword более чем на 10 процентов (ratio=%s)"
			% ratio)

func test_max_heavy_strike_spear_lowest_dps_but_keeps_reach() -> void:
	# Copьё остаётся ниже sword по DPS даже с 3x Heavy Strike — плата за
	# самый длинный reach.
	var spear_dps := _dps_with_heavy_strike_max(SpearRes)
	var sword_dps := _dps_with_heavy_strike_max(ShortSwordRes)
	assert_lt(spear_dps, sword_dps,
		"spear DPS ниже sword даже с max Heavy Strike (spear=%s, sword=%s)"
			% [spear_dps, sword_dps])
	# Reach spear'а всё равно длиннее — базовое поле не меняется от Heavy Strike.
	assert_gt(SpearRes.hitbox_length, ShortSwordRes.hitbox_length)

# --- Long Reach ---

func test_long_reach_multiplies_hitbox_length_for_all_warrior_weapons() -> void:
	GameState.player_upgrade_stacks = {"long_reach": LongReach.max_stacks}
	var mods := GameState.get_player_upgrade_modifiers()
	# max_stacks = 2, multiplier = 1.10 → комбинированный ×1.21.
	for weapon in [DaggerRes, ShortSwordRes, SpearRes]:
		var stats := WeaponStats.compute(weapon, mods)
		assert_almost_eq(
			stats.hitbox_length,
			weapon.hitbox_length * pow(1.10, LongReach.max_stacks),
			0.01,
			"%s: long_reach ×2 должно давать 1.21× hitbox_length" % weapon.display_name,
		)

# --- Pushback ---

func test_pushback_adds_flat_knockback_to_all_warrior_weapons() -> void:
	GameState.player_upgrade_stacks = {"pushback": Pushback.max_stacks}
	var mods := GameState.get_player_upgrade_modifiers()
	# max_stacks = 2, amount = 20 → +40 knockback.
	for weapon in [DaggerRes, ShortSwordRes, SpearRes]:
		var stats := WeaponStats.compute(weapon, mods)
		assert_almost_eq(
			stats.knockback,
			weapon.knockback + 20.0 * Pushback.max_stacks,
			0.01,
			"%s: pushback ×2 должно давать +40 knockback" % weapon.display_name,
		)

# --- Sweeping Blade compatibility filter ---

func test_sweeping_blade_offered_for_arc_weapons_dagger_and_sword() -> void:
	PlayerUpgradeLibrary.set_cache_for_testing([SweepingBlade])
	var ctx_dagger := {
		"tower_seed": 1,
		"player_level": 3,
		"offer_counter": 0,
		"current_weapon_style": "warrior",
		"current_weapon_attack_type": DaggerRes.attack_type,
	}
	var offer_dagger: Array = UpgradeOfferGenerator.generate_offer(ctx_dagger, {})
	var dagger_ids: Array = offer_dagger.map(func(u): return u.id)
	assert_true(dagger_ids.has("sweeping_blade"),
		"sweeping_blade должен предлагаться для dagger (melee_arc)")

	var ctx_sword := ctx_dagger.duplicate()
	ctx_sword.current_weapon_attack_type = ShortSwordRes.attack_type
	var offer_sword: Array = UpgradeOfferGenerator.generate_offer(ctx_sword, {})
	var sword_ids: Array = offer_sword.map(func(u): return u.id)
	assert_true(sword_ids.has("sweeping_blade"),
		"sweeping_blade должен предлагаться для sword (melee_arc)")
	PlayerUpgradeLibrary.clear_cache_for_testing()

func test_sweeping_blade_not_offered_for_spear_thrust() -> void:
	# Pool содержит только sweeping_blade. После фильтра по melee_thrust
	# offer должен быть пуст — карта отсеяна, других eligible нет.
	PlayerUpgradeLibrary.set_cache_for_testing([SweepingBlade])
	var ctx := {
		"tower_seed": 1,
		"player_level": 3,
		"offer_counter": 0,
		"current_weapon_style": "warrior",
		"current_weapon_attack_type": SpearRes.attack_type,  # melee_thrust
	}
	var offer: Array = UpgradeOfferGenerator.generate_offer(ctx, {})
	assert_eq(offer.size(), 0,
		"sweeping_blade отсеян по attack_type, других eligible карт нет → offer пуст")
	PlayerUpgradeLibrary.clear_cache_for_testing()

func test_sweeping_blade_not_in_offer_when_other_warrior_cards_available_for_spear() -> void:
	# Более практичный кейс: несколько warrior-карт eligible, но sweeping_blade
	# фильтруется — она не должна попасть в offer, остальные должны.
	PlayerUpgradeLibrary.set_cache_for_testing([
		SweepingBlade,
		HeavyStrike,
		LongReach,
		Pushback,
	])
	var ctx := {
		"tower_seed": 42,
		"player_level": 3,
		"offer_counter": 0,
		"current_weapon_style": "warrior",
		"current_weapon_attack_type": SpearRes.attack_type,
	}
	var offer: Array = UpgradeOfferGenerator.generate_offer(ctx, {})
	var offer_ids: Array = offer.map(func(u): return u.id)
	assert_false(offer_ids.has("sweeping_blade"),
		"sweeping_blade не должна быть в offer для spear")
	assert_gt(offer.size(), 0,
		"остальные warrior-карты должны заполнить offer")
	PlayerUpgradeLibrary.clear_cache_for_testing()
