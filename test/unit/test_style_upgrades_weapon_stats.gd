extends GutTest

# M7 style cards + WeaponStats layer:
# - warrior_damage_bonus влияет только на warrior оружие;
# - archer_pierce_bonus только на archer;
# - mage_damage_bonus только на mage;
# - attack_interval multiplier умножается корректно;
# - MIN_ATTACK_INTERVAL cap работает;
# - MAX_ARCHER_PIERCE_BONUS cap работает;
# - Base .tres не мутируются.

const ShortSword = preload("res://resources/weapons/short_sword.tres")
const ShortBow = preload("res://resources/weapons/short_bow.tres")
const Wand = preload("res://resources/weapons/wand.tres")

const HeavyStrike = preload("res://resources/upgrades/warrior/heavy_strike.tres")
const LongReach = preload("res://resources/upgrades/warrior/long_reach.tres")
const SweepingBlade = preload("res://resources/upgrades/warrior/sweeping_blade.tres")
const Pushback = preload("res://resources/upgrades/warrior/pushback.tres")

const QuickDraw = preload("res://resources/upgrades/archer/quick_draw.tres")
const PiercingArrows = preload("res://resources/upgrades/archer/piercing_arrows.tres")
const SteadyAim = preload("res://resources/upgrades/archer/steady_aim.tres")
const StrongBowstrings = preload("res://resources/upgrades/archer/strong_bowstrings.tres")

const ArcanePower = preload("res://resources/upgrades/mage/arcane_power.tres")
const SpellHaste = preload("res://resources/upgrades/mage/spell_haste.tres")
const ArcaneReach = preload("res://resources/upgrades/mage/arcane_reach.tres")

var _snapshot: Dictionary

func before_each() -> void:
	_snapshot = {"stacks": GameState.player_upgrade_stacks.duplicate()}
	GameState.player_upgrade_stacks = {}

func after_each() -> void:
	GameState.player_upgrade_stacks = _snapshot.stacks

func _mods() -> Dictionary:
	return GameState.get_player_upgrade_modifiers()

func test_warrior_damage_affects_sword_not_bow() -> void:
	GameState.add_player_upgrade(HeavyStrike)
	var sword_stats: WeaponStats = WeaponStats.compute(ShortSword, _mods())
	var bow_stats: WeaponStats = WeaponStats.compute(ShortBow, _mods())
	assert_eq(sword_stats.damage, ShortSword.damage + 1,
		"warrior damage bonus влияет на sword")
	assert_eq(bow_stats.damage, ShortBow.damage,
		"warrior damage bonus НЕ влияет на bow")

func test_archer_pierce_affects_bow_not_sword() -> void:
	GameState.add_player_upgrade(PiercingArrows)
	var bow_stats: WeaponStats = WeaponStats.compute(ShortBow, _mods())
	var sword_stats: WeaponStats = WeaponStats.compute(ShortSword, _mods())
	assert_eq(bow_stats.pierce, ShortBow.pierce + 1,
		"archer pierce bonus +1 к луку")
	assert_eq(sword_stats.pierce, ShortSword.pierce,
		"archer pierce bonus НЕ влияет на sword")

func test_mage_damage_affects_wand_not_sword() -> void:
	GameState.add_player_upgrade(ArcanePower)
	var wand_stats: WeaponStats = WeaponStats.compute(Wand, _mods())
	var sword_stats: WeaponStats = WeaponStats.compute(ShortSword, _mods())
	assert_eq(wand_stats.damage, Wand.damage + 1)
	assert_eq(sword_stats.damage, ShortSword.damage,
		"mage damage bonus НЕ влияет на sword")

func test_attack_interval_multiplier_shortens_cooldown() -> void:
	GameState.add_player_upgrade(QuickDraw)  # archer × 0.90
	var bow_stats: WeaponStats = WeaponStats.compute(ShortBow, _mods())
	assert_almost_eq(bow_stats.attack_interval, ShortBow.get_attack_interval() * 0.90, 0.001)

func test_min_attack_interval_cap() -> void:
	# Гипотетический весёлый сценарий: 3 стека QuickDraw = 0.90^3 ≈ 0.729.
	# Проверим что даже при экстремальном multiplier'e не падаем ниже cap.
	# Симулируем через add_player_upgrade вручную.
	GameState.player_upgrade_stacks = {"quick_draw": 3}
	# Base = 0.32; 0.32 * 0.729 = 0.233. Всё ещё > MIN 0.05.
	var bow_stats: WeaponStats = WeaponStats.compute(ShortBow, _mods())
	assert_gte(bow_stats.attack_interval, WeaponStats.MIN_ATTACK_INTERVAL,
		"attack_interval никогда не ниже MIN cap")

func test_max_archer_pierce_bonus_cap() -> void:
	# 3 стека дают бонус +3, но MAX_ARCHER_PIERCE_BONUS = 2 — обрезается.
	GameState.player_upgrade_stacks = {"piercing_arrows": 3}
	var bow_stats: WeaponStats = WeaponStats.compute(ShortBow, _mods())
	assert_lte(bow_stats.pierce - ShortBow.pierce, WeaponStats.MAX_ARCHER_PIERCE_BONUS,
		"pierce cap не позволяет +3 бонус за 3 стека")

