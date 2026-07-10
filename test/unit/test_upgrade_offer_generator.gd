extends GutTest

# UpgradeOfferGenerator (M4):
# - detem same seed;
# - no duplicates;
# - исключает maxed cards;
# - general card в offer'e если есть eligible general;
# - current-style в offer'e если есть eligible current-style;
# - graceful degrade когда < 3 eligible.

func after_each() -> void:
	PlayerUpgradeLibrary.clear_cache_for_testing()

func _make_upgrade(id: String, style: String = "", rarity: String = "common", max_stacks: int = 3) -> PlayerUpgradeResource:
	var u := PlayerUpgradeResource.new()
	u.id = id
	u.display_name = "UPGRADE_%s" % id.to_upper()
	u.description = "UPGRADE_%s_DESC" % id.to_upper()
	u.style = style
	u.rarity = rarity
	u.max_stacks = max_stacks
	u.effect_type = "max_health_bonus"  # неважно для offer generator
	u.parameters = {"amount": 1}
	return u

func _basic_context(current_style: String = "warrior") -> Dictionary:
	return {
		"tower_seed": 12345,
		"player_level": 3,
		"current_floor_number": 1,
		"offer_counter": 0,
		"current_weapon_style": current_style,
	}

func test_same_seed_returns_same_offer() -> void:
	PlayerUpgradeLibrary._cache = [
		_make_upgrade("a", ""),
		_make_upgrade("b", ""),
		_make_upgrade("c", "warrior"),
		_make_upgrade("d", "archer"),
		_make_upgrade("e", "mage"),
	]
	var ctx := _basic_context()
	var offer_a := UpgradeOfferGenerator.generate_offer(ctx, {})
	var offer_b := UpgradeOfferGenerator.generate_offer(ctx, {})
	assert_eq(offer_a.size(), offer_b.size())
	for i in offer_a.size():
		assert_eq(offer_a[i].id, offer_b[i].id,
			"one seed → same offer at slot %d" % i)

func test_no_duplicates_in_offer() -> void:
	PlayerUpgradeLibrary._cache = [
		_make_upgrade("a", ""),
		_make_upgrade("b", ""),
		_make_upgrade("c", ""),
		_make_upgrade("d", ""),
	]
	var offer: Array = UpgradeOfferGenerator.generate_offer(_basic_context(""), {})
	var seen := {}
	for u in offer:
		assert_false(seen.has(u.id),
			"duplicate id %s в offer'e" % u.id)
		seen[u.id] = true

func test_excludes_maxed_cards() -> void:
	# a max_stacks = 2, уже 2 стека → должна быть исключена.
	PlayerUpgradeLibrary._cache = [
		_make_upgrade("a", "", "common", 2),
		_make_upgrade("b", "", "common", 3),
		_make_upgrade("c", "", "common", 3),
	]
	var offer: Array = UpgradeOfferGenerator.generate_offer(
		_basic_context(""),
		{"a": 2},
	)
	for u in offer:
		assert_ne(u.id, "a", "maxed 'a' не должна быть в offer'e")

func test_includes_general_when_available() -> void:
	PlayerUpgradeLibrary._cache = [
		_make_upgrade("gen1", ""),
		_make_upgrade("gen2", ""),
		_make_upgrade("warrior1", "warrior"),
	]
	var offer: Array = UpgradeOfferGenerator.generate_offer(_basic_context("warrior"), {})
	var has_general := false
	for u in offer:
		if u.style == "":
			has_general = true
			break
	assert_true(has_general, "минимум одна general карта должна быть в offer'e")

func test_includes_current_style_when_available() -> void:
	PlayerUpgradeLibrary._cache = [
		_make_upgrade("gen1", ""),
		_make_upgrade("warrior1", "warrior"),
		_make_upgrade("archer1", "archer"),
	]
	var offer: Array = UpgradeOfferGenerator.generate_offer(_basic_context("warrior"), {})
	var has_current_style := false
	for u in offer:
		if u.style == "warrior":
			has_current_style = true
			break
	assert_true(has_current_style,
		"minimum одна current-style (warrior) карта должна быть в offer'e")

func test_offer_size_is_three_when_pool_large_enough() -> void:
	var cards: Array = []
	for i in 10:
		cards.append(_make_upgrade("u%d" % i, ""))
	PlayerUpgradeLibrary.set_cache_for_testing(cards)
	var offer: Array = UpgradeOfferGenerator.generate_offer(_basic_context(""), {})
	assert_eq(offer.size(), 3, "offer размера 3 когда pool большой")

func test_offer_degrades_when_less_than_three_eligible() -> void:
	# Всего 2 eligible карты — offer не должен крешить, просто короче.
	PlayerUpgradeLibrary._cache = [
		_make_upgrade("a", ""),
		_make_upgrade("b", ""),
	]
	var offer: Array = UpgradeOfferGenerator.generate_offer(_basic_context(""), {})
	assert_lte(offer.size(), 2)
	assert_gt(offer.size(), 0, "если хотя бы одна eligible — offer не пустой")

func test_empty_library_returns_empty_offer() -> void:
	PlayerUpgradeLibrary.set_cache_for_testing([])
	var offer: Array = UpgradeOfferGenerator.generate_offer(_basic_context(""), {})
	assert_eq(offer.size(), 0, "пустая library → пустой offer, не креш")

func test_rare_cards_are_reachable_but_not_dominant() -> void:
	# 4 common + 1 rare + 1 uncommon. Prob каждого common = 100/... rare 10.
	# После 200 offer'ов ×3 = 600 slot'ов — rare должен появляться реже.
	var cards: Array = [
		_make_upgrade("c1", "", "common"),
		_make_upgrade("c2", "", "common"),
		_make_upgrade("c3", "", "common"),
		_make_upgrade("c4", "", "common"),
		_make_upgrade("u1", "", "uncommon"),
		_make_upgrade("r1", "", "rare"),
	]
	PlayerUpgradeLibrary.set_cache_for_testing(cards)
	var common_count := 0
	var rare_count := 0
	for i in 200:
		var ctx := {
			"tower_seed": i,
			"player_level": 3,
			"offer_counter": 0,
			"current_weapon_style": "",
		}
		var offer: Array = UpgradeOfferGenerator.generate_offer(ctx, {})
		for u in offer:
			if u.rarity == "common":
				common_count += 1
			elif u.rarity == "rare":
				rare_count += 1
	assert_gt(common_count, rare_count,
		"common карты должны появляться чаще rare (%d vs %d)" % [common_count, rare_count])
	assert_gt(rare_count, 0,
		"rare карта должна быть достижима хотя бы иногда")

func test_seed_changes_with_offer_counter() -> void:
	# Один и тот же level, разный offer_counter → разный offer (иначе
	# два запроса подряд дадут одинаковый выбор).
	var cards: Array = []
	for i in 8:
		cards.append(_make_upgrade("u%d" % i, ""))
	PlayerUpgradeLibrary.set_cache_for_testing(cards)
	var ctx := _basic_context("")
	var offer_a := UpgradeOfferGenerator.generate_offer(ctx, {})
	ctx.offer_counter = 1
	var offer_b := UpgradeOfferGenerator.generate_offer(ctx, {})
	# По крайней мере одна позиция должна отличаться.
	var any_diff := false
	for i in mini(offer_a.size(), offer_b.size()):
		if offer_a[i].id != offer_b[i].id:
			any_diff = true
			break
	assert_true(any_diff,
		"разный offer_counter должен давать разный offer")