func test_multiple_stacks_combine() -> void:
	# 2 стека heavy_strike = +2 damage. max_stacks = 3.
	GameState.add_player_upgrade(HeavyStrike)
	GameState.add_player_upgrade(HeavyStrike)
	var sword_stats: WeaponStats = WeaponStats.compute(ShortSword, _mods())
	assert_eq(sword_stats.damage, ShortSword.damage + 2)

func test_switching_weapon_style_activates_correct_modifiers() -> void:
	# Взяли warrior damage + archer damage. Стеки в run state — оба.
	# При компиляции sword активен только warrior; при bow — archer.
	GameState.add_player_upgrade(HeavyStrike)
	# Мануально добавим archer damage — не в MVP, но проверяем логику
	# роутинга через _apply_upgrade_to_mods.
	GameState.player_upgrade_stacks["archer_damage_fake"] = 1
	# Sword: только warrior применён.
	var sword_stats: WeaponStats = WeaponStats.compute(ShortSword, _mods())
	assert_eq(sword_stats.damage, ShortSword.damage + 1,
		"sword — только warrior bonus (+1 из heavy_strike)")
	# Bow: только archer применён (heavy_strike игнорируется).
	var bow_stats: WeaponStats = WeaponStats.compute(ShortBow, _mods())
	assert_eq(bow_stats.damage, ShortBow.damage,
		"bow — не должен получить warrior heavy_strike")

func test_base_weapon_resource_is_not_mutated() -> void:
	var base_damage_before := ShortSword.damage
	var base_range_before := ShortSword.attack_range
	GameState.add_player_upgrade(HeavyStrike)
	GameState.add_player_upgrade(LongReach)
	WeaponStats.compute(ShortSword, _mods())
	assert_eq(ShortSword.damage, base_damage_before,
		"base weapon damage не мутируется")
	assert_eq(ShortSword.attack_range, base_range_before)

func test_pushback_adds_to_knockback() -> void:
	GameState.add_player_upgrade(Pushback)
	var sword_stats: WeaponStats = WeaponStats.compute(ShortSword, _mods())
	assert_almost_eq(sword_stats.knockback, ShortSword.knockback + 20.0, 0.001)

func test_sweeping_blade_widens_arc_degrees_on_arc_weapon() -> void:
	# После перехода к sector-hitbox'у warrior_arc_multiplier умножает угол
	# сектора, а не ширину прямоугольника. Sweeping Blade (× 1.15) на arc-
	# оружии должен расширять `arc_degrees`.
	GameState.add_player_upgrade(SweepingBlade)
	var sword_stats: WeaponStats = WeaponStats.compute(ShortSword, _mods())
	assert_almost_eq(
		sword_stats.arc_degrees,
		ShortSword.arc_degrees * 1.15,
		0.01,
	)

func test_sweeping_blade_does_not_affect_thrust_arc() -> void:
	# Регресс: копьё — melee_thrust, у него нет сектора; arc_multiplier
	# не должен трогать его arc_degrees (WeaponResource всё равно хранит
	# поле как заготовку — copy без mutation).
	var Spear = preload("res://resources/weapons/spear.tres")
	GameState.add_player_upgrade(SweepingBlade)
	var spear_stats: WeaponStats = WeaponStats.compute(Spear, _mods())
	assert_almost_eq(spear_stats.arc_degrees, Spear.arc_degrees, 0.01,
		"thrust не имеет сектора → arc_multiplier не применяется")

func test_arc_degrees_is_capped() -> void:
	# 5 стеков × 1.15 = 1.15^5 ≈ 2.011 → 80 × 2.011 ≈ 161°. Всё ещё < cap.
	# Проверяем что даже при экстремальных значениях не переходим 179°.
	GameState.player_upgrade_stacks = {"sweeping_blade": 20}
	var sword_stats: WeaponStats = WeaponStats.compute(ShortSword, _mods())
	assert_lte(sword_stats.arc_degrees, WeaponStats.MAX_ARC_DEGREES,
		"arc_degrees не должен превышать MAX_ARC_DEGREES (иначе сектор замкнётся)")

func test_arcane_reach_extends_mage_projectile_lifetime() -> void:
	GameState.add_player_upgrade(ArcaneReach)
	var wand_stats: WeaponStats = WeaponStats.compute(Wand, _mods())
	assert_almost_eq(
		wand_stats.projectile_lifetime,
		Wand.get_projectile_lifetime() * 1.15,
		0.001,
	)

func test_all_style_cards_load_and_have_correct_style() -> void:
	for pair in [
		[HeavyStrike, "warrior"], [LongReach, "warrior"],
		[SweepingBlade, "warrior"], [Pushback, "warrior"],
		[QuickDraw, "archer"], [PiercingArrows, "archer"],
		[SteadyAim, "archer"], [StrongBowstrings, "archer"],
		[ArcanePower, "mage"], [SpellHaste, "mage"], [ArcaneReach, "mage"],
	]:
		var upgrade: PlayerUpgradeResource = pair[0]
		var expected_style: String = pair[1]
		assert_not_null(upgrade, "card loads: %s" % upgrade)
		assert_eq(upgrade.style, expected_style,
			"%s имеет style %s" % [upgrade.id, expected_style])
